import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";

test.describe("M3 CRM reports", () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page, adminEmail);
  });

  test("1. admin can access CRM reports", async ({ page }) => {
    await page.goto("/crm/reports");
    await expect(page.getByRole("heading", { name: /CRM reports|Báo cáo CRM/i })).toBeVisible();
    await expect(page.getByRole("heading", { name: /Funnel|Phễu/i })).toBeVisible();
  });

  test("2. reports navigation is visible under admissions", async ({ page }) => {
    await page.goto("/crm/leads");
    await expect(page.getByRole("link", { name: /Reports|Báo cáo/i })).toBeVisible();
  });

  test("3. date filter form renders", async ({ page }) => {
    await page.goto("/crm/reports");
    await expect(page.locator('input[name="startDate"]')).toBeVisible();
    await expect(page.locator('input[name="endDate"]')).toBeVisible();
  });

  test("4. source breakdown renders", async ({ page }) => {
    await page.goto("/crm/reports");
    await expect(page.getByRole("heading", { name: /Source performance|Hiệu suất nguồn/i })).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Unattributed|Chưa xác định/i }).first(),
    ).toBeVisible();
  });

  test("5. campaign breakdown renders", async ({ page }) => {
    await page.goto("/crm/reports");
    await expect(page.getByRole("heading", { name: /Campaign performance|Hiệu suất chiến dịch/i })).toBeVisible();
  });

});

test.describe("M3 CRM reports access", () => {
  test("6. reader without lead.read is denied", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/crm/reports");
    await expect(page.getByText(/do not have permission|không có quyền/i)).toBeVisible();
  });
});
