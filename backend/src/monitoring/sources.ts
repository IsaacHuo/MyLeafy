import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { open, readdir, stat, readFile } from "node:fs/promises";
import { join } from "node:path";
import { MonitorStore } from "./store";
import { normalizeLog, type Environment, type LogEntry } from "./model";

const run = promisify(execFile);
function journalBatch(
  args: string[],
): Promise<{ rows: Record<string, any>[]; backlog: boolean }> {
  return new Promise((resolve, reject) => {
    const child = spawn("/usr/bin/journalctl", args, {
      stdio: ["ignore", "pipe", "pipe"],
    });
    const rows: Record<string, any>[] = [];
    let pending = "",
      stopped = false,
      problem: Error | undefined;
    const stop = () => {
      stopped = true;
      child.kill("SIGTERM");
    };
    const timeout = setTimeout(() => {
      if (rows.length) stop();
      else {
        problem = new Error("journal_read_timeout");
        child.kill("SIGTERM");
      }
    }, 5000);
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      if (stopped || problem) return;
      pending += chunk;
      if (pending.length > 2 * 1024 * 1024) {
        problem = new Error("oversized_journal_entry");
        child.kill("SIGTERM");
        return;
      }
      let index: number;
      while ((index = pending.indexOf("\n")) >= 0) {
        const line = pending.slice(0, index);
        pending = pending.slice(index + 1);
        if (line) {
          try {
            rows.push(JSON.parse(line));
          } catch {
            problem = new Error("invalid_journal_entry");
            child.kill("SIGTERM");
            return;
          }
        }
        if (rows.length >= 1000) {
          stop();
          break;
        }
      }
    });
    child.stderr.resume();
    child.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timeout);
      if (problem) reject(problem);
      else if (code !== 0 && !stopped) reject(new Error("journal_read_failed"));
      else resolve({ rows, backlog: stopped });
    });
  });
}
export async function accessLogs(
  store: MonitorStore,
  environment: Environment,
  directory: string,
) {
  const files = await readdir(directory);
  const candidates = await Promise.all(
    files
      .filter((name) => /^access(?:-.*)?\.log$/.test(name))
      .map(async (name) => ({ name, info: await stat(join(directory, name)) })),
  );
  candidates.sort((a, b) => a.info.mtimeMs - b.info.mtimeMs);
  const all: LogEntry[] = [];
  for (const { name, info } of candidates) {
    const key = `file:${info.dev}:${info.ino}`,
      previous = store.get<number>(key) ?? 0;
    const offset = previous > info.size ? 0 : previous;
    if (offset === info.size) continue;
    const file = await open(join(directory, name), "r");
    try {
      const buffer = Buffer.alloc(
        Math.min(2 * 1024 * 1024, info.size - offset),
      );
      const { bytesRead } = await file.read(buffer, 0, buffer.length, offset),
        last = buffer.lastIndexOf(10, bytesRead - 1);
      if (last < 0) {
        if (bytesRead >= 64 * 1024) {
          store.set("collectionError", "oversized_access_log");
          store.set(key, offset + bytesRead);
        }
        continue;
      }
      const entries: LogEntry[] = [];
      for (const line of buffer
        .subarray(0, last)
        .toString("utf8")
        .split("\n")) {
        if (!line) continue;
        try {
          const entry = normalizeLog(JSON.parse(line), environment);
          if (entry) entries.push(entry);
        } catch {
          store.set("collectionError", "invalid_access_log");
        }
      }
      store.ingest(entries, { key, value: offset + last + 1 });
      all.push(...entries);
    } finally {
      await file.close();
    }
  }
  return all;
}
export async function journalLogs(
  store: MonitorStore,
  environment: Environment,
) {
  const key = "journalCursor",
    cursor = store.get<string>(key),
    since = store.get<number>("journalTime") ?? Date.now() - 60_000;
  const args = [
    "--no-pager",
    "--output=json",
    "--unit",
    `myleafy@${environment}.service`,
    "--unit",
    `myleafy-backup@${environment}.service`,
    "--unit",
    "myleafy-caddy.service",
    "--unit",
    "systemd-oomd.service",
  ];
  if (cursor) args.push(`--after-cursor=${cursor}`);
  else args.push(`--since=@${Math.floor(since / 1000)}`);
  const { rows, backlog } = await journalBatch(args);
  store.set("journalBacklog", backlog);
  const entries: LogEntry[] = [];
  let lastCursor = cursor,
    lastTime = since;
  for (const row of rows) {
    const unit = String(row.UNIT ?? row._SYSTEMD_UNIT ?? ""),
      timestamp = Number(row.__REALTIME_TIMESTAMP) / 1000;
    lastCursor = row.__CURSOR;
    lastTime = timestamp;
    const source = unit.startsWith("myleafy-backup")
      ? "backup"
      : unit.startsWith("myleafy@")
        ? "application"
        : unit === "systemd-oomd.service"
          ? "system"
          : "caddy";
    const text = typeof row.MESSAGE === "string" ? row.MESSAGE : "";
    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(text);
    } catch {
      const event = /out of memory|oom.kill|Killed.*memory/i.test(text)
        ? "oom"
        : /Main process exited|Failed with result/i.test(text)
          ? "unexpected_exit"
          : /backup_failed/.test(text)
            ? "backup_failed"
            : Number(row.PRIORITY) <= 3
              ? "service_error"
              : "service_event";
      payload = { event };
    }
    if (source === "caddy" && !payload.event)
      payload = {
        event: payload.level === "error" ? "caddy_error" : "caddy_event",
      };
    if (!payload.event)
      payload = {
        event:
          Number(row.PRIORITY) <= 3 || payload.level === "error"
            ? "unstructured_error"
            : "service_event",
      };
    const entry = normalizeLog({ ...payload, source, timestamp }, environment);
    if (entry) entries.push(entry);
  }
  store.db.transaction(() => {
    store.ingest(entries);
    if (lastCursor) store.set(key, lastCursor);
    store.set("journalTime", lastTime);
  })();
  return entries;
}
export async function kernelLogs(
  store: MonitorStore,
  environment: Environment,
) {
  const cursor = store.get<string>("kernelCursor"),
    args = ["--dmesg", "--no-pager", "--output=json"];
  args.push(
    cursor
      ? `--after-cursor=${cursor}`
      : `--since=@${Math.floor(Date.now() / 1000 - 60)}`,
  );
  const { rows, backlog } = await journalBatch(args),
    entries: LogEntry[] = [];
  for (const row of rows) {
    const message = String(row.MESSAGE ?? "");
    const event = /out of memory|oom.kill|Killed process.*total-vm/i.test(
      message,
    )
      ? "oom"
      : /I\/O error|filesystem.*error|EXT4-fs error/i.test(message)
        ? "disk_io_error"
        : null;
    if (event) {
      const entry = normalizeLog(
        {
          timestamp: Number(row.__REALTIME_TIMESTAMP) / 1000,
          source: "system",
          event,
        },
        environment,
      );
      if (entry) entries.push(entry);
    }
  }
  store.db.transaction(() => {
    store.ingest(entries);
    if (rows.length) store.set("kernelCursor", rows[rows.length - 1].__CURSOR);
    store.set("kernelBacklog", backlog);
  })();
  return entries;
}
export async function serviceStatus(environment: Environment) {
  const { stdout } = await run(
    "/usr/bin/systemctl",
    [
      "show",
      `myleafy@${environment}.service`,
      "myleafy-caddy.service",
      `myleafy-backup@${environment}.service`,
      "-p",
      "Id",
      "-p",
      "ActiveState",
      "-p",
      "NRestarts",
      "-p",
      "Result",
    ],
    { timeout: 3000, maxBuffer: 64 * 1024 },
  );
  return stdout
    .trim()
    .split("\n\n")
    .map((block) =>
      Object.fromEntries(
        block.split("\n").map((line) => {
          const i = line.indexOf("=");
          return [line.slice(0, i), line.slice(i + 1)];
        }),
      ),
    );
}
export async function backupStatus(environment: Environment) {
  const file = `/var/lib/myleafy-monitor/backup/${environment}.json`;
  try {
    const state = JSON.parse(await readFile(file, "utf8"));
    return {
      successAt: Number.isFinite(state.successAt) ? state.successAt : null,
      failed: state.failed === true,
    };
  } catch (error: any) {
    if (error.code === "ENOENT") return { successAt: null, failed: null };
    throw error;
  }
}
export async function maintenanceStatus(
  environment: Environment,
  now = Date.now(),
) {
  try {
    const data = JSON.parse(
      await readFile(
        `/run/myleafy-monitor/${environment}.maintenance.json`,
        "utf8",
      ),
    );
    return Number.isFinite(data.until) && data.until <= now + 30 * 60_000
      ? data.until
      : null;
  } catch (error: any) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}
