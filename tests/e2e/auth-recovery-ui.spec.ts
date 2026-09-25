import { test, expect } from "@playwright/test";

test.describe("Auth recovery UI (M8-T04)", () => {
  test("login exposes forgot-password link", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByRole("link", { name: /forgot password|quên mật khẩu/i })).toBeVisible();
  });

  test("forgot-password form submits to neutral confirmation", async ({ page }) => {
    await page.goto("/forgot-password");
    await page.locator('input[name="email"]').fill("nobody@example.com");
    await page.getByRole("button", { name: /send reset|gửi liên kết/i }).click();
    await expect(page.getByRole("status")).toBeVisible({ timeout: 15_000 });
  });

  test("update-password without session shows expired guidance", async ({ page }) => {
    await page.goto("/update-password");
    await expect(page.getByRole("link", { name: /request a new|yêu cầu liên kết mới/i })).toBeVisible();
  });
});
