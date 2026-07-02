import { createClient } from "npm:@supabase/supabase-js@2";
import {
  normalizeText,
  verifyAppTransactionJWS,
} from "../_shared/campus-ai-billing.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const deepSeekChatCompletionsURL = "https://api.deepseek.com/chat/completions";
const providerName = "deepseek";
const defaultModel = "deepseek-v4-flash";
const maxMessageLength = 1200;
const maxRecentMessages = 10;
const maxUserSystemPromptLength = 3000;
const inputCacheMissCostPerMillion = 0.14;
const outputCostPerMillion = 0.28;
const encoder = new TextEncoder();

type CampusAIRequest = {
  request_id?: string;
  app_transaction_id?: string;
  app_transaction_jws?: string;
  service_mode?: string;
  message?: string;
  context?: unknown;
  recent_messages?: Array<{ role?: string; text?: string }>;
  recentMessages?: Array<{ role?: string; text?: string }>;
  user_system_prompt?: string;
  userSystemPrompt?: string;
  context_settings?: unknown;
  contextSettings?: unknown;
};

type CampusAIActionKind =
  | "openAcademicRoute"
  | "createCountdown"
  | "createTimetableReminder";

type CampusAIActionPayload = {
  route?: string;
  countdownTitle?: string;
  targetDate?: string;
  week?: number;
  dayOfWeek?: number;
  period?: number;
  endPeriod?: number;
  title?: string;
  location?: string;
  note?: string;
  minutesBefore?: number;
};

type CampusAIActionDraft = {
  id?: string;
  kind: CampusAIActionKind;
  title?: string;
  detail?: string;
  payload?: CampusAIActionPayload;
};

type DeepSeekUsage = {
  prompt_tokens?: number;
  prompt_cache_hit_tokens?: number;
  prompt_cache_miss_tokens?: number;
  completion_tokens?: number;
  reasoning_tokens?: number;
  total_tokens?: number;
};

type UsageCompletion = {
  requestUUID: string;
  status: "success" | "error";
  counted: boolean;
  requestCharCount: number;
  responseCharCount: number;
  usage: DeepSeekUsage;
  errorCode: string | null;
};

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  if (!bearerToken(request)) {
    return json({ error: "缺少登录凭证。" }, 401);
  }

  const adminClient = makeAdminClient();
  if (!adminClient) {
    return json({ error: "AI 服务配置不完整。" }, 500);
  }

  const authResult = await authenticateUser(adminClient, request);
  if (!authResult.ok) {
    return json({ error: authResult.error }, authResult.status);
  }

  if (deepSeekAPIKeys().length === 0) {
    return json({ error: "AI 服务未配置 DeepSeek API Key。" }, 500);
  }

  const body = await readJSON<CampusAIRequest>(request);
  const requestUUID = normalizeUUID(body.request_id);
  if (!requestUUID) {
    return json({ error: "请求标识无效。" }, 400);
  }

  if (body.service_mode !== "leafyManaged") {
    return json({ error: "托管服务只接受 Leafy 托管模式请求。" }, 400);
  }

  const message = normalizeText(body.message);
  if (!message) {
    return json({ error: "请先输入想问的问题。" }, 400);
  }
  if (message.length > maxMessageLength) {
    return json({ error: "问题太长了，请拆成更短的一次提问。" }, 400);
  }

  let appTransactionID: string | null = null;
  try {
    const appTransaction = await verifyAppTransactionJWS(
      body.app_transaction_jws,
      body.app_transaction_id,
    );
    appTransactionID = appTransaction?.appTransactionID ??
      normalizeText(body.app_transaction_id);
  } catch (error) {
    console.error(
      "campus-ai-assistant: app transaction verification failed",
      errorMessage(error),
    );
    return json({ error: "App Store 安装记录验证失败，请稍后重试。" }, 401);
  }

  if (!appTransactionID) {
    return json({ error: "缺少 App Store 安装标识。" }, 400);
  }

  const campusID = campusIDFromContext(body.context);
  const reservation = await reserveQuota(adminClient, {
    requestUUID,
    authUserID: authResult.userID,
    appTransactionID,
    campusID,
  });

  if (!reservation.allowed) {
    const status = reservation.error === "quota_exhausted" ? 402 : 429;
    const error = reservation.error === "quota_exhausted"
      ? "本月 Leafy AI 次数已用完。"
      : "AI 助手请求太频繁了，稍后再试。";
    return json({ error, quota: reservation.quota }, status);
  }

  const requestCharCount = safeJSONStringify(body).length;
  return streamResponse(async (controller, signal) => {
    let answer = "";
    let reasoning = "";
    let firstTokenSeen = false;
    let usage: DeepSeekUsage = {};
    let completed = false;

    try {
      if (reservation.quota) {
        enqueueSSE(controller, { type: "quota", quota: reservation.quota });
      }

      const result = await streamDeepSeek(body, message, signal, {
        onDelta(delta) {
          if (delta.length > 0) {
            firstTokenSeen = true;
            answer += delta;
            enqueueSSE(controller, { type: "delta", text: delta });
          }
        },
        onReasoningDelta(delta) {
          if (delta.length > 0) {
            reasoning += delta;
            enqueueSSE(controller, { type: "reasoning_delta", text: delta });
          }
        },
        onUsage(nextUsage) {
          usage = nextUsage;
        },
      });
      const actionPlan = await planActions(
        body,
        message,
        result.answer,
        signal,
      );
      usage = mergeUsage(usage, actionPlan.usage);

      completed = true;
      enqueueSSE(controller, {
        type: "done",
        answer: result.answer,
        reasoning: result.reasoning,
        finish_reason: result.finishReason,
        suggested_title: shortTitle(message),
        summary: "",
        actions: actionPlan.actions,
      });

      await completeUsage(adminClient, {
        requestUUID,
        status: "success",
        counted: result.answer.length > 0,
        requestCharCount,
        responseCharCount: result.answer.length +
          safeJSONStringify(actionPlan.actions).length,
        usage,
        errorCode: null,
      });
      const quota = await quotaSnapshot(
        adminClient,
        authResult.userID,
        appTransactionID,
      );
      enqueueSSE(controller, { type: "quota", quota });
    } catch (error) {
      console.error("campus-ai-assistant: request failed", errorMessage(error));
      enqueueSSE(controller, {
        type: "error",
        error: "AI 助手暂时不可用，请稍后重试。",
      });
      await completeUsage(adminClient, {
        requestUUID,
        status: "error",
        counted: firstTokenSeen,
        requestCharCount,
        responseCharCount: answer.length + reasoning.length,
        usage,
        errorCode: signal.aborted
          ? "client_aborted"
          : completed
          ? null
          : "provider_error",
      });
      const quota = await quotaSnapshot(
        adminClient,
        authResult.userID,
        appTransactionID,
      );
      enqueueSSE(controller, { type: "quota", quota });
    }
  });
}

if (import.meta.main) {
  Deno.serve(handler);
}

async function streamDeepSeek(
  body: CampusAIRequest,
  message: string,
  signal: AbortSignal,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
): Promise<{ answer: string; reasoning: string; finishReason: string | null }> {
  const apiKeys = deepSeekAPIKeys();
  if (apiKeys.length === 0) {
    throw new Error("Missing DEEPSEEK_API_KEY or DEEPSEEK_API_KEYS.");
  }

  const payload = JSON.stringify(deepSeekPayload(body, message));
  let lastError: Error | null = null;
  for (const [index, apiKey] of apiKeys.entries()) {
    let response: Response;
    try {
      response = await fetch(deepSeekChatCompletionsURL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          Accept: "text/event-stream",
        },
        body: payload,
        signal,
      });
    } catch (error) {
      if (signal.aborted || index === apiKeys.length - 1) throw error;
      lastError = new Error(redactProviderError(errorMessage(error)));
      console.warn(
        `campus-ai-assistant: DeepSeek key ${
          index + 1
        }/${apiKeys.length} failed before stream; trying fallback`,
        lastError.message,
      );
      continue;
    }

    if (!response.ok) {
      const responseText = await response.text();
      const error = new Error(
        `DeepSeek key ${
          index + 1
        }/${apiKeys.length} returned ${response.status}: ${
          redactProviderError(responseText)
        }`,
      );
      if (
        index < apiKeys.length - 1 &&
        shouldRetryDeepSeekStatus(response.status)
      ) {
        lastError = error;
        console.warn(
          "campus-ai-assistant: DeepSeek key failed before stream; trying fallback",
          error.message,
        );
        continue;
      }
      throw error;
    }
    if (!response.body) {
      throw new Error("DeepSeek response did not include a stream body.");
    }
    return await readDeepSeekStream(response, callbacks);
  }

  throw lastError ?? new Error("DeepSeek request failed.");
}

async function planActions(
  body: CampusAIRequest,
  message: string,
  answer: string,
  signal: AbortSignal,
): Promise<{ actions: CampusAIActionDraft[]; usage: DeepSeekUsage }> {
  if (!answer.trim()) return { actions: [], usage: {} };

  try {
    const payload = JSON.stringify(actionPlannerPayload(body, message, answer));
    const apiKeys = deepSeekAPIKeys();
    let lastError: Error | null = null;
    for (const [index, apiKey] of apiKeys.entries()) {
      let response: Response;
      try {
        response = await fetch(deepSeekChatCompletionsURL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${apiKey}`,
            "Content-Type": "application/json",
            Accept: "application/json",
          },
          body: payload,
          signal,
        });
      } catch (error) {
        if (signal.aborted || index === apiKeys.length - 1) throw error;
        lastError = new Error(redactProviderError(errorMessage(error)));
        console.warn(
          `campus-ai-assistant: DeepSeek action planner key ${
            index + 1
          }/${apiKeys.length} failed before response; trying fallback`,
          lastError.message,
        );
        continue;
      }

      const responseText = await response.text();
      if (!response.ok) {
        const error = new Error(
          `DeepSeek action planner key ${
            index + 1
          }/${apiKeys.length} returned ${response.status}: ${
            redactProviderError(responseText)
          }`,
        );
        if (
          index < apiKeys.length - 1 &&
          shouldRetryDeepSeekStatus(response.status)
        ) {
          lastError = error;
          console.warn(
            "campus-ai-assistant: DeepSeek action planner key failed; trying fallback",
            error.message,
          );
          continue;
        }
        throw error;
      }

      return parseActionPlannerProviderResponse(responseText);
    }

    throw lastError ?? new Error("DeepSeek action planner failed.");
  } catch (error) {
    if (!signal.aborted) {
      console.warn(
        "campus-ai-assistant: action planning failed",
        redactProviderError(errorMessage(error)),
      );
    }
    return { actions: [], usage: {} };
  }
}

async function readDeepSeekStream(
  response: Response,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
): Promise<{ answer: string; reasoning: string; finishReason: string | null }> {
  const body = response.body;
  if (!body) {
    throw new Error("DeepSeek response did not include a stream body.");
  }
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let answer = "";
  let reasoning = "";
  let finishReason: string | null = null;

  const process = (value: string, includeRemainder = false) => {
    const result = drainDeepSeekSSEBuffer(value, {
      onDelta(delta) {
        answer += delta;
        callbacks.onDelta(delta);
      },
      onReasoningDelta(delta) {
        reasoning += delta;
        callbacks.onReasoningDelta(delta);
      },
      onFinishReason(nextFinishReason) {
        if (nextFinishReason) finishReason = nextFinishReason;
      },
      onUsage: callbacks.onUsage,
    }, includeRemainder);
    return result.remainder;
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    buffer = process(buffer);
  }

  buffer += decoder.decode();
  process(buffer, true);
  return { answer, reasoning, finishReason };
}

export function deepSeekPayload(body: CampusAIRequest, message: string) {
  const recentMessages = recentMessagesFromBody(body)
    .slice(-maxRecentMessages)
    .map((item) => ({
      role: item.role === "assistant" ? "assistant" : "user",
      text: normalizeText(item.text) ?? "",
    }))
    .filter((item) => item.text.length > 0);

  return {
    model: defaultModel,
    messages: [
      {
        role: "system",
        content: systemPrompt(
          normalizeText(body.user_system_prompt) ??
            normalizeText(body.userSystemPrompt),
        ),
      },
      {
        role: "user",
        content: safeJSONStringify({
          message,
          context: body.context ?? {},
          context_settings: body.context_settings ?? body.contextSettings ?? {},
          recent_messages: recentMessages,
        }),
      },
    ],
    stream: true,
    stream_options: { include_usage: true },
    thinking: { type: "enabled" },
    temperature: 0.2,
    max_tokens: 1800,
    user: userCacheKey(body.app_transaction_id),
  };
}

export function actionPlannerPayload(
  body: CampusAIRequest,
  message: string,
  answer: string,
) {
  return {
    model: defaultModel,
    messages: [
      {
        role: "system",
        content: actionPlannerSystemPrompt(),
      },
      {
        role: "user",
        content: safeJSONStringify({
          message,
          answer,
          context: body.context ?? {},
          context_settings: body.context_settings ?? body.contextSettings ?? {},
          supported_actions: [
            {
              kind: "openAcademicRoute",
              required_payload_fields: ["route"],
              allowed_values: {
                route: [
                  "grades",
                  "gradeAnalytics",
                  "examSchedule",
                  "scheduleReports",
                  "customCountdowns",
                  "teachingPlan",
                  "trainingProgram",
                ],
              },
            },
            {
              kind: "createCountdown",
              required_payload_fields: ["countdownTitle", "targetDate"],
              allowed_values: { targetDate: ["yyyy-MM-dd"] },
            },
            {
              kind: "createTimetableReminder",
              required_payload_fields: ["week", "dayOfWeek", "period", "title"],
              allowed_values: {
                week: ["1...30"],
                dayOfWeek: ["1...7"],
                period: ["1...12"],
              },
            },
          ],
          safety_boundary: [
            "所有动作都只生成待确认草稿，不会自动执行。",
            "不要生成删除、修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
            "缺少必要 payload 字段或字段无法从上下文确定时，返回空 actions。",
          ],
        }),
      },
    ],
    stream: false,
    temperature: 0,
    max_tokens: 700,
    user: userCacheKey(body.app_transaction_id),
  };
}

export function systemPrompt(userSystemPrompt?: string | null) {
  const customPrompt = normalizeText(userSystemPrompt)
    ?.slice(0, maxUserSystemPromptLength);
  return [
    "你是 MyLeafy 的校园学习与生活助手，当前是测试功能。",
    "优先根据请求中提供的本机缓存或本地保存上下文回答；可以补充明确标注为一般建议的常识，但不要把常识伪装成本机数据。",
    "数据不足时直接说明缺少哪些上下文。",
    "不要声称读取了未提供的数据，不要声称读取了用户上传文件正文、图片像素、OCR、PDF、Word、PPT、表格或本地文件路径。",
    "社区内容只可当作用户当前设备已缓存的公开 feed 摘要，不要推断私信、身份资料或未缓存远端内容。",
    "医疗台账只能做整理、提醒、流程梳理和材料核对，不提供诊断、治疗、用药或医疗决策建议。",
    "回复必须是中文 Markdown。优先使用短标题、列表、加粗和清晰分段；不要在正文输出 JSON 或动作草稿，动作会由单独规划器生成。",
    customPrompt ? `用户自定义偏好：\n${customPrompt}` : "",
  ].filter(Boolean).join("\n");
}

export function actionPlannerSystemPrompt() {
  return [
    "你是 MyLeafy 的动作规划器，只能输出 JSON，不能输出 Markdown、解释、代码块或多余文本。",
    "根据用户问题、AI 已生成回答和本机上下文，最多生成 3 个需要用户确认后执行的动作。",
    '只有用户明确想打开页面、设置倒计时、设置课表提醒，或回答中明显需要这一步时才生成动作；否则返回 {"actions":[]}。',
    "支持 kind：openAcademicRoute、createCountdown、createTimetableReminder。",
    "openAcademicRoute.payload.route 只能是 grades、gradeAnalytics、examSchedule、scheduleReports、customCountdowns、teachingPlan、trainingProgram。",
    "createCountdown.payload 必须包含 countdownTitle 和 targetDate，targetDate 使用 yyyy-MM-dd。",
    "createTimetableReminder.payload 必须包含 week、dayOfWeek、period、title；dayOfWeek 为 1 到 7，minutesBefore 必须大于等于 0。",
    "不要生成删除、修改成绩或课表原始数据、医疗决策、社区发帖评论、远程抓取、后台登录等动作。",
    '输出格式必须是 {"actions":[{"kind":"...","title":"...","detail":"...","payload":{...}}]}。',
  ].join("\n");
}

export function campusAIResponseFormat() {
  return null;
}

export function drainDeepSeekSSEBuffer(
  value: string,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onFinishReason: (finishReason: string | null) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
  includeRemainder = false,
): { remainder: string } {
  let buffer = value;
  while (true) {
    const newlineIndex = buffer.indexOf("\n\n");
    const carriageIndex = buffer.indexOf("\r\n\r\n");
    const indexes = [newlineIndex, carriageIndex].filter((index) => index >= 0);
    if (indexes.length === 0) break;
    const index = Math.min(...indexes);
    const separatorLength = buffer.startsWith("\r\n\r\n", index) ? 4 : 2;
    const block = buffer.slice(0, index);
    buffer = buffer.slice(index + separatorLength);
    processDeepSeekSSEBlock(block, callbacks);
  }

  if (includeRemainder && buffer.trim().length > 0) {
    processDeepSeekSSEBlock(buffer, callbacks);
    buffer = "";
  }
  return { remainder: buffer };
}

export function processDeepSeekSSEBlock(
  block: string,
  callbacks: {
    onDelta: (delta: string) => void;
    onReasoningDelta: (delta: string) => void;
    onFinishReason: (finishReason: string | null) => void;
    onUsage: (usage: DeepSeekUsage) => void;
  },
) {
  const dataText = block
    .replaceAll("\r\n", "\n")
    .split("\n")
    .filter((line) => !line.startsWith(":"))
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trim())
    .join("\n")
    .trim();
  if (!dataText || dataText === "[DONE]") return;

  const payload = JSON.parse(dataText) as Record<string, unknown>;
  const topLevelError = payload.error;
  if (topLevelError && typeof topLevelError === "object") {
    const message =
      normalizeText((topLevelError as Record<string, unknown>).message) ??
        "DeepSeek stream error.";
    throw new Error(redactProviderError(message));
  }

  const usage = objectValue(payload.usage);
  if (usage) callbacks.onUsage(deepSeekUsage(usage));

  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  for (const choice of choices) {
    if (!choice || typeof choice !== "object") continue;
    const choiceRecord = choice as Record<string, unknown>;
    const finishReason = normalizeText(choiceRecord.finish_reason);
    if (finishReason) callbacks.onFinishReason(finishReason);

    const delta = objectValue(choiceRecord.delta);
    if (!delta) continue;
    const reasoning = stringValue(delta.reasoning_content);
    if (reasoning) callbacks.onReasoningDelta(reasoning);
    const content = stringValue(delta.content);
    if (content) callbacks.onDelta(content);
  }
}

export function parseActionPlannerProviderResponse(
  responseText: string,
): { actions: CampusAIActionDraft[]; usage: DeepSeekUsage } {
  const payload = JSON.parse(responseText) as Record<string, unknown>;
  const usagePayload = objectValue(payload.usage);
  const usage = usagePayload ? deepSeekUsage(usagePayload) : {};
  const choices = Array.isArray(payload.choices) ? payload.choices : [];
  const content = choices
    .map((choice) => objectValue(choice))
    .map((choice) => objectValue(choice?.message))
    .map((message) => stringValue(message?.content))
    .find((value) => !!value) ?? "";

  return {
    actions: parseActionPlannerActions(content),
    usage,
  };
}

export function parseActionPlannerActions(content: string) {
  for (const candidate of actionPlannerJSONCandidates(content)) {
    try {
      const parsed = JSON.parse(candidate);
      const rawActions = Array.isArray(parsed)
        ? parsed
        : Array.isArray(parsed?.actions)
        ? parsed.actions
        : [];
      const actions = rawActions
        .map((item: unknown) => validateActionDraft(item))
        .filter((
          item: CampusAIActionDraft | null,
        ): item is CampusAIActionDraft => item !== null);
      if (actions.length > 0 || rawActions.length === 0) {
        return actions.slice(0, 3);
      }
    } catch {
      // Try the next candidate.
    }
  }
  return [];
}

function actionPlannerJSONCandidates(content: string) {
  let trimmed = content.trim();
  if (trimmed.startsWith("```")) {
    const lines = trimmed.replaceAll("\r\n", "\n").split("\n");
    if (lines.length > 1) {
      if (lines.at(-1)?.trim() === "```") lines.pop();
      lines.shift();
      trimmed = lines.join("\n").trim();
    }
  }

  const candidates = [trimmed];
  const objectStart = trimmed.indexOf("{");
  const objectEnd = trimmed.lastIndexOf("}");
  if (objectStart >= 0 && objectEnd >= objectStart) {
    candidates.push(trimmed.slice(objectStart, objectEnd + 1));
  }
  const arrayStart = trimmed.indexOf("[");
  const arrayEnd = trimmed.lastIndexOf("]");
  if (arrayStart >= 0 && arrayEnd >= arrayStart) {
    candidates.push(trimmed.slice(arrayStart, arrayEnd + 1));
  }
  return Array.from(new Set(candidates.filter(Boolean)));
}

function validateActionDraft(value: unknown): CampusAIActionDraft | null {
  const record = objectValue(value);
  if (!record) return null;
  const rawKind = stringValue(record.kind);
  const kind = normalizeActionKind(rawKind);
  if (!kind) return null;

  const payloadRecord = objectValue(record.payload) ?? {};
  const payload = normalizeActionPayload(payloadRecord);
  const draft: CampusAIActionDraft = {
    id: stringValue(record.id) ?? crypto.randomUUID(),
    kind,
    title: stringValue(record.title) ?? "",
    detail: stringValue(record.detail) ?? "",
    payload,
  };

  switch (kind) {
    case "openAcademicRoute":
      return validateOpenAcademicRoute(draft);
    case "createCountdown":
      return validateCreateCountdown(draft);
    case "createTimetableReminder":
      return validateCreateTimetableReminder(draft);
  }
}

function normalizeActionKind(value: string | null): CampusAIActionKind | null {
  switch (value) {
    case "openAcademicRoute":
    case "open_academic_route":
      return "openAcademicRoute";
    case "createCountdown":
    case "create_countdown":
      return "createCountdown";
    case "createTimetableReminder":
    case "create_timetable_reminder":
      return "createTimetableReminder";
    default:
      return null;
  }
}

function normalizeActionPayload(
  payload: Record<string, unknown>,
): CampusAIActionPayload {
  return {
    route: stringValue(payload.route) ?? undefined,
    countdownTitle: stringValue(payload.countdownTitle) ??
      stringValue(payload.countdown_title) ?? undefined,
    targetDate: stringValue(payload.targetDate) ??
      stringValue(payload.target_date) ?? undefined,
    week: integerValue(payload.week) ?? undefined,
    dayOfWeek: integerValue(payload.dayOfWeek) ??
      integerValue(payload.day_of_week) ?? undefined,
    period: integerValue(payload.period) ?? undefined,
    endPeriod: integerValue(payload.endPeriod) ??
      integerValue(payload.end_period) ?? undefined,
    title: stringValue(payload.title) ?? undefined,
    location: stringValue(payload.location) ?? undefined,
    note: stringValue(payload.note) ?? undefined,
    minutesBefore: integerValue(payload.minutesBefore) ??
      integerValue(payload.minutes_before) ?? undefined,
  };
}

function validateOpenAcademicRoute(
  draft: CampusAIActionDraft,
): CampusAIActionDraft | null {
  const route = draft.payload?.route;
  const allowedRoutes = new Set([
    "grades",
    "gradeAnalytics",
    "examSchedule",
    "scheduleReports",
    "customCountdowns",
    "teachingPlan",
    "trainingProgram",
  ]);
  if (!route || !allowedRoutes.has(route)) return null;
  return {
    ...draft,
    title: normalizeText(draft.title) ?? `打开${academicRouteTitle(route)}`,
    payload: { route },
  };
}

function validateCreateCountdown(
  draft: CampusAIActionDraft,
): CampusAIActionDraft | null {
  const title = normalizeText(draft.payload?.countdownTitle) ??
    normalizeText(draft.payload?.title);
  const targetDate = normalizeText(draft.payload?.targetDate);
  if (!title || !targetDate || !/^\d{4}-\d{2}-\d{2}$/.test(targetDate)) {
    return null;
  }
  return {
    ...draft,
    title: normalizeText(draft.title) ?? "创建倒计时",
    payload: {
      countdownTitle: title,
      targetDate,
    },
  };
}

function validateCreateTimetableReminder(
  draft: CampusAIActionDraft,
): CampusAIActionDraft | null {
  const week = draft.payload?.week;
  const dayOfWeek = draft.payload?.dayOfWeek;
  const period = draft.payload?.period;
  const title = normalizeText(draft.payload?.title);
  if (
    !week || week < 1 || week > 30 ||
    !dayOfWeek || dayOfWeek < 1 || dayOfWeek > 7 ||
    !period || period < 1 || period > 12 ||
    !title
  ) {
    return null;
  }
  const endPeriod =
    draft.payload?.endPeriod && draft.payload.endPeriod >= period &&
      draft.payload.endPeriod <= 12
      ? draft.payload.endPeriod
      : undefined;
  return {
    ...draft,
    title: normalizeText(draft.title) ?? "创建课表提醒",
    payload: {
      week,
      dayOfWeek,
      period,
      endPeriod,
      title,
      location: normalizeText(draft.payload?.location) ?? undefined,
      note: normalizeText(draft.payload?.note) ?? undefined,
      minutesBefore: Math.max(0, draft.payload?.minutesBefore ?? 0),
    },
  };
}

function academicRouteTitle(route: string) {
  switch (route) {
    case "grades":
      return "成绩查询";
    case "gradeAnalytics":
      return "成绩分析";
    case "examSchedule":
      return "考试与日程";
    case "scheduleReports":
      return "日程推送";
    case "customCountdowns":
      return "自定义倒计时";
    case "teachingPlan":
      return "教学计划";
    case "trainingProgram":
      return "培养方案";
    default:
      return "学业页面";
  }
}

function deepSeekUsage(payload: Record<string, unknown>): DeepSeekUsage {
  return {
    prompt_tokens: integerValue(payload.prompt_tokens) ?? 0,
    prompt_cache_hit_tokens: integerValue(payload.prompt_cache_hit_tokens) ?? 0,
    prompt_cache_miss_tokens: integerValue(payload.prompt_cache_miss_tokens) ??
      0,
    completion_tokens: integerValue(payload.completion_tokens) ?? 0,
    reasoning_tokens: integerValue(payload.reasoning_tokens) ?? 0,
    total_tokens: integerValue(payload.total_tokens) ?? 0,
  };
}

async function reserveQuota(adminClient: any, params: {
  requestUUID: string;
  authUserID: string;
  appTransactionID: string;
  campusID: string;
}) {
  const { data, error } = await adminClient.schema("private").rpc(
    "reserve_campus_ai_quota",
    {
      p_request_uuid: params.requestUUID,
      p_auth_user_id: params.authUserID,
      p_app_transaction_id: params.appTransactionID,
      p_campus_id: params.campusID,
    },
  );
  if (error) {
    console.error("campus-ai-assistant: quota reserve failed", error.message);
    return { allowed: false, error: "quota_error", quota: null };
  }
  return data as {
    allowed: boolean;
    error?: string;
    quota?: Record<string, unknown>;
  };
}

async function completeUsage(adminClient: any, event: UsageCompletion) {
  const estimatedCost = estimatedCostUSD(event.usage);
  const { error } = await adminClient.schema("private").rpc(
    "complete_campus_ai_usage",
    {
      p_request_uuid: event.requestUUID,
      p_status: event.status,
      p_counted: event.counted,
      p_request_char_count: event.requestCharCount,
      p_response_char_count: event.responseCharCount,
      p_input_tokens: event.usage.prompt_tokens ?? 0,
      p_input_cache_hit_tokens: event.usage.prompt_cache_hit_tokens ?? 0,
      p_input_cache_miss_tokens: event.usage.prompt_cache_miss_tokens ?? 0,
      p_output_tokens: event.usage.completion_tokens ?? 0,
      p_reasoning_tokens: event.usage.reasoning_tokens ?? 0,
      p_total_tokens: event.usage.total_tokens ?? 0,
      p_estimated_cost_usd: estimatedCost,
      p_error_code: event.errorCode,
    },
  );
  if (error) {
    console.error(
      "campus-ai-assistant: usage completion failed",
      error.message,
    );
  }
}

async function quotaSnapshot(
  adminClient: any,
  authUserID: string,
  appTransactionID: string,
) {
  const { data, error } = await adminClient.schema("private").rpc(
    "campus_ai_quota_snapshot",
    {
      p_auth_user_id: authUserID,
      p_app_transaction_id: appTransactionID,
    },
  );
  if (error) {
    console.error("campus-ai-assistant: quota snapshot failed", error.message);
    return null;
  }
  return data;
}

async function authenticateUser(adminClient: any, request: Request) {
  const token = bearerToken(request);
  if (!token) {
    return { ok: false as const, status: 401, error: "缺少登录凭证。" };
  }

  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data?.user?.id) {
    return {
      ok: false as const,
      status: 401,
      error: "登录状态已失效，请稍后重试。",
    };
  }
  return { ok: true as const, userID: data.user.id as string };
}

function streamResponse(
  producer: (
    controller: ReadableStreamDefaultController<Uint8Array>,
    signal: AbortSignal,
  ) => Promise<void>,
) {
  const abortController = new AbortController();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        await producer(controller, abortController.signal);
      } finally {
        controller.close();
      }
    },
    cancel() {
      abortController.abort();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      ...corsHeaders,
    },
  });
}

function enqueueSSE(
  controller: ReadableStreamDefaultController<Uint8Array>,
  payload: Record<string, unknown>,
) {
  controller.enqueue(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`));
}

function makeAdminClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return null;
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

export function deepSeekAPIKeys() {
  const keys: string[] = [];
  appendDeepSeekAPIKeys(keys, Deno.env.get("DEEPSEEK_API_KEY"));
  appendDeepSeekAPIKeys(keys, Deno.env.get("DEEPSEEK_API_KEYS"));
  for (let index = 1; index <= 10; index += 1) {
    appendDeepSeekAPIKeys(keys, Deno.env.get(`DEEPSEEK_API_KEY_${index}`));
  }
  return Array.from(new Set(keys));
}

function appendDeepSeekAPIKeys(keys: string[], value: string | undefined) {
  for (const key of parseDeepSeekAPIKeys(value)) {
    if (key.length > 0) keys.push(key);
  }
}

export function parseDeepSeekAPIKeys(value: string | undefined) {
  const raw = value?.trim();
  if (!raw) return [];

  if (raw.startsWith("[")) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        return parsed
          .map((item) => typeof item === "string" ? item.trim() : "")
          .filter(Boolean);
      }
    } catch {
      // Fall back to delimiter parsing below.
    }
  }

  return raw
    .split(/[\n,;]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function shouldRetryDeepSeekStatus(status: number) {
  return status === 401 ||
    status === 403 ||
    status === 408 ||
    status === 409 ||
    status === 425 ||
    status === 429 ||
    status >= 500;
}

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return await request.json() as T;
  } catch {
    return {} as T;
  }
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

function bearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return null;
  const [scheme, token] = authHeader.split(/\s+/, 2);
  return scheme?.toLowerCase() === "bearer" && token ? token : null;
}

function recentMessagesFromBody(body: CampusAIRequest) {
  if (Array.isArray(body.recent_messages)) return body.recent_messages;
  if (Array.isArray(body.recentMessages)) return body.recentMessages;
  return [];
}

function userCacheKey(appTransactionID: unknown): string | null {
  const value = normalizeText(appTransactionID);
  if (!value) return null;
  return `leafy-${hashString(value)}`;
}

function hashString(value: string) {
  let hash = 5381;
  for (const char of value) {
    hash = ((hash << 5) + hash + char.charCodeAt(0)) >>> 0;
  }
  return hash.toString(16);
}

function estimatedCostUSD(usage: DeepSeekUsage) {
  const cacheMissInput = usage.prompt_cache_miss_tokens ??
    usage.prompt_tokens ??
    0;
  const output = usage.completion_tokens ?? 0;
  return (cacheMissInput * inputCacheMissCostPerMillion +
    output * outputCostPerMillion) / 1_000_000;
}

function mergeUsage(lhs: DeepSeekUsage, rhs: DeepSeekUsage): DeepSeekUsage {
  return {
    prompt_tokens: (lhs.prompt_tokens ?? 0) + (rhs.prompt_tokens ?? 0),
    prompt_cache_hit_tokens: (lhs.prompt_cache_hit_tokens ?? 0) +
      (rhs.prompt_cache_hit_tokens ?? 0),
    prompt_cache_miss_tokens: (lhs.prompt_cache_miss_tokens ?? 0) +
      (rhs.prompt_cache_miss_tokens ?? 0),
    completion_tokens: (lhs.completion_tokens ?? 0) +
      (rhs.completion_tokens ?? 0),
    reasoning_tokens: (lhs.reasoning_tokens ?? 0) +
      (rhs.reasoning_tokens ?? 0),
    total_tokens: (lhs.total_tokens ?? 0) + (rhs.total_tokens ?? 0),
  };
}

function campusIDFromContext(context: unknown): string {
  if (context && typeof context === "object") {
    const campusID = normalizeText(
      (context as Record<string, unknown>).campusID,
    );
    if (campusID) return campusID;
  }
  return "unknown";
}

function shortTitle(message: string) {
  const compact = message
    .replace(/\s+/g, "")
    .trim();
  if (!compact) return "新的对话";
  return compact.length <= 10 ? compact : `${compact.slice(0, 9)}…`;
}

function normalizeUUID(value: unknown): string | null {
  const text = normalizeText(value);
  if (!text) return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(text)
    ? text
    : null;
}

function safeJSONStringify(value: unknown): string {
  try {
    return JSON.stringify(value);
  } catch {
    return "{}";
  }
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function integerValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function redactProviderError(value: string) {
  return value.replace(/sk-[A-Za-z0-9_-]+/g, "sk-redacted").slice(0, 500);
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
