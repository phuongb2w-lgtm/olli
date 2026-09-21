import { expect, type Page } from "@playwright/test";

const DEFAULT_PASSWORD = "testpass123";

/** Wait for Supabase Auth round-trip; local GoTrue can lag under full-suite load. */
export async function signIn(
  page: Page,
  email: string,
  password: string = DEFAULT_PASSWORD,
): Promise<void> {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  const leaveLogin = page.waitForURL((url) => !url.pathname.endsWith("/login"), {
    timeout: 60_000,
  });
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await leaveLogin;
  await expect(page).toHaveURL("/");
}
