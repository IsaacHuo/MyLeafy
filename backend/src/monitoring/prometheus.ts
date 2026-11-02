import type { Environment } from "./model";

export function metricQueries(environment: Environment) {
  const labels = `environment="${environment}"`;
  const trafficLabels =
    labels + ',route!~"/health|/release.json|/api/admin/.*"';
  return {
    cpu: '100 * (1 - avg(rate(node_cpu_seconds_total{job="host",mode="idle"}[5m])))',
    memory:
      '100 * (1 - node_memory_MemAvailable_bytes{job="host"} / node_memory_MemTotal_bytes{job="host"})',
    disk: '100 * (1 - node_filesystem_avail_bytes{job="host",mountpoint="/",fstype!="rootfs"} / node_filesystem_size_bytes{job="host",mountpoint="/",fstype!="rootfs"})',
    diskRead:
      'sum(rate(node_disk_read_bytes_total{job="host",device!~"loop.*|ram.*"}[5m]))',
    diskWrite:
      'sum(rate(node_disk_written_bytes_total{job="host",device!~"loop.*|ram.*"}[5m]))',
    networkIn:
      'sum(rate(node_network_receive_bytes_total{job="host",device!="lo"}[5m]))',
    networkOut:
      'sum(rate(node_network_transmit_bytes_total{job="host",device!="lo"}[5m]))',
    nodeMemory: `process_resident_memory_bytes{job="api",${labels}}`,
    nodeCPU: `rate(process_cpu_user_seconds_total{job="api",${labels}}[5m]) + rate(process_cpu_system_seconds_total{job="api",${labels}}[5m])`,
    eventLoop: `nodejs_eventloop_lag_p99_seconds{job="api",${labels}}`,
    websocket: `myleafy_websocket_connections{job="api",${labels}}`,
    requests: `sum(rate(myleafy_http_requests_total{job="monitor",${trafficLabels}}[5m]))`,
    bytes: `sum(rate(myleafy_http_response_bytes_total{job="monitor",${trafficLabels}}[5m]))`,
    errors: `sum(rate(myleafy_http_requests_total{job="monitor",${trafficLabels},status=~"5.."}[5m])) / sum(rate(myleafy_http_requests_total{job="monitor",${trafficLabels}}[5m]))`,
    p50: `histogram_quantile(0.50,sum by (le)(rate(myleafy_http_duration_seconds_bucket{job="monitor",${trafficLabels}}[5m])))`,
    p95: `histogram_quantile(0.95,sum by (le)(rate(myleafy_http_duration_seconds_bucket{job="monitor",${trafficLabels}}[5m])))`,
    p99: `histogram_quantile(0.99,sum by (le)(rate(myleafy_http_duration_seconds_bucket{job="monitor",${trafficLabels}}[5m])))`,
  };
}
export type MetricKey = keyof ReturnType<typeof metricQueries>;
export class PrometheusClient {
  constructor(
    readonly environment: Environment,
    private readonly request: typeof fetch = fetch,
  ) {}
  private async query(path: string, params: Record<string, string>) {
    const response = await this.request(
      `http://127.0.0.1:9090/api/v1/${path}?${new URLSearchParams(params)}`,
      { signal: AbortSignal.timeout(5000) },
    );
    if (!response.ok) throw new Error("指标存储暂时不可用。");
    const value = (await response.json()) as any;
    if (value.status !== "success" || !Array.isArray(value.data?.result))
      throw new Error("指标查询失败。");
    return value.data.result;
  }
  async instant(key: MetricKey, now = Date.now()): Promise<number | null> {
    const result = await this.query("query", {
      query: metricQueries(this.environment)[key],
      time: String(now / 1000),
    });
    const value = result[0]?.value?.[1];
    return value !== undefined && Number.isFinite(Number(value))
      ? Number(value)
      : null;
  }
  async series(key: string, start: number, end: number) {
    if (!Object.hasOwn(metricQueries(this.environment), key))
      throw new Error("未知指标。");
    const step = Math.max(30, Math.ceil((end - start) / 1000 / 800));
    const result = await this.query("query_range", {
      query: metricQueries(this.environment)[key as MetricKey],
      start: String(start / 1000),
      end: String(end / 1000),
      step: String(step),
    });
    return {
      metric: key,
      step,
      series: result.map((row: any) => ({
        labels: row.metric,
        points: row.values.map(([time, value]: [number, string]) => [
          time * 1000,
          Number.isFinite(Number(value)) ? Number(value) : null,
        ]),
      })),
      retentionDays: 14,
    };
  }
}
