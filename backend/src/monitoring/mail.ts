import { createHash } from "node:crypto";
import { day, reportPeriod } from "./model";
import { MonitorStore } from "./store";

export function queueDailyReport(
  store: MonitorStore,
  environment: string,
  now = Date.now(),
) {
  const period = reportPeriod(now),
    id = `report:${environment}:${period.key}`;
  if (store.db.prepare("SELECT id FROM reports WHERE id=?").get(id)) return id;
  const summary = {
    ...store.summary(period.start, period.end),
    coverage: store.coverage(now),
    sample: store.get("sample") ?? null,
    alerts: store.db
      .prepare(
        "SELECT title,firstSeen,resolvedAt FROM alerts WHERE lastSeen>=? AND firstSeen<?",
      )
      .all(period.start, period.end),
    peaks: store.get("dailyPeaks:" + period.key) ?? null,
  };
  const gaps = (
    store.db
      .prepare(
        "SELECT count(*) AS n FROM logs WHERE event='collection_gap' AND timestamp>=? AND timestamp-coalesce(duration,0)*1000<?",
      )
      .get(period.start, period.end) as any
  ).n;
  const complete =
    Number(summary.coverage.startedAt) <= period.start &&
    !summary.coverage.stale &&
    !summary.coverage.collectionError &&
    !gaps &&
    !summary.coverage.capacityLimited;
  const body = [
    `MyLeafy ${environment} 每日报告`,
    `${new Date(period.start).toLocaleString("zh-CN", { timeZone: "Asia/Shanghai" })} — ${new Date(period.end).toLocaleString("zh-CN", { timeZone: "Asia/Shanghai" })}`,
    complete
      ? "采集范围：完整（服务端请求统计，不代表活跃用户）"
      : "采集范围：不完整，首日或采集中断；未采集部分不计为正常",
    `请求：${summary.requests}；响应流量：${summary.bytes} 字节；5xx：${summary.errors}；P95：${summary.p95 ?? "未采集"} 秒`,
    `资源峰值：${summary.peaks ? JSON.stringify(summary.peaks) : "未采集"}`,
    `最新服务/备份状态：${JSON.stringify(summary.sample)}`,
    `异常与恢复：${JSON.stringify(summary.alerts)}`,
    `主要错误：${JSON.stringify(summary.topErrors)}`,
    "详情：https://myleafy.space/admin/monitoring/reports",
  ].join("\n\n");
  store.db.transaction(() => {
    store.enqueue(id, "report", `[MyLeafy 日报] ${period.key}`, body, now);
    store.db
      .prepare(
        "INSERT OR IGNORE INTO reports(id,start,end,createdAt,summary,deliveryId) VALUES(?,?,?,?,?,?)",
      )
      .run(
        id,
        period.start,
        period.end,
        now,
        JSON.stringify({ ...summary, complete }),
        id,
      );
  })();
  return id;
}
export async function deliverMail(
  store: MonitorStore,
  settings: {
    enabled: boolean;
    key?: string;
    from?: string;
    recipient?: string;
    dailyLimit?: number;
  },
  now = Date.now(),
  request: typeof fetch = fetch,
) {
  if (!settings.enabled) return;
  if (
    !settings.key ||
    !settings.from ||
    !settings.recipient ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(settings.recipient)
  ) {
    store.set("mailError", "email_not_configured");
    return;
  }
  const start = now - ((now + 8 * 3_600_000) % day),
    limit = settings.dailyLimit ?? 10;
  const sent = (
    store.db
      .prepare(
        "SELECT count(*) AS n FROM deliveries WHERE status='sent' AND nextAttempt>=?",
      )
      .get(start) as any
  ).n;
  if (sent >= limit) {
    store.set("mailError", "monitor_daily_budget_reached");
    return;
  }
  const delivery = store.db.transaction(() => {
    const row = store.db
      .prepare(
        "SELECT * FROM deliveries WHERE status='pending' AND nextAttempt<=? AND (leaseUntil IS NULL OR leaseUntil<?) ORDER BY CASE kind WHEN 'report' THEN 0 ELSE 1 END,createdAt LIMIT 1",
      )
      .get(now, now) as any;
    if (row)
      store.db
        .prepare("UPDATE deliveries SET leaseUntil=? WHERE id=?")
        .run(now + 30_000, row.id);
    return row;
  })();
  if (!delivery) return;
  const nonReportSent = (
    store.db
      .prepare(
        "SELECT count(*) AS n FROM deliveries WHERE status='sent' AND kind<>'report' AND nextAttempt>=?",
      )
      .get(start) as any
  ).n;
  if (delivery.kind !== "report" && nonReportSent >= Math.max(0, limit - 1)) {
    store.db
      .prepare("UPDATE deliveries SET leaseUntil=NULL WHERE id=?")
      .run(delivery.id);
    store.set("mailError", "monitor_alert_budget_reserved_for_report");
    return;
  }
  if (now - delivery.createdAt > day) {
    store.db
      .prepare(
        "UPDATE deliveries SET status='failed',error='delivery_expired',leaseUntil=NULL WHERE id=?",
      )
      .run(delivery.id);
    return;
  }
  try {
    const response = await request("https://api.resend.com/emails", {
      method: "POST",
      signal: AbortSignal.timeout(15_000),
      headers: {
        Authorization: `Bearer ${settings.key}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `myleafy-monitor-${createHash("sha256").update(delivery.id).digest("hex")}`,
      },
      body: JSON.stringify({
        from: settings.from,
        to: [settings.recipient],
        subject: delivery.subject,
        text: delivery.body,
      }),
    });
    const result = (await response.json()) as any;
    if (!response.ok || typeof result.id !== "string")
      throw Object.assign(new Error("provider_rejected"), {
        retryable: response.status === 429 || response.status >= 500,
        code: `email_http_${response.status}`,
      });
    store.db
      .prepare(
        "UPDATE deliveries SET status='sent',attempts=attempts+1,providerId=?,error=NULL,leaseUntil=NULL,nextAttempt=? WHERE id=?",
      )
      .run(result.id, now, delivery.id);
    store.set("mailError", null);
  } catch (error: any) {
    const attempts = delivery.attempts + 1,
      retryable = error.retryable !== false && attempts < 12;
    const code =
      typeof error.code === "string" && /^email_http_\d+$/.test(error.code)
        ? error.code
        : "email_transport_failed";
    store.db
      .prepare(
        "UPDATE deliveries SET status=?,attempts=?,error=?,nextAttempt=?,leaseUntil=NULL WHERE id=?",
      )
      .run(
        retryable ? "pending" : "failed",
        attempts,
        code,
        now + Math.min(3_600_000, 30_000 * 2 ** Math.min(attempts, 7)),
        delivery.id,
      );
    store.set("mailError", code);
  }
}
