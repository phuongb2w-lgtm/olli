import { expect, test, type Page } from "@playwright/test";
import { signIn } from "./sign-in";

/** Grid keyboard focus ring can intercept Playwright clicks on row 0; DOM click still fires handlers. */
async function openEligibleDeclarationDrawer(page: Page) {
  const action = page.getByTestId("portfolio-tuition-action").first();
  await action.waitFor({ state: "visible" });
  await action.evaluate((el) => {
    (el as HTMLButtonElement).click();
  });
  await expect(page.getByTestId("payment-declaration-drawer")).toBeVisible();
}

async function openPendingRowDeclarationDrawer(page: Page) {
  const action = page.getByTestId("portfolio-row").nth(2).getByTestId("portfolio-tuition-action");
  await action.scrollIntoViewIfNeeded();
  await action.evaluate((el) => {
    (el as HTMLButtonElement).click();
  });
  await expect(page.getByTestId("payment-declaration-drawer")).toBeVisible();
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
  tuition_pending_declaration: 0,
  tuition_payment_state: "nop_phi",
  tuition_payment_state_label: "Paying tuition",
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

const zeroPlanRow = {
  ...eligibleRow,
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000104",
  workspace_sequence: 47,
  tuition_total_net: 0,
  tuition_outstanding: 0,
  tuition_paid: 0,
  tuition_payment_state: "chua_nop_phi",
  tuition_payment_state_label: null as unknown as string,
  capabilities: {
    ...eligibleRow.capabilities,
    can_create_payment_declaration: true,
  },
};

const fullPhiRow = {
  ...eligibleRow,
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000102",
  workspace_sequence: 49,
  tuition_outstanding: 0,
  tuition_paid: 10_000_000,
  tuition_total_net: 10_000_000,
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
  tuition_paid: 5_000_000,
  tuition_outstanding: 5_000_000,
  tuition_pending_declaration: 2_000_000,
  tuition_payment_state: "mot_phan",
  tuition_payment_state_label: "Partial",
  capabilities: {
    ...eligibleRow.capabilities,
    can_open_payment_declaration: true,
    can_create_payment_declaration: true,
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
      await route.fulfill({
        json: portfolioRoute([eligibleRow, fullPhiRow, pendingRow, zeroPlanRow]),
      });
    });
    await page.route("**/rest/v1/rpc/get_cw2_tuition_declaration_context", async (route) => {
      const body = route.request().postDataJSON() as { p_enrollment_id?: string };
      const established = body?.p_enrollment_id !== eligibleRow.enrollment_id;
      await route.fulfill({
        json: {
          enrollment_id: body?.p_enrollment_id,
          tuition_established: established,
          billing_mode: established ? "course_lump_sum" : null,
          finance: {
            tuition_total_net: established ? 10_000_000 : 0,
            tuition_paid: established ? 3_000_000 : 0,
            tuition_outstanding: established ? 7_000_000 : 0,
            pending_declaration_amount: 0,
          },
          can_change_billing_mode: !established,
        },
      });
    });
    await signIn(page, consultantEmail);
    await page.goto("/consultant");
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
  });

  test("eligible row shows declare payment action", async ({ page }) => {
    await expect(page.getByTestId("portfolio-tuition-action").first()).toBeVisible();
    await expect(page.getByTestId("portfolio-tuition-action")).toHaveCount(3);
  });

  test("full phí row has no declare action", async ({ page }) => {
    const rows = page.getByTestId("portfolio-row");
    await expect(rows.nth(1).getByTestId("portfolio-tuition-action")).toHaveCount(0);
  });

  test("pending row shows pending total separately from confirmed paid", async ({ page }) => {
    const tuition = page.getByTestId("portfolio-tuition").nth(2);
    await expect(tuition).toContainText(/pending confirmation|chờ xác nhận/i);
    await expect(tuition).toContainText(/2\.000\.000|2,000,000/);
    await expect(tuition).toContainText(/5\.000\.000|5,000,000/);
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

  test("pending row opens editable declaration for another payment", async ({ page }) => {
    await openPendingRowDeclarationDrawer(page);
    const drawer = page.getByTestId("payment-declaration-drawer");
    await expect(drawer).toBeVisible();
    await expect(drawer.getByTestId("drawer-pending")).toContainText(/2\.000\.000|2,000,000/);
    await expect(drawer.getByTestId("drawer-paid")).toContainText(/5\.000\.000|5,000,000/);
    await expect(drawer.getByTestId("drawer-outstanding")).toContainText(/5\.000\.000|5,000,000/);
    await expect(drawer.getByTestId("drawer-amount")).toBeEnabled();
    await expect(drawer.getByTestId("drawer-submit")).toBeEnabled();
    await expect(page.getByText(/read only|chỉ xem/i)).toHaveCount(0);
  });

  test("EN declare payment label", async ({ page }) => {
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("en");
    await expect(page.getByTestId("portfolio-tuition-action").nth(2)).toContainText(
      /tuition not submitted/i,
    );
  });

  test("VI declare payment label", async ({ page }) => {
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
    await expect(page.getByTestId("portfolio-tuition-action").nth(2)).toContainText(/chưa nộp phí/i);
  });

  test("zero tuition plan shows Chưa nộp phí not Full phí", async ({ page }) => {
    const tuition = page.getByTestId("portfolio-tuition").nth(3);
    await expect(tuition).toContainText(/tuition not submitted|chưa nộp phí/i);
    await expect(tuition).not.toContainText(/paid in full|full phí/i);
  });

  test("drawer shows course vs periodic options for new plan", async ({ page }) => {
    await page.getByTestId("portfolio-row").nth(3).getByTestId("portfolio-tuition-action").click();
    await expect(page.getByTestId("tuition-billing-mode")).toBeVisible();
    await expect(page.getByText(/pay by course|nộp theo khóa học/i)).toBeVisible();
    await expect(page.getByText(/pay periodically|nộp định kỳ/i)).toBeVisible();
  });

  test("school year period disabled without organization academic year", async ({ page }) => {
    await page.route("**/rest/v1/rpc/get_cw2_tuition_declaration_context", async (route) => {
      await route.fulfill({
        json: {
          enrollment_id: zeroPlanRow.enrollment_id,
          tuition_established: false,
          billing_mode: null,
          finance: { tuition_total_net: 0 },
          can_change_billing_mode: true,
          has_organization_academic_year: false,
        },
      });
    });
    await page.getByTestId("portfolio-row").nth(3).getByTestId("portfolio-tuition-action").click();
    await page.getByText(/pay periodically|nộp định kỳ/i).click();
    const schoolYearOption = page.getByTestId("drawer-period-unit").locator('option[value="school_year"]');
    await expect(schoolYearOption).toHaveAttribute("disabled", "");
    await expect(page.getByTestId("school-year-unavailable")).toBeVisible();
  });

  test("390px viewport drawer usable", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await openEligibleDeclarationDrawer(page);
    await expect(page.getByTestId("drawer-amount")).toBeVisible();
    await expect(page.getByTestId("drawer-submit")).toBeVisible();
  });
});
