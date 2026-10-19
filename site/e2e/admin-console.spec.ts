import { expect, test, type Page } from "@playwright/test";
test.setTimeout(120_000);
const resources = [
  "dashboard",
  "manual",
  "work-queue",
  "operations",
  "data-quality",
  "android-releases",
  "campuses",
  "campus-requests",
  "posts",
  "polls",
  "comments",
  "reports",
  "profiles",
  "feedback",
  "announcements",
  "community-banners",
  "postgraduate",
  "postgraduate-suggestions",
  "suggestions",
  "teachers",
  "courses",
  "dishes",
  "ratings",
  "semester-configs",
  "national-calendar",
  "admins",
  "sessions",
  "audit-logs",
];
const today = "2026-10-13";
const daily = [{ bucket_date: today, posts: 2, comments: 3, profiles: 1 }];
const overview = {
  summary: {
    operations: {
      totalProfiles: 2323,
      completeProfiles: 686,
      newProfilesToday: 1,
      mutedProfiles: 0,
      postsToday: 2,
      commentsToday: 3,
      postsInRange: 2,
      commentsInRange: 3,
      daily,
    },
    moderation: { openReports: 2, overdueReports: 1, hiddenPostsInRange: 2 },
    feedback: {
      open: 2,
      reviewed: 3,
      pending: 5,
      overdue: 1,
      aging: [
        { key: "0-24h", label: "24 小时内", count: 2 },
        { key: "1-3d", label: "1–3 天", count: 3 },
      ],
    },
    teachers: { average: 4.2, totalRatings: 89 },
  },
  cards: { posts: { hidden: 4 } },
  analyticsMeta: {
    days: 30,
    timezone: "Asia/Shanghai",
    startDate: "2026-09-14",
    startAt: "2026-09-13T16:00:00Z",
    endAt: "2026-10-13T08:00:00Z",
    generatedAt: "2026-10-13T08:00:00Z",
  },
};
async function setup(page: Page, role = "super_admin") {
  let loggedIn = false;
  const calls: { action: string; params: any }[] = [];
  const identity = {
    admin: {
      id: role,
      username: role,
      display_name: role === "viewer" ? "只读管理员" : "超级管理员",
      role,
      active: true,
    },
    permissions: resources
      .filter(
        (r) =>
          role !== "viewer" ||
          ![
            "operations",
            "data-quality",
            "admins",
            "sessions",
            "audit-logs",
          ].includes(r),
      )
      .map((resource) => ({
        resource,
        actions:
          role === "viewer"
            ? ["list", "show"]
            : ["list", "show", "create", "edit", "delete", "bulk", "export"],
      })),
    session: { expires_at: "2099-01-01T00:00:00Z" },
  };
  await page.route("**/api/admin/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname.endsWith("/login")) {
      loggedIn = true;
      await route.fulfill({ json: identity });
      return;
    }
    if (url.pathname.endsWith("/me")) {
      await route.fulfill(
        loggedIn
          ? { json: identity }
          : { status: 401, json: { error: "请登录" } },
      );
      return;
    }
    if (url.pathname.endsWith("/logout")) {
      loggedIn = false;
      await route.fulfill({ json: { ok: true } });
      return;
    }
    if (url.pathname.endsWith("/export")) {
      await route.fulfill({
        body: "id,title\np1,测试",
        contentType: "text/csv",
        headers: { "content-disposition": 'attachment; filename="posts.csv"' },
      });
      return;
    }
    const { action, params } = route.request().postDataJSON();
    calls.push({ action, params });
    const post = {
      id: "post-1",
      title: "测试图片帖子",
      body: "校园生活与学习交流",
      status: "pending_review",
      display_status: "publish_exception",
      upload_state: "publish_failed",
      category: "校园",
      image_count: 1,
      expected_image_count: 1,
      attachment_count: 0,
      expected_attachment_count: 0,
      created_at: "2026-10-13T01:00:00Z",
      images: [
        {
          id: "image-1",
          signed_url:
            "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==",
        },
      ],
    };
    let data: any = { items: [], total: 0, page: 0, pageSize: 20 };
    if (action === "overview") data = overview;
    else if (action === "listCampuses")
      data = {
        items: [
          { id: "bjfu", display_name: "北京林业大学" },
          { id: "another", display_name: "另一学校" },
        ],
        total: 2,
      };
    else if (action === "listPosts") data = { items: [post], total: 1 };
    else if (action === "getPost") data = { post, comments: [] };
    else if (action === "listFeedback")
      data = {
        items: [
          {
            id: "feedback-1",
            body: "课表建议",
            status: "reviewed",
            issue_type: "bug",
            created_at: "2026-10-13T03:00:00Z",
          },
        ],
        total: 1,
      };
    else if (action === "listProfiles")
      data = {
        items: [
          {
            id: "profile-1",
            nickname: "测试学生",
            display_name: "测试",
            community_access_status: "approved",
            created_at: "2026-10-12T03:00:00Z",
          },
        ],
        total: 1,
      };
    else if (action === "getProfile")
      data = {
        profile: { id: "profile-1", nickname: "测试学生" },
        recentPosts: [post],
      };
    else if (
      action === "listTeacherRatings" ||
      action === "listCourseRatings" ||
      action === "listDishRatings"
    )
      data = {
        items: [
          {
            id: "teacher:341:user-1",
            teacher_id: 341,
            user_id: "user-1",
            teacher: { name: "测试教师" },
            user: { nickname: "测试用户" },
            stars: 4,
            updated_at: "2026-10-13T08:00:00Z",
          },
        ],
        total: 1,
      };
    else if (action === "listAdminSessions")
      data = {
        items: [
          {
            id: "session-1",
            admin_id: "admin-1",
            // Mirrors the backend adminHydrate contract: admin_id -> admin_accounts
            admin: {
              id: "admin-1",
              username: "ops",
              display_name: "运维管理员",
              role: "operator",
            },
            expires_at: "2099-01-01T00:00:00Z",
            is_current: false,
          },
        ],
        total: 1,
      };
    else if (action === "listAuditLogs")
      data = {
        items: [
          {
            id: 2,
            admin_id: "admin-1",
            admin: {
              id: "admin-1",
              username: "ops",
              display_name: "运维管理员",
              role: "operator",
            },
            action: "disableAdmin",
            target_type: "admin",
            outcome: "success",
            duration_ms: 12,
            created_at: "2026-10-13T08:00:00Z",
          },
          {
            id: 1,
            admin_id: null,
            admin: null,
            action: "migrationReplay",
            target_type: "system",
            outcome: "success",
            created_at: "2026-10-13T07:00:00Z",
          },
        ],
        total: 2,
      };
    else if (action === "workQueue")
      data = {
        groups: [
          {
            resource: "feedback",
            label: "反馈",
            total: 1,
            items: [
              {
                id: "feedback-1",
                body: "课表建议",
                created_at: "2026-10-13T03:00:00Z",
              },
            ],
            filters: { pending: true, status: "all" },
          },
        ],
      };
    else if (action === "operationalHealth")
      data = {
        environment: "staging",
        mode: "active",
        commit: "test-commit",
        signals: { pending: 0 },
        media: { pending: 0 },
        generatedAt: "2026-10-13T08:00:00Z",
      };
    else if (action === "diagnosticList")
      data = {
        items: [
          {
            id: "run-1",
            job: "media",
            status: "succeeded",
            started_at: "2026-10-13T08:00:00Z",
          },
        ],
        total: 1,
      };
    else if (action === "dataQuality")
      data = {
        checks: [
          {
            key: "teachers",
            label: "教师评分聚合",
            count: 1,
            samples: [{ id: 341 }],
          },
        ],
        generatedAt: "2026-10-13T08:00:00Z",
      };
    else if (action === "globalSearch")
      data = [
        {
          resource: "posts",
          id: "post-1",
          path: "/admin/posts/post-1",
          title: "搜索帖子",
          subtitle: "校园",
        },
      ];
    else if (action === "previewCommunityFeed") data = { posts: [post] };
    else if (action === "listAndroidReleases")
      data = {
        items: [
          {
            id: "release-1",
            versionName: "1.2.5",
            versionCode: 9,
            status: "ready",
            sizeBytes: 54000000,
            ciVerified: true,
            releaseNotes: "新增真实活动采集",
          },
        ],
        total: 1,
      };
    await route.fulfill({
      json: { data, meta: { request_id: "e2e", audit_logged: true } },
    });
  });
  await page.goto("/admin");
  await page.getByLabel("账号", { exact: true }).fill(role);
  await page.getByLabel("密码", { exact: true }).fill("test-only");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page.getByRole("heading", { name: "运营总览" })).toBeVisible();
  return calls;
}
async function navigate(page: Page, label: string) {
  const link = page
    .locator(".studio-sidebar nav")
    .getByRole("link", { name: label, exact: true });
  if (!(await link.isVisible()))
    await page.getByRole("button", { name: "展开导航", exact: true }).click();
  await link.click();
  if (
    await page
      .getByRole("button", { name: "展开导航", exact: true })
      .isVisible()
  )
    await page.getByRole("button", { name: "展开导航", exact: true }).click();
}
test("Studio data browsing, scopes, saved views, details and dangerous confirmations", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  const calls = await setup(page);
  await expect(page.getByText("资料完善", { exact: true })).toBeVisible();
  await expect(page.getByRole("img", { name: /内容趋势/ })).toBeVisible();
  await navigate(page, "帖子");
  await expect(page.getByLabel("状态", { exact: true })).toHaveValue(
    "pending_review",
  );
  await page.getByLabel("状态", { exact: true }).selectOption("all");
  await expect
    .poll(
      () => calls.filter((c) => c.action === "listPosts").at(-1)?.params.status,
    )
    .toBe("all");
  await page.getByLabel("学校范围").selectOption("bjfu");
  await expect
    .poll(
      () =>
        calls.filter((c) => c.action === "listPosts").at(-1)?.params.campusID,
    )
    .toBe("bjfu");
  await page.getByRole("button", { name: "视图", exact: true }).click();
  await page.getByLabel("视图名称").fill("校园全部帖子");
  await page.getByRole("button", { name: "保存视图", exact: true }).click();
  await page.getByRole("button", { name: "关闭", exact: true }).click();
  await page.getByRole("button", { name: "列", exact: true }).click();
  await page.getByLabel("点赞", { exact: true }).uncheck();
  await page.getByRole("button", { name: "关闭", exact: true }).click();
  await expect(
    page.getByRole("columnheader", { name: "点赞", exact: true }),
  ).toHaveCount(0);
  await page
    .getByRole("table")
    .getByRole("link", { name: "详情", exact: true })
    .click();
  await expect(page.getByRole("img", { name: "帖子图片 1" })).toBeVisible();
  await page.getByRole("button", { name: "关闭", exact: true }).click();
  await page.getByRole("button", { name: "重新发布", exact: true }).click();
  await expect(page.getByText(/仅完整上传的帖子才会公开/)).toBeVisible();
  await page.getByRole("button", { name: "取消", exact: true }).click();
  await navigate(page, "评分");
  await page.getByLabel("评分类型").selectOption("course");
  await expect
    .poll(() => calls.filter((c) => c.action === "listCourseRatings").length)
    .toBeGreaterThan(0);
  await page.getByRole("button", { name: "删除", exact: true }).click();
  await expect(page.getByText(/评分：测试教师/)).toBeVisible();
  await page.getByRole("button", { name: "取消", exact: true }).click();
  await navigate(page, "教师");
  await page.getByRole("button", { name: "新增", exact: true }).click();
  await page.getByLabel("姓名", { exact: true }).fill("未保存");
  await page.getByRole("button", { name: "取消", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "放弃未保存的修改？" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "放弃修改", exact: true }).click();
  await page.getByRole("button", { name: "全局搜索", exact: true }).click();
  await page.getByLabel("搜索内容").fill("校园");
  await page.getByRole("button", { name: "搜索帖子", exact: false }).click();
  await expect(page).toHaveURL(/\/admin\/posts\/post-1/);
  await page.getByRole("button", { name: "关闭", exact: true }).click();
  expect(
    await page.evaluate(() => localStorage.getItem("leafy-admin-session")),
  ).toBeNull();
  expect(errors).toEqual([]);
});
test("sessions and audit logs show the owning admin name and a system placeholder", async ({
  page,
}) => {
  await setup(page);
  await navigate(page, "会话");
  await expect(
    page.getByRole("link", { name: "运维管理员", exact: true }),
  ).toBeVisible();
  await page.locator("tbody").getByRole("button", { name: "撤销", exact: true }).click();
  await expect(page.getByText(/管理会话：运维管理员/)).toBeVisible();
  await page.getByRole("button", { name: "取消", exact: true }).click();
  await navigate(page, "审计日志");
  await expect(
    page.getByRole("link", { name: "运维管理员", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("link", { name: "系统", exact: true }),
  ).toBeVisible();
});
test("viewer retains read access and cannot manage or see system diagnostics", async ({
  page,
}) => {
  await setup(page, "viewer");
  await navigate(page, "帖子");
  await expect(
    page.getByRole("table").getByRole("link", { name: "详情", exact: true }),
  ).toBeVisible();
  for (const label of ["重新发布", "导出 CSV", "编辑"])
    await expect(
      page.getByRole("button", { name: label, exact: true }),
    ).toHaveCount(0);
  await expect(
    page.locator(".studio-sidebar nav").getByRole("link", { name: "运行诊断" }),
  ).toHaveCount(0);
  await page.goto("/admin/operations");
  await expect(page.getByRole("alert")).toContainText("无权访问");
});
test("every resource and diagnostics renders in light and dark themes", async ({
  page,
}, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await setup(page);
  for (const theme of ["light", "dark"]) {
    await page.getByLabel("主题", { exact: true }).selectOption(theme);
    for (const path of resources.filter((r) => r !== "dashboard")) {
      await page.goto(`/admin/${path}`);
      await expect(page.locator("main h1")).toBeVisible();
      await expect(page.locator("main .studio-loading")).toHaveCount(0);
      await expect(page.locator("main [role=alert]")).toHaveCount(0);
      if (
        ["posts", "operations", "data-quality", "android-releases"].includes(
          path,
        )
      )
        await page.screenshot({
          path: testInfo.outputPath(`${path}-${theme}.png`),
          fullPage: true,
        });
    }
    await page.goto("/admin");
    await expect(page.getByRole("heading", { name: "运营总览" })).toBeVisible();
    await expect(page.locator(".studio-chart canvas").first()).toBeVisible();
    await page.screenshot({
      path: testInfo.outputPath(`overview-${theme}.png`),
      fullPage: true,
    });
  }
  expect(errors).toEqual([]);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});
