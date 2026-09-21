import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";

test.describe("M5-T01 permission-aware navigation", () => {
  test("1. center manager sees executive overview nav", async ({ page }) => {
    await signIn(page, adminEmail);
    await expect(
      page.locator('nav a[href="/executive"]'),
    ).toBeVisible();
  });

  test("2. student reader does not see finance or admissions", async ({ page }) => {
    await signIn(page, readerEmail);
    await expect(page.locator('nav a[href="/finance"]')).toHaveCount(0);
    await expect(page.locator('nav a[href="/crm/leads"]')).toHaveCount(0);
    await expect(page.locator('nav a[href="/executive"]')).toHaveCount(0);
  });

  test("3. direct executive URL denied without permission", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/executive");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("4. admin executive page shows cross-domain overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByText(/financial position|tình hình tài chính/i),
    ).toBeVisible({ timeout: 60_000 });
  });
});
