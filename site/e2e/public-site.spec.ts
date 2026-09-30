import { expect, test } from "@playwright/test";

for (const width of [320, 390, 768, 1440]) {
  test(`public routes and downloads fit ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const scripts: string[] = [];
    page.on("request", request => { if (request.resourceType() === "script") scripts.push(request.url()); });
    for (const path of ["/", "/features", "/support", "/privacy", "/share/timetable/ABCDEFGHJKL2", "/share/community/post/123e4567-e89b-12d3-a456-426614174000", "/share/timetable/bad", "/missing"]) {
      await page.goto(path);
      await expect(page.locator("h1")).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    }
    expect(scripts.some(url => /AdminConsole|echarts/i.test(url))).toBe(false);
    await page.goto("/");
    const hero = page.locator(".home-hero");
    await expect(hero.getByRole("link", { name: "App Store 下载" })).toHaveAttribute("href", "https://apps.apple.com/cn/app/myleafy/id6763968535");
    await expect(hero.getByRole("link", { name: "Android 下载" })).toHaveAttribute("href", "https://api.myleafy.space/v1/releases/android/download");
    await expect(hero.getByRole("link", { name: "Android 下载" })).toBeInViewport();
  });
}

test("tabs respond to keyboard and rapid switches without changing section height", async ({ page }) => {
  await page.goto("/#explore");
  const tabs = page.getByRole("tab");
  const section = page.locator("#explore");
  const height = (await section.boundingBox())!.height;
  await tabs.first().focus();
  await page.keyboard.press("ArrowRight");
  await expect(tabs.nth(1)).toBeFocused();
  await expect(page.getByRole("tabpanel")).toHaveAttribute("id", "panel-community");
  await page.keyboard.press("End");
  await expect(tabs.last()).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("Home");
  for (let i = 0; i < 16; i++) await page.keyboard.press("ArrowRight");
  await expect(page.getByRole("tabpanel")).toHaveAttribute("id", "panel-timetable");
  expect(Math.abs((await section.boundingBox())!.height - height)).toBeLessThan(1);
  await page.getByRole("tabpanel").getByRole("link").click();
  await expect(page).toHaveURL(/\/features#timetable$/);
  await expect(page.locator("#timetable")).toBeFocused();
});

test("mobile menu closes, returns focus, and follows history", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  const menu = page.getByRole("button", { name: "打开导航菜单" });
  await menu.click();
await page.getByRole("navigation", { name: "移动端导航" }).getByRole("link", { name: "支持", exact: true }).focus();
  await page.keyboard.press("Escape");
  await expect(menu).toBeFocused();
  await expect(page.getByRole("navigation", { name: "移动端导航" })).toHaveCount(0);
  await menu.click();
  await page.getByRole("navigation", { name: "移动端导航" }).getByRole("link", { name: "支持", exact: true }).click();
  await expect(page.locator("h1")).toBeFocused();
  await expect(menu).toHaveAttribute("aria-expanded", "false");
  await page.getByRole("link", { name: "下载", exact: true }).click();
  await expect(page).toHaveURL(/\/#download$/);
  await expect(page.locator("#download")).toBeFocused();
  await page.reload();
  await expect(page.locator("#download")).toBeFocused();
  await page.goBack();
  await expect(page).toHaveURL(/\/support$/);
  await page.goForward();
  await expect(page).toHaveURL(/\/#download$/);
});

test("privacy anchors, FAQ and clipboard errors remain usable", async ({ page }) => {
  await page.goto("/privacy#privacy-rights");
  await expect(page.locator("#privacy-rights")).toBeFocused();
  await page.goto("/support");
  const faq = page.locator("summary").filter({ hasText: "Android 版怎么下载和更新" });
  await faq.click();
  await expect(faq.locator("..")).toHaveAttribute("open", "");
  await page.addInitScript(() => Object.defineProperty(navigator, "clipboard", { value: { writeText: () => Promise.reject(new Error("denied")) } }));
  await page.goto("/share/timetable/ABCDEFGHJKL2");
  await page.getByRole("button", { name: "复制邀请码" }).click();
  await expect(page.getByRole("status")).toContainText("无法访问剪贴板");
  await expect(page.getByRole("link", { name: "在 App 中接受" })).toHaveAttribute("href", "leafy://timetable-invite?code=ABCDEFGHJKL2");
});

test("image failure and reduced motion preserve visible content", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.route("**/media/app-*.webp", route => route.abort());
  await page.goto("/");
  await expect(page.locator(".home-hero").getByRole("status")).toContainText("界面预览暂时无法加载");
  await page.getByRole("tab", { name: "社区" }).click();
  await expect(page.getByRole("tabpanel")).toHaveAttribute("id", "panel-community");
  expect(await page.getByRole("tabpanel").evaluate(el => getComputedStyle(el).transitionDuration)).toBe("0s");
});

test("200 percent zoom keeps reading and controls available", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/");
  await page.evaluate(() => { document.documentElement.style.zoom = "2"; });
  await expect(page.locator("h1")).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.getByRole("tab", { name: "日迹" }).click();
  await expect(page.getByRole("tabpanel")).toHaveAttribute("id", "panel-schedule");
});
