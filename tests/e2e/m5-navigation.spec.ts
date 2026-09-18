import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

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

  test("4. admin executive page confirms access", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByText(/executive reporting access confirmed|đã xác nhận quyền truy cập/i),
    ).toBeVisible();
  });
});
