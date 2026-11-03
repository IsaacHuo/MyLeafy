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
  const display = (value: unknown, digits = 2) =>
    typeof value === "number" && Number.isFinite(value)
      ? value.toLocaleString("zh-CN", { maximumFractionDigits: digits })
      : "未采集";
  const clock = (value: unknown) =>
    typeof value === "number" || typeof value === "string"
      ? new Date(value).toLocaleString("zh-CN", {
          timeZone: "Asia/Shanghai",
          hour12: false,
        })
      : "未采集";
  const status = (value: unknown) =>
    value === true ? "正常" : value === false ? "异常" : "未知";
  const sample = summary.sample ?? {},
    peak = summary.peaks ?? {};
  const serviceLines =
    Object.entries(sample.services ?? {})
      .map(([name, value]) => `  ${name}：${status((value as any).healthy)}`)
      .join("\n") || "  未采集";
  const alertLines =
    (summary.alerts as any[])
      .map(
        (row) =>
          `  ${row.resolvedAt ? "已恢复" : "未恢复"} · ${row.title}（首次 ${clock(row.firstSeen)}）`,
      )
      .join("\n") || "  暂无已记录告警";
  const errorLines =
    (summary.topErrors as any[])
      .map(
        (row) =>
          `  ${row.source} / ${row.event}${row.code ? " / " + row.code : ""}：${row.count} 次`,
      )
      .join("\n") || "  暂无已记录错误";
  const tasks = store.get<any>("taskSnapshot")?.tasks ?? [];
  const taskLines =
    tasks
      .map(
        (row: any) =>
          `  ${row.job} UTC：${row.status === "succeeded" ? "成功" : row.status === "failed" ? "失败" : "执行中"}，最近完成 ${clock(row.finished_at)}`,
      )
      .join("\n") || "  未采集";
  const body = [
    `MyLeafy ${environment} 每日报告`,
    `统计范围（北京时间）：${clock(period.start)} — ${clock(period.end)}`,
    complete
      ? "采集范围完整；请求数不代表活跃用户。"
      : "采集范围不完整：首日、断采或容量清理。以下累计值仅涵盖已采集部分，不能据此认定全天正常或零访问。",
    `流量与接口\n  已记录请求：${display(summary.requests, 0)}\n  响应流量：${display(summary.bytes / 1048576)} MiB\n  5xx：${display(summary.errors, 0)} 次（${display(summary.errorRate === null ? null : summary.errorRate * 100)}%）\n  P50 / P95 / P99：${display(summary.p50)} / ${display(summary.p95)} / ${display(summary.p99)} 秒`,
    `资源峰值\n  CPU：${display(peak.cpu)}%\n  内存：${display(peak.memory)}%\n  磁盘：${display(peak.disk)}%`,
    `当前服务状态（采集于 ${clock(sample.timestamp)}）\n${serviceLines}`,
    `备份\n  最近成功：${clock(sample.backup?.successAt)}\n  最近结果：${sample.backup?.failed === true ? "失败" : sample.backup?.failed === false ? "成功" : "未采集"}`,
    `定时任务\n${taskLines}`,
    `异常与恢复\n${alertLines}`,
    `主要错误\n${errorLines}`,
    "后台详情：https://myleafy.space/admin/monitoring/reports",
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
    acceptanceOnly?: boolean;
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
        "SELECT * FROM deliveries WHERE status='pending' AND nextAttempt<=? AND (leaseUntil IS NULL OR leaseUntil<?) AND (?=0 OR kind='acceptance') ORDER BY CASE kind WHEN 'report' THEN 0 ELSE 1 END,createdAt LIMIT 1",
      )
      .get(now, now, settings.acceptanceOnly ? 1 : 0) as any;
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
