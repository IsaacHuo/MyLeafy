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
import { observations, type Sample } from "../src/monitoring/alerts";
import { accessLogs } from "../src/monitoring/sources";
import { PrometheusClient } from "../src/monitoring/prometheus";
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
  it('marks a report incomplete when a later restart reveals a gap covering its whole period',()=>{
    const {store}=database();store.set('startedAt',now-3*day);store.set('lastCollection',now);store.set('collectionError',null);
    store.ingest([{timestamp:now+30_000,source:'monitor',event:'collection_gap',level:'warning',duration:2*day/1000}]);
    queueDailyReport(store,'production',now);
    expect(JSON.parse((store.db.prepare('SELECT summary FROM reports').get() as any).summary).complete).toBe(false);
  });
  it("requires continuous observations for both firing and recovery after an unknown interval", () => {
    const { store } = database(),
      rule = { key: "memory", title: "Memory", failing: true, forMs: 120_000 };
    store.observe(rule, now);
    store.observe(rule, now + 30_000);
    store.observe({ ...rule, failing: null }, now + 60_000);
    for (let offset = 90_000; offset < 210_000; offset += 30_000)
      store.observe(rule, now + offset);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(0);
    store.observe(rule, now + 210_000);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(1);
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
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(1);
    store.observe({ ...observation, failing: null }, now + 900_000);
    expect(
      (store.db.prepare("SELECT * FROM alerts").get() as any).recoveringAt,
    ).toBeNull();
    for (let offset = 1_000_000; offset <= 1_300_000; offset += 30_000)
      store.observe({ ...observation, failing: false }, now + offset);
    expect(store.db.prepare("SELECT * FROM deliveries").all()).toHaveLength(2);
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
