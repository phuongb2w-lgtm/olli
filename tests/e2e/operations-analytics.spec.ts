import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";
const password = "testpass123";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

test.describe("M4-T07 operations analytics", () => {
  test("authorized user opens workload view", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations/workload");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByRole("link", { name: /workload|khối lượng/i })).toBeVisible();
  });

  test("teacher and room metrics render", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations/workload");
    await expect(
      page.getByRole("heading", { level: 2, name: /teacher workload|khối lượng giáo viên/i }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { level: 2, name: /room usage|sử dụng phòng/i }),
    ).toBeVisible();
    await expect(
      page.getByRole("columnheader", { name: /scheduled sessions|buổi đã lên lịch/i }).first(),
    ).toBeVisible();
    await expect(
      page.getByRole("columnheader", { name: /booked sessions|buổi đã đặt/i }).first(),
    ).toBeVisible();
  });

  test("projected vs scheduled distinction visible", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations/workload");
    await expect(
      page.getByRole("columnheader", { name: /projected sessions|buổi dự kiến/i }).first(),
    ).toBeVisible();
    await expect(
      page.getByRole("columnheader", { name: /scheduled sessions|buổi đã lên lịch/i }).first(),
    ).toBeVisible();
    await expect(
      page.getByText(/projected = future timetable|dự kiến = buổi tương lai/i).first(),
    ).toBeVisible();
  });

  test("date range filter applies", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations/workload");
    await page.locator("#from").fill("2039-01-01");
    await page.locator("#to").fill("2039-01-31");
    await page.getByRole("button", { name: /apply|áp dụng/i }).click();
    await expect(page).toHaveURL(/from=2039-01-01/);
    await expect(page).toHaveURL(/to=2039-01-31/);
  });

  test("unauthorized access blocked", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/operations/workload");
    await expect(page.getByText(/do not have permission|không có quyền/i)).toBeVisible();
  });

  test("VI labels render correctly", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations/workload");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await page.reload();
    await expect(page.getByRole("heading", { level: 1, name: /khối lượng giảng dạy/i })).toBeVisible();
    await expect(page.getByRole("heading", { level: 2, name: /khối lượng giáo viên/i })).toBeVisible();
    await expect(page.getByRole("heading", { level: 2, name: /sử dụng phòng/i })).toBeVisible();
  });

  test("operations subnav links calendar and workload", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations/workload");
    await page.getByRole("link", { name: /today|hôm nay/i }).click();
    await expect(page).toHaveURL(/\/operations$/);
    await page.getByRole("link", { name: /calendar|lịch vận hành/i }).click();
    await expect(page).toHaveURL(/\/operations\/calendar/);
    await page.getByRole("link", { name: /workload|khối lượng/i }).click();
    await expect(page).toHaveURL(/\/operations\/workload/);
  });
});
