import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";
const noStudentEmail = "org-a-no-student@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

test.describe("M1-T02 student list", () => {
  test("21. Vietnamese labels render on /students", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await expect(page.getByRole("heading", { name: "Học viên" })).toBeVisible();
    await expect(page.getByLabel("Tìm kiếm")).toBeVisible();
  });

  test("22. English labels render on /students", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("en");
    await expect(page.getByRole("heading", { name: "Students" })).toBeVisible();
    await expect(page.getByLabel("Search")).toBeVisible();
  });

  test("1. student.read can access student list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students?q=HV001");
    await expect(page.getByRole("table").getByText("HV001")).toBeVisible();
  });

  test("2. without student.read access is denied", async ({ page }) => {
    await signIn(page, noStudentEmail);
    await page.goto("/students");
    await expect(
      page.getByText(/do not have permission to read students|không có quyền đọc học viên/i),
    ).toBeVisible();
    await expect(page.getByText("HV001")).not.toBeVisible();
  });

  test("3. student.read without guardian.read hides primary contact data", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/students?q=HV001");
    const table = page.getByRole("table");
    await expect(table.getByText("HV001")).toBeVisible();
    await expect(table.getByText("0912345678")).toHaveCount(0);
    await expect(table.getByText(/primary contact|liên hệ chính/i)).toHaveCount(0);
  });

  test("5. with guardian.read primary contact is visible", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students?q=HV001");
    await expect(page.getByRole("table").getByText("0912345678")).toBeVisible();
  });

  test("6. guardian search finds student when permitted", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students?q=Lan&pageSize=25");
    await expect(page.getByRole("table").getByText("HV001")).toBeVisible();
  });

  test("4. guardian search does not leak without guardian.read", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/students?q=Lan&pageSize=25");
    await expect(page.getByText("HV001")).not.toBeVisible();
    await expect(page.getByText(/no students found|không tìm thấy học viên/i)).toBeVisible();
  });

  test("12. status filter works", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students?status=prospect");
    const table = page.getByRole("table");
    await expect(table.getByText("HV002")).toBeVisible();
    await expect(table.getByText("HV001")).toHaveCount(0);
  });

  test("21b. no-results state", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students?q=zzzznotfoundxxx");
    await expect(page.getByText(/no students found|không tìm thấy học viên/i)).toBeVisible();
  });
});
