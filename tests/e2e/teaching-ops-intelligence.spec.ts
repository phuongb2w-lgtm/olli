import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const readerEmail = "org-a-reader@olli.local";
const teacherEmail = "m5-t05-teacher@olli.local";

test.describe("M5-T05 teaching operations intelligence", () => {
  test("1. manager opens executive operations", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/operations");
    await expect(
      page.getByRole("heading", { level: 1, name: /teaching operations|vận hành giảng dạy/i }),
    ).toBeVisible();
    await expect(page.getByText(/completed sessions|buổi học đã hoàn thành/i).first()).toBeVisible();
  });

  test("2. staff opens operations intelligence workspace", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/operations/intelligence");
    await expect(
      page.getByRole("heading", { level: 1, name: /operations intelligence|thông tin vận hành/i }),
    ).toBeVisible();
  });

  test("3. reader denied executive operations", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/executive/operations");
    await expect(
      page.getByText(/center managers only|quản lý trung tâm|center-wide/i),
    ).toBeVisible();
  });

  test("4. period filter on executive operations", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/operations");
    await expect(page.locator('input[name="start"]')).toBeVisible();
    await expect(page.locator('input[name="end"]')).toBeVisible();
  });

  test("5. workload drill-down link from executive operations", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/operations");
    await expect(
      page.getByRole("link", { name: /workload|khối lượng/i }),
    ).toBeVisible();
  });

  test("6. teacher personal my teaching page", async ({ page }) => {
    await signIn(page, teacherEmail);
    await page.goto("/operations/my-teaching");
    await expect(
      page.getByRole("heading", { level: 1, name: /my teaching|giảng dạy của tôi/i }),
    ).toBeVisible();
  });

  test("7. teacher denied executive operations route", async ({ page }) => {
    await signIn(page, teacherEmail);
    await page.goto("/executive/operations");
    await expect(
      page.getByText(/center managers only|quản lý trung tâm|center-wide/i),
    ).toBeVisible();
  });

  test("8. operations intelligence shows change history section", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/operations/intelligence");
    await expect(
      page.getByText(/recent changes|thay đổi gần đây/i),
    ).toBeVisible();
  });

  test("9. workload drill-down from intelligence workspace", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/operations/intelligence");
    await page.getByRole("link", { name: /teacher workload|khối lượng giáo viên/i }).click();
    await expect(page).toHaveURL(/\/operations\/workload/);
  });
});
