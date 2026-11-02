import { Registry, Counter, Histogram } from "prom-client";
import type { LogEntry } from "./model";

export function accessMetrics() {
  const registry = new Registry(),
    labels = ["host", "method", "route", "status"] as const;
  const requests = new Counter({
    name: "myleafy_http_requests_total",
    help: "Completed gateway requests",
    labelNames: labels,
    registers: [registry],
  });
  const bytes = new Counter({
    name: "myleafy_http_response_bytes_total",
    help: "Actual response body bytes at gateway",
    labelNames: labels,
    registers: [registry],
  });
  const duration = new Histogram({
    name: "myleafy_http_duration_seconds",
    help: "Completed gateway request duration",
    labelNames: labels,
    buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 120],
    registers: [registry],
  });
  return {
    registry,
    observe(entry: LogEntry) {
      if (entry.source !== "access") return;
      const values = {
        host: entry.host ?? "",
        method: entry.method ?? "",
        route: entry.route ?? "/:unmatched",
        status: String(entry.status),
      };
      requests.inc(values);
      bytes.inc(values, entry.bytes ?? 0);
      duration.observe(values, entry.duration ?? 0);
    },
  };
}
