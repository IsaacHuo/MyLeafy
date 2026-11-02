import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { join, resolve } from "node:path";
import { MonitorStore } from "./monitoring/store";
import {
  type Environment,
  type MonitorKind,
  validateQuery,
  reportPeriod,
  hosts,
  jobKeys,
} from "./monitoring/model";
import { PrometheusClient } from "./monitoring/prometheus";
import {
  accessLogs,
  journalLogs,
  kernelLogs,
  serviceStatus,
  backupStatus,
  maintenanceStatus,
} from "./monitoring/sources";
import { observations, observeEvents, type Sample } from "./monitoring/alerts";
import { accessMetrics } from "./monitoring/metrics";
import { queueDailyReport, deliverMail } from "./monitoring/mail";

const environment = process.env.ENVIRONMENT as Environment;
if (!["production", "staging"].includes(environment))
  throw new Error("Invalid monitoring environment");
const token = process.env.MONITOR_TOKEN ?? "";
if (token.length < 32) throw new Error("MONITOR_TOKEN is required");
const directory = resolve(
  process.env.MONITOR_DIRECTORY ?? `/var/lib/myleafy-monitor/${environment}`,
);
const store = new MonitorStore(join(directory, "monitoring.sqlite"));
if (process.argv.includes("--report")) {
  queueDailyReport(store, environment);
  store.close();
} else {
  const prometheus = new PrometheusClient(environment),
    metrics = accessMetrics();
  const email = {
    enabled:
      environment === "production" &&
      process.env.MONITOR_EMAIL_ENABLED === "true",
    key: process.env.EMAIL_API_KEY,
    from: process.env.EMAIL_FROM,
    recipient: process.env.MONITOR_EMAIL_TO,
    dailyLimit: Math.min(
      10,
      Math.max(1, Number(process.env.MONITOR_EMAIL_DAILY_LIMIT) || 10),
    ),
  };
  let running = false,
    stopping = false,
    ticks = 0;
  async function tick() {
    if (running || stopping) return;
    running = true;
    const now = Date.now(),
      errors: string[] = [];
    const previousError = store.get("collectionError");
    store.set("collectionError", null);
    try {
      for (const [name, read] of [
        [
          "access",
          () =>
            accessLogs(
              store,
              environment,
              `/var/lib/caddy/myleafy-access/${environment}`,
            ),
        ],
        ["journal", () => journalLogs(store, environment)],
        ["kernel", () => kernelLogs(store, environment)],
      ] as const) {
        try {
          const entries = await read();
          for (const entry of entries) metrics.observe(entry);
          observeEvents(store, entries, now);
        } catch {
          errors.push(`${name}_collection_failed`);
        }
      }
      const values = await Promise.allSettled(
        ["cpu", "memory", "disk"].map((key) =>
          prometheus.instant(key as "cpu" | "memory" | "disk", now),
        ),
      );
      const metricValue = (index: number) => {
        const result = values[index];
        if (result.status === "fulfilled") return result.value;
        errors.push("metrics_unavailable");
        return null;
      };
      const sample: Sample = {
        timestamp: now,
        cpu: metricValue(0),
        memory: metricValue(1),
        disk: metricValue(2),
        services: {},
        backup: { successAt: null, failed: null },
        maintenanceUntil: null,
        collectionError: null,
      };
      const origins = {
        website: `https://${hosts[environment][0]}/`,
        api: `https://${hosts[environment][1 + (environment === "production" ? 1 : 0)]}/health`,
      };
      // Explicit origins only. Probes never follow redirects or send student credentials.
      await Promise.all(
        Object.entries(origins).map(async ([name, url]) => {
          const prior = store.get<Sample>("sample")?.services[name];
          let healthy = false;
          try {
            const response = await fetch(url, {
              redirect: "manual",
              signal: AbortSignal.timeout(5000),
              headers: { "User-Agent": "MyLeafy-Monitor/1" },
            });
            healthy = response.status === 200;
            await response.body?.cancel();
          } catch {}
          sample.services[name] = {
            healthy,
            failures: healthy ? 0 : (prior?.failures ?? 0) + 1,
            restarts: null,
          };
        }),
      );
      try {
        const services = await serviceStatus(environment);
        for (const service of services) {
          if (service.Id.startsWith("myleafy-backup")) continue;
          const key = service.Id,
            restarts = Number(service.NRestarts),
            prior = store.get<Sample>("sample")?.services[key],
            healthy = service.ActiveState === "active";
          sample.services[key] = {
            healthy,
            failures: healthy ? 0 : (prior?.failures ?? 0) + 1,
            restarts,
          };
          if (
            prior?.restarts !== null &&
            prior?.restarts !== undefined &&
            restarts > prior.restarts
          ) {
            const entry = {
              timestamp: now,
              source: key.includes("caddy") ? "caddy" : "application",
              level: "error" as const,
              event: "unexpected_exit",
            };
            store.ingest([entry]);
            observeEvents(store, [entry], now);
          }
        }
      } catch {
        errors.push("service_state_unavailable");
      }
      try {
        sample.backup = await backupStatus(environment);
      } catch {
        errors.push("backup_state_unavailable");
      }
      try {
        sample.maintenanceUntil = await maintenanceStatus(environment, now);
      } catch {
        errors.push("maintenance_state_unavailable");
      }
      // Snapshot is intentionally bounded and contains only task state, never user records.
      try {
        const response = await fetch(
          `http://127.0.0.1:${environment === "production" ? 3120 : 3121}/snapshot`,
          {
            headers: { Authorization: `Bearer ${token}` },
            signal: AbortSignal.timeout(3000),
          },
        );
        if (response.ok) {
          const snapshot = (await response.json()) as any;
          store.set("taskSnapshot", snapshot);
          const jobs = new Map<string, any>();
          for (const task of snapshot.tasks ?? [])
            if (!jobs.has(task.job)) jobs.set(task.job, task);
          for (const [job, task] of jobs)
            if (jobKeys[job])
              store.observe(
                {
                  key: `task:${jobKeys[job]}`,
                  title: `定时任务 ${jobKeys[job]} 执行失败`,
                  failing: task.status === "failed",
                  forMs: 0,
                },
                now,
              );
        } else {
          await response.body?.cancel();
          if (!sample.maintenanceUntil || sample.maintenanceUntil <= now)
            errors.push("task_snapshot_unavailable");
        }
      } catch {
        if (!sample.maintenanceUntil || sample.maintenanceUntil <= now)
          errors.push("task_snapshot_unavailable");
      }
      const previous = store.get<number>("lastCollection");
      if (previous && now - previous > 90_000)
        store.ingest([
          {
            timestamp: now,
            source: "monitor",
            event: "collection_gap",
            duration: (now-previous)/1000,
            level: "warning",
          },
        ]);
      sample.collectionError =
        [
          ...new Set([
            ...errors,
            ...(store.get("collectionError")
              ? [store.get<string>("collectionError")!]
              : []),
          ]),
        ].join(",") || null;
      if(sample.collectionError&&!previousError)store.set('collectionErrorSince',now);
      if(!sample.collectionError&&previousError){
        const since=store.get<number>('collectionErrorSince')??previous??now;
        store.ingest([{timestamp:now,source:'monitor',event:'collection_gap',duration:Math.max(0,(now-since)/1000),level:'warning'}]);
        store.set('collectionErrorSince',null);
      }
      store.set("sample", sample);
      store.set("lastCollection", now);
      store.set("collectionError", sample.collectionError);
      for (const observation of observations(store, sample))
        store.observe(observation, now);
      if (!sample.maintenanceUntil || sample.maintenanceUntil <= now) {
        for (const source of ["application", "caddy", "system"]) {
          const healthy =
            source === "caddy"
              ? sample.services["myleafy-caddy.service"]?.healthy
              : source === "system"
                ? sample.memory !== null && sample.memory < 85
                : sample.services[`myleafy@${environment}.service`]?.healthy;
          if (healthy)
            for (const row of store.db
              .prepare(
                "SELECT key,title FROM alerts WHERE key LIKE ? AND resolvedAt IS NULL",
              )
              .all(`event:${source}:%`) as any[])
              store.observe({ ...row, failing: false, forMs: 0 }, now);
        }
      }
      for (const event of store.db
        .prepare(
          "SELECT key,title FROM alerts WHERE recoveringAt IS NOT NULL AND resolvedAt IS NULL AND key LIKE 'event:%'",
        )
        .all() as any[])
        store.observe({ ...event, failing: false, forMs: 0 }, now);
      const period = reportPeriod(now + 86_400_000),
        peakKey = "dailyPeaks:" + period.key,
        peaks = store.get<Record<string, number>>(peakKey) ?? {};
      for (const key of ["cpu", "memory", "disk"] as const)
        if (sample[key] !== null)
          peaks[key] = Math.max(peaks[key] ?? 0, sample[key]!);
      store.set(peakKey, peaks);
      // Persistent timer enqueues the report; this also retries the most recent missed period.
      if (email.enabled) queueDailyReport(store, environment, now);
      await deliverMail(store, email, now);
      if (++ticks % 20 === 0) store.retain(now);
    } catch {
      store.set("collectionError", "monitor_cycle_failed");
    } finally {
      running = false;
    }
  }
  function authorized(value: string | undefined) {
    const expected = Buffer.from(`Bearer ${token}`),
      actual = Buffer.from(value ?? "");
    return (
      expected.length === actual.length && timingSafeEqual(expected, actual)
    );
  }
  const server = createServer(async (request, response) => {
    response.setHeader("Content-Type", "application/json");
    response.setHeader("Cache-Control", "no-store");
    try {
      if (request.url === "/metrics" && request.method === "GET") {
        response.setHeader("Content-Type", metrics.registry.contentType);
        response.end(await metrics.registry.metrics());
        return;
      }
      if (request.url === "/health" && request.method === "GET") {
        response.end(JSON.stringify(store.coverage()));
        return;
      }
      if (!authorized(request.headers.authorization)) {
        response.writeHead(401).end(JSON.stringify({ error: "unauthorized" }));
        return;
      }
      if (request.method !== "POST") {
        response.writeHead(405).end();
        return;
      }
      const kind = request.url?.replace(/^\/query\//, "") as MonitorKind;
      if (
        ![
          "overview",
          "series",
          "requests",
          "logs",
          "alerts",
          "reports",
        ].includes(kind)
      ) {
        response.writeHead(404).end();
        return;
      }
      let body = "";
      for await (const chunk of request) {
        body += chunk;
        if (body.length > 16_384) {
          response.writeHead(413).end();
          return;
        }
      }
      const params = JSON.parse(body || "{}");
      if (!params || typeof params !== "object" || Array.isArray(params))
        throw new Error("查询参数无效。");
      const range = validateQuery(kind, params);
      let data: unknown;
      if (kind === "overview")
        data = {
          environment,
          generatedAt: Date.now(),
          coverage: {
            ...store.coverage(),
            partial: range.start < Number(store.get("startedAt") ?? Date.now()),
          },
          sample: store.get("sample") ?? null,
          summary: store.summary(range.start, range.end),
          tasks: store.get("taskSnapshot") ?? null,
          alerts: store.db
            .prepare(
              "SELECT * FROM alerts WHERE resolvedAt IS NULL ORDER BY firstSeen DESC LIMIT 100",
            )
            .all(),
          mail: {
            enabled: email.enabled,
            error: store.get("mailError") ?? null,
            pending: (
              store.db
                .prepare(
                  "SELECT count(*) AS n FROM deliveries WHERE status='pending'",
                )
                .get() as any
            ).n,
          },
        };
      else if (kind === "series")
        data = await prometheus.series(
          String(params.metric ?? "requests"),
          range.start,
          range.end,
        );
      else if (kind === "requests" || kind === "logs")
        data = store.list(kind, params);
      else data = store.history(kind, params);
      response.end(JSON.stringify(data));
    } catch (error) {
      const message = error instanceof Error ? error.message : "";
      const validation =
        /时间范围|分页参数|筛选条件|耗时条件|未知指标|查询参数|筛选参数|JSON/.test(
          message,
        );
      response.writeHead(validation ? 400 : 503).end(
        JSON.stringify({
          error: validation ? message : "监控查询暂时不可用。",
        }),
      );
    }
  });
  server.listen(environment === "production" ? 3140 : 3141, "127.0.0.1", () => {
    void tick();
  });
  const timer = setInterval(() => {
    void tick();
  }, 30_000);
  for (const signal of ["SIGTERM", "SIGINT"])
    process.on(signal, () => {
      stopping = true;
      clearInterval(timer);
      server.close();
      const wait = setInterval(() => {
        if (!running) {
          clearInterval(wait);
          store.close();
        }
      }, 100);
      wait.unref();
    });
}
