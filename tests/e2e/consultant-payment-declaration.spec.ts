import { expect, test, type Page } from "@playwright/test";
import { signIn } from "./sign-in";

/** Grid keyboard focus ring can intercept Playwright clicks on row 0; DOM click still fires handlers. */
async function openEligibleDeclarationDrawer(page: Page) {
  await page.getByTestId("declare-payment-action").nth(0).evaluate((el) => {
    (el as HTMLButtonElement).click();
  });
}

const consultantEmail = "m6-t04-consultant@olli.local";

const eligibleRow = {
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000101",
  workspace_sequence: 50,
  lead_id: null,
  student_id: "a6200000-0000-4000-8000-000000000101",
  display_subject_id: "a6200000-0000-4000-8000-000000000101",
  subject_type: "student",
  family_name: "Tran",
  given_name: "Eligible",
  student_code_official: null,
  student_code_display: "26000099",
  student_code_is_provisional: true,
  lifecycle_status: "ghi_danh",
  lifecycle_status_label: "Registered",
  primary_guardian_id: "a6300000-0000-4000-8000-000000000101",
  primary_guardian_name: "Guardian",
  primary_guardian_phone: "0902000001",
  course_id: "a6400000-0000-4000-8000-000000000101",
  course_name: "Python Basics",
  class_id: null,
  class_name: null,
  enrollment_id: "a6500000-0000-4000-8000-000000000101",
  enrollment_financial_terms_id: "a6600000-0000-4000-8000-000000000101",
  tuition_total_net: 10_000_000,
  tuition_paid: 3_000_000,
  tuition_outstanding: 7_000_000,
  tuition_payment_state: "mot_phan",
  tuition_payment_state_label: "Partial",
  declaration_id: null,
  declaration_status: null,
  declaration_workflow_kind: null,
  portfolio_entered_at: "2026-01-01T00:00:00Z",
  student_details_subject_id: "a6200000-0000-4000-8000-000000000101",
  is_hidden: false,
  custom_fields: [],
  capabilities: {
    can_edit_contact: true,
    can_open_payment_declaration: true,
    can_create_payment_declaration: true,
    can_edit_payment_declaration: false,
    can_submit_declaration: false,
    can_add_payment: false,
    can_open_student_details: true,
  },
};

const fullPhiRow = {
  ...eligibleRow,
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000102",
  workspace_sequence: 49,
  tuition_outstanding: 0,
  tuition_paid: 10_000_000,
  tuition_payment_state: "full_phi",
  tuition_payment_state_label: "Paid in full",
  capabilities: {
    ...eligibleRow.capabilities,
    can_open_payment_declaration: false,
    can_create_payment_declaration: false,
  },
};

const pendingRow = {
  ...eligibleRow,
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000103",
  workspace_sequence: 48,
  declaration_id: "a6700000-0000-4000-8000-000000000101",
  declaration_status: "pending",
  declaration_workflow_kind: "cw2_payment",
  tuition_payment_state: "cho_xac_nhan",
  tuition_payment_state_label: "Pending confirmation",
  capabilities: {
    ...eligibleRow.capabilities,
    can_create_payment_declaration: false,
    can_edit_payment_declaration: false,
    can_submit_declaration: false,
  },
};

function portfolioRoute(rows: unknown[]) {
  return { rows, has_more: false, next_cursor: null };
}

test.describe("CW2-T07 payment declaration drawer", () => {
  test.beforeEach(async ({ page }) => {
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      await route.fulfill({ json: portfolioRoute([eligibleRow, fullPhiRow, pendingRow]) });
    });
    await signIn(page, consultantEmail);
    await page.goto("/consultant");
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
  });

  test("eligible row shows declare payment action", async ({ page }) => {
    await expect(page.getByTestId("declare-payment-action").first()).toBeVisible();
    await expect(page.getByTestId("declare-payment-action")).toHaveCount(2);
  });

  test("full phí row has no declare action", async ({ page }) => {
    const rows = page.getByTestId("portfolio-row");
    await expect(rows.nth(1).getByTestId("declare-payment-action")).toHaveCount(0);
  });

  test("pending row shows pending tuition state", async ({ page }) => {
    await expect(page.getByTestId("portfolio-tuition").nth(2)).toContainText(/pending|chờ/i);
  });

  test("drawer opens with financial context", async ({ page }) => {
    await openEligibleDeclarationDrawer(page);
    const drawer = page.getByTestId("payment-declaration-drawer");
    await expect(drawer).toBeVisible();
    await expect(drawer.getByTestId("drawer-course")).toContainText("Python Basics");
    await expect(drawer.getByTestId("drawer-total")).toBeVisible();
    await expect(drawer.getByTestId("drawer-paid")).toBeVisible();
    await expect(drawer.getByTestId("drawer-outstanding")).toBeVisible();
    await expect(drawer.getByTestId("drawer-student-code")).toContainText("26000099");
  });

  test("Escape closes drawer", async ({ page }) => {
    await openEligibleDeclarationDrawer(page);
    await expect(page.getByTestId("payment-declaration-drawer")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByTestId("payment-declaration-drawer")).toHaveCount(0);
  });

  test("zero amount shows client validation", async ({ page }) => {
    await openEligibleDeclarationDrawer(page);
    await page.getByTestId("drawer-amount").fill("0");
    await page.getByTestId("drawer-save-draft").click();
    await expect(page.getByTestId("drawer-error")).toBeVisible();
  });

  test("pending declaration drawer is read-only", async ({ page }) => {
    await page.getByTestId("declare-payment-action").nth(1).click();
    await expect(page.getByText(/read only|chỉ xem/i)).toBeVisible();
    await expect(page.getByTestId("drawer-save-draft")).toBeDisabled();
    await expect(page.getByTestId("drawer-submit")).toBeDisabled();
  });

  test("EN declare payment label", async ({ page }) => {
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("en");
    await expect(page.getByTestId("declare-payment-action").first()).toContainText(/declare payment/i);
  });

  test("VI declare payment label", async ({ page }) => {
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
    await expect(page.getByTestId("declare-payment-action").first()).toContainText(/khai báo khoản nộp/i);
  });

  test("390px viewport drawer usable", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await openEligibleDeclarationDrawer(page);
    await expect(page.getByTestId("drawer-amount")).toBeVisible();
    await expect(page.getByTestId("drawer-submit")).toBeVisible();
  });
});
