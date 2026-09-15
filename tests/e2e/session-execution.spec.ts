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

async function openSeededClassTeaching(page: import("@playwright/test").Page) {
  // course-class smoke renames seed "Class A1" → "Renamed Seed Class" before e2e runs in verify.
  for (const className of ["Class A1", "Renamed Seed Class"]) {
    await page.goto(`/classes?q=${encodeURIComponent(className)}`);
    const row = page.getByRole("row").filter({ hasText: className });
    if ((await row.count()) === 0) continue;
    await row.getByRole("link", { name: /^Teaching$|^Giảng dạy$/i }).click();
    await expect(page.getByRole("heading", { level: 1, name: new RegExp(className, "i") })).toBeVisible();
    return;
  }
  throw new Error("Seeded teaching class not found (Class A1 or Renamed Seed Class)");
}

test.describe("M1-T08 session execution", () => {
  test("admin can open session execution from teaching list", async ({ page }) => {
    await signIn(page, adminEmail);
    await openSeededClassTeaching(page);
    const openSession = page.getByRole("link", { name: /open session|mở buổi học/i }).first();
    await expect(openSession).toBeVisible({ timeout: 10000 });
    await openSession.click();
    await expect(
      page.getByRole("heading", { level: 1, name: /session execution|thực hiện buổi học/i }),
    ).toBeVisible();
  });

  test("staff can view session execution but not mark attendance", async ({ page }) => {
    await signIn(page, staffEmail);
    await openSeededClassTeaching(page);
    const openSession = page.getByRole("link", { name: /open session|mở buổi học/i }).first();
    await expect(openSession).toBeVisible({ timeout: 10000 });
    await openSession.click();
    await expect(
      page.getByRole("heading", { level: 1, name: /session execution|thực hiện buổi học/i }),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: /present|có mặt/i })).toHaveCount(0);
  });

  test("session execution shows not recorded label", async ({ page }) => {
    await signIn(page, adminEmail);
    await openSeededClassTeaching(page);
    const openLink = page.getByRole("link", { name: /open session|mở buổi học/i }).first();
    await expect(openLink).toBeVisible({ timeout: 10000 });
    await openLink.click();
    await expect(page.getByText(/not recorded|chưa điểm danh/i).first()).toBeVisible();
  });
});
