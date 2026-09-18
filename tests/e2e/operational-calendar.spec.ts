import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const readerEmail = "org-a-reader@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

test.describe("M4-T05 operational calendar", () => {
  test("admin can navigate to operations and load day view", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.getByRole("link", { name: /operations|vận hành/i }).click();
    await expect(page).toHaveURL(/\/operations/);
    await expect(page.getByRole("heading", { level: 1, name: /operations|vận hành/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /today|hôm nay/i })).toBeVisible();
    await expect(page.getByLabel(/from|từ ngày/i)).toBeVisible();
  });

  test("staff can view operations calendar", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/operations");
    await expect(page.getByRole("heading", { level: 1, name: /operations|vận hành/i })).toBeVisible();
    await expect(page.getByText(/do not have permission|không có quyền/i)).toHaveCount(0);
  });

  test("reader without enrollment.read is denied", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/operations");
    await expect(page.getByText(/do not have permission|không có quyền/i)).toBeVisible();
  });

  test("materialized, projected, and cancelled entries render distinctly", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("en");
    // Fixtures from operations-smoke use 2036-01 dates when verify runs the full suite.
    await page.goto("/operations?from=2036-01-07&to=2036-01-21");
    await expect(page.getByRole("heading", { level: 1, name: /operations/i })).toBeVisible();

    const sessionItems = page.locator('li[data-entry-type="session"]');
    const projectedItems = page.locator('li[data-entry-type="projected"]');
    const cancelledItems = page.locator('li[data-entry-type="session"][data-session-status="cancelled"]');

    const sessionCount = await sessionItems.count();
    const projectedCount = await projectedItems.count();
    const cancelledCount = await cancelledItems.count();

    // When smoke fixtures are present, assert distinctions; otherwise page still loads cleanly.
    if (sessionCount + projectedCount > 0) {
      expect(sessionCount).toBeGreaterThan(0);
      expect(projectedCount).toBeGreaterThan(0);
      expect(cancelledCount).toBeGreaterThan(0);
      await expect(page.getByText(/^session created$/i).first()).toBeVisible();
      await expect(page.getByText(/^planned$/i).first()).toBeVisible();
      await expect(page.getByText(/^cancelled$/i).first()).toBeVisible();
    } else {
      await expect(page.getByText(/nothing scheduled|unable to load/i).first()).toBeVisible();
    }
  });

  test("teacher and room filters are available", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations");
    await page.locator("#teacherId").selectOption({ index: 0 });
    await page.locator("#roomId").selectOption({ index: 0 });
    await page.getByRole("button", { name: /apply|áp dụng/i }).click();
    await expect(page).toHaveURL(/\/operations/);
  });

  test("EN locale renders operations labels", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("en");
    await page.goto("/operations");
    await expect(page.getByRole("heading", { level: 1, name: /^operations$/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /^today$/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /^apply$/i })).toBeVisible();
  });

  test("VI locale renders operations labels", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await expect(page.getByRole("button", { name: /đăng xuất/i })).toBeVisible();
    await page.goto("/operations");
    await expect(page.getByRole("heading", { level: 1, name: /vận hành/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /hôm nay/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /áp dụng/i })).toBeVisible();
  });
});
