import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const unmappedEmail = "unmapped@olli.local";

test.describe("M0-T05 application smoke", () => {
  test("1. unauthenticated protected route redirects to login", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveURL(/\/login/);
  });

  test("2. valid local staff login succeeds", async ({ page }) => {
    await signIn(page, adminEmail);
    await expect(page).toHaveURL("/");
  });

  test("3. mapped active user reaches protected shell", async ({ page }) => {
    await signIn(page, adminEmail);
    await expect(page.getByText("Olli Test Org A")).toBeVisible();
    await expect(page.getByText("Org A Admin")).toBeVisible();
  });

  test("4. unmapped Auth user is denied", async ({ page }) => {
    await signIn(page, unmappedEmail);
    await expect(
      page.getByRole("heading", { name: /access denied|truy cập bị từ chối/i }),
    ).toBeVisible();
  });

  test("5. organization name shown is server-resolved", async ({ page }) => {
    await signIn(page, adminEmail);
    await expect(page.getByText("Olli Test Org A")).toBeVisible();
  });

  test("6. sign-out removes protected access", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.getByRole("button", { name: /sign out|đăng xuất/i }).click();
    await expect(page).toHaveURL(/\/login/);
    await page.goto("/");
    await expect(page).toHaveURL(/\/login/);
  });

  test("7. Vietnamese renders", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await expect(page.getByRole("button", { name: "Đăng nhập" })).toBeVisible();
  });

  test("8. English renders", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("en");
    await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
  });
});
