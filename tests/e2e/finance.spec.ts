import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const readerEmail = "org-a-reader@olli.local";

test.describe("M2-T10 finance UI", () => {
  test("1. finance navigation visible with permission", async ({ page }) => {
    await signIn(page, adminEmail);
    const financeNav = page.locator('nav a[href="/finance"]');
    await expect(financeNav).toBeVisible();
    await financeNav.click();
    await expect(page).toHaveURL(/\/finance/);
  });

  test("2. overview renders finance categories", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance");
    await expect(page.getByText(/recognized revenue|doanh thu đã ghi nhận/i)).toBeVisible();
    await expect(page.getByText(/outstanding tuition|học phí còn nợ/i)).toBeVisible();
    await expect(page.getByText(/cash collected|tiền mặt đã thu/i)).toBeVisible();
  });

  test("3. enrollment summary distinguishes finance metrics labels", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await page.getByRole("link", { name: /enrollment history|lịch sử ghi danh/i }).first().click();
    const financeLink = page.locator('a[href*="/enrollments/"][href$="/finance"]').first();
    if (await financeLink.count()) {
      await financeLink.click();
      await expect(page.getByText(/financial summary|tóm tắt tài chính|net tuition|học phí ròng/i)).toBeVisible();
    } else {
      await expect(page.getByRole("heading", { name: /enrollment history|lịch sử ghi danh/i })).toBeVisible();
    }
  });

  test("4. payments list renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/payments");
    await expect(page.getByRole("heading", { name: /payments|thanh toán/i })).toBeVisible();
  });

  test("5. record payment form renders for admin", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/payments/new");
    await expect(page.getByRole("heading", { name: /record payment|ghi nhận thanh toán/i })).toBeVisible();
  });

  test("6. staff cannot see record payment action", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/finance/payments");
    await expect(page.getByRole("link", { name: /record payment|ghi nhận thanh toán/i })).toHaveCount(0);
  });

  test("7. costs page renders domains", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/costs");
    await expect(page.getByRole("heading", { name: /operating overhead|chi phí vận hành/i })).toBeVisible();
  });

  test("8. capital assets list renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/costs/assets");
    await expect(page.getByRole("heading", { name: /capital assets|tài sản cố định/i })).toBeVisible();
  });

  test("9. quick asset creation form renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/costs/assets/new?mode=quick");
    await expect(page.getByText(/quick setup|thiết lập nhanh/i)).toBeVisible();
  });

  test("10. personnel rules page renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/costs/personnel");
    await expect(page.getByText(/compensation rules|quy tắc lương/i)).toBeVisible();
    await expect(page.getByRole("heading", { name: /welfare fund baseline|mức cơ sở quỹ phúc lợi/i })).toBeVisible();
  });

  test("11. class economics index renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/class-economics");
    await expect(page.getByText(/select a class|chọn lớp học/i)).toBeVisible();
  });

  test("12. unallocated shared cost visible on costs", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/costs");
    await expect(page.getByText(/shared cost reconciliation|đối soát chi phí dùng chung/i)).toBeVisible();
  });

  test("13. simulator list renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/simulator");
    await expect(page.getByRole("heading", { name: /class simulator|mô phỏng lớp/i })).toBeVisible();
  });

  test("14. simulator draft form renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/simulator/new");
    await expect(page.getByText(/projected|dự kiến/i).first()).toBeVisible();
  });

  test("15. reader denied finance section", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/finance");
    await expect(page.getByText(/do not have permission|không có quyền/i)).toBeVisible();
  });

  test("16. VI locale renders finance UI", async ({ page }) => {
    test.setTimeout(90_000);
    await signIn(page, adminEmail);
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await expect(page.getByRole("button", { name: /đăng xuất/i })).toBeVisible();
    await page.goto("/finance");
    await expect(page.getByRole("main")).toBeVisible();
    await expect(page.getByText(/doanh thu đã ghi nhận/i)).toBeVisible({ timeout: 60_000 });
    await expect(page.getByRole("main").getByRole("link", { name: /^thanh toán$/i })).toBeVisible();
  });

  test("17. EN locale renders finance UI", async ({ page }) => {
    test.setTimeout(90_000);
    await signIn(page, adminEmail);
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("en");
    await expect(page.getByRole("button", { name: /sign out/i })).toBeVisible();
    await page.goto("/finance");
    await expect(page.getByRole("main")).toBeVisible();
    await expect(page.getByText(/recognized revenue/i)).toBeVisible({ timeout: 60_000 });
    await expect(page.getByRole("main").getByRole("link", { name: /^payments$/i })).toBeVisible();
  });

  test("18. empty states render on payments", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/payments");
    await expect(page.getByRole("heading", { name: /payments|thanh toán/i })).toBeVisible();
    await expect(
      page.getByText(/no payments recorded|chưa có thanh toán/i).or(page.locator("table tbody tr").first()),
    ).toBeVisible({ timeout: 10000 });
  });

  test("19. cash and revenue drill-down page renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/cash-revenue");
    await expect(
      page.getByRole("heading", { name: /cash & recognized revenue|tiền mặt & doanh thu đã ghi nhận/i }),
    ).toBeVisible();
  });

  test("20. receivables page renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance/receivables");
    await expect(
      page.getByRole("heading", { name: /outstanding tuition|học phí còn nợ/i }),
    ).toBeVisible();
  });

  test("21. finance overview period filter renders", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/finance");
    await expect(page.locator('input[name="start"]')).toBeVisible();
    await expect(page.locator('input[name="end"]')).toBeVisible();
  });
});
