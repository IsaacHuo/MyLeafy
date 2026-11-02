import { test, expect, type Page } from "@playwright/test";
declare const process:{env:{MONITOR_NAV_DEBUG?:string}};

const navigationDebug=new WeakMap<Page,string[]>();
test.afterEach(async({page},info)=>{const entries=navigationDebug.get(page);if(entries)await info.attach('navigation-debug',{body:JSON.stringify(entries,null,2),contentType:'application/json'});});
async function setup(page: Page, role = "super_admin", stale = false) {
  if(process.env.MONITOR_NAV_DEBUG){
    const entries:string[]=[];navigationDebug.set(page,entries);
    page.on('framenavigated',frame=>{if(frame===page.mainFrame())entries.push('FRAME '+frame.url());});
    page.on('request',request=>{if(request.isNavigationRequest())entries.push('REQUEST '+request.url());});
    page.on('console',message=>{if(message.text().startsWith('MONITOR_NAV'))entries.push(message.text());});
    await page.addInitScript(()=>{for(const method of ['pushState','replaceState'] as const){const original=history[method];history[method]=function(...args){console.debug('MONITOR_NAV',method,String(args[2]));return original.apply(this,args);};}});
  }

  const now = Date.now(),
    calls: { action: string; params: any }[] = [];
  const identity = {
    admin: {
      id: "monitor-admin",
      username: "monitor",
      display_name: "监控管理员",
      role,
      active: true,
    },
    permissions:
      role === "super_admin"
        ? [
            { resource: "monitoring", actions: ["list", "show"] },
            { resource: "dashboard", actions: ["list", "show"] },
          ]
        : [{ resource: "dashboard", actions: ["list", "show"] }],
    session: { expires_at: "2099-01-01T00:00:00Z" },
  };
  await page.route("**/api/admin/**", async (route) => {
    if (new URL(route.request().url()).pathname.endsWith("/me"))
      return route.fulfill({ json: identity });
    const { action, params } = route.request().postDataJSON();
    calls.push({ action, params });
    let data: any = { items: [], total: 0 };
    if (action === "monitoringOverview")
      data = {
        environment: "production",
        generatedAt: now,
        coverage: {
          startedAt: now - 86_400_000,
          lastCollection: stale ? now - 300_000 : now,
          oldestLog: now - 86_400_000,
          stale,
          collectionError: stale ? "metrics_unavailable" : null,
        },
        sample: {
          cpu: 34,
          memory: 42,
          disk: 33,
          backup: { successAt: now - 3_600_000, failed: false },
          services: {
            api: { healthy: true, failures: 0, restarts: 0 },
            website: { healthy: true, failures: 0, restarts: 0 },
          },
        },
        summary: {
          requests: 1234,
          bytes: 1048576,
          errorRate: 0.001,
          p95: 0.08,
          topRoutes: [
            {
              host: "api.myleafy.space",
              method: "GET",
              route: "/v1/catalog/:kind",
              requests: 1200,
              bytes: 1024,
              errors: 1,
            },
          ],
          topErrors: [],
        },
        tasks: {
          commit: "test-commit",
          tasks: [{ job: "17 * * * *", status: "succeeded", finished_at: now }],
        },
        alerts: [],
        mail: { enabled: true, error: null, pending: 0 },
      };
    else if (action === "monitoringSeries")
      data = {
        metric: params.metric,
        step: 30,
        series: stale
          ? []
          : [
              {
                labels: {},
                points: [
                  [now - 60_000, 1],
                  [now - 30_000, null],
                  [now, 2],
                ],
              },
            ],
      };
    else if (action === "requestLogList")
      data = {
        items: [
          {
            id: 1,
            timestamp: now,
            source: "access",
            host: "api.myleafy.space",
            method: "GET",
            route: "/v1/catalog/:kind",
            status: 200,
            duration: 0.08,
            bytes: 1024,
            ip: "192.0.2.0/24",
            requestId: "request-test-1",
          },
        ],
        total: 1,
      };
    else if (action === "serviceLogList")
      data = {
        items: [
          {
            id: 2,
            timestamp: now,
            source: "application",
            level: "error",
            event: "api_error",
            code: "internal_error",
            requestId: "request-test-1",
          },
        ],
        total: 1,
      };
    else if (action === "monitoringAlerts")
      data = {
        items: [
          {
            id: "alert-1",
            key: "cpu",
            title: "CPU 持续超过 85%",
            firstSeen: now - 300_000,
            resolvedAt: null,
            lastNotified: now - 120_000,
            notification: { status: "sent" },
          },
        ],
        total: 1,
      };
    else if (action === "monitoringReports")
      data = {
        items: [
          {
            id: "report-1",
            start: now - 86_400_000,
            end: now,
            createdAt: now,
            summary: { complete: false, requests: 1234 },
            delivery: {
              status: "sent",
              attempts: 1,
              providerId: "provider-test",
              error: null,
            },
          },
        ],
        total: 1,
      };
    return route.fulfill({ json: { data, meta: { request_id: "test" } } });
  });
  await page.goto("/admin/monitoring");
  return calls;
}
test("monitoring presents resources, traffic, redacted logs and delivery receipts", async ({
  page,
}, info) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const calls = await setup(page);
  await expect(
    page.getByRole("heading", { name: "监控总览", exact: true }),
  ).toBeVisible();
  await expect(page.getByText("1,234", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("img", { name: /每秒请求数趋势图/ }),
  ).toBeVisible();
  await expect(page.locator(".monitor-chart canvas")).toBeVisible();
  await page.screenshot({
    path: info.outputPath("monitoring-overview.png"),
    fullPage: true,
  });
  await page.goto("/admin/monitoring/traffic");
  await expect(
    page.getByRole("cell", { name: "/v1/catalog/:kind", exact: true }),
  ).toBeVisible();
  await page.goto("/admin/monitoring/server");
  await expect(page.getByText("CPU（%）", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("cell", { name: "succeeded", exact: true }),
  ).toBeVisible();
  await page.goto("/admin/monitoring/requests");
  await expect(
    page.getByRole("cell", { name: "192.0.2.0/24", exact: true }),
  ).toBeVisible();
  await page.getByLabel("请求 ID", { exact: true }).fill("request-test-1");
  await expect
    .poll(
      () =>
        calls.filter((c) => c.action === "requestLogList").at(-1)?.params
          .requestId,
    )
    .toBe("request-test-1");
  await page.getByRole("button", { name: "详情", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("request-test-1");
  await page.getByRole("button", { name: "关闭", exact: true }).click();
  await page.goto("/admin/monitoring/logs");
  await expect(
    page.getByRole("cell", { name: "api_error", exact: true }),
  ).toBeVisible();
  await page.goto("/admin/monitoring/alerts");
  await expect(
    page.getByRole("cell", { name: "CPU 持续超过 85%", exact: true }),
  ).toBeVisible();
  await page.goto("/admin/monitoring/reports");
  await expect(page.getByText("不完整", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "详情", exact: true }).click();
  await expect(page.getByRole("dialog")).toContainText("provider-test");
  expect(errors).toEqual([]);
});
test("missing monitoring data remains unknown and is never presented as a healthy zero", async ({
  page,
}) => {
  await setup(page, "super_admin", true);
  await expect(page.getByText("监控数据不完整", { exact: true })).toBeVisible();
  await expect(
    page.getByText("该时间范围尚无指标数据", { exact: true }),
  ).toBeVisible();
});
test("viewer cannot access monitoring even through a direct URL", async ({
  page,
}) => {
  const calls = await setup(page, "viewer");
  await expect(page.getByRole("alert")).toContainText("无权访问");
  expect(calls.some((c) => c.action === "monitoringOverview")).toBe(false);
  await expect(
    page.getByRole("link", { name: "监控总览", exact: true }),
  ).toHaveCount(0);
});
