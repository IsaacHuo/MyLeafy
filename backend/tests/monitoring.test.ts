import { describe, it, expect, afterEach, vi } from "vitest";
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
  renameSync,
  mkdirSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { MonitorStore } from "../src/monitoring/store";
import {
  normalizeLog,
  maskIP,
  parseRange,
  reportPeriod,
  day,
} from "../src/monitoring/model";
import { deliverMail, queueDailyReport } from "../src/monitoring/mail";
import {
  healthFailures,
  observations,
  observeEventRecovery,
  observeEvents,
  retireLegacyLatencyAlerts,
  type Sample,
} from "../src/monitoring/alerts";
import { accessLogs } from "../src/monitoring/sources";
import { metricQueries, PrometheusClient } from "../src/monitoring/prometheus";
import { adminMonitoring } from "../src/admin-monitoring";
import { readFileSync } from "node:fs";
import routeTemplates from "../src/monitoring/routes.json";
import { app } from "../src/index";

const now = Date.parse("2026-11-02T13:00:00Z"),
  cleanups: (() => void)[] = [];
function database() {
  const directory = mkdtempSync(join(tmpdir(), "myleafy-monitor-test-")),
    store = new MonitorStore(join(directory, "monitor.sqlite"));
  cleanups.push(() => {
    store.close();
    rmSync(directory, { recursive: true, force: true });
  });
  return { store, directory };
}
afterEach(() => {
  for (const cleanup of cleanups.splice(0)) cleanup();
  vi.restoreAllMocks();
});
const requestLog = (extra = {}) => ({
  ts: now / 1000,
  request: {
    host: "api.myleafy.space",
    method: "GET",
    uri: "/v1/admin-media?ticket=secret",
    remote_ip: "192.168.33.91",
    headers: { Authorization: "secret" },
  },
  route: "/v1/admin-media",
  duration: 0.5,
  size: 123,
  status: 200,
  ...extra,
});
const emptySample = (timestamp = now): Sample => ({
  timestamp,
  cpu: null,
  memory: null,
  disk: null,
  services: {},
  backup: { successAt: null, failed: null },
  maintenanceUntil: null,
  collectionError: null,
});
const testMail = {
  enabled: true,
  key: "test-key",
  from: "sender@example.com",
  recipient: "owner@example.com",
};
describe("monitoring privacy, range and sources", () => {
  it("keeps source log templates aligned and never persists raw path tokens", () => {
    const text = readFileSync(
      new URL("../deploy/Caddyfile.monitoring-routes", import.meta.url),
      "utf8",
    );
    const mapped = text
      .split("\n")
      .map((line) => line.trim().split(/\s+/))
      .filter(
        (row) =>
          row.length === 2 && (row[0].startsWith("~") || row[0] === "default"),
      )
      .map((row) => row[1]);
    expect(new Set(mapped)).toEqual(new Set(routeTemplates));
    const patterns = text
      .split("\n")
      .map((line) => line.trim().split(/\s+/))
      .filter((row) => row[0].startsWith("~"));
    const routeFor = (path: string) =>
      patterns.find((row) => new RegExp(row[0].slice(1)).test(path))?.[1] ??
      "/:unmatched";
    expect(routeFor("/v1/catalog/suggestions")).toBe("/v1/catalog/suggestions");
    expect(routeFor("/v1/catalog/cafes")).toBe("/v1/catalog/:kind");
    expect(routeFor("/v1/releases/android/latest")).toBe(
      "/v1/releases/android/latest",
    );
    expect(routeFor("/share/private-invite-token")).toBe("/share/*");
    for (const route of app.routes.filter((route) => route.method !== "ALL"))
      expect(routeTemplates).toContain(route.path);
    expect(
      normalizeLog(
        requestLog({ route: "/share/private-invite-token" }),
        "production",
      )?.route,
    ).toBe("/:unmatched");
    expect(
      normalizeLog(requestLog({ duration: undefined }), "production"),
    ).toBeNull();
  });
  it("projects only permitted fields and masks IPv4/IPv6 before indexing", () => {
    const entry = normalizeLog(requestLog(), "production");
    expect(entry?.ip).toBe("192.168.33.0/24");
    expect(JSON.stringify(entry)).not.toContain("secret");
    expect(entry?.route).toBe("/v1/admin-media");
    expect(maskIP("2001:db8:1234:abcd::1")).toBe("2001:db8:1234::/48");
    expect(maskIP("::1")).toBe("0:0:0::/48");
    expect(maskIP("not-an-ip")).toBeUndefined();
    expect(normalizeLog(requestLog(), "staging")).toBeNull();
    expect(
      normalizeLog(
        {
          event: "api_error",
          code: "internal_error",
          body: "student",
          password: "secret",
        },
        "production",
      ),
    ).not.toHaveProperty("body");
  });
  it("never indexes untrusted paths or arbitrary journal text", () => {
    expect(
      normalizeLog(
        requestLog({ route: "/share/invite?secret=token" }),
        "production",
      )?.route,
    ).toBe("/:unmatched");
    expect(
      normalizeLog({ MESSAGE: "private student content" }, "production"),
    ).toBeNull();
    expect(
      normalizeLog(
        requestLog({
          request: { host: "api.myleafy.space", method: "CUSTOM123" },
        }),
        "production",
      )?.method,
    ).toBe("OTHER");
  });
  it("rejects excessive and invalid ranges and pagination", () => {
    expect(() =>
      parseRange(
        {
          start: new Date(now - 15 * day).toISOString(),
          end: new Date(now).toISOString(),
        },
        now,
      ),
    ).toThrow();
    expect(() => parseRange({ pageSize: 1000 }, now)).toThrow();
    expect(() => parseRange({ page: -1 }, now)).toThrow();
    expect(() => parseRange({ start: "bad" }, now)).toThrow();
    expect(parseRange({}, now).end - now).toBe(0);
  });
  it("reads complete lines once across restart, partial writes and rotation", async () => {
    const { store, directory } = database(),
      file = join(directory, "access.log");
    writeFileSync(
      file,
      JSON.stringify(requestLog()) +
        "\n" +
        JSON.stringify(requestLog({ size: 321 })).slice(0, 20),
    );
    expect(await accessLogs(store, "production", directory)).toHaveLength(1);
    expect(await accessLogs(store, "production", directory)).toHaveLength(0);
    writeFileSync(
      file,
      JSON.stringify(requestLog()) +
        "\n" +
        JSON.stringify(requestLog({ size: 321 })) +
        "\n",
    );
    expect(await accessLogs(store, "production", directory)).toHaveLength(1);
    renameSync(file, join(directory, "access-rotation.log"));
    writeFileSync(file, JSON.stringify(requestLog({ size: 456 })) + "\n");
    expect(await accessLogs(store, "production", directory)).toHaveLength(1);
    expect(store.summary(now - 1, now + 1).bytes).toBe(900);
  });
  it("applies filters in SQL and never treats injection as a query", () => {
    const { store } = database();
    store.ingest([normalizeLog(requestLog(), "production")!]);
    expect(
      store.list("requests", { route: "' OR 1=1 --" }, now + 1).total,
    ).toBe(0);
    expect(store.list("requests", { status: 200 }, now + 1).total).toBe(1);
    expect(() => store.list("requests", { minDuration: "NaN" }, now)).toThrow();
  });
  it("removes expired records and reports actual coverage", () => {
    const { store } = database();
    store.ingest([
      {
        timestamp: now - 8 * day,
        source: "application",
        level: "error",
        event: "api_error",
      },
      {
        timestamp: now - 1000,
        source: "application",
        level: "info",
        event: "listening",
      },
    ]);
    store.retain(now);
    expect(
      (store.db.prepare("SELECT count(*) AS n FROM logs").get() as any).n,
    ).toBe(1);
    expect(store.coverage(now).stale).toBe(true);
    store.set("lastCollection", now);
    expect(store.coverage(now).stale).toBe(false);
  });
  it("bounds each log database and removes oldest records when capacity is reached", () => {
    const { store } = database();
    const bytes =
      Number(store.db.pragma("page_size", { simple: true })) *
      Number(store.db.pragma("max_page_count", { simple: true }));
    expect(bytes).toBeLessThanOrEqual(100 * 1024 * 1024);
    store.ingest(
      Array.from({ length: 4000 }, (_, index) => ({
        timestamp: now - 4000 + index,
        source: "access",
        level: "info" as const,
        event: "request",
        route: "/v1/community/posts/:id",
        requestId: "test-" + index,
        bytes: 100,
        duration: 0.1,
        status: 200,
      })),
    );
    store.retain(now, 512 * 1024);
    const rows = store.db
      .prepare(
        "SELECT count(*) n,min(timestamp) oldest,max(timestamp) newest FROM logs",
      )
      .get() as any;
    expect(rows.n).toBeLessThan(4000);
    expect(rows.oldest).toBeGreaterThan(now - 4000);
    expect(rows.newest).toBe(now - 1);
    expect(store.coverage(now).capacityLimited).toBe(true);
  });
  it("only permits predefined metric queries and handles empty/NaN as missing", async () => {
    const request = vi.fn(async () =>
      Response.json({
        status: "success",
        data: { result: [{ value: [now / 1000, "NaN"] }] },
      }),
    ) as unknown as typeof fetch;
    const client = new PrometheusClient("staging", request);
    expect(await client.instant("cpu", now)).toBeNull();
    await expect(
      client.series("arbitrary PromQL", now - day, now),
    ).rejects.toThrow();
    expect(request).toHaveBeenCalledTimes(1);
  });
});
describe("alert lifecycle and mail ledger", () => {
  it("keeps repeated application rejections, cancellations and an isolated 5xx as diagnostics", () => {
    const { store } = database();
    const rejection = normalizeLog({
      source: "application", event: "api_error", status: 403,
      code: "invalid_ticket", request_id: "rejected-download", timestamp: now - 1000,
    }, "production")!;
    expect(rejection).toMatchObject({ level: "info", status: 403, code: "invalid_ticket" });
    const rejectedRequest = normalizeLog(requestLog({
      ts: (now - 1000) / 1000, route: "/v1/files/download", status: 403,
    }), "production")!;
    const cancellation = { ...rejectedRequest, status: 499 };
    const serverError = normalizeLog({
      source: "application", event: "api_error", status: 500,
      code: "internal_error", timestamp: now - 1000,
    }, "production")!;
    const entries = [
      ...Array(105).fill(rejectedRequest), ...Array(105).fill(rejection),
      { ...rejection, level: "error" as const }, // Stored before the new classification.
      cancellation, serverError, { ...rejectedRequest, status: 500, level: "error" as const },
    ];
    store.ingest(entries);
    observeEvents(store, entries, now);
    for (const entry of observations(store, emptySample())) store.observe(entry, now);
    expect(store.db.prepare("SELECT * FROM alerts").all()).toHaveLength(0);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    expect(store.list("logs", { code: "invalid_ticket" }, now).total).toBe(106);
    expect(store.list("requests", { status: 499 }, now).total).toBe(1);
    const id = queueDailyReport(store, "production", now);
    const { summary } = store.db.prepare("SELECT summary FROM reports WHERE id=?").get(id) as { summary: string };
    expect(JSON.parse(summary)).toMatchObject({ errors: 1, alerts: [] });
    expect(summary).toContain("internal_error");
    expect(summary).not.toContain("invalid_ticket");
  });

  it("emails on the existing 5xx rate threshold and waits for a known recovery window", () => {
    const { store } = database();
    const sample = emptySample();
    const access = normalizeLog(requestLog({
      ts: (now - 1000) / 1000, route: "/v1/files/download",
    }), "production")!;
    const check = (timestamp = now) => {
      const rate = observations(store, { ...sample, timestamp }).find((entry) => entry.key === "http-errors")!;
      store.observe(rate, timestamp);
      return rate.failing;
    };
    store.ingest([...Array(95).fill(access), ...Array(5).fill({ ...access, status: 500 })]);
    expect(check()).toBe(false);
    store.ingest([{ ...access, status: 502 }]);
    expect(check()).toBe(true);
    expect(check(now + 300_000)).toBeNull();
    expect(store.db.prepare("SELECT id,status FROM deliveries").all()).toEqual([
      { id: `alert:http-errors:${now}:0`, status: "pending" },
    ]);
    expect(store.db.prepare("SELECT recoveringAt FROM alerts").get()).toEqual({ recoveringAt: null });
  });

  it("requires three consecutive bad probes outside maintenance and restarts the count after a gap", () => {
    const { store } = database();
    let previous: Sample | undefined;
    const check = (offset: number, maintenanceUntil: number | null, healthy = false) => {
      const sample = { ...emptySample(now + offset), maintenanceUntil };
      const failures = healthFailures("api", healthy, sample, previous);
      sample.services.api = { healthy, failures, restarts: null };
      previous = sample;
      const observation = observations(store, sample).find((entry) => entry.key === "health:api")!;
      store.observe(observation, sample.timestamp);
      return failures;
    };
    expect(check(0, null)).toBe(1);
    expect(check(30_000, now + 100_000)).toBe(0);
    expect(check(60_000, now + 100_000)).toBe(0);
    expect(check(120_000, null)).toBe(1);
    expect(check(240_000, null)).toBe(1);
    expect(check(270_000, null)).toBe(2);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    expect(check(300_000, null)).toBe(3);
    expect(store.db.prepare("SELECT id FROM deliveries").all()).toEqual([
      { id: `alert:health:api:${now + 300_000}:0` },
    ]);
    expect(check(330_000, null, true)).toBe(0);
    expect(check(360_000, null)).toBe(1);
    expect(store.db.prepare("SELECT recoveringAt FROM alerts").get()).toEqual({ recoveringAt: null });
  });

  it("emails resource and process emergencies while keeping single task and backup failures in the dashboard", () => {
    const { store } = database();
    const sample: Sample = {
      ...emptySample(), disk: 96,
      backup: { successAt: now - 27 * 3_600_000, failed: true },
    };
    observeEvents(store, [
      { timestamp: now, source: "system", event: "oom", level: "error" },
      { timestamp: now, source: "caddy", event: "unexpected_exit", level: "error" },
      { timestamp: now, source: "application", event: "unexpected_exit", level: "error" },
      { timestamp: now, source: "application", event: "scheduled_job_failed", code: "media", level: "error" },
    ], now);
    for (const entry of observations(store, sample)) store.observe(entry, now);
    expect(store.db.prepare("SELECT id FROM deliveries ORDER BY id").all().map((row: any) => row.id)).toEqual([
      `alert:backup-expired:${now}:0`, `alert:disk-critical:${now}:0`,
      `alert:event:application:unexpected_exit:${now}:0`,
      `alert:event:caddy:unexpected_exit:${now}:0`, `alert:event:system:oom:${now}:0`,
    ]);
    for (const key of ["backup-failed", "task:media"]) {
      expect(store.db.prepare("SELECT confirmedAt FROM alerts WHERE key=?").get(key)).toEqual({ confirmedAt: now });
    }
    const caddy = { healthy: true, failures: 0, restarts: 1 };
    const eventSample = { ...sample, services: { "myleafy-caddy.service": caddy } };
    observeEventRecovery(store, { ...eventSample, timestamp: now + 30_000 }, "production");
    observeEventRecovery(store, { ...eventSample, timestamp: now + 60_000, maintenanceUntil: now + 90_000 }, "production");
    expect(store.db.prepare("SELECT recoveringAt FROM alerts WHERE key='event:caddy:unexpected_exit'").get()).toEqual({ recoveringAt: null });
  });

  it.each(["accepted", "waiting", "failed"])("pairs recovery only with an accepted alert across a restart (%s)", async (outcome) => {
    const { store, directory } = database();
    const rule = { key: "health:api", title: "API", failing: true, forMs: 0 };
    const incidentId = `health:api:${now}`;
    const request = vi.fn(async () => outcome === "failed"
      ? Response.json({}, { status: 400 })
      : Response.json({ id: "provider-alert" }));
    store.observe(rule, now);
    if (outcome !== "waiting") await deliverMail(store, testMail, now, request);
    const reopened = new MonitorStore(join(directory, "monitor.sqlite"));
    try {
      reopened.observe(rule, now + 3_600_000);
      for (let offset = 30_000; offset <= 330_000; offset += 30_000)
        reopened.observe({ ...rule, failing: false }, now + 3_600_000 + offset);
      expect(reopened.db.prepare("SELECT id,status FROM deliveries ORDER BY id").all()).toEqual([
        { id: `alert:${incidentId}:0`, status: outcome === "accepted" ? "sent" : outcome === "waiting" ? "superseded" : "failed" },
        ...(outcome === "accepted" ? [{ id: `recovery:${incidentId}`, status: "pending" }] : []),
      ]);
      if (outcome === "accepted") {
        await deliverMail(reopened, testMail, now + 4_000_000, async () => Response.json({ id: "provider-recovery" }));
        expect(reopened.history("alerts", {}, now + 4_000_000).items[0]).toMatchObject({
          confirmedAt: now,
          notificationPolicy: "email",
          notification: { status: "sent", providerId: "provider-alert" },
          recoveryNotification: { status: "sent", providerId: "provider-recovery" },
        });
      }
    } finally {
      reopened.close();
    }
  });

  it("preserves the accepted receipt of a still-open alert through retention", async () => {
    const { store } = database();
    const rule = { key: "disk-critical", title: "Disk", failing: true, forMs: 0 };
    store.observe(rule, now);
    await deliverMail(store, testMail, now, async () => Response.json({ id: "provider-alert" }));
    store.observe(rule, now + 31 * day);
    store.retain(now + 31 * day);
    expect(store.db.prepare("SELECT status FROM deliveries").all()).toEqual([{ status: "sent" }]);
    for (let offset = 30_000; offset <= 330_000; offset += 30_000)
      store.observe({ ...rule, failing: false }, now + 31 * day + offset);
    expect(store.db.prepare("SELECT status FROM deliveries WHERE kind='recovery'").get()).toEqual({ status: "pending" });
  });

  it("upgrades an old monitoring database and retires only obsolete pending mail", () => {
    const { store, directory } = database();
    const observe = (key: string) => {
      store.observe({ key, title: key, failing: true, forMs: 0 }, now);
      return `${key}:${now}`;
    };
    const obsolete = observe("repeated:application:api_error:invalid_ticket");
    const dashboard = observe("backup-failed");
    const active = observe("health:api");
    const delivered = observe("disk-critical");
    const resolved = observe("health:website");
    const orphan = observe("backup-expired");
    for (const key of [obsolete, dashboard])
      store.enqueue(`alert:${key}:0`, "alert", "Old alert", "", now);
    for (const key of [obsolete, active, delivered])
      store.enqueue(`alert:${key}:1`, "alert", "Old reminder", "", now + 500);
    for (const key of [obsolete, delivered, resolved])
      store.db.prepare("UPDATE deliveries SET status='sent',providerId='old-receipt' WHERE id=?").run(`alert:${key}:0`);
    for (const key of [resolved, orphan])
      store.db.prepare("UPDATE alerts SET resolvedAt=? WHERE id=?").run(now + 500, key);
    for (const key of [obsolete, resolved, orphan])
      store.enqueue(`recovery:${key}`, "recovery", "Old recovery", "", now + 500);
    store.enqueue("report:production:old", "report", "Report", "", now);
    store.db.exec("ALTER TABLE alerts DROP COLUMN confirmedAt");

    const reopened = new MonitorStore(join(directory, "monitor.sqlite"));
    try {
      const cutover = now + 1000;
      reopened.retireLegacyAlertNotifications(cutover);
      const pending = () => reopened.db.prepare("SELECT id FROM deliveries WHERE status='pending' ORDER BY id").all();
      expect(pending()).toEqual([
        { id: `alert:${active}:1` }, { id: `recovery:${resolved}` }, { id: "report:production:old" },
      ]);
      const old = reopened.history("alerts", {}, now + 2000).items.find((row) => row.id === obsolete);
      expect(old).toMatchObject({
        resolvedAt: cutover, policyRetired: true,
        notification: { status: "sent", providerId: "old-receipt" },
        recoveryNotification: { status: "superseded", error: "alert_email_policy_changed" },
      });
      expect(reopened.history("alerts", {}, now + 2000).items.find((row) => row.id === active)).toMatchObject({ confirmedAt: now });
      reopened.observe({ key: "health:api", title: "API", failing: true, forMs: 0 }, now + 3_600_000);
      reopened.retireLegacyAlertNotifications(now + 3_600_000);
      expect(pending()).toHaveLength(3);
      expect(reopened.db.prepare("SELECT resolvedAt FROM alerts WHERE id=?").get(obsolete)).toEqual({ resolvedAt: cutover });
    } finally {
      reopened.close();
    }
  });

  it("excludes WebSocket lifetimes from reported HTTP latency and the alert sample minimum", () => {
    const { store } = database();
    const sample: Sample = {
      timestamp: now,
      cpu: null,
      memory: null,
      disk: null,
      services: {},
      backup: { successAt: null, failed: null },
      maintenanceUntil: null,
      collectionError: null,
    };
    const websocket = normalizeLog(
      requestLog({
        ts: (now - 1_000) / 1000,
        route: "/v1/events/:scope",
        status: 101,
        duration: 300,
      }),
      "production",
    )!;
    const http = { ...websocket, route: "/v1/community/feed", status: 200 };
    const observeLatency = (timestamp = now) => {
      const observation = observations(store, { ...sample, timestamp }).find(
        (entry) => entry.key === "http-latency",
      )!;
      store.observe(observation, timestamp);
      return observation;
    };
    store.ingest(Array(15).fill(websocket));
    expect(store.summary(now - day, now).p95).toBeNull();
    store.ingest(Array(99).fill({ ...http, duration: 0.012 }));
    expect(store.summary(now - day, now)).toMatchObject({
      requests: 114,
      latencySamples: 99,
      p50: 0.012,
      p95: 0.012,
      p99: 0.012,
      errors: 0,
    });
    expect(observeLatency().failing).toBe(false);

    const nextWindow = now + 600_000;
    const slowHttp = { ...http, timestamp: nextWindow - 1_000, duration: 3 };
    store.ingest([
      { ...websocket, timestamp: slowHttp.timestamp },
      ...Array(99).fill(slowHttp),
    ]);
    expect(observeLatency(nextWindow)).toMatchObject({ failing: false, value: 3 });
    store.ingest([{ ...slowHttp, status: 500 }]);
    expect(observeLatency(nextWindow)).toMatchObject({ failing: true, value: 3 });
    expect(store.db.prepare("SELECT confirmedAt FROM alerts").get()).toEqual({
      confirmedAt: nextWindow,
    });
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    expect(store.summary(now, nextWindow).errors).toBe(1);

    const queries = metricQueries("production");
    for (const query of [queries.p50, queries.p95, queries.p99])
      expect(query).toContain('status!="101"');
  });
  it("retires legacy latency alerts once and leaves them out of new mail", () => {
    const { store } = database();
    const rule = {
      key: "http-latency",
      title: "Latency",
      failing: true,
      forMs: 0,
    };
    store.observe(rule, now);
    store.enqueue(`alert:http-latency:${now}:0`, "alert", "Latency", "", now);
    store.enqueue("recovery:http-latency:old", "recovery", "Latency", "", now);
    store.enqueue("report:production:old", "report", "Report", "", now);
    retireLegacyLatencyAlerts(store, now + 1_000);
    expect(
      store.db.prepare("SELECT resolvedAt FROM alerts").get(),
    ).toEqual({ resolvedAt: now + 1_000 });
    expect(
      store.db.prepare("SELECT kind,status FROM deliveries ORDER BY kind").all(),
    ).toEqual([
      { kind: "alert", status: "superseded" },
      { kind: "recovery", status: "superseded" },
      { kind: "report", status: "pending" },
    ]);
    store.observe(rule, now + 2_000);
    retireLegacyLatencyAlerts(store, now + 3_000);
    expect(
      store.db
        .prepare("SELECT firstSeen FROM alerts WHERE resolvedAt IS NULL")
        .get(),
    ).toEqual({ firstSeen: now + 2_000 });
    expect(
      store.db
        .prepare("SELECT status FROM deliveries WHERE id=?")
        .get(`alert:http-latency:${now + 2_000}:0`),
    ).toBeUndefined();
    const report = queueDailyReport(store, "production", now + day);
    const { summary } = store.db
      .prepare("SELECT summary FROM reports WHERE id=?")
      .get(report) as { summary: string };
    expect(JSON.parse(summary).alerts).toEqual([
      { title: rule.title, firstSeen: now + 2_000, resolvedAt: null },
    ]);
  });
  it("marks a report incomplete when a later restart reveals a gap covering its whole period", () => {
    const { store } = database();
    store.set("startedAt", now - 3 * day);
    store.set("lastCollection", now);
    store.set("collectionError", null);
    store.ingest([
      {
        timestamp: now + 30_000,
        source: "monitor",
        event: "collection_gap",
        level: "warning",
        duration: (2 * day) / 1000,
      },
    ]);
    queueDailyReport(store, "production", now);
    expect(
      JSON.parse(
        (store.db.prepare("SELECT summary FROM reports").get() as any).summary,
      ).complete,
    ).toBe(false);
  });
  it("requires continuous observations for both firing and recovery after an unknown interval", () => {
    const { store } = database(),
      rule = { key: "health:api", title: "API", failing: true, forMs: 120_000 };
    store.observe(rule, now);
    store.observe(rule, now + 30_000);
    store.observe({ ...rule, failing: null }, now + 60_000);
    for (let offset = 90_000; offset < 210_000; offset += 30_000)
      store.observe(rule, now + offset);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    store.observe(rule, now + 210_000);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(1);
    store.db.prepare("UPDATE deliveries SET status='sent'").run();
    store.observe({ ...rule, failing: false }, now + 240_000);
    store.observe({ ...rule, failing: null }, now + 270_000);
    for (let offset = 300_000; offset < 600_000; offset += 30_000)
      store.observe({ ...rule, failing: false }, now + offset);
    expect(
      store.db.prepare("SELECT * FROM deliveries WHERE kind='recovery'").all(),
    ).toHaveLength(0);
    store.observe({ ...rule, failing: false }, now + 600_000);
    expect(
      store.db.prepare("SELECT * FROM deliveries WHERE kind='recovery'").all(),
    ).toHaveLength(1);
  });
  it("reserves a mail slot for the nightly report when alerts reach the daily budget", async () => {
    const { store } = database();
    store.enqueue("sent-alert", "alert", "test", "test", now);
    store.db
      .prepare("UPDATE deliveries SET status='sent' WHERE id='sent-alert'")
      .run();
    store.enqueue("pending-alert", "alert", "test", "test", now);
    const request = vi.fn(async () =>
      Response.json({ id: "report-provider-id" }),
    );
    const settings = {
      enabled: true,
      key: "private",
      recipient: "owner@example.com",
      from: "sender",
      dailyLimit: 2,
    };
    await deliverMail(store, settings, now, request as unknown as typeof fetch);
    expect(request).not.toHaveBeenCalled();
    store.enqueue("nightly-report", "report", "report", "test", now);
    await deliverMail(
      store,
      settings,
      now + 1000,
      request as unknown as typeof fetch,
    );
    expect(request).toHaveBeenCalledTimes(1);
    expect(
      (
        store.db
          .prepare("SELECT status FROM deliveries WHERE id='nightly-report'")
          .get() as any
      ).status,
    ).toBe("sent");
  });
  it("persists debounce, deduplication, unknown-state and recovery across stores", () => {
    const { store } = database(),
      observation = { key: "cpu", title: "CPU", failing: true, forMs: 600_000 };
    for (let offset = 0; offset < 600_000; offset += 30_000)
      store.observe(observation, now + offset);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    store.observe(observation, now + 600_000);
    store.observe(observation, now + 630_000);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    expect(store.db.prepare("SELECT confirmedAt,lastNotified FROM alerts").get()).toEqual({
      confirmedAt: now + 600_000, lastNotified: null,
    });
    store.observe({ ...observation, failing: null }, now + 900_000);
    expect(
      (store.db.prepare("SELECT * FROM alerts").get() as any).recoveringAt,
    ).toBeNull();
    for (let offset = 1_000_000; offset <= 1_300_000; offset += 30_000)
      store.observe({ ...observation, failing: false }, now + offset);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    store.observe(observation, now + 2_000_000);
    expect(store.db.prepare("SELECT * FROM alerts").all()).toHaveLength(2);
  });
  it("does not infer recovery from missing host metrics or a maintenance window", () => {
    const { store } = database();
    const sample: Sample = {
      timestamp: now,
      cpu: null,
      memory: null,
      disk: null,
      services: { api: { healthy: false, failures: 3, restarts: null } },
      backup: { successAt: null, failed: null },
      maintenanceUntil: now + 60_000,
      collectionError: null,
    };
    const values = observations(store, sample);
    expect(values.find((x) => x.key === "cpu")?.failing).toBeNull();
    expect(values.find((x) => x.key === "health:api")?.failing).toBeNull();
    expect(values.find((x) => x.key === "backup-expired")?.failing).toBeNull();
    expect(
      observations(store, { ...sample, maintenanceUntil: null }).find(
        (x) => x.key === "health:api",
      )?.failing,
    ).toBe(true);
  });
  it("uses Shanghai 21:00 boundaries and queues the latest missed daily report once", () => {
    expect(reportPeriod(now - 1).end).toBe(now - day);
    expect(reportPeriod(now).end).toBe(now);
    const { store } = database();
    queueDailyReport(store, "production", now);
    queueDailyReport(store, "production", now + 3_600_000);
    expect(store.db.prepare("SELECT * FROM reports").all()).toHaveLength(1);
    expect(
      (store.db.prepare("SELECT summary FROM reports").get() as any).summary,
    ).toContain('"complete":false');
  });
  it("retries a timeout with the same provider idempotency key and fixed recipient", async () => {
    const { store } = database();
    store.enqueue("test:1", "alert", "test", "redacted", now);
    const failed = vi.fn(async () => {
      throw new Error("secret network details");
    });
    await deliverMail(
      store,
      {
        enabled: true,
        key: "private",
        recipient: "owner@example.com",
        from: "monitor@example.com",
      },
      now,
      failed as unknown as typeof fetch,
    );
    let row = store.db.prepare("SELECT * FROM deliveries").get() as any;
    expect(row.status).toBe("pending");
    expect(row.error).toBe("email_transport_failed");
    const sent = vi.fn(async () => Response.json({ id: "provider-id" }));
    await deliverMail(
      store,
      {
        enabled: true,
        key: "private",
        recipient: "owner@example.com",
        from: "monitor@example.com",
      },
      row.nextAttempt,
      sent as unknown as typeof fetch,
    );
    expect(JSON.parse((sent.mock.calls as any)[0][1].body).to).toEqual([
      "owner@example.com",
    ]);
    expect((sent.mock.calls as any)[0][1].headers["Idempotency-Key"]).toBe(
      (failed.mock.calls as any)[0][1].headers["Idempotency-Key"],
    );
    await deliverMail(
      store,
      {
        enabled: true,
        key: "private",
        recipient: "owner@example.com",
        from: "monitor@example.com",
      },
      row.nextAttempt + 1000,
      sent as unknown as typeof fetch,
    );
    expect(sent).toHaveBeenCalledTimes(1);
  });
  it("respects disabled staging mail, daily budget and permanent failures", async () => {
    const { store } = database();
    store.enqueue("test:1", "alert", "test", "redacted", now);
    const send = vi.fn(async () =>
      Response.json({ message: "private provider detail" }, { status: 401 }),
    );
    await deliverMail(
      store,
      {
        enabled: false,
        key: "private",
        recipient: "owner@example.com",
        from: "sender",
      },
      now,
      send as unknown as typeof fetch,
    );
    expect(send).not.toHaveBeenCalled();
    await deliverMail(
      store,
      {
        enabled: true,
        key: "private",
        recipient: "owner@example.com",
        from: "sender",
      },
      now,
      send as unknown as typeof fetch,
    );
    expect(
      (store.db.prepare("SELECT status FROM deliveries").get() as any).status,
    ).toBe("failed");
    store.enqueue("test:2", "alert", "test", "redacted", now);
    store.db
      .prepare(
        "UPDATE deliveries SET status='sent',nextAttempt=? WHERE id='test:1'",
      )
      .run(now);
    await deliverMail(
      store,
      {
        enabled: true,
        key: "private",
        recipient: "owner@example.com",
        from: "sender",
        dailyLimit: 1,
      },
      now,
      send as unknown as typeof fetch,
    );
    expect(send).toHaveBeenCalledTimes(1);
    expect(store.get("mailError")).toBe("monitor_daily_budget_reached");
  });
  it("rejects non-super-admin monitoring access before any private fetch", async () => {
    const request = vi.spyOn(globalThis, "fetch");
    await expect(
      adminMonitoring(
        {} as any,
        { role: "viewer" } as any,
        "monitoringOverview",
        {},
      ),
    ).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
  });
});
