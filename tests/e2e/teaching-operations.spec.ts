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

test.describe("M1-T07 teaching operations", () => {
  test("admin can open class teaching from classes list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /teaching|giảng dạy/i }).first().click();
    await expect(page.getByRole("heading", { level: 1, name: /teaching|giảng dạy/i })).toBeVisible();
    await expect(page.getByRole("heading", { name: /recurring schedule|lịch học định kỳ/i })).toBeVisible();
  });

  test("staff can view teaching but not add teacher", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /teaching|giảng dạy/i }).first().click();
    await expect(page.getByRole("heading", { level: 1, name: /teaching|giảng dạy/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /add teacher|thêm giáo viên/i })).toHaveCount(0);
  });

  test("admin can open rooms list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/rooms");
    await expect(page.getByRole("heading", { name: /rooms|phòng học/i })).toBeVisible();
  });

  test("schedule section shows localized weekday labels when slots exist", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /teaching|giảng dạy/i }).first().click();
    const weekdayPattern = /monday|tuesday|thứ/i;
    const hasSchedule = await page.getByText(weekdayPattern).count();
    if (hasSchedule > 0) {
      await expect(page.getByText(weekdayPattern).first()).toBeVisible();
    } else {
      await expect(page.getByText(/no recurring schedule|chưa có lịch học định kỳ/i)).toBeVisible();
    }
  });
});
