import { type Observation, type LogEntry } from "./model";
import { type MonitorStore } from "./store";

export const httpLatencyCutoverKey = "httpLatencyExcludesUpgradesAt";

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

export function inMaintenance(
  sample: Pick<Sample, "timestamp" | "maintenanceUntil">,
) {
  return (
    sample.maintenanceUntil !== null && sample.maintenanceUntil > sample.timestamp
  );
}

export function healthFailures(
  name: string,
  healthy: boolean,
  sample: Pick<Sample, "timestamp" | "maintenanceUntil">,
  previous: Sample | undefined,
) {
  if (healthy || inMaintenance(sample)) return 0;
  const consecutive =
    previous &&
    !inMaintenance(previous) &&
    sample.timestamp - previous.timestamp <= 90_000;
  return (consecutive ? (previous.services[name]?.failures ?? 0) : 0) + 1;
}

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
  const maintaining = inMaintenance(sample);
  for (const [name, service] of Object.entries(sample.services)) {
    observations.push({
      key: `health:${name}`,
      title: `${name} 连续健康检查失败`,
      failing:
        maintaining || service.healthy === null
          ? null
          : service.healthy
            ? false
            : service.failures >= 3 ? true : null,
      forMs: 0,
      value: service.failures,
    });
  }
  const short = store.summary(sample.timestamp - 300_000, sample.timestamp),
    long = store.summary(sample.timestamp - 600_000, sample.timestamp);
  observations.push({
    key: "http-errors",
    title: "接口 5xx 比例超过 5%",
    failing: short.requests >= 100 ? (short.errorRate ?? 0) > 0.05 : null,
    forMs: 0,
    value: short.errorRate ?? undefined,
  });
  observations.push({
    key: "http-latency",
    title: "接口 P95 响应超过 2 秒",
    failing: long.latencySamples >= 100 && long.p95 !== null && long.p95 > 2,
    forMs: 0,
    value: long.p95 ?? undefined,
  });
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

export function retireLegacyLatencyAlerts(
  store: MonitorStore,
  now = Date.now(),
) {
  store.db.transaction(() => {
    if (store.get(httpLatencyCutoverKey) !== undefined) return;
    // Reassess any active incident using the corrected sample on the first tick.
    store.db
      .prepare(
        "UPDATE alerts SET resolvedAt=? WHERE key='http-latency' AND resolvedAt IS NULL",
      )
      .run(now);
    store.db
      .prepare(
        "UPDATE deliveries SET status='superseded',error='latency_definition_changed',leaseUntil=NULL WHERE status='pending' AND (id GLOB 'alert:http-latency:*' OR id GLOB 'recovery:http-latency:*')",
      )
      .run();
    store.set(httpLatencyCutoverKey, now);
  }).immediate();
}

export function observeEvents(
  store: MonitorStore,
  entries: LogEntry[],
  now = Date.now(),
) {
  const alertEvents = ["oom", "unexpected_exit", "backup_failed"];
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
    else if (alertEvents.includes(entry.event))
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
}

export function observeEventRecovery(
  store: MonitorStore,
  sample: Sample,
  environment: string,
) {
  const healthy: Record<string, boolean | null | undefined> = {
    application: sample.services[`myleafy@${environment}.service`]?.healthy,
    caddy: sample.services["myleafy-caddy.service"]?.healthy,
    system: sample.memory !== null && sample.memory < 85,
  };
  const active = store.db
    .prepare(
      "SELECT key,title FROM alerts WHERE key GLOB 'event:*' AND resolvedAt IS NULL",
    )
    .all() as Pick<Observation, "key" | "title">[];
  const maintaining = inMaintenance(sample);
  for (const event of active) {
    const source = event.key.split(":")[1];
    store.observe(
      {
        ...event,
        failing: !maintaining && healthy[source] === true ? false : null,
        forMs: 0,
      },
      sample.timestamp,
    );
  }
}
