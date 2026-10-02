import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const consultantEmail = "m6-t04-consultant@olli.local";

/**
 * CW2-T10: thin E2E integration smoke — authoritative UI surfaces wired together.
 * Domain invariants are proven in supabase/tests/cw2_t10_milestone_acceptance_tests.sql.
 */
test.describe("CW2-T10 Consultant Workspace V2 integration smoke", () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page, consultantEmail);
  });

  test("1. workspace grid and monthly sales header load", async ({ page }) => {
    await page.goto("/consultant");
    await expect(page.getByTestId("consultant-workspace")).toBeVisible();
    await expect(page.getByTestId("consultant-monthly-sales-header")).toBeVisible();
  });

  test("2. declaration drawer opens from grid context", async ({ page }) => {
    await page.goto("/consultant");
    await expect(page.getByTestId("consultant-workspace")).toBeVisible();
    const declareBtn = page.getByTestId("portfolio-tuition-action").first();
    if ((await declareBtn.count()) === 0) {
      test.skip(true, "No eligible declare row in seed — covered by CW2-T07 E2E mocks");
    }
    await declareBtn.click();
    await expect(page.getByTestId("payment-declaration-drawer")).toBeVisible();
  });

  test("3. portfolio details route uses T09 contract", async ({ page }) => {
    await page.goto("/consultant");
    const details = page.getByTestId("portfolio-details-link").first();
    if ((await details.count()) === 0) {
      test.skip(true, "No portfolio rows in seed — SQL acceptance covers detail RPC");
    }
    const href = await details.getAttribute("href");
    expect(href).toMatch(/^\/consultant\/portfolio\/[0-9a-f-]+(\?return=.*)?$/i);
  });

  test("4. 390px viewport keeps critical actions reachable", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/consultant");
    await expect(page.getByTestId("consultant-workspace")).toBeVisible();
    await expect(page.getByTestId("consultant-monthly-sales-header")).toBeVisible();
  });
});
