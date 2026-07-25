import { expect, test } from "@playwright/test";

const permissions = [
  "dashboard", "manual", "campuses", "campus-requests", "posts", "polls", "comments", "reports",
  "profiles", "feedback", "announcements", "postgraduate", "postgraduate-suggestions", "suggestions",
  "teachers", "courses", "dishes", "ratings", "semester-configs", "national-calendar",
  "admins", "sessions", "audit-logs",
].map((resource) => ({ resource, actions: ["list", "show", "create", "edit", "delete", "bulk", "export"] }));

const identity = {
  admin: { id: "admin-1", username: "admin", display_name: "超级管理员", role: "super_admin", active: true },
  permissions: [...permissions, { resource: "global-search", actions: ["search"] }],
  session: { expires_at: "2099-01-01T00:00:00.000Z" },
};

test("logs in through the BFF and opens a real resource route", async ({ page }) => {
  let loggedIn = false;
  await page.route("**/api/admin/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname.endsWith("/login")) {
      loggedIn = true;
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(identity) });
      return;
    }
    if (url.pathname.endsWith("/me")) {
      await route.fulfill(loggedIn
        ? { status: 200, contentType: "application/json", body: JSON.stringify(identity) }
        : { status: 401, contentType: "application/json", headers: { "x-request-id": "e2e-login" }, body: JSON.stringify({ error: "登录已过期", errorEnvelope: { code: "unauthorized", message: "登录已过期", retryable: false } }) });
      return;
    }
    if (url.pathname.endsWith("/logout")) {
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ data: { ok: true }, meta: { request_id: "e2e-logout", audit_logged: true, duration_ms: 1 } }) });
      return;
    }
    if (url.pathname.endsWith("/actions")) {
      const body = route.request().postDataJSON() as { action: string };
      const data = body.action === "overview"
        ? { summary: { operations: { totalProfiles: 12, activeProfiles: 10, newProfilesToday: 1, mutedProfiles: 0, postsToday: 2, commentsToday: 3, daily: [{ bucket_date: "2026-07-13", posts: 2, comments: 3, profiles: 1 }] }, moderation: {}, feedback: { open: 2, reviewed: 3, pending: 5, overdue: 1, aging: [] }, teachers: {} } }
          : body.action === "listCampuses"
          ? { items: [{ id: "campus-a", display_name: "测试大学" }], total: 1, page: 0, pageSize: 100 }
          : body.action === "listPosts"
            ? { items: [{ id: "post-1", title: "测试图片帖子", status: "pending_review", display_status: "publish_exception", upload_state: "publish_failed", image_count: 1, expected_image_count: 1, created_at: "2026-07-10T00:00:00Z" }], total: 1, page: 0, pageSize: 20 }
            : body.action === "getPost"
              ? { post: { id: "post-1", title: "测试图片帖子", body: "图片证据", status: "pending_review", upload_state: "publish_failed", images: [{ id: "image-1", signed_url: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==", thumbnail_signed_url: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==" }] }, comments: [] }
            : body.action === "retryPostPublish"
              ? { id: "post-1", title: "测试图片帖子", status: "published" }
            : body.action === "listFeedback"
              ? { items: [{ id: "feedback-1", issue_type: "bug", body: "测试反馈", status: "reviewed", created_at: "2026-07-12T00:00:00Z" }], total: 1, page: 0, pageSize: 20 }
              : body.action === "listAdminSessions"
                ? { items: [{ id: "session-1", admin_id: "admin-2", admin: { display_name: "运营管理员" }, last_seen_at: "2026-07-13T08:00:00Z", expires_at: "2099-01-01T00:00:00Z", revoked_at: null, is_current: false }], total: 1, page: 0, pageSize: 20 }
                : body.action === "listTeacherRatings"
                  ? { items: [{ id: "teacher:341:user-1", target: "teacher", teacher_id: 341, user_id: "user-1", teacher: { name: "测试教师" }, user: { nickname: "测试用户" }, stars: 4, updated_at: "2026-07-13T08:00:00Z" }], total: 1, page: 0, pageSize: 20 }
            : { items: [], total: 0, page: 0, pageSize: 20 };
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ data, meta: { request_id: "e2e", audit_logged: true, duration_ms: 1 } }) });
      return;
    }
    await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ error: "not found" }) });
  });

  await page.goto("/admin");
  await page.getByLabel("账号").fill("operator");
  await page.getByLabel("密码").fill("secret");
  await page.getByRole("button", { name: "登录" }).click();
  await expect(page.getByRole("heading", { name: "运营总览" })).toBeVisible();
  await expect(page.getByRole("img", { name: /内容趋势，日期：07-13/ })).toBeVisible();
  await expect(page.getByText("未查看 2 · 已查看 3 · 逾期 1")).toBeVisible();
  await expect(page.getByText("undefined", { exact: true })).toHaveCount(0);

  await page.getByText("帖子", { exact: true }).click();
  await expect(page).toHaveURL(/\/admin\/posts/);
  await expect(page.getByText("测试图片帖子")).toBeVisible();
  await expect(page.getByText("发布异常", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "重新发布" })).toBeVisible();
  await expect(page.getByRole("columnheader", { name: "标题" })).toBeVisible();
  await page.getByRole("button", { name: "查看" }).click();
  await expect(page.getByRole("img", { name: "帖子图片 1" })).toBeVisible();
  await page.getByRole("button", { name: "关闭" }).click();
  await page.getByRole("button", { name: "重新发布" }).click();
  await expect(page.getByText(/仅完整上传的帖子才会公开/)).toBeVisible();
  await page.getByRole("button", { name: "取消" }).click();

  await page.getByText("反馈", { exact: true }).click();
  await expect(page.getByRole("columnheader", { name: /类型/ })).toBeVisible();
  await expect(page.getByText("已查看待处理", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: /新增反馈/ })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "添加筛选" })).toBeVisible();

  await page.getByText("会话", { exact: true }).click();
  await expect(page.getByRole("button", { name: "撤销", exact: true })).toBeVisible();

  await page.getByText("评分", { exact: true }).click();
  await page.getByRole("button", { name: "删除", exact: true }).click();
  await expect(page.getByText(/评分：测试教师 · 4 星 · 用户：测试用户/)).toBeVisible();
  await expect(page.getByText("undefined", { exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "取消" }).click();
  await expect(page.evaluate(() => localStorage.getItem("leafy-admin-session"))).resolves.toBeNull();
});

test("viewer sees evidence but no edit, export, or bulk controls", async ({ page }) => {
  const viewerIdentity = {
    admin: { id: "viewer-1", username: "viewer", display_name: "只读管理员", role: "viewer", active: true },
    permissions: permissions
      .filter((permission) => !["admins", "sessions", "audit-logs"].includes(permission.resource))
      .map((permission) => ({ resource: permission.resource, actions: ["list", "show"] })),
    session: { expires_at: "2099-01-01T00:00:00.000Z" },
  };
  let loggedIn = false;
  await page.route("**/api/admin/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname.endsWith("/login")) {
      loggedIn = true;
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(viewerIdentity) });
      return;
    }
    if (url.pathname.endsWith("/me")) {
      await route.fulfill(loggedIn
        ? { status: 200, contentType: "application/json", body: JSON.stringify(viewerIdentity) }
        : {
            status: 401,
            contentType: "application/json",
            headers: { "x-request-id": "e2e-viewer-login" },
            body: JSON.stringify({
              error: "登录已过期",
              errorEnvelope: { code: "unauthorized", message: "登录已过期", retryable: false },
            }),
          });
      return;
    }
    if (url.pathname.endsWith("/logout")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          data: { ok: true },
          meta: { request_id: "e2e-viewer-logout", audit_logged: true, duration_ms: 1 },
        }),
      });
      return;
    }
    if (url.pathname.endsWith("/actions")) {
      const body = route.request().postDataJSON() as { action: string };
      const data = body.action === "overview"
        ? { summary: { operations: {}, moderation: {}, feedback: {}, teachers: {} } }
        : body.action === "listCampuses"
          ? { items: [{ id: "campus-a", display_name: "测试大学" }], total: 1, page: 0, pageSize: 100 }
          : body.action === "listPosts"
            ? { items: [{ id: "post-1", title: "只读图片帖子", status: "pending_review", display_status: "publish_exception", upload_state: "publish_failed", image_count: 1, expected_image_count: 1, created_at: "2026-07-10T00:00:00Z" }], total: 1, page: 0, pageSize: 20 }
            : body.action === "listFeedback"
              ? { items: [{ id: "feedback-1", issue_type: "bug", body: "只读反馈", status: "open", created_at: "2026-07-12T00:00:00Z" }], total: 1, page: 0, pageSize: 20 }
              : { items: [], total: 0, page: 0, pageSize: 20 };
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ data }) });
      return;
    }
    await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ error: "not found" }) });
  });

  await page.goto("/admin");
  await page.getByLabel("账号").fill("viewer");
  await page.getByLabel("密码").fill("secret");
  await page.getByRole("button", { name: "登录" }).click();
  await page.getByText("帖子", { exact: true }).click();
  await expect(page.getByText("只读图片帖子")).toBeVisible();
  await expect(page.getByRole("button", { name: "查看" })).toBeVisible();
  await expect(page.getByRole("button", { name: "重新发布" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "下架异常" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "导出 CSV" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /批量/ })).toHaveCount(0);

  await page.getByText("反馈", { exact: true }).click();
  await expect(page.getByText("只读反馈")).toBeVisible();
  await expect(page.getByRole("button", { name: "编辑" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "导出 CSV" })).toHaveCount(0);
});
