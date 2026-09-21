import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const readerEmail = "org-a-reader@olli.local";

test.describe("M5-T03 academic quality", () => {
  test("1. manager can open executive quality page", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/quality");
    await expect(page.getByText(/academic quality|chất lượng học thuật/i)).toBeVisible();
    await expect(page.getByText(/delivered sessions|buổi học đã dạy/i)).toBeVisible();
  });

  test("2. manager sees attendance rate metric", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/quality");
    await expect(page.getByText(/attendance rate|tỷ lệ điểm danh/i)).toBeVisible();
  });

  test("3. reader denied executive quality", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/executive/quality");
    await expect(
      page.getByText(/center managers only|quản lý trung tâm/i),
    ).toBeVisible();
  });

  test("4. executive overview links to quality", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(page.getByText(/learning.*service quality|chất lượng học tập/i)).toBeVisible({
      timeout: 45_000,
    });
    const qualitySection = page.locator("section").filter({
      has: page.getByRole("heading", {
        level: 2,
        name: /learning.*service quality|chất lượng học tập/i,
      }),
    });
    await qualitySection.getByRole("link", { name: /view details|xem chi tiết/i }).click();
    await expect(page).toHaveURL(/\/executive\/quality(\?|$)/);
  });

  test("5. period filter visible on quality page", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/quality");
    await expect(page.locator('input[name="start"]')).toBeVisible({ timeout: 60_000 });
    await expect(page.locator('input[name="end"]')).toBeVisible();
  });
});
