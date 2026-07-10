import { expect, test } from "@playwright/test";

const permissions = [
  "dashboard", "manual", "campuses", "campus-requests", "posts", "polls", "comments", "reports",
  "profiles", "feedback", "announcements", "postgraduate", "postgraduate-suggestions", "suggestions",
  "teachers", "courses", "dishes", "ratings", "semester-configs", "national-calendar",
].map((resource) => ({ resource, actions: ["list", "show", "create", "edit", "delete", "bulk", "export"] }));

const identity = {
  admin: { id: "admin-1", username: "operator", display_name: "运营管理员", role: "operator", active: true },
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
        ? { summary: { operations: { totalProfiles: 12, newProfilesToday: 1, daily: [] }, moderation: {}, feedback: {}, teachers: {} } }
        : body.action === "listCampuses"
          ? { items: [{ id: "campus-a", display_name: "测试大学" }], total: 1, page: 0, pageSize: 100 }
          : body.action === "listPosts"
            ? { items: [{ id: "post-1", title: "测试帖子", status: "published", created_at: "2026-07-10T00:00:00Z" }], total: 1, page: 0, pageSize: 20 }
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

  await page.getByText("帖子", { exact: true }).click();
  await expect(page).toHaveURL(/\/admin\/posts/);
  await expect(page.getByText("测试帖子")).toBeVisible();
  await expect(page.evaluate(() => localStorage.getItem("leafy-admin-session"))).resolves.toBeNull();
});
