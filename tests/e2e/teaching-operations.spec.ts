import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";

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
    for (const className of ["Class A1", "Renamed Seed Class"]) {
      await page.goto(`/classes?q=${encodeURIComponent(className)}`);
      const row = page.getByRole("row").filter({ hasText: className });
      if ((await row.count()) === 0) continue;
      await row.getByRole("link", { name: /teaching|giảng dạy/i }).click();
      break;
    }
    await expect(page.getByRole("heading", { name: /recurring schedule|lịch học định kỳ/i })).toBeVisible();
    const weekdayPattern = /monday|tuesday|wednesday|thursday|friday|saturday|sunday|thứ/i;
    const scheduleList = page.getByRole("heading", { name: /recurring schedule|lịch học định kỳ/i }).locator("..").locator("..");
    const hasSchedule = await scheduleList.getByText(weekdayPattern).count();
    if (hasSchedule > 0) {
      await expect(scheduleList.getByText(weekdayPattern).first()).toBeVisible();
    } else {
      await expect(page.getByText(/no recurring schedule yet|chưa có lịch học định kỳ/i)).toBeVisible();
    }
  });
});
