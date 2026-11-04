import {
  mkdirSync,
  writeFileSync,
  renameSync,
  readFileSync,
  existsSync,
  statSync,
  chownSync,
  chmodSync,
} from "node:fs";
import { randomUUID } from "node:crypto";

// Only root-owned, non-secret status receipts use these explicit reader permissions.
export function writeMonitorMetadata(path, data, mode, group) {
  const temporary = path + "." + randomUUID();
  writeFileSync(temporary, JSON.stringify(data) + String.fromCharCode(10), {
    mode,
    flag: "wx",
  });
  if (group !== undefined) chownSync(temporary, 0, group);
  chmodSync(temporary, mode); // systemd backup uses umask 0077.
  renameSync(temporary, path);
}

if (import.meta.main) {
  const [environment, operation] = process.argv.slice(2);
  if (
    !["production", "staging"].includes(environment) ||
    !["begin", "end", "backup-success", "backup-failed"].includes(operation)
  )
    throw new Error("Invalid monitoring maintenance operation");
  const directory = "/run/myleafy-monitor",
    path = `${directory}/${environment}.maintenance.json`;
  mkdirSync(directory, { recursive: true, mode: 0o755 });
  chmodSync(directory, 0o755);
  if (operation === "begin" || operation === "end") {
    writeMonitorMetadata(
      path,
      {
        until: operation === "begin" ? Date.now() + 15 * 60_000 : Date.now(),
        reason: "deployment_or_backup",
      },
      0o644,
    );
  } else {
    const destination = `/var/lib/myleafy-monitor/backup/${environment}.json`;
    if (!existsSync(destination)) process.exit(0);
    const old = JSON.parse(readFileSync(destination, "utf8"));
    writeMonitorMetadata(
      destination,
      {
        successAt:
          operation === "backup-success" ? Date.now() : (old.successAt ?? null),
        failed: operation === "backup-failed",
      },
      0o640,
      statSync(destination).gid,
    );
  }
}
