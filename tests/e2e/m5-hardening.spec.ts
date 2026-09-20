import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const readerEmail = "org-a-reader@olli.local";
const consultantEmail = "m5-t04-consultant-a@olli.local";
const teacherEmail = "m5-t05-teacher@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

test.describe("M5-T08 management intelligence hardening", () => {
  test.describe.configure({ timeout: 90_000 });
  test("1. executive drill-down preserves reporting period", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive?start=2026-01-01&end=2026-01-31&compare=0");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 60_000 });
    await page
      .getByRole("link", { name: /view details|xem chi tiết/i })
      .first()
      .click();
    await expect(page).toHaveURL(/start=2026-01-01/);
    await expect(page).toHaveURL(/end=2026-01-31/);
    await expect(page).toHaveURL(/compare=0/);
  });

  test("2. compare previous can be disabled from period form", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive?compare=1");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 60_000 });
    await page.locator('input[name="compare"][type="checkbox"]').uncheck();
    await page.getByRole("button", { name: /apply|áp dụng/i }).click();
    await expect(page).toHaveURL(/compare=0/);
  });

  test("3. staff cannot access executive overview directly", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/executive");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("4. consultant cannot access executive exceptions", async ({ page }) => {
    await signIn(page, consultantEmail);
    await page.goto("/executive/exceptions");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("5. teacher cannot access executive operations intelligence", async ({ page }) => {
    await signIn(page, teacherEmail);
    await page.goto("/executive/operations");
    await expect(
      page.getByText(
        /executive reporting is available|báo cáo điều hành chỉ dành|center-wide teaching operations|toàn trung tâm chỉ dành cho quản lý/i,
      ),
    ).toBeVisible();
  });

  test("6. reader cannot access finance intelligence", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/finance");
    await expect(
      page.getByText(/finance reporting|báo cáo tài chính|permission|quyền/i),
    ).toBeVisible();
  });

  test("7. manager navigates executive domain surfaces", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await page.goto("/executive/admissions");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await page.goto("/executive/quality");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await page.goto("/executive/operations");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await page.goto("/executive/exceptions");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive exceptions|ngoại lệ điều hành/i }),
    ).toBeVisible();
  });

  test("8. attendance rate shows unavailable not zero money on executive overview", async ({
    page,
  }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 60_000 });
    const attendanceCard = page.locator("section").filter({
      has: page.getByRole("heading", {
        level: 2,
        name: /learning.*service quality|chất lượng học tập/i,
      }),
    });
    await expect(attendanceCard.getByText(/attendance rate|tỷ lệ điểm danh/i)).toBeVisible();
    await expect(attendanceCard.locator("text=₫")).toHaveCount(0);
  });
});
