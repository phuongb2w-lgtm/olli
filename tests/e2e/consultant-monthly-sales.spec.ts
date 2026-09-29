import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const consultantEmail = "m6-t04-consultant@olli.local";

const mockRow = {
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000201",
  workspace_sequence: 40,
  lead_id: null,
  student_id: "a6200000-0000-4000-8000-000000000201",
  display_subject_id: "a6200000-0000-4000-8000-000000000201",
  subject_type: "student",
  family_name: "Sales",
  given_name: "Test",
  student_code_official: "26010002",
  student_code_display: "26010002",
  student_code_is_provisional: false,
  lifecycle_status: "dang_hoc",
  lifecycle_status_label: "Active",
  primary_guardian_id: "a6300000-0000-4000-8000-000000000201",
  primary_guardian_name: "Guardian",
  primary_guardian_phone: "0903000001",
  course_id: null,
  course_name: null,
  class_id: null,
  class_name: null,
  enrollment_id: null,
  enrollment_financial_terms_id: null,
  tuition_total_net: 5_000_000,
  tuition_paid: 0,
  tuition_outstanding: 5_000_000,
  tuition_payment_state: "dong_phi",
  tuition_payment_state_label: "Unpaid",
  declaration_id: null,
  declaration_status: null,
  declaration_workflow_kind: null,
  portfolio_entered_at: "2026-01-01T00:00:00Z",
  student_details_subject_id: "a6200000-0000-4000-8000-000000000201",
  is_hidden: false,
  custom_fields: [],
  capabilities: {
    can_edit_contact: true,
    can_open_payment_declaration: false,
    can_create_payment_declaration: false,
    can_edit_payment_declaration: false,
    can_submit_declaration: false,
    can_add_payment: false,
    can_open_student_details: true,
  },
};

function portfolioRoute(rows: unknown[]) {
  return { rows, has_more: false, next_cursor: null };
}

function monthlySalesPayload(overrides: Record<string, unknown> = {}) {
  return {
    consultant_user_id: "00000000-0000-4000-8000-000000000001",
    organization_id: "00000000-0000-4000-8000-000000000002",
    currency_code: "VND",
    sales_amount: 12_500_000,
    payment_count: 3,
    period: {
      month_start: "2026-09-01",
      month_end: "2026-09-30",
      start_date: "2026-09-01",
      end_date: "2026-09-30",
      timezone: "Asia/Ho_Chi_Minh",
    },
    previous_period: { sales_amount: 10_000_000, payment_count: 2 },
    comparison: { delta_amount: 2_500_000, percent: 25, kind: "increase" },
    navigation: {
      is_current_month: false,
      can_go_next: true,
      can_go_previous: true,
      current_month_start: "2026-09-01",
    },
    ...overrides,
  };
}

test.describe("CW2-T08 consultant monthly sales header", () => {
  test.beforeEach(async ({ page }) => {
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      await route.fulfill({ json: portfolioRoute([mockRow]) });
    });
    await page.route("**/rest/v1/rpc/get_consultant_monthly_sales", async (route) => {
      const body = route.request().postDataJSON() as { p_period_month?: string };
      const month = body?.p_period_month?.slice(0, 7) ?? "2026-09";
      await route.fulfill({
        json: monthlySalesPayload({
          period: {
            month_start: `${month}-01`,
            month_end: `${month}-01`,
            start_date: `${month}-01`,
            end_date: `${month}-01`,
            timezone: "Asia/Ho_Chi_Minh",
          },
          navigation: {
            is_current_month: month === new Date().toISOString().slice(0, 7),
            can_go_next: month < new Date().toISOString().slice(0, 7),
            can_go_previous: true,
          },
        }),
      });
    });
    await signIn(page, consultantEmail);
  });

  test("header visible with formatted VND", async ({ page }) => {
    await page.goto("/consultant?month=2026-09");
    const header = page.getByTestId("consultant-monthly-sales-header");
    await expect(header).toBeVisible({ timeout: 30_000 });
    await expect(page.getByTestId("month-sales-amount")).toContainText(/12[.,\s]?500[.,\s]?000/);
    await expect(page.getByTestId("portfolio-grid")).toBeVisible();
  });

  test("zero sales empty context", async ({ page }) => {
    await page.route("**/rest/v1/rpc/get_consultant_monthly_sales", async (route) => {
      await route.fulfill({
        json: monthlySalesPayload({ sales_amount: 0, payment_count: 0, comparison: { kind: "neutral" } }),
      });
    });
    await page.goto("/consultant?month=2026-08");
    await expect(page.getByTestId("month-sales-amount")).toContainText(/0/);
    await expect(page.getByTestId("month-sales-empty")).toBeVisible();
  });

  test("previous and next month update URL", async ({ page }) => {
    await page.goto("/consultant?month=2026-08");
    await expect(page.getByTestId("consultant-monthly-sales-header")).toBeVisible();
    await page.getByTestId("month-sales-prev").click();
    await expect(page).toHaveURL(/month=2026-07/);
    await page.getByTestId("month-sales-next").click();
    await expect(page).toHaveURL(/month=2026-08/);
  });

  test("invalid month falls back", async ({ page }) => {
    await page.goto("/consultant?month=not-a-month");
    await expect(page.getByTestId("consultant-monthly-sales-header")).toBeVisible();
    await expect(page).not.toHaveURL(/month=not-a-month/);
  });

  test("error state distinct from zero", async ({ page }) => {
    await page.route("**/rest/v1/rpc/get_consultant_monthly_sales", async (route) => {
      await route.fulfill({ status: 500, json: { message: "fail" } });
    });
    await page.goto("/consultant?month=2026-07");
    await expect(page.getByTestId("month-sales-error")).toBeVisible();
    await expect(page.getByTestId("month-sales-retry")).toBeVisible();
  });

  test("EN monthly sales labels", async ({ page }) => {
    await page.goto("/consultant?month=2026-09");
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("en");
    await expect(page.getByTestId("consultant-monthly-sales-header")).toContainText(/monthly sales/i);
  });

  test("VI monthly sales labels", async ({ page }) => {
    await page.goto("/consultant?month=2026-09");
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
    await expect(page.getByTestId("consultant-monthly-sales-header")).toContainText(/doanh số của tháng/i);
  });

  test("390px viewport header stacks", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/consultant?month=2026-09");
    await expect(page.getByTestId("month-sales-amount")).toBeVisible();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible();
  });

  test("accessible month navigation labels", async ({ page }) => {
    await page.goto("/consultant?month=2026-09");
    await expect(page.getByTestId("month-sales-prev")).toHaveAttribute("aria-label", /.+/);
    await expect(page.getByTestId("month-sales-next")).toHaveAttribute("aria-label", /.+/);
  });

  test("grid filter survives month navigation", async ({ page }) => {
    await page.goto("/consultant?month=2026-09");
    await page.getByTestId("filter-name-search").fill("Sales");
    await page.getByTestId("month-sales-prev").click();
    await expect(page.getByTestId("filter-name-search")).toHaveValue("Sales");
  });
});
