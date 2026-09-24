import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";
const staffEmail = "org-a-staff@olli.local";

test.describe("M5-T04 CRM admissions intelligence", () => {
  test.describe.configure({ timeout: 90_000 });

  test("1. manager can open executive admissions page", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/admissions?start=2026-01-01&end=2026-01-31");
    await expect(
      page.getByRole("heading", { level: 1, name: /crm.*admissions|crm.*tuyển sinh/i }),
    ).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText(/leads created|lead mới/i).first()).toBeVisible({ timeout: 60_000 });
  });

  test("2. manager sees consultant productivity section", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/admissions?start=2026-01-01&end=2026-01-31");
    await expect(
      page.getByText(/consultant productivity|năng suất tư vấn viên/i),
    ).toBeVisible({ timeout: 60_000 });
  });

  test("3. reader denied executive admissions", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/executive/admissions");
    await expect(
      page.getByText(/center managers only|quản lý trung tâm/i),
    ).toBeVisible();
  });

  test("4. staff denied executive admissions direct route", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/executive/admissions");
    await expect(
      page.getByText(/center managers only|quản lý trung tâm|executive reporting/i),
    ).toBeVisible();
  });

  test("5. period filter visible on admissions page", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/admissions?start=2026-01-01&end=2026-01-31");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 60_000 });
    await expect(page.locator('input[name="end"]')).toBeVisible({ timeout: 60_000 });
  });

  test("6. executive overview links to admissions", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(page.getByText(/admissions.*crm|tuyển sinh.*crm/i)).toBeVisible({
      timeout: 45_000,
    });
    const admissionsSection = page.locator("section").filter({
      has: page.getByRole("heading", {
        level: 2,
        name: /admissions.*crm|tuyển sinh.*crm/i,
      }),
    });
    const drillDown = admissionsSection.getByRole("link", {
      name: /view details|xem chi tiết/i,
    });
    const href = await drillDown.getAttribute("href");
    expect(href).toMatch(/\/executive\/admissions/);
    await page.goto(href!);
    await expect(page).toHaveURL(/\/executive\/admissions(\?|$)/);
  });

  test("7. admin can open CRM my work with performance metrics", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/crm/my-work");
    await expect(
      page.getByRole("heading", { name: /my work|công việc của tôi/i }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: /my performance|hiệu suất của tôi/i }),
    ).toBeVisible();
  });

  test("8. admissions exceptions section renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/admissions?start=2026-01-01&end=2026-01-31");
    await expect(
      page.getByText(/admissions exceptions|ngoại lệ tuyển sinh/i),
    ).toBeVisible({ timeout: 60_000 });
  });
});
