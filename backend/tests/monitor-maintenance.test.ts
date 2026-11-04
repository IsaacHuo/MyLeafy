import { afterEach, expect, it } from "vitest";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { writeMonitorMetadata } from "../deploy/monitor-maintenance.mjs";

const directories: string[] = [];
afterEach(() => {
  for (const directory of directories.splice(0))
    rmSync(directory, { recursive: true, force: true });
});
it("keeps status receipts readable with the backup service's restrictive umask", () => {
  const directory = mkdtempSync(join(tmpdir(), "myleafy-monitor-mode-"));
  directories.push(directory);
  const previous = process.umask(0o077);
  try {
    for (const mode of [0o644, 0o640]) {
      const path = join(directory, String(mode));
      writeMonitorMetadata(path, { until: 123, failed: false }, mode);
      expect(statSync(path).mode & 0o777).toBe(mode);
      expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({
        until: 123,
        failed: false,
      });
      writeMonitorMetadata(path, { until: 456 }, mode);
      expect(statSync(path).mode & 0o777).toBe(mode);
      expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ until: 456 });
    }
  } finally {
    process.umask(previous);
  }
});
