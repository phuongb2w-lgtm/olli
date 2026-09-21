import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";

test.describe("M1-T03 student create/edit", () => {
  test("admin sees create student control on list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await expect(page.getByRole("link", { name: /create student|thêm học viên/i })).toBeVisible();
  });

  test("reader does not see create student control", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/students");
    await expect(page.getByRole("link", { name: /create student|thêm học viên/i })).toHaveCount(0);
  });

  test("reader cannot access create route", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/students/new");
    await expect(
      page.getByText(/do not have permission|không có quyền/i),
    ).toBeVisible();
  });

  test("admin can create a student", async ({ page }) => {
    const code = `E2E-${Date.now()}`;
    await signIn(page, adminEmail);
    await page.goto("/students/new");
    await page.getByLabel(/family name|họ/i).fill("E2E");
    await page.getByLabel(/given name|tên đệm/i).fill("Student");
    await page.getByLabel(/student code|mã học viên/i).fill(code);
    await page.getByRole("button", { name: /save|lưu/i }).click();
    await expect(page).toHaveURL(/\/students\?success=created/);
    await expect(page.getByText(/created successfully|tạo học viên thành công/i)).toBeVisible();
    await expect(page.getByRole("table").getByText(code)).toBeVisible();
  });

  test("admin sees edit link and can open edit form", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await page.getByRole("link", { name: /edit student|sửa học viên/i }).first().click();
    await expect(page.getByRole("heading", { name: /edit student|sửa học viên/i })).toBeVisible();
    await expect(page.getByLabel(/family name|họ/i)).not.toHaveValue("");
  });

  test("reader does not see edit links", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/students");
    await expect(page.getByRole("link", { name: /edit student|sửa học viên/i })).toHaveCount(0);
  });
});
