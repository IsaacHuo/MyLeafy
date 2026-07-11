import { expect, test } from "@playwright/test";

test("keeps the public home page available", async ({ page }) => {
  const response = await page.goto("/");

  expect(response?.ok()).toBe(true);
  await expect(page).toHaveTitle("MyLeafy | Campus Timetable and Student Tools");
});
