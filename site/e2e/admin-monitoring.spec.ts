import { test, expect, type Page } from "@playwright/test";
async function setup(
  page: Page,
  role = "super_admin",
  stale = false,
  path = "/admin/monitoring",
) {
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
  await page.goto(path);
  return calls;
}
async function navigate(page: Page, label: string) {
  const toggle = page.getByRole("button", { name: "切换导航", exact: true }),
    navigation = page.locator(".admin-navigation");
  if ((await toggle.getAttribute("aria-expanded")) !== "true")
    await toggle.click();
  await navigation.getByRole("link", { name: label, exact: true }).click();
  if ((page.viewportSize()?.width ?? 1200) < 992)
    await expect(navigation).toBeHidden();
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
  await navigate(page, "流量与接口");
  await expect(
    page.getByRole("cell", { name: "/v1/catalog/:kind", exact: true }),
  ).toBeVisible();
  await navigate(page, "主机与服务");
  await expect(page.getByText("CPU（%）", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("cell", { name: "succeeded", exact: true }),
  ).toBeVisible();
  await navigate(page, "访问日志");
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
  await navigate(page, "应用与系统日志");
  await expect(
    page.getByRole("cell", { name: "api_error", exact: true }),
  ).toBeVisible();
  await navigate(page, "告警");
  await expect(
    page.getByRole("cell", { name: "CPU 持续超过 85%", exact: true }),
  ).toBeVisible();
  await navigate(page, "日报与发送记录");
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

for (const [path, title] of [
  ["", "监控总览"],
  ["traffic", "流量与接口"],
  ["server", "主机与服务"],
  ["requests", "访问日志"],
  ["logs", "应用与系统日志"],
  ["alerts", "告警"],
  ["reports", "日报与发送记录"],
]) {
  test(`monitoring deep link ${path || "overview"} loads independently`, async ({
    page,
  }) => {
    await setup(
      page,
      "super_admin",
      false,
      "/admin/monitoring" + (path ? "/" + path : ""),
    );
    await expect(
      page.getByRole("heading", { name: title, exact: true }),
    ).toBeVisible();
    await expect(page.getByRole("alert")).toHaveCount(0);
  });
}
