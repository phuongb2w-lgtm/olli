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

test.describe("M5-T07 executive exceptions", () => {
  test("1. manager opens executive overview worklist entry", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive");
    await expect(
      page.getByRole("heading", { name: /exception worklist|danh sách ngoại lệ/i }),
    ).toBeVisible();
    await page.getByRole("link", { name: /open exception worklist|mở danh sách ngoại lệ/i }).first().click();
    await expect(page).toHaveURL(/\/executive\/exceptions/);
  });

  test("2. exceptions page shows filters and period", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/exceptions");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive exceptions|ngoại lệ điều hành/i }),
    ).toBeVisible();
    await expect(page.locator('input[name="start"][type="date"]')).toBeVisible();
    await expect(page.locator('select[name="domain"]')).toBeVisible();
  });

  test("3. domain filter applies", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/exceptions");
    await page.locator('select[name="domain"]').selectOption("finance");
    await page.getByRole("button", { name: /apply filters|áp dụng bộ lọc/i }).click();
    await expect(page).toHaveURL(/domain=finance/);
  });

  test("4. drill-down link when exceptions exist", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/exceptions");
    const drillDown = page.getByRole("link", { name: /drill down|xem chi tiết/i }).first();
    if ((await drillDown.count()) > 0) {
      await drillDown.click();
      await expect(page).toHaveURL(/\/finance|\/executive\/|\/classes\/|\/academic\/|\/crm\//);
      await page.goto("/executive/exceptions");
    } else {
      await expect(page.getByText(/no exceptions match|không có ngoại lệ phù hợp/i)).toBeVisible();
    }
  });

  test("5. management follow-up persists after refresh", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/exceptions");
    const firstRow = page.locator("ul.space-y-4 > li").first();
    const saveButton = firstRow.getByRole("button", { name: /save follow-up|lưu theo dõi/i });
    if ((await saveButton.count()) === 0) {
      await expect(page.getByText(/no exceptions match|không có ngoại lệ phù hợp/i)).toBeVisible();
      return;
    }
    const note = `E2E follow-up ${Date.now()}`;
    await firstRow.locator('textarea[name="note"]').fill(note);
    await firstRow.locator('select[name="status"]').selectOption("acknowledged");
    await saveButton.click();
    await expect(firstRow.locator('select[name="status"]')).toHaveValue("acknowledged", {
      timeout: 15000,
    });
    await page.reload();
    await expect(page.locator("ul.space-y-4 > li").first().locator('select[name="status"]')).toHaveValue(
      "acknowledged",
    );
    await expect(page.locator("ul.space-y-4 > li").first().locator('textarea[name="note"]')).toHaveValue(note);
  });

  test("6. source state label visible independently of follow-up", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/exceptions");
    const sourceLabel = page.getByText(/source:|nguồn:/i).first();
    if ((await sourceLabel.count()) > 0) {
      await expect(sourceLabel).toBeVisible();
    } else {
      await expect(page.getByText(/no exceptions match|không có ngoại lệ phù hợp/i)).toBeVisible();
    }
  });

  test("7. reader denied executive exceptions workspace", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/executive/exceptions");
    await expect(
      page.getByText(/executive reporting is available|báo cáo điều hành chỉ dành/i),
    ).toBeVisible();
  });

  test("8. Vietnamese locale executive exceptions", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/settings");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await page.goto("/executive/exceptions");
    await expect(
      page.getByRole("heading", { level: 1, name: /ngoại lệ điều hành/i }),
    ).toBeVisible();
  });

  test("9. empty state when filters exclude all rows", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/executive/exceptions?exceptionCode=__no_such_code__");
    await expect(page.getByText(/no exceptions match|không có ngoại lệ phù hợp/i)).toBeVisible();
  });
});
