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

test.describe("M5-T06 executive overview", () => {
  test("1. manager opens executive overview with four domains", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive overview|tổng quan điều hành/i }),
    ).toBeVisible();
    await expect(page.getByText(/financial position|tình hình tài chính/i)).toBeVisible();
    await expect(page.getByText(/admissions.*crm|tuyển sinh.*crm/i)).toBeVisible();
    await expect(
      page.getByText(/learning.*service quality|chất lượng học tập.*dịch vụ/i),
    ).toBeVisible();
    await expect(page.getByText(/teaching operations|vận hành giảng dạy/i).first()).toBeVisible();
  });

  test("2. period filter on executive overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(page.locator('input[name="start"]')).toBeVisible();
    await expect(page.locator('input[name="end"]')).toBeVisible();
  });

  test("3. drill-down links reach domain pages", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await page.getByRole("link", { name: /view details|xem chi tiết/i }).first().click();
    await expect(page).toHaveURL(/\/finance|\/executive\//);
  });

  test("4. admissions drill-down from overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    const admissionsSection = page.locator("section").filter({
      has: page.getByRole("heading", {
        level: 2,
        name: /admissions.*crm|tuyển sinh.*crm/i,
      }),
    });
    await admissionsSection.getByRole("link", { name: /view details|xem chi tiết/i }).click();
    await expect(page).toHaveURL("/executive/admissions");
  });

  test("5. reader denied executive overview", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/executive");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("6. needs attention section renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(page.getByText(/needs attention|cần chú ý/i)).toBeVisible();
  });

  test("7. comparison checkbox on executive overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive?compare=1");
    await expect(page.locator('input[name="compare"]')).toBeChecked();
  });

  test("8. Vietnamese locale executive overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/settings");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await page.goto("/executive");
    await expect(page.getByText(/tình hình tài chính/i)).toBeVisible();
    await expect(page.getByText(/cần chú ý/i)).toBeVisible();
  });

  test("9. quality drill-down from overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    const qualitySection = page.locator("section").filter({
      has: page.getByRole("heading", {
        level: 2,
        name: /learning.*service quality|chất lượng học tập/i,
      }),
    });
    await qualitySection.getByRole("link", { name: /view details|xem chi tiết/i }).click();
    await expect(page).toHaveURL("/executive/quality");
  });
});
