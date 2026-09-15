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

test.describe("M1-T05 course and class operations", () => {
  test("admin sees classes navigation and list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/classes");
    await expect(page.getByRole("heading", { name: /classes|lớp học/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /create class|thêm lớp học/i })).toBeVisible();
  });

  test("staff can read classes but not create", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/classes");
    await expect(page.getByRole("heading", { name: /classes|lớp học/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /create class|thêm lớp học/i })).toHaveCount(0);
  });

  test("staff cannot access create class route", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/classes/new");
    await expect(
      page.getByText(/do not have permission|không có quyền/i),
    ).toBeVisible();
  });

  test("admin can create a class", async ({ page }) => {
    const className = `E2E Class ${Date.now()}`;
    await signIn(page, adminEmail);
    await page.goto("/classes/new");
    await page.getByLabel(/class name|tên lớp/i).fill(className);
    await page.getByLabel(/^course$|chương trình/i).selectOption({ index: 1 });
    await page.getByRole("button", { name: /save|lưu/i }).click();
    await expect(page).toHaveURL(/\/classes\?success=created/);
    await expect(page.getByText(/created successfully|tạo lớp học thành công/i)).toBeVisible();
    await expect(page.getByRole("table").getByText(className)).toBeVisible();
  });

  test("admin can open courses list and create course", async ({ page }) => {
    const code = `E2E-${Date.now()}`;
    await signIn(page, adminEmail);
    await page.goto("/courses");
    await expect(page.getByRole("heading", { name: /courses|chương trình/i })).toBeVisible();
    await page.getByRole("link", { name: /create course|thêm chương trình/i }).click();
    await page.getByLabel(/course code|mã chương trình/i).fill(code);
    await page.getByLabel(/course name|tên chương trình/i).fill("E2E Course");
    await page.getByRole("button", { name: /save|lưu/i }).click();
    await expect(page).toHaveURL(/\/courses\?success=created/);
    await expect(page.getByRole("table").getByText(code)).toBeVisible();
  });

  test("admin sees edit class link", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /edit class|sửa lớp học/i }).first().click();
    await expect(page.getByRole("heading", { name: /edit class|sửa lớp học/i })).toBeVisible();
  });
});
