import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const consultantEmail = "m6-t04-consultant@olli.local";
const readerEmail = "org-a-reader@olli.local";
const adminEmail = "org-a-admin@olli.local";

const mockRow = {
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000001",
  workspace_sequence: 99,
  lead_id: "a6100000-0000-4000-8000-000000000001",
  student_id: null,
  display_subject_id: "a6100000-0000-4000-8000-000000000001",
  subject_type: "lead",
  family_name: "Nguyen",
  given_name: "An",
  student_code_official: null,
  student_code_display: "26000000",
  student_code_is_provisional: true,
  lifecycle_status: "tiem_nang",
  lifecycle_status_label: "Prospect",
  primary_guardian_id: null,
  primary_guardian_name: "Parent One",
  primary_guardian_phone: "0901000001",
  course_id: null,
  course_name: null,
  class_id: null,
  class_name: null,
  enrollment_id: null,
  enrollment_financial_terms_id: null,
  tuition_total_net: 5000000,
  tuition_paid: 0,
  tuition_outstanding: 5000000,
  tuition_payment_state: "dong_phi",
  tuition_payment_state_label: "Unpaid",
  declaration_id: null,
  declaration_status: null,
  declaration_workflow_kind: null,
  portfolio_entered_at: "2026-01-01T00:00:00Z",
  student_details_subject_id: null,
  is_hidden: false,
  custom_fields: [{ definition_id: "c0000000-0000-4000-8000-000000000001", field_key: "note", label: "Note", data_type: "text", value: "CF1" }],
  capabilities: {
    can_edit_contact: true,
    can_open_payment_declaration: false,
    can_create_payment_declaration: false,
    can_edit_payment_declaration: false,
    can_submit_declaration: true,
    can_add_payment: false,
    can_open_student_details: false,
  },
};

const mockStudentRow = {
  ...mockRow,
  portfolio_entry_id: "b0000000-0000-4000-8000-000000000002",
  workspace_sequence: 98,
  lead_id: null,
  student_id: "a6200000-0000-4000-8000-000000000010",
  display_subject_id: "a6200000-0000-4000-8000-000000000010",
  subject_type: "student",
  student_code_official: "26010001",
  student_code_display: "26010001",
  student_code_is_provisional: false,
  student_details_subject_id: "a6200000-0000-4000-8000-000000000010",
  primary_guardian_phone: "0902000002",
  lifecycle_status: "dang_hoc",
  lifecycle_status_label: "Enrolled",
  tuition_payment_state: "full_phi",
  tuition_payment_state_label: "Paid in full",
  tuition_outstanding: 0,
  tuition_paid: 5000000,
  capabilities: {
    can_edit_contact: false,
    can_open_payment_declaration: false,
    can_create_payment_declaration: false,
    can_edit_payment_declaration: false,
    can_submit_declaration: false,
    can_add_payment: false,
    can_open_student_details: true,
  },
};

function portfolioRoute(body: unknown, hasMore = false) {
  return {
    rows: body,
    has_more: hasMore,
    next_cursor: hasMore
      ? {
          workspace_sequence: 97,
          portfolio_entry_id: "b0000000-0000-4000-8000-000000000099",
        }
      : null,
  };
}

const defaultPortfolioRows = [mockRow, mockStudentRow];

function filterPortfolioRows(filters: Record<string, string> | undefined) {
  const f = filters ?? {};
  return defaultPortfolioRows.filter((row) => {
    if (f.lifecycle_status && row.lifecycle_status !== f.lifecycle_status) return false;
    if (f.tuition_payment_state && row.tuition_payment_state !== f.tuition_payment_state) return false;
    if (f.guardian_phone?.trim()) {
      const needle = f.guardian_phone.trim();
      if (!row.primary_guardian_phone?.includes(needle)) return false;
    }
    return true;
  });
}

test.describe("CW2-T06 consultant portfolio workspace", () => {
  test.describe.configure({ timeout: 60_000 });

  test("1. consultant workspace route loads", async ({ page }) => {
    await signIn(page, consultantEmail);
    await page.goto("/consultant");
    await expect(page.getByTestId("consultant-workspace")).toBeVisible({ timeout: 30_000 });
  });

  test("2. unauthorized reader denied", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/consultant");
    await expect(page.getByTestId("consultant-workspace-denied")).toBeVisible({ timeout: 15_000 });
  });

  test("3. CRM leads regression still reachable for admin", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/crm/leads");
    await expect(page.getByRole("heading", { level: 1, name: "Leads" })).toBeVisible();
  });
});

test.describe("CW2-T06 portfolio grid (mocked RPC)", () => {
  test.beforeEach(async ({ page }) => {
    await page.route("**/rest/v1/consultant_custom_field_definition*", async (route) => {
      await route.fulfill({ json: [] });
    });

    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      const request = route.request();
      const postData = request.postDataJSON() as {
        p_filters?: Record<string, string>;
        p_sort_field?: string;
        p_include_hidden?: boolean;
      };

      if (postData.p_filters?.lifecycle_status === "dang_hoc") {
        await route.fulfill({ json: portfolioRoute([]) });
        return;
      }

      if (postData.p_include_hidden) {
        await route.fulfill({
          json: portfolioRoute([{ ...mockRow, is_hidden: true }]),
        });
        return;
      }

      await route.fulfill({
        json: {
          rows: [mockRow, mockStudentRow],
          has_more: true,
          next_cursor: {
            workspace_sequence: 97,
            portfolio_entry_id: "b0000000-0000-4000-8000-000000000099",
          },
        },
      });
    });

    await signIn(page, consultantEmail);
    await page.goto("/consultant");
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
  });

  test("4. STT uses authoritative value", async ({ page }) => {
    await expect(page.getByTestId("portfolio-stt").first()).toHaveText("99");
  });

  test("5. provisional student code styled", async ({ page }) => {
    const code = page.getByTestId("portfolio-student-code").first();
    await expect(code).toHaveText("26000000");
    await expect(code).toHaveClass(/border-dashed/);
  });

  test("DOB contract. missing DOB shows incomplete code not fabricated YY", async ({ page }) => {
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      await route.fulfill({
        json: portfolioRoute([
          {
            ...mockRow,
            student_code_official: null,
            student_code_display: null,
            student_code_is_provisional: true,
          },
        ]),
      });
    });
    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible();
    const row = page.locator('[data-testid="portfolio-row"]').first();
    await expect(row).toContainText("—");
    await expect(row.getByTestId("portfolio-student-code")).toHaveCount(0);
  });

  test("6. official student code on student row", async ({ page }) => {
    await expect(page.getByTestId("portfolio-student-code").nth(1)).toHaveText("26010001");
  });

  test("7. tuition state and no M2 record payment", async ({ page }) => {
    await expect(page.getByTestId("portfolio-tuition").first()).toContainText(/unpaid|đóng phí/i);
    await expect(page.getByRole("button", { name: /record payment|ghi nhận thanh toán/i })).toHaveCount(0);
  });

  test("8. details links for lead and student", async ({ page }) => {
    const returnQuery = encodeURIComponent("/consultant");
    await expect(page.getByTestId("portfolio-details-link").first()).toHaveAttribute(
      "href",
      `/consultant/portfolio/${mockRow.portfolio_entry_id}?return=${returnQuery}`,
    );
    await expect(page.getByTestId("portfolio-details-link").nth(1)).toHaveAttribute(
      "href",
      `/consultant/portfolio/${mockStudentRow.portfolio_entry_id}?return=${returnQuery}`,
    );
  });

  test("9. lifecycle filter calls server", async ({ page }) => {
    let sawFilter = false;
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      const postData = route.request().postDataJSON() as { p_filters?: Record<string, string> };
      if (postData.p_filters?.lifecycle_status === "dang_hoc") sawFilter = true;
      await route.fulfill({ json: portfolioRoute([]) });
    });
    await page.getByTestId("filter-lifecycle-status").selectOption("dang_hoc");
    await expect(page.getByTestId("portfolio-filtered-empty")).toBeVisible({ timeout: 10_000 });
    expect(sawFilter).toBe(true);
  });

  test("10. column visibility toggle", async ({ page }) => {
    await page.getByTestId("column-toggle-guardian_phone").uncheck();
    await expect(page.getByRole("columnheader", { name: /phone|sđt/i })).toHaveCount(0);
  });

  test("11. keyboard Tab moves focus", async ({ page }) => {
    const firstCell = page.locator('[data-testid="portfolio-new-row"] td').first();
    await firstCell.click();
    await page.keyboard.press("Tab");
    await expect(page.locator('[data-testid="portfolio-new-row"] td:focus')).toBeVisible();
  });

  test("12. EN locale labels", async ({ page }) => {
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("en");
    await expect(page.getByRole("heading", { level: 3, name: /consultant portfolio/i })).toBeVisible({
      timeout: 15_000,
    });
  });

  test("13. load more visible when has_more", async ({ page }) => {
    await expect(page.getByTestId("portfolio-load-more")).toBeVisible();
  });

  test("14. custom field column toggle", async ({ page }) => {
    await expect(page.getByRole("cell", { name: "CF1" }).first()).toBeVisible();
  });

  test("A. empty portfolio still shows table and inline new row", async ({ page }) => {
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      await route.fulfill({ json: portfolioRoute([]) });
    });
    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible();
    await expect(page.getByTestId("portfolio-new-row")).toBeVisible();
  });

  test("B. new row shows Save action", async ({ page }) => {
    await expect(page.getByTestId("portfolio-save-new-row")).toHaveText(/save|lưu/i);
  });

  test("C. no add-student modal button", async ({ page }) => {
    await expect(page.getByRole("button", { name: /add student|thêm học viên/i })).toHaveCount(0);
  });

  test("F. provisional row shows Edit", async ({ page }) => {
    await expect(page.getByTestId("portfolio-edit-row").first()).toHaveText(/edit|sửa/i);
  });

  test("I. official student row has no Edit", async ({ page }) => {
    const officialRow = page.locator('[data-testid="portfolio-row"]').nth(1);
    await expect(officialRow.getByTestId("portfolio-edit-row")).toHaveCount(0);
  });

  test("Q. standalone search panel removed", async ({ page }) => {
    await expect(page.getByTestId("portfolio-filters")).toHaveCount(0);
  });

  test("R. column filter row present", async ({ page }) => {
    await expect(page.getByTestId("portfolio-column-filters")).toBeVisible();
  });

  test("S. family name filter calls server", async ({ page }) => {
    let saw = false;
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      const postData = route.request().postDataJSON() as { p_filters?: Record<string, string> };
      if (postData.p_filters?.family_name === "Tran") saw = true;
      await route.fulfill({ json: portfolioRoute([mockRow]) });
    });
    await page.getByTestId("filter-family-name").fill("Tran");
    await expect.poll(() => saw, { timeout: 10_000 }).toBe(true);
  });

  test("U. guardian phone column filter applies and clears", async ({ page }) => {
    let lastGuardianPhone: string | undefined;
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      const postData = route.request().postDataJSON() as { p_filters?: Record<string, string> };
      lastGuardianPhone = postData.p_filters?.guardian_phone;
      const rows = filterPortfolioRows(postData.p_filters);
      await route.fulfill({ json: portfolioRoute(rows, true) });
    });

    const phoneToggle = page.getByTestId("column-toggle-guardian_phone");
    if (!(await phoneToggle.isChecked())) await phoneToggle.check();
    await expect(page.getByTestId("filter-guardian-phone")).toBeVisible();
    await expect(page.getByTestId("portfolio-row")).toHaveCount(2);

    await page.getByTestId("filter-guardian-phone").fill("0901000001");
    await page.getByTestId("filter-guardian-phone").blur();
    await expect.poll(() => lastGuardianPhone, { timeout: 10_000 }).toBe("0901000001");
    await expect(page.getByTestId("portfolio-row")).toHaveCount(1);
    await expect(page.getByTestId("portfolio-stt").first()).toHaveText("99");

    await page.getByTestId("filter-guardian-phone").fill("");
    await page.getByTestId("filter-guardian-phone").blur();
    await expect(page.getByTestId("portfolio-row")).toHaveCount(2);

    await phoneToggle.uncheck();
    await expect(page.getByTestId("filter-guardian-phone")).toHaveCount(0);
    await page.getByTestId("filter-lifecycle-status").selectOption("tiem_nang");
    await expect(page.getByTestId("portfolio-row")).toHaveCount(1);
    await expect(page.getByTestId("portfolio-load-more")).toBeVisible();
    await expect(page.getByTestId("resize-stt")).toBeVisible();
  });

  test("V. lifecycle status column filter applies and clears", async ({ page }) => {
    let lastLifecycle: string | undefined;
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      const postData = route.request().postDataJSON() as { p_filters?: Record<string, string> };
      lastLifecycle = postData.p_filters?.lifecycle_status;
      const rows = filterPortfolioRows(postData.p_filters);
      await route.fulfill({ json: portfolioRoute(rows, true) });
    });

    await expect(page.getByTestId("filter-lifecycle-status")).toBeVisible();
    await expect(page.getByTestId("portfolio-row")).toHaveCount(2);

    await page.getByTestId("filter-lifecycle-status").selectOption("dang_hoc");
    await expect.poll(() => lastLifecycle, { timeout: 10_000 }).toBe("dang_hoc");
    await expect(page.getByTestId("portfolio-row")).toHaveCount(1);
    await expect(page.getByTestId("portfolio-stt").first()).toHaveText("98");

    await page.getByTestId("filter-lifecycle-status").selectOption("");
    await expect(page.getByTestId("portfolio-row")).toHaveCount(2);
    await expect(page.getByTestId("portfolio-load-more")).toBeVisible();
  });

  test("W. tuition payment state column filter applies and clears", async ({ page }) => {
    let lastTuition: string | undefined;
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      const postData = route.request().postDataJSON() as { p_filters?: Record<string, string> };
      lastTuition = postData.p_filters?.tuition_payment_state;
      const rows = filterPortfolioRows(postData.p_filters);
      await route.fulfill({ json: portfolioRoute(rows, true) });
    });

    await expect(page.getByTestId("filter-payment-state")).toBeVisible();
    await expect(page.getByTestId("portfolio-row")).toHaveCount(2);

    await page.getByTestId("filter-payment-state").selectOption("full_phi");
    await expect.poll(() => lastTuition, { timeout: 10_000 }).toBe("full_phi");
    await expect(page.getByTestId("portfolio-row")).toHaveCount(1);
    await expect(page.getByTestId("portfolio-tuition").first()).toContainText(/paid in full|full phí/i);

    await page.getByTestId("filter-payment-state").selectOption("");
    await expect(page.getByTestId("portfolio-row")).toHaveCount(2);
    await page.getByTestId("column-toggle-guardian_phone").uncheck();
    await expect(page.getByTestId("portfolio-load-more")).toBeVisible();
  });

  test("T. student code filter calls server", async ({ page }) => {
    let saw = false;
    await page.unroute("**/rest/v1/rpc/list_consultant_workspace_portfolio");
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      const postData = route.request().postDataJSON() as { p_filters?: Record<string, string> };
      if (postData.p_filters?.student_code === "2601") saw = true;
      await route.fulfill({ json: portfolioRoute([mockRow]) });
    });
    await page.getByTestId("filter-student-code").fill("2601");
    await page.getByTestId("filter-student-code").blur();
    await expect.poll(() => saw, { timeout: 10_000 }).toBe(true);
  });

  test("G. inline edit opens on same row", async ({ page }) => {
    const row = page.locator('[data-testid="portfolio-row"]').first();
    await row.scrollIntoViewIfNeeded();
    await row.getByTestId("portfolio-edit-row").click();
    await expect(row.getByTestId("portfolio-save-edit-row")).toBeVisible({ timeout: 10_000 });
    await expect(row.getByTestId("inline-family-name")).toBeVisible();
  });

  test("AE. narrow viewport keeps horizontal grid scroll", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 800 });
    await expect(page.getByTestId("portfolio-grid-scroll")).toBeVisible();
    const scrollWidth = await page.getByTestId("portfolio-grid").evaluate((el) => el.scrollWidth);
    expect(scrollWidth).toBeGreaterThan(390);
  });
});

test.describe("CW2 inline intake (mocked RPC)", () => {
  test("D/E. inline save keeps new row and adds portfolio row", async ({ page }) => {
    let callCount = 0;
    await page.route("**/rest/v1/consultant_custom_field_definition*", async (route) => {
      await route.fulfill({ json: [] });
    });
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      callCount += 1;
      if (callCount === 1) {
        await route.fulfill({ json: portfolioRoute([]) });
        return;
      }
      await route.fulfill({
        json: portfolioRoute([
          {
            ...mockRow,
            family_name: "Tran",
            given_name: "Mai",
            workspace_sequence: 1,
          },
        ]),
      });
    });
    await page.route("**/rest/v1/rpc/create_consultant_workspace_portfolio_intake", async (route) => {
      await route.fulfill({
        json: {
          portfolio_entry_id: mockRow.portfolio_entry_id,
          workspace_sequence: 1,
          family_name: "Tran",
          given_name: "Mai",
          lifecycle_status: "tiem_nang",
          capabilities: mockRow.capabilities,
          custom_fields: [],
        },
      });
    });
    await signIn(page, consultantEmail);
    await page.goto("/consultant");
    await page.getByTestId("inline-family-name").fill("Tran");
    await page.getByTestId("inline-given-name").fill("Mai");
    await page.getByTestId("portfolio-save-new-row").click();
    await expect(page.getByTestId("portfolio-new-row")).toBeVisible();
    await expect(page.getByTestId("portfolio-row")).toHaveCount(1);
  });
});

test.describe("CW2-T06 VI locale", () => {
  test("15. Vietnamese workspace strings", async ({ page }) => {
    await page.route("**/rest/v1/consultant_custom_field_definition*", async (route) => {
      await route.fulfill({ json: [] });
    });
    await page.route("**/rest/v1/rpc/list_consultant_workspace_portfolio", async (route) => {
      await route.fulfill({ json: portfolioRoute([]) });
    });
    await signIn(page, consultantEmail);
    await page.goto("/consultant");
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
    await expect(page.getByRole("heading", { level: 3, name: /danh mục tư vấn/i })).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByTestId("portfolio-save-new-row")).toHaveText(/lưu/i);
  });
});
