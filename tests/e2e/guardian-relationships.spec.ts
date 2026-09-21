import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";
const studentTranPath = "/students/a5100000-0000-4000-8000-000000000001/guardians";

test.describe("M1-T04 guardian relationships", () => {
  test("admin can access student guardians page", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(studentTranPath);
    await expect(page.getByRole("heading", { name: /guardians|phụ huynh/i })).toBeVisible();
    await expect(page.getByText("0912345678")).toBeVisible();
  });

  test("reader without guardian.read is denied", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto(studentTranPath);
    await expect(page.getByText(/do not have permission|không có quyền/i)).toBeVisible();
  });

  test("admin sees guardians link on student list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await expect(page.getByRole("link", { name: /guardians|phụ huynh/i }).first()).toBeVisible();
  });

  test("reader does not see guardians link", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/students");
    await expect(page.getByRole("link", { name: /guardians|phụ huynh/i })).toHaveCount(0);
  });
});
