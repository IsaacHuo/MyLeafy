import type { ApiMetadata, ApiResponse, ExportRequest, GlobalSearchResult } from "../contracts";
import type { AdminAccount } from "../contracts";

export type AdminIdentityResponse = {
  admin: AdminAccount;
  permissions: Array<{ resource: string; actions: string[] }>;
  session: { expires_at: string };
};

export class AdminApiError extends Error {
  status: number;
  code: string;
  retryable: boolean;
  details?: unknown;

  constructor(status: number, code: string, message: string, retryable = false, details?: unknown) {
    super(message);
    this.name = "AdminApiError";
    this.status = status;
    this.code = code;
    this.retryable = retryable;
    this.details = details;
  }
}

export async function loginRequest(username: string, password: string): Promise<AdminIdentityResponse> {
  return requestJSON("/api/admin/login", { method: "POST", body: { username, password } });
}

export async function meRequest(): Promise<AdminIdentityResponse> {
  return requestJSON("/api/admin/me", { method: "GET" });
}

export async function logoutRequest(): Promise<void> {
  await requestJSON("/api/admin/logout", { method: "POST", body: {} });
}

export async function actionRequest<T>(action: string, params: Record<string, unknown> = {}): Promise<ApiResponse<T>> {
  const response = await requestJSON<ApiResponse<T>>("/api/admin/actions", { method: "POST", body: { action, params } });
  warnIfAuditFailed(response.meta, action);
  return response;
}

export async function globalSearchRequest(query: string, resources?: string[]): Promise<GlobalSearchResult[]> {
  const response = await actionRequest<GlobalSearchResult[]>("globalSearch", { query, resources });
  return [...response.data];
}

export async function exportRequest(payload: ExportRequest): Promise<{ blob: Blob; filename: string }> {
  const response = await adminFetch("/api/admin/export", {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", "X-Leafy-Admin-CSRF": "1" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw await responseError(response);
  if (response.headers.get("x-audit-logged") === "false") {
    emitAuditWarning("exportResource", response.headers.get("x-request-id") ?? undefined);
  }
  return {
    blob: await response.blob(),
    filename: filenameFromDisposition(response.headers.get("content-disposition")) ?? `leafy-${payload.resource}.csv`,
  };
}

async function requestJSON<T>(url: string, options: { method: "GET" | "POST"; body?: unknown }): Promise<T> {
  const response = await adminFetch(url, {
    method: options.method,
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
      "X-Leafy-Admin-CSRF": "1",
      ...(options.method === "POST" ? { "Content-Type": "application/json" } : {}),
    },
    ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {}),
  });
  if (!response.ok) throw await responseError(response);
  return response.json() as Promise<T>;
}

async function responseError(response: Response) {
  const payload = await response.json().catch(() => ({}));
  const envelope = payload?.errorEnvelope ?? payload?.error ?? {};
  const baseMessage = typeof payload?.error === "string"
    ? payload.error
    : envelope.message ?? `后台请求失败（${response.status}）`;
  const requestID = response.headers.get("x-request-id") ?? envelope.details?.request_id;
  const message = requestID ? `${baseMessage}（请求 ID: ${requestID}）` : baseMessage;
  const details = { ...(typeof envelope.details === "object" && envelope.details ? envelope.details : {}), ...(requestID ? { request_id: requestID } : {}) };
  return new AdminApiError(response.status, envelope.code ?? "unknown", message, envelope.retryable === true, details);
}

async function adminFetch(input: RequestInfo | URL, init: RequestInit) {
  try {
    return await fetch(input, init);
  } catch (error) {
    throw new AdminApiError(0, "network_error", "无法连接后台服务，请检查网络后重试。", true, { cause: String(error) });
  }
}

function warnIfAuditFailed(meta: ApiMetadata | undefined, action: string) {
  if (meta?.audit_logged === false) {
    emitAuditWarning(action, meta.request_id);
  }
}

function emitAuditWarning(action: string, requestID?: string) {
  console.warn(`Admin action ${action} completed without an audit record`, requestID);
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent("leafy-admin-audit-warning", { detail: { action, requestID } }));
  }
}

function filenameFromDisposition(value: string | null) {
  return value?.match(/filename="?([^";]+)"?/i)?.[1] ?? null;
}
