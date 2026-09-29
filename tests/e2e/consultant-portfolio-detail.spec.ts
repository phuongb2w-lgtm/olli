import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const consultantEmail = "m6-t04-consultant@olli.local";
const portfolioEntryId = "b0000000-0000-4000-8000-000000000301";

const detailPayload = {
  portfolio_entry_id: portfolioEntryId,
  workspace_sequence: 7,
  portfolio_entered_at: "2026-01-01T00:00:00Z",
  lead_id: null,
  student_id: "a6200000-0000-4000-8000-000000000301",
  subject_type: "student",
  display_subject_id: "a6200000-0000-4000-8000-000000000301",
  is_hidden: false,
  family_name: "Nguyen",
  given_name: "Detail",
  date_of_birth: "2015-05-01",
  subject_updated_at: "2026-01-01T00:00:00Z",
  student_code_official: "26010031",
  student_code_display: "26010031",
  student_code_is_provisional: false,
  lifecycle_status: "dang_hoc",
  enrollment_id: "a6500000-0000-4000-8000-000000000301",
  enrollment_status: "active",
  enrollment_start_date: "2026-01-01",
  enrollment_financial_terms_id: "a6600000-0000-4000-8000-000000000301",
  course_id: "a6400000-0000-4000-8000-000000000301",
  course_name: "English",
  class_id: null,
  class_name: null,
  tuition_total_net: 10_000_000,
  tuition_paid: 2_000_000,
  tuition_outstanding: 8_000_000,
  tuition_payment_state: "mot_phan",
  declaration_id: null,
  declaration_status: null,
  declaration_workflow_kind: null,
  primary_guardian_id: "a6300000-0000-4000-8000-000000000301",
  primary_guardian_family_name: "Nguyen",
  primary_guardian_given_name: "Parent",
  primary_guardian_phone: "0903000031",
  custom_fields: [
    {
      definition_id: "c0000000-0000-4000-8000-000000000301",
      field_key: "school",
      label: "School",
      data_type: "text",
      value: "THCS A",
    },
  ],
  capabilities: {
    can_edit_contact: true,
    can_open_payment_declaration: true,
    can_create_payment_declaration: true,
    can_edit_payment_declaration: false,
    can_submit_declaration: false,
    can_add_payment: false,
    can_open_student_details: true,
  },
  editable: {
    can_edit_profile: true,
    can_edit_date_of_birth: true,
    can_edit_custom_fields: true,
    official_student_code_locked: true,
  },
};

function portfolioRoute(rows: unknown[]) {
  return { rows, has_more: false, next_cursor: null };
}

const gridRow = {
  portfolio_entry_id: portfolioEntryId,
  workspace_sequence: 7,
  lead_id: null,
  student_id: detailPayload.student_id,
  display_subject_id: detailPayload.student_id,
  subject_type: "student",
  family_name: "Nguyen",
  given_name: "Detail",
  student_code_official: "26010031",
  student_code_display: "26010031",
  student_code_is_provisional: false,
  lifecycle_status: "dang_hoc",
  lifecycle_status_label: "Active learning",
  primary_guardian_id: detailPayload.primary_guardian_id,
  primary_guardian_name: "Nguyen Parent",
  primary_guardian_phone: "0903000031",
  course_id: detailPayload.course_id,
  course_name: "English",
  class_id: null,
  class_name: null,
  enrollment_id: detailPayload.enrollment_id,
  enrollment_financial_terms_id: detailPayload.enrollment_financial_terms_id,
  tuition_total_net: 10_000_000,
  tuition_paid: 2_000_000,
  tuition_outstanding: 8_000_000,
  tuition_payment_state: "mot_phan",
  tuition_payment_state_label: "Partial",
  declaration_id: null,
  declaration_status: null,
  declaration_workflow_kind: null,
  portfolio_entered_at: "2026-01-01T00:00:00Z",
  student_details_subject_id: detailPayload.student_id,
  is_hidden: false,
  custom_fields: detailPayload.custom_fields,
  capabilities: detailPayload.capabilities,
};

test.describe("CW2-T09 consultant portfolio detail", () => {
  test.beforeEach(async ({ page }) => {
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      await route.fulfill({ json: portfolioRoute([gridRow]) });
    });
    await page.route("**/rest/v1/rpc/get_consultant_portfolio_entry_detail", async (route) => {
      await route.fulfill({ json: detailPayload });
    });
    await page.route("**/rest/v1/rpc/get_consultant_monthly_sales", async (route) => {
      await route.fulfill({
        json: {
          sales_amount: 0,
          payment_count: 0,
          currency_code: "VND",
          period: { month_start: "2026-09-01", month_end: "2026-09-30" },
          previous_period: { sales_amount: 0 },
          comparison: { kind: "neutral" },
          navigation: { is_current_month: true, can_go_next: false },
        },
      });
    });
    await signIn(page, consultantEmail);
  });

  test("opens detail from grid", async ({ page }) => {
    await page.goto("/consultant");
    await page.getByTestId("portfolio-details-link").first().click();
    await expect(page.getByTestId("consultant-portfolio-detail")).toBeVisible({ timeout: 30_000 });
    await expect(page.getByTestId("detail-student-code")).toContainText("26010031");
  });

  test("finance section read-only", async ({ page }) => {
    await page.goto(`/consultant/portfolio/${portfolioEntryId}`);
    await expect(page.getByTestId("detail-finance-section")).toBeVisible();
    await expect(page.getByTestId("detail-payment-state")).toBeVisible();
  });

  test("edit and save profile", async ({ page }) => {
    let saved = false;
    await page.route("**/rest/v1/rpc/save_consultant_portfolio_profile", async (route) => {
      saved = true;
      await route.fulfill({
        json: { ...detailPayload, given_name: "Saved" },
      });
    });
    await page.route("**/rest/v1/rpc/save_consultant_portfolio_custom_fields", async (route) => {
      await route.fulfill({ json: { ...detailPayload, given_name: "Saved" } });
    });
    await page.goto(`/consultant/portfolio/${portfolioEntryId}?edit=1`);
    await page.getByTestId("detail-given-name").fill("Saved");
    await page.getByTestId("detail-save").click();
    await expect.poll(() => saved).toBe(true);
  });

  test("390px viewport usable", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`/consultant/portfolio/${portfolioEntryId}`);
    await expect(page.getByTestId("consultant-portfolio-detail")).toBeVisible();
    await expect(page.getByTestId("detail-back-link")).toBeVisible();
  });

  test("VI detail title", async ({ page }) => {
    await page.goto(`/consultant/portfolio/${portfolioEntryId}`);
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
    await expect(page.getByTestId("consultant-portfolio-detail")).toContainText(/chi tiết/i);
  });
});
