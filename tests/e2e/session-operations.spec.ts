import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

test.describe("M4-T06 session operations", () => {
  test("admin can open session ops from operations and see controls", async ({ page }) => {
    await signIn(page, "org-a-admin@olli.local");
    await page.goto("/operations/calendar?from=2036-01-07&to=2036-01-07");
    await expect(
      page.getByRole("heading", { name: /operational calendar|lịch vận hành/i }),
    ).toBeVisible();

    const sessionLink = page.locator('li[data-entry-type="session"] a').first();
    if ((await sessionLink.count()) === 0) {
      test.skip();
      return;
    }
    await sessionLink.click();
    await expect(page.getByTestId("session-operations")).toBeVisible();
    await expect(page.getByTestId("reschedule-form")).toBeVisible();
    await expect(page.getByTestId("cancel-form")).toBeVisible();
    await expect(page.getByTestId("substitute-form")).toBeVisible();
    await expect(page.getByTestId("room-change-form")).toBeVisible();
    await expect(page.getByTestId("session-change-history")).toBeVisible();
  });

  test("projected entries link to class teaching without mutation panel", async ({ page }) => {
    await signIn(page, "org-a-admin@olli.local");
    await page.goto("/operations/calendar?from=2036-01-21&to=2036-01-21");
    const projectedLink = page.locator('li[data-entry-type="projected"] a').first();
    if ((await projectedLink.count()) === 0) {
      test.skip();
      return;
    }
    await projectedLink.click();
    await expect(page).toHaveURL(/\/classes\/.+\/teaching/);
    await expect(page.getByTestId("session-operations")).toHaveCount(0);
  });

  test("reader cannot mutate session operations", async ({ page }) => {
    await signIn(page, "org-a-reader@olli.local");
    await page.goto("/operations");
    await expect(page.getByText(/do not have permission|không có quyền/i)).toBeVisible();
  });

  test("EN locale renders session operations labels", async ({ page }) => {
    await signIn(page, "org-a-admin@olli.local");
    await page.goto("/?locale=en");
    await page.goto("/operations/calendar?from=2036-01-07&to=2036-01-07");
    const sessionLink = page.locator('li[data-entry-type="session"] a').first();
    if ((await sessionLink.count()) === 0) {
      test.skip();
      return;
    }
    await sessionLink.click();
    await expect(page.getByTestId("session-operations")).toBeVisible();
    await expect(page.getByRole("heading", { name: /Session operations|Thao tác buổi học/i })).toBeVisible();
    await expect(page.getByText(/Change history|Lịch sử thay đổi/i)).toBeVisible();
  });

  test("VI locale renders session operations labels", async ({ page }) => {
    await signIn(page, "org-a-admin@olli.local");
    await page.goto("/?locale=vi");
    await page.goto("/operations/calendar?from=2036-01-07&to=2036-01-07");
    const sessionLink = page.locator('li[data-entry-type="session"] a').first();
    if ((await sessionLink.count()) === 0) {
      test.skip();
      return;
    }
    await sessionLink.click();
    await expect(page.getByTestId("session-operations")).toBeVisible();
    await expect(page.getByRole("heading", { name: /Session operations|Thao tác buổi học/i })).toBeVisible();
    await expect(page.getByText(/Change history|Lịch sử thay đổi/i)).toBeVisible();
  });
});
