import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

async function openSeededClassReports(page: import("@playwright/test").Page) {
  for (const className of ["Class A1", "Renamed Seed Class"]) {
    await page.goto(`/classes?q=${encodeURIComponent(className)}`);
    const row = page.getByRole("row").filter({ hasText: className });
    if ((await row.count()) === 0) continue;
    await row.getByRole("link", { name: /^Reports$|^Báo cáo$/i }).click();
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    return;
  }
  throw new Error("Seeded class not found for reports");
}

test.describe("M1-T10 reports", () => {
  test("admin can open class reports hub", async ({ page }) => {
    await signIn(page, adminEmail);
    await openSeededClassReports(page);
    await expect(page.getByRole("heading", { level: 1, name: /Reports|Báo cáo/i })).toBeVisible();
  });

  test("admin can open class attendance report", async ({ page }) => {
    await signIn(page, adminEmail);
    await openSeededClassReports(page);
    await page.getByRole("link", { name: /Attendance report|Báo cáo điểm danh/i }).click();
    await expect(
      page.getByRole("heading", { level: 1, name: /Attendance report|Báo cáo điểm danh/i }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: /Print|In/i })).toBeVisible();
  });

  test("admin can open learner progress report from enrollments", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await page.getByRole("link", { name: /enrollment|ghi danh/i }).first().click();
    await page
      .getByRole("link", { name: /Learner progress report|Báo cáo tiến độ học viên/i })
      .click();
    await expect(
      page.getByRole("heading", { level: 1, name: /Learner progress report|Báo cáo tiến độ học viên/i }),
    ).toBeVisible();
  });
});
