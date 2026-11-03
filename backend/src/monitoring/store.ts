import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { day, parseRange, type LogEntry, type Observation } from "./model";

type Row = Record<string, any>;
export class MonitorStore {
  readonly db: Database.Database;
  constructor(path: string) {
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    this.db = new Database(path);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("busy_timeout = 3000");
    // Two environments share the 512 MiB log budget with Caddy's 128 MiB each.
    const pageSize = Number(this.db.pragma("page_size", { simple: true }));
    this.db.pragma(
      `max_page_count = ${Math.floor((100 * 1024 * 1024) / pageSize)}`,
    );
    this.db.pragma("journal_size_limit = 8388608");
    this.db.pragma("auto_vacuum = INCREMENTAL");
    this.db
      .exec(`CREATE TABLE IF NOT EXISTS logs(id INTEGER PRIMARY KEY, timestamp INTEGER NOT NULL, source TEXT NOT NULL, level TEXT NOT NULL, event TEXT NOT NULL, host TEXT, method TEXT, route TEXT, status INTEGER, duration REAL, bytes INTEGER, ip TEXT, requestId TEXT, code TEXT);
      CREATE INDEX IF NOT EXISTS logs_time ON logs(timestamp,id);
      CREATE INDEX IF NOT EXISTS logs_source_time ON logs(source,timestamp);
      CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS alerts(id TEXT PRIMARY KEY,key TEXT NOT NULL,title TEXT NOT NULL,firstSeen INTEGER NOT NULL,lastSeen INTEGER NOT NULL,resolvedAt INTEGER,recoveringAt INTEGER,lastNotified INTEGER,value REAL,conditionSince INTEGER,lastCheck INTEGER NOT NULL);
      CREATE UNIQUE INDEX IF NOT EXISTS alert_active_key ON alerts(key) WHERE resolvedAt IS NULL;
      CREATE TABLE IF NOT EXISTS deliveries(id TEXT PRIMARY KEY,kind TEXT NOT NULL,createdAt INTEGER NOT NULL,subject TEXT NOT NULL,body TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,nextAttempt INTEGER NOT NULL,providerId TEXT,error TEXT,leaseUntil INTEGER);
      CREATE INDEX IF NOT EXISTS delivery_due ON deliveries(status,nextAttempt);
      CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,start INTEGER NOT NULL,end INTEGER NOT NULL,createdAt INTEGER NOT NULL,summary TEXT NOT NULL,deliveryId TEXT NOT NULL);`);
    if (!this.get("startedAt")) this.set("startedAt", Date.now());
  }
  get<T = any>(key: string): T | undefined {
    const row = this.db
      .prepare("SELECT value FROM state WHERE key=?")
      .get(key) as Row | undefined;
    return row ? JSON.parse(row.value) : undefined;
  }
  set(key: string, value: unknown) {
    this.db
      .prepare(
        "INSERT INTO state(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      )
      .run(key, JSON.stringify(value));
  }
  ingest(entries: LogEntry[], cursor?: { key: string; value: unknown }) {
    this.db.transaction(() => {
      const insert = this.db.prepare(
        "INSERT INTO logs(timestamp,source,level,event,host,method,route,status,duration,bytes,ip,requestId,code) VALUES(@timestamp,@source,@level,@event,@host,@method,@route,@status,@duration,@bytes,@ip,@requestId,@code)",
      );
      for (const entry of entries)
        insert.run({
          host: null,
          method: null,
          route: null,
          status: null,
          duration: null,
          bytes: null,
          ip: null,
          requestId: null,
          code: null,
          ...entry,
        });
      if (cursor) this.set(cursor.key, cursor.value);
    })();
  }
  list(kind: "requests" | "logs", params: Row, now = Date.now()) {
    const range = parseRange(params, now),
      clauses = [
        "timestamp>=?",
        "timestamp<?",
        kind === "requests" ? "source='access'" : "source<>'access'",
      ],
      values: (string | number)[] = [range.start, range.end];
    for (const field of kind === "requests"
      ? ["host", "method", "route", "status", "requestId"]
      : ["source", "level", "event", "code", "requestId"]) {
      if (params[field] !== undefined && params[field] !== "") {
        if (String(params[field]).length > 150)
          throw new Error("筛选条件过长。");
        clauses.push(`${field}=?`);
        values.push(String(params[field]));
      }
    }
    if (params.minDuration !== undefined && params.minDuration !== "") {
      const value = Number(params.minDuration);
      if (!Number.isFinite(value) || value < 0 || value > 3600)
        throw new Error("耗时条件无效。");
      clauses.push("duration>=?");
      values.push(value);
    }
    const where = clauses.join(" AND ");
    return {
      items: this.db
        .prepare(
          `SELECT * FROM logs WHERE ${where} ORDER BY timestamp DESC,id DESC LIMIT ? OFFSET ?`,
        )
        .all(...values, range.pageSize, range.page * range.pageSize),
      total: (
        this.db
          .prepare(`SELECT count(*) AS n FROM logs WHERE ${where}`)
          .get(...values) as Row
      ).n,
      ...range,
    };
  }
  summary(start: number, end: number) {
    const stats = this.db
      .prepare(
        "SELECT count(*) AS requests,coalesce(sum(bytes),0) AS bytes,coalesce(sum(status>=500),0) AS errors,avg(duration) AS meanDuration FROM logs WHERE source='access' AND timestamp>=? AND timestamp<? AND route NOT IN('/health','/release.json') AND route NOT LIKE '/api/admin/%'",
      )
      .get(start, end) as {
      requests: number;
      bytes: number;
      errors: number;
      meanDuration: number | null;
    };
    const percentile = (p: number) => {
      if (!stats.requests) return null;
      return (
        (
          this.db
            .prepare(
              "SELECT duration FROM logs WHERE source='access' AND timestamp>=? AND timestamp<? AND route NOT IN('/health','/release.json') AND route NOT LIKE '/api/admin/%' ORDER BY duration LIMIT 1 OFFSET ?",
            )
            .get(start, end, Math.floor((stats.requests - 1) * p)) as Row
        )?.duration ?? null
      );
    };
    return {
      ...stats,
      errorRate: stats.requests ? stats.errors / stats.requests : null,
      p50: percentile(0.5),
      p95: percentile(0.95),
      p99: percentile(0.99),
      topRoutes: this.db
        .prepare(
          "SELECT host,method,route,count(*) AS requests,sum(bytes) AS bytes,sum(status>=500) AS errors FROM logs WHERE source='access' AND timestamp>=? AND timestamp<? AND route NOT IN('/health','/release.json') AND route NOT LIKE '/api/admin/%' GROUP BY host,method,route ORDER BY requests DESC LIMIT 10",
        )
        .all(start, end),
      topErrors: this.db
        .prepare(
          "SELECT source,event,code,count(*) AS count FROM logs WHERE level='error' AND timestamp>=? AND timestamp<? GROUP BY source,event,code ORDER BY count DESC LIMIT 10",
        )
        .all(start, end),
    };
  }
  enqueue(
    id: string,
    kind: string,
    subject: string,
    body: string,
    now = Date.now(),
  ) {
    this.db
      .prepare(
        "INSERT OR IGNORE INTO deliveries(id,kind,createdAt,subject,body,nextAttempt) VALUES(?,?,?,?,?,?)",
      )
      .run(id, kind, now, subject, body, now);
  }
  observe(observation: Observation, now = Date.now()) {
    const { key, title, value } = observation;
    this.db.transaction(() => {
      const row = this.db
        .prepare("SELECT * FROM alerts WHERE key=? AND resolvedAt IS NULL")
        .get(key) as Row | undefined;
      if (row) {
        if (observation.failing === null || now - row.lastCheck > 90_000) {
          row.conditionSince = null;
          row.recoveringAt = null;
        }
        this.db
          .prepare(
            "UPDATE alerts SET lastCheck=?,conditionSince=?,recoveringAt=? WHERE id=?",
          )
          .run(now, row.conditionSince, row.recoveringAt, row.id);
      }
      if (observation.failing === null) return;
      if (observation.failing) {
        if (!row)
          this.db
            .prepare(
              "INSERT INTO alerts(id,key,title,firstSeen,lastSeen,value,conditionSince,lastCheck) VALUES(?,?,?,?,?,?,?,?)",
            )
            .run(
              `${key}:${now}`,
              key,
              title,
              now,
              now,
              value ?? null,
              now,
              now,
            );
        else
          this.db
            .prepare(
              "UPDATE alerts SET lastSeen=?,recoveringAt=NULL,value=?,conditionSince=coalesce(conditionSince,?) WHERE id=?",
            )
            .run(now, value ?? null, now, row.id);
        const current = this.db
          .prepare("SELECT * FROM alerts WHERE key=? AND resolvedAt IS NULL")
          .get(key) as Row;
        if (
          now - current.conditionSince >= observation.forMs &&
          (!current.lastNotified || now - current.lastNotified >= 3_600_000)
        ) {
          const id = `alert:${key}:${current.firstSeen}:${Math.floor((now - current.firstSeen) / 3_600_000)}`;
          this.db
            .prepare(
              "UPDATE deliveries SET status='superseded',error='newer_alert_state' WHERE kind='alert' AND status='pending' AND id LIKE ?",
            )
            .run(`alert:${key}:${current.firstSeen}:%`);
          this.enqueue(
            id,
            "alert",
            `[MyLeafy 异常] ${title}`,
            `${title}\n首次发现：${new Date(current.firstSeen).toISOString()}\n当前值：${value ?? "不适用"}\n详情：https://myleafy.space/admin/monitoring/alerts`,
            now,
          );
          this.db
            .prepare("UPDATE alerts SET lastNotified=? WHERE id=?")
            .run(now, current.id);
        }
      } else if (row) {
        const since = row.recoveringAt ?? now;
        this.db
          .prepare(
            "UPDATE alerts SET conditionSince=NULL,recoveringAt=? WHERE id=?",
          )
          .run(since, row.id);
        if (now - since >= 300_000) {
          this.db
            .prepare("UPDATE alerts SET resolvedAt=? WHERE id=?")
            .run(now, row.id);
          this.db
            .prepare(
              "UPDATE deliveries SET status='superseded',error='incident_recovered' WHERE kind='alert' AND status='pending' AND id LIKE ?",
            )
            .run(`alert:${key}:${row.firstSeen}:%`);
          if (row.lastNotified)
            this.enqueue(
              `recovery:${key}:${row.firstSeen}`,
              "recovery",
              `[MyLeafy 恢复] ${title}`,
              `${title}已稳定恢复 5 分钟。\n首次发现：${new Date(row.firstSeen).toISOString()}\n详情：https://myleafy.space/admin/monitoring/alerts`,
              now,
            );
        }
      }
    })();
  }
  history(kind: "alerts" | "reports", params: Row, now = Date.now()) {
    const { start, end, page, pageSize } = parseRange(params, now),
      column = kind === "alerts" ? "firstSeen" : "createdAt";
    const items = this.db
      .prepare(
        `SELECT * FROM ${kind} WHERE ${column}>=? AND ${column}<? ORDER BY ${column} DESC LIMIT ? OFFSET ?`,
      )
      .all(start, end, pageSize, page * pageSize) as Row[];
    if (kind === "reports")
      for (const item of items) {
        item.summary = JSON.parse(item.summary);
        item.delivery = this.db
          .prepare(
            "SELECT status,attempts,providerId,error,nextAttempt FROM deliveries WHERE id=?",
          )
          .get(item.deliveryId);
      }
    else
      for (const item of items)
        item.notification = this.db
          .prepare(
            "SELECT status,error FROM deliveries WHERE id LIKE ? ORDER BY createdAt DESC LIMIT 1",
          )
          .get(`alert:${item.key}:${item.firstSeen}:%`);
    return {
      items,
      total: (
        this.db
          .prepare(
            `SELECT count(*) AS n FROM ${kind} WHERE ${column}>=? AND ${column}<?`,
          )
          .get(start, end) as Row
      ).n,
      page,
      pageSize,
    };
  }
  coverage(now = Date.now()) {
    return {
      ...(this.db
        .prepare(
          "SELECT min(timestamp) AS oldestLog,max(timestamp) AS newestLog FROM logs",
        )
        .get() as Row),
      startedAt: this.get("startedAt"),
      lastCollection: this.get("lastCollection"),
      collectionError: this.get("collectionError") ?? null,
      capacityLimited: this.get("capacityLimited") ?? false,
      sourceBacklog: Boolean(
        this.get("journalBacklog") || this.get("kernelBacklog"),
      ),
      stale: now - (this.get<number>("lastCollection") ?? 0) > 90_000,
      retentionDays: 7,
    };
  }
  retain(now = Date.now(), maxBytes = 100 * 1024 * 1024) {
    this.db.transaction(() => {
      this.db.prepare("DELETE FROM logs WHERE timestamp<?").run(now - 7 * day);
      for (const [table, column] of [
        ["alerts", "lastSeen"],
        ["reports", "createdAt"],
        ["deliveries", "createdAt"],
      ])
        this.db
          .prepare(`DELETE FROM ${table} WHERE ${column}<?`)
          .run(now - 30 * day);
    })();
    // Bound live pages, including index overhead; incremental vacuum bounds the file.
    const used = () =>
      Number(this.db.pragma("page_size", { simple: true })) *
      (Number(this.db.pragma("page_count", { simple: true })) -
        Number(this.db.pragma("freelist_count", { simple: true })));
    let limited = false;
    for (let n = 0; used() > maxBytes * 0.85 && n < 100; n++) {
      const result = this.db
        .prepare(
          "DELETE FROM logs WHERE id IN(SELECT id FROM logs ORDER BY timestamp LIMIT 2000)",
        )
        .run();
      if (!result.changes) break;
      limited = true;
    }
    if (limited) this.set("capacityLimited", true);
    this.db.pragma("wal_checkpoint(TRUNCATE)");
    this.db.pragma("incremental_vacuum(4096)");
  }
  close() {
    this.db.close();
  }
}
