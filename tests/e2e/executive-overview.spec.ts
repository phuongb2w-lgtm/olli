import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";

test.describe("M5-T06 executive overview", () => {
  test.describe.configure({ timeout: 90_000 });
  test("1. manager opens executive overview with four domains", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive overview|tổng quan điều hành/i }),
    ).toBeVisible({ timeout: 45_000 });
    await expect(page.getByText(/financial position|tình hình tài chính/i)).toBeVisible({
      timeout: 45_000,
    });
    await expect(page.getByText(/admissions.*crm|tuyển sinh.*crm/i)).toBeVisible();
    await expect(
      page.getByText(/learning.*service quality|chất lượng học tập.*dịch vụ/i),
    ).toBeVisible();
    await expect(page.getByText(/teaching operations|vận hành giảng dạy/i).first()).toBeVisible();
  });

  test("2. period filter on executive overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 45_000 });
    await expect(page.locator('input[name="end"]')).toBeVisible({ timeout: 45_000 });
  });

  test("3. drill-down links reach domain pages", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive overview|tổng quan điều hành/i }),
    ).toBeVisible({ timeout: 45_000 });
    await page
      .getByRole("link", { name: /view details|xem chi tiết/i })
      .first()
      .click({ timeout: 45_000 });
    await expect(page).toHaveURL(/\/finance|\/executive\//);
  });

  test("4. admissions drill-down from overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive overview|tổng quan điều hành/i }),
    ).toBeVisible({ timeout: 45_000 });
    const admissionsSection = page.locator("section").filter({
      has: page.getByRole("heading", {
        level: 2,
        name: /admissions.*crm|tuyển sinh.*crm/i,
      }),
    });
    const admissionsHref = await admissionsSection
      .getByRole("link", { name: /view details|xem chi tiết/i })
      .getAttribute("href");
    expect(admissionsHref).toMatch(/\/executive\/admissions/);
    await page.goto(admissionsHref!);
    await expect(page).toHaveURL(/\/executive\/admissions(\?|$)/);
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
    await expect(page.getByText(/needs attention|cần chú ý/i)).toBeVisible({
      timeout: 45_000,
    });
  });

  test("7. comparison checkbox on executive overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive?compare=1");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 45_000 });
    await expect(page.locator('input[name="compare"][type="checkbox"]')).toBeChecked();
  });

  test("8. Vietnamese locale executive overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await expect(page.getByRole("button", { name: /đăng xuất/i })).toBeVisible();
    await page.goto("/executive");
    await expect(page.getByText(/tình hình tài chính/i)).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText(/hạng mục cần chú ý|cần chú ý/i)).toBeVisible();
  });

  test("9. quality drill-down from overview", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive overview|tổng quan điều hành/i }),
    ).toBeVisible({ timeout: 45_000 });
    const qualitySection = page.locator("section").filter({
      has: page.getByRole("heading", {
        level: 2,
        name: /learning.*service quality|chất lượng học tập/i,
      }),
    });
    const qualityHref = await qualitySection
      .getByRole("link", { name: /view details|xem chi tiết/i })
      .getAttribute("href");
    expect(qualityHref).toMatch(/\/executive\/quality/);
    await page.goto(qualityHref!);
    await expect(page).toHaveURL(/\/executive\/quality(\?|$)/);
  });
});
