import { createServer } from "node:http";
import { Registry, collectDefaultMetrics, Gauge } from "prom-client";
import type { BackendEnv } from "../auth";

export function startAPIMetrics(
  env: BackendEnv,
  connectionCount: () => number,
) {
  const registry = new Registry();
  collectDefaultMetrics({ register: registry });
  new Gauge({
    name: "myleafy_websocket_connections",
    help: "Open WebSocket connections",
    registers: [registry],
    collect() {
      this.set(connectionCount());
    },
  });
  const metricsServer = createServer(async (request, response) => {
    try {
      if (request.method !== "GET") {
        response.writeHead(405).end();
        return;
      }
      if (request.url === "/metrics") {
        response.setHeader("Content-Type", registry.contentType);
        response.end(await registry.metrics());
        return;
      }
      if (
        request.url === "/snapshot" &&
        env.MONITOR_TOKEN &&
        request.headers.authorization === `Bearer ${env.MONITOR_TOKEN}`
      ) {
        const tasks = await env.DB.prepare(
          "SELECT job,status,error_code,finished_at FROM (SELECT job,status,error_code,finished_at,row_number() OVER(PARTITION BY job ORDER BY started_at DESC,id DESC) AS n FROM scheduled_runs) WHERE n=1 LIMIT 10",
        ).all();
        response.setHeader("Content-Type", "application/json");
        response.end(
          JSON.stringify({
            environment: env.ENVIRONMENT,
            commit: env.DEPLOY_COMMIT,
            tasks: tasks.results,
          }),
        );
        return;
      }
      response.writeHead(404).end();
    } catch {
      response.writeHead(503).end();
    }
  });
  metricsServer.on("error", () =>
    console.error(JSON.stringify({ event: "metrics_listener_failed" })),
  );
  metricsServer.listen(
    env.ENVIRONMENT === "production" ? 3120 : 3121,
    "127.0.0.1",
  );
  return metricsServer;
}
