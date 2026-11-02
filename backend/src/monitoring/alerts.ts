import { type Observation, type LogEntry } from "./model";
import { type MonitorStore } from "./store";

export type Sample = {
  timestamp: number;
  cpu: number | null;
  memory: number | null;
  disk: number | null;
  services: Record<
    string,
    { healthy: boolean | null; failures: number; restarts: number | null }
  >;
  backup: { successAt: number | null; failed: boolean | null };
  maintenanceUntil: number | null;
  collectionError: string | null;
};
export function observations(
  store: MonitorStore,
  sample: Sample,
): Observation[] {
  const observations: Observation[] = [];
  for (const [key, title, threshold, forMs] of [
    ["cpu", "CPU 持续超过 85%", 85, 600_000],
    ["memory", "内存持续超过 85%", 85, 300_000],
    ["disk", "磁盘使用率超过 85%", 85, 300_000],
  ] as const) {
    const value = sample[key];
    observations.push({
      key,
      title,
      failing: value === null ? null : value > threshold,
      forMs,
      value: value ?? undefined,
    });
  }
  observations.push({
    key: "disk-critical",
    title: "磁盘使用率超过 95%",
    failing: sample.disk === null ? null : sample.disk > 95,
    forMs: 0,
    value: sample.disk ?? undefined,
  });
  const maintaining =
    sample.maintenanceUntil !== null &&
    sample.maintenanceUntil > sample.timestamp;
  for (const [name, service] of Object.entries(sample.services)) {
    observations.push({
      key: `health:${name}`,
      title: `${name} 连续健康检查失败`,
      failing: maintaining
        ? null
        : service.healthy === null
          ? null
          : service.failures >= 3,
      forMs: 0,
      value: service.failures,
    });
  }
  const short = store.summary(sample.timestamp - 300_000, sample.timestamp),
    long = store.summary(sample.timestamp - 600_000, sample.timestamp);
  observations.push({
    key: "http-errors",
    title: "接口 5xx 比例超过 5%",
    failing: short.requests >= 100 ? (short.errorRate ?? 0) > 0.05 : false,
    forMs: 0,
    value: short.errorRate ?? undefined,
  });
  observations.push({
    key: "http-latency",
    title: "接口 P95 响应超过 2 秒",
    failing: long.requests >= 100 ? long.p95 > 2 : false,
    forMs: 0,
    value: long.p95 ?? undefined,
  });
  const repeated = store.db
    .prepare(
      "SELECT source,event,code,count(*) AS n FROM logs WHERE source<>'access' AND level='error' AND timestamp>=? GROUP BY source,event,code HAVING count(*)>=10",
    )
    .all(sample.timestamp - 300_000) as any[];
  const activeRepeatKeys = new Set<string>();
  for (const row of repeated) {
    const key = `repeated:${row.source}:${row.event}:${row.code ?? ""}`;
    activeRepeatKeys.add(key);
    observations.push({
      key,
      title: `${row.event} 反复发生`,
      failing: true,
      forMs: 0,
      value: row.n,
    });
  }
  for (const row of store.db
    .prepare(
      "SELECT key,title FROM alerts WHERE key LIKE 'repeated:%' AND resolvedAt IS NULL",
    )
    .all() as any[])
    if (!activeRepeatKeys.has(row.key))
      observations.push({ ...row, failing: false, forMs: 0 });
  observations.push({
    key: "backup-failed",
    title: "每日备份执行失败",
    failing: sample.backup.failed,
    forMs: 0,
  });
  observations.push({
    key: "backup-expired",
    title: "超过 26 小时没有成功备份",
    failing:
      sample.backup.successAt === null
        ? null
        : sample.timestamp - sample.backup.successAt > 26 * 3_600_000,
    forMs: 0,
  });
  observations.push({
    key: "collection",
    title: "监控采集异常",
    failing: sample.collectionError !== null,
    forMs: 90_000,
  });
  return observations;
}
export function observeEvents(
  store: MonitorStore,
  entries: LogEntry[],
  now = Date.now(),
) {
  const severe = ["oom", "unexpected_exit", "backup_failed"];
  for (const entry of entries) {
    if (entry.event === "scheduled_job_failed" && entry.code)
      store.observe(
        {
          key: `task:${entry.code}`,
          title: `定时任务 ${entry.code} 执行失败`,
          failing: true,
          forMs: 0,
        },
        now,
      );
    else if (severe.includes(entry.event))
      store.observe(
        {
          key:
            entry.source === "backup"
              ? "backup-failed"
              : `event:${entry.source}:${entry.event}`,
          title:
            entry.source === "backup"
              ? "每日备份执行失败"
              : `${entry.source}: ${entry.event}`,
          failing: true,
          forMs: 0,
        },
        now,
      );
  }
  // One-off events remain visible; recovery is tied to a subsequent explicit success.
  for (const entry of entries)
    if (
      entry.event === "backup_succeeded" ||
      entry.event === "listening" ||
      entry.event === "scheduled_job_succeeded"
    ) {
      const suffix =
        entry.event === "backup_succeeded"
          ? "backup_failed"
          : entry.event === "listening"
            ? "unexpected_exit"
            : "scheduled_job_failed";
      store.observe(
        {
          key: `event:${entry.source}:${suffix}`,
          title: `${entry.source}: ${suffix}`,
          failing: false,
          forMs: 0,
        },
        now,
      );
    }
}
