import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

async function openSeededClassAssessments(page: import("@playwright/test").Page) {
  for (const className of ["Class A1", "Renamed Seed Class"]) {
    await page.goto(`/classes?q=${encodeURIComponent(className)}`);
    const row = page.getByRole("row").filter({ hasText: className });
    if ((await row.count()) === 0) continue;
    await row.getByRole("link", { name: /^Assessments$|^Đánh giá$/i }).click();
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    return;
  }
  throw new Error("Seeded class not found for assessments");
}

test.describe("M1-T09 assessments", () => {
  test("admin can open class assessments list", async ({ page }) => {
    await signIn(page, adminEmail);
    await openSeededClassAssessments(page);
    await expect(page.getByRole("heading", { level: 1, name: /Assessments|Đánh giá/i })).toBeVisible();
  });

  test("staff can view assessments but not create", async ({ page }) => {
    await signIn(page, staffEmail);
    await openSeededClassAssessments(page);
    await expect(page.getByRole("button", { name: /create assessment|tạo bài đánh giá/i })).toHaveCount(0);
  });

  test("admin can open student academic progress", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await page.getByRole("link", { name: /enrollment|ghi danh/i }).first().click();
    await page.getByRole("link", { name: /academic progress|tiến độ học tập/i }).click();
    await expect(page.getByRole("heading", { level: 1, name: /academic progress|tiến độ học tập/i })).toBeVisible();
  });
});
