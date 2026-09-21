import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const accountantEmail = "org-a-staff@olli.local";
const consultantEmail = "m5-t04-consultant-a@olli.local";
const academicEmail = "m5-t03-academic@olli.local";
const teacherEmail = "m5-t05-teacher@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

test.describe("M5-T09 milestone acceptance smoke", () => {
  test.describe.configure({ timeout: 90_000 });

  test("manager executive walkthrough EN", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive?start=2026-01-01&end=2026-01-31&compare=0");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 60_000 });
    await page.goto("/executive/exceptions");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive exceptions|ngoại lệ điều hành/i }),
    ).toBeVisible();
    await page.goto("/executive/admissions?start=2026-01-01&end=2026-01-31");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  });

  test("accountant finance without executive", async ({ page }) => {
    await signIn(page, accountantEmail);
    await page.goto("/finance");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible({ timeout: 60_000 });
    await page.goto("/executive");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("consultant CRM without finance or executive", async ({ page }) => {
    await signIn(page, consultantEmail);
    await page.goto("/crm/my-work");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible({ timeout: 60_000 });
    await page.goto("/finance");
    await expect(
      page.getByText(/finance reporting|báo cáo tài chính|permission|quyền/i),
    ).toBeVisible();
    await page.goto("/executive");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("academic operations without executive cross-domain", async ({ page }) => {
    await signIn(page, academicEmail);
    await page.goto("/academic/review");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible({ timeout: 60_000 });
    await page.goto("/executive");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("teacher my teaching without center-wide executive ops", async ({ page }) => {
    await signIn(page, teacherEmail);
    await page.goto("/operations/my-teaching");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible({ timeout: 60_000 });
    await page.goto("/executive/operations");
    await expect(
      page.getByText(
        /executive reporting is available|báo cáo điều hành chỉ dành|center-wide teaching operations|toàn trung tâm chỉ dành cho quản lý/i,
      ),
    ).toBeVisible();
  });

  test("manager executive overview VI locale", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await expect(page.getByRole("button", { name: /đăng xuất/i })).toBeVisible();
    await page.goto("/executive");
    await expect(page.getByText(/tình hình tài chính/i)).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText(/hạng mục cần chú ý|cần chú ý/i)).toBeVisible();
  });
});
