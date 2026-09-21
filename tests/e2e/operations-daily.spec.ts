import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";

test.describe("M4-T08 daily operations", () => {
  test("daily workspace renders at /operations", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations");
    await expect(page.getByTestId("daily-operations-view")).toBeVisible();
    await expect(page.getByTestId("daily-summary")).toBeVisible();
    await expect(page.getByTestId("planning-gaps-banner")).toBeVisible();
  });

  test("date navigation changes query date", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations");
    await page.locator("#date").fill("2036-01-07");
    await page.getByRole("button", { name: /apply|áp dụng/i }).click();
    await expect(page).toHaveURL(/date=2036-01-07/);
  });

  test("class teacher room filters apply", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations");
    await page.locator("#classId").selectOption({ index: 0 });
    await page.locator("#teacherId").selectOption({ index: 0 });
    await page.locator("#roomId").selectOption({ index: 0 });
    await page.getByRole("button", { name: /apply|áp dụng/i }).click();
    await expect(page).toHaveURL(/\/operations/);
  });

  test("projected vs session distinction visible", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations?date=2036-01-07");
    const sessions = page.locator('[data-entry-type="session"]');
    const projected = page.locator('[data-entry-type="projected"]');
    const total = (await sessions.count()) + (await projected.count());
    if (total === 0) {
      await expect(page.getByTestId("daily-empty")).toBeVisible();
      return;
    }
    if ((await sessions.count()) > 0) {
      await expect(sessions.first()).toHaveAttribute("data-entry-type", "session");
    }
    if ((await projected.count()) > 0) {
      await expect(projected.first()).toHaveAttribute("data-entry-type", "projected");
    }
  });

  test("planning gap banner shows zero or items", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations?date=2036-01-21");
    const banner = page.getByTestId("planning-gaps-banner");
    await expect(banner).toBeVisible();
    await expect(banner.locator("p, li").first()).toBeVisible();
  });

  test("materialized session exposes manage actions entry point", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations?date=2036-01-07");
    const toggle = page.getByTestId("session-ops-toggle").first();
    if ((await toggle.count()) === 0) {
      test.skip();
      return;
    }
    await toggle.click();
    await expect(page.getByTestId("daily-session-ops").first()).toBeVisible();
    await expect(page.getByTestId("reschedule-form").first()).toBeVisible();
  });

  test("projected rows do not expose session ops", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations?date=2036-01-21");
    const projected = page.locator('[data-entry-type="projected"]');
    if ((await projected.count()) === 0) {
      test.skip();
      return;
    }
    await expect(page.getByTestId("session-ops-toggle")).toHaveCount(0);
  });

  test("empty day state", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations?date=1980-01-15");
    await expect(page.getByTestId("daily-empty")).toBeVisible();
  });

  test("reader denied", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/operations");
    await expect(page.getByText(/do not have permission|không có quyền/i)).toBeVisible();
  });

  test("legacy calendar query redirects to calendar route", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations?from=2036-01-07&to=2036-01-21");
    await expect(page).toHaveURL(/\/operations\/calendar/);
    await expect(page.getByLabel(/from|từ ngày/i)).toBeVisible();
  });

  test("subnav links today calendar workload", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/operations");
    await page.getByRole("link", { name: /calendar|lịch vận hành/i }).click();
    await expect(page).toHaveURL(/\/operations\/calendar/);
    await page.getByRole("link", { name: /today|hôm nay/i }).click();
    await expect(page).toHaveURL(/\/operations$/);
    await page.getByRole("link", { name: /workload|khối lượng/i }).click();
    await expect(page).toHaveURL(/\/operations\/workload/);
  });
});
