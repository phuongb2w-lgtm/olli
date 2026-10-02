import { expect, test, type Locator, type Page } from "@playwright/test";
import { signIn } from "./sign-in";

const consultantEmail = "m6-t04-consultant@olli.local";

async function ensureVietnamese(page: Page) {
  const lang = await page.locator("html").getAttribute("lang");
  if (lang === "vi") return;
  await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
  await expect(page.locator("html")).toHaveAttribute("lang", "vi", { timeout: 30_000 });
}

async function openConsultant(page: Page) {
  await page.goto("/consultant");
  await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
}

async function prepareGrid(page: Page) {
  await signIn(page, consultantEmail);
  await openConsultant(page);
  await ensureVietnamese(page);
  await openConsultant(page);
  for (const col of ["student_code", "lifecycle_status", "guardian_name", "guardian_phone", "tuition"]) {
    await page.getByTestId(`column-toggle-${col}`).setChecked(true);
  }
}

async function createIntakeRow(page: Page, guardianName: string, guardianPhone: string): Promise<Locator> {
  const newRow = page.getByTestId("portfolio-new-row");
  await newRow.getByTestId("inline-family-name").fill("PHÙNG VĂN");
  await newRow.getByTestId("inline-given-name").fill("ĐOÀN");
  await newRow.getByTestId("inline-date-of-birth").fill("2008-08-28");
  await newRow.getByTestId("inline-guardian-name").fill(guardianName);
  await newRow.getByTestId("inline-guardian-phone").fill(guardianPhone);
  await page.getByTestId("portfolio-save-new-row").click();

  const firstRow = page.getByTestId("portfolio-row").first();
  await expect(firstRow).toContainText(guardianPhone, { timeout: 30_000 });
  const entryId = (await firstRow.getAttribute("data-entry-id"))!;
  const row = page.locator(`[data-testid="portfolio-row"][data-entry-id="${entryId}"]`);

  await expect(row.getByTestId("portfolio-student-code")).toHaveText("02080000");
  await expect(row.getByTestId("portfolio-lifecycle-status")).toHaveText("Tiềm năng");
  await expect(row.getByTestId("portfolio-tuition")).toContainText("Chưa nộp phí");
  return row;
}

async function openDrawer(row: Locator, page: Page): Promise<Locator> {
  await row.getByTestId("portfolio-tuition-action").click();
  const drawer = page.getByTestId("payment-declaration-drawer");
  await expect(drawer).toBeVisible();
  return drawer;
}

async function assertPlanNotEstablished(drawer: Locator) {
  await expect(drawer.getByTestId("drawer-plan-not-established")).toBeVisible();
  await expect(drawer.getByTestId("drawer-fully-settled")).toHaveCount(0);
  await expect(drawer).not.toContainText("Học phí đã hoàn tất");
  await expect(drawer.getByTestId("drawer-total")).toHaveText("—");
  await expect(drawer.getByTestId("drawer-paid")).toHaveText("—");
  await expect(drawer.getByTestId("drawer-outstanding")).toHaveText("—");
  await expect(drawer.getByTestId("tuition-billing-mode")).toBeVisible();
}

async function fillPayment(drawer: Locator) {
  await drawer.getByTestId("drawer-amount").fill("2500000");
  await drawer.getByTestId("drawer-payment-method").selectOption("cash");
  await drawer.getByTestId("drawer-promotion").fill("12%");
  await drawer.getByTestId("drawer-note").fill("oK");
}

async function assertSubmittedPending(page: Page, row: Locator) {
  const drawer = page.getByTestId("payment-declaration-drawer");
  await expect(drawer).toHaveCount(0, { timeout: 30_000 });
  await expect(page.getByText("Không lưu được khai báo")).toHaveCount(0);
  await expect(row.getByTestId("portfolio-tuition")).toContainText(/chờ xác nhận/i, { timeout: 30_000 });

  const reopened = await openDrawer(row, page);
  await expect(reopened.getByTestId("drawer-pending")).toContainText(/2[.,\s]?500[.,\s]?000/);
  await expect(reopened.getByTestId("drawer-pending-initial")).toBeVisible();
  await expect(reopened.getByTestId("drawer-fully-settled")).toHaveCount(0);
  await expect(reopened.getByTestId("drawer-submit")).toBeDisabled();
  await expect(reopened.getByTestId("drawer-error")).toHaveCount(0);
  await page.keyboard.press("Escape");
  await expect(reopened).toHaveCount(0);
}

test.describe("CW2-T14 lead-first tuition declaration", () => {
  test.describe.configure({ mode: "serial", timeout: 180_000 });

  test("new intake: periodic first declaration submits to accounting", async ({ page }) => {
    await prepareGrid(page);
    const row = await createIntakeRow(page, "PHÙNG VĂN BÌNH", "0908280801");

    const drawer = await openDrawer(row, page);
    await assertPlanNotEstablished(drawer);

    await drawer.getByRole("radio", { name: /định kỳ|periodic/i }).check();
    await drawer.getByTestId("drawer-period-unit").selectOption("month");
    await drawer.getByTestId("drawer-amount-per-period").fill("2500000");
    await fillPayment(drawer);
    await drawer.getByTestId("drawer-submit").click();

    await assertSubmittedPending(page, row);

    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
    await expect(row.getByTestId("portfolio-tuition")).toContainText(/chờ xác nhận/i);
  });

  test("new intake: save draft then submit course lump sum", async ({ page }) => {
    await prepareGrid(page);
    const row = await createIntakeRow(page, "PHÙNG VĂN CƯỜNG", "0908280802");

    const drawer = await openDrawer(row, page);
    await assertPlanNotEstablished(drawer);

    await drawer.getByRole("radio", { name: /Nộp theo khóa học/i }).check();
    await drawer.getByTestId("drawer-course-total").fill("10000000");
    await fillPayment(drawer);
    await drawer.getByTestId("drawer-save-draft").click();

    await expect(drawer.getByTestId("drawer-save-draft")).toBeEnabled({ timeout: 30_000 });
    await expect(drawer.getByTestId("drawer-error")).toHaveCount(0);
    await expect(drawer).toBeVisible();

    await drawer.getByTestId("drawer-submit").click();
    await assertSubmittedPending(page, row);
  });
});
