import { isIP } from "node:net";
import routeTemplates from "./routes.json";
const allowedRoutes = new Set(routeTemplates);

export type Environment = "production" | "staging";
export type LogEntry = {
  timestamp: number;
  source: string;
  level: "info" | "warning" | "error";
  event: string;
  host?: string;
  method?: string;
  route?: string;
  status?: number;
  duration?: number;
  bytes?: number;
  ip?: string;
  requestId?: string;
  code?: string;
};
export type Observation = {
  key: string;
  title: string;
  failing: boolean | null;
  forMs: number;
  value?: number;
  immediate?: boolean;
};
export const day = 86_400_000;
export const jobKeys: Record<string, string> = {
  "* * * * *": "signals",
  "17 * * * *": "invites",
  "20 17 * * *": "retention",
  "35 18 * * *": "media",
};
export const hosts: Record<Environment, string[]> = {
  production: [
    "myleafy.space",
    "www.myleafy.space",
    "api.myleafy.space",
    "downloads.myleafy.space",
  ],
  staging: [
    "staging.myleafy.space",
    "api-staging.myleafy.space",
    "downloads-staging.myleafy.space",
  ],
};
export const actionKinds = {
  monitoringOverview: "overview",
  monitoringSeries: "series",
  requestLogList: "requests",
  serviceLogList: "logs",
  monitoringAlerts: "alerts",
  monitoringReports: "reports",
} as const;
export type MonitorKind = (typeof actionKinds)[keyof typeof actionKinds];
export function validateQuery(
  kind: MonitorKind,
  params: Record<string, unknown>,
  now = Date.now(),
) {
  const fields: Record<MonitorKind, string[]> = {
    overview: [],
    series: ["metric"],
    requests: ["host", "method", "route", "status", "requestId", "minDuration"],
    logs: ["source", "level", "event", "code", "requestId"],
    alerts: [],
    reports: [],
  };
  const allowed = new Set([
    "start",
    "end",
    "page",
    "pageSize",
    ...fields[kind],
  ]);
  if (Object.keys(params).some((key) => !allowed.has(key)))
    throw new Error("不支持的监控筛选参数。");
  return parseRange(params, now);
}
export function maskIP(value: unknown): string | undefined {
  if (typeof value !== "string") return;
  if (isIP(value) === 4)
    return value.split(".").slice(0, 3).join(".") + ".0/24";
  if (isIP(value) === 6) {
    // Use URL's canonical IPv6 expansion to avoid retaining any host bits.
    const canonical = new URL(`http://[${value}]/`).hostname.slice(1, -1);
    const halves = canonical.split("::"),
      left = halves[0].split(":").filter(Boolean);
    const right = (halves[1] ?? "").split(":").filter(Boolean);
    const expanded =
      halves.length === 2
        ? [
            ...left,
            ...Array(8 - left.length - right.length).fill("0"),
            ...right,
          ]
        : left;
    return (
      expanded
        .slice(0, 3)
        .map((x) => x || "0")
        .join(":") + "::/48"
    );
  }
  // Caddy already masks before writing its log.
  if (
    /^(?:\d{1,3}\.){3}0\/24$/.test(value) ||
    /^[a-f0-9:]+::\/48$/i.test(value)
  )
    return value;
}
const safeToken = (value: unknown, max = 100): string | undefined =>
  typeof value === "string" && /^[A-Za-z0-9_.:-]+$/.test(value)
    ? value.slice(0, max)
    : undefined;
export function normalizeLog(
  input: Record<string, any>,
  environment: Environment,
): LogEntry | null {
  const request = input.request;
  if (request) {
    if (input.probe === true || input.probe === "true") return null;
    const host = String(request.host ?? "").toLowerCase();
    if (!hosts[environment].includes(host)) return null;
    const timestamp = Number(input.ts) * 1000,
      status = Number(input.status);
    if (
      !Number.isFinite(timestamp) ||
      !Number.isInteger(status) ||
      status < 100 ||
      status > 599
    )
      return null;
    const route = allowedRoutes.has(input.route)
      ? String(input.route)
      : "/:unmatched";
    const duration = Number(input.duration),
      bytes = Number(input.size);
    if (
      !Number.isFinite(duration) ||
      duration < 0 ||
      !Number.isFinite(bytes) ||
      bytes < 0
    )
      return null;
    return {
      timestamp,
      source: "access",
      level: status >= 500 ? "error" : "info",
      event: "http_request",
      host,
      method: [
        "GET",
        "HEAD",
        "POST",
        "PUT",
        "PATCH",
        "DELETE",
        "OPTIONS",
        "CONNECT",
      ].includes(request.method)
        ? request.method
        : "OTHER",
      route,
      status,
      duration,
      bytes,
      ip: maskIP(request.client_ip ?? request.remote_ip),
      requestId: safeToken(
        input.request_id ?? input.resp_headers?.["X-Request-Id"]?.[0],
        128,
      ),
    };
  }
  const timestamp = Number(input.timestamp ?? Date.now());
  if (!Number.isFinite(timestamp)) return null;
  // Whitelist structured fields. Never index arbitrary journal MESSAGE/stack traces.
  const event = safeToken(input.event),
    code = safeToken(input.code);
  if (!event) return null;
  const error = /failed|error|oom|unexpected_exit/.test(event);
  return {
    timestamp,
    source: safeToken(input.source) ?? "application",
    level: error ? "error" : input.level === "warning" ? "warning" : "info",
    event,
    code: jobKeys[String(input.job)] ?? code,
    requestId: safeToken(input.request_id, 128),
    status: Number.isInteger(input.status) ? input.status : undefined,
  };
}
export function parseRange(params: Record<string, unknown>, now = Date.now()) {
  const end = params.end === undefined ? now : Date.parse(String(params.end));
  const start =
    params.start === undefined ? end - day : Date.parse(String(params.start));
  if (
    !Number.isFinite(start) ||
    !Number.isFinite(end) ||
    start >= end ||
    end - start > 14 * day ||
    end > now + 60_000 ||
    start < now - 31 * day
  )
    throw new Error("时间范围无效，单次最多查询 14 天。");
  const page = Number(params.page ?? 0),
    pageSize = Number(params.pageSize ?? 20);
  if (
    !Number.isInteger(page) ||
    page < 0 ||
    page > 10000 ||
    !Number.isInteger(pageSize) ||
    pageSize < 1 ||
    pageSize > 100
  )
    throw new Error("分页参数无效。");
  return { start, end, page, pageSize };
}
export function reportPeriod(now = Date.now()) {
  // Shanghai has no DST: 21:00 CST is 13:00 UTC.
  const date = new Date(now),
    boundary = Date.UTC(
      date.getUTCFullYear(),
      date.getUTCMonth(),
      date.getUTCDate(),
      13,
    );
  const end = boundary > now ? boundary - day : boundary;
  return {
    start: end - day,
    end,
    key: new Date(end + 8 * 3_600_000).toISOString().slice(0, 10),
  };
}
