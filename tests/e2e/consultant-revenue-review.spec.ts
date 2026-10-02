import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "m6-t04-accountant@olli.local";

const pendingDeclaration = {
  declaration_id: "a6700000-0000-4000-8000-000000000201",
  declaration_date: "2026-06-15",
  declared_amount: 2_500_000,
  status: "pending",
  consultant_user_id: "a6660002-0000-4000-8000-000000000002",
  consultant_name: "M6 Fixture Consultant",
  approved_payment_id: null,
  has_canonical_payment: false,
  description: "Tuition payment",
  declaration_kind: "payment_only",
  workflow_kind: "cw2_payment",
  student_id: "a6200000-0000-4000-8000-000000000101",
  enrollment_id: "a6500000-0000-4000-8000-000000000101",
};

const reviewDetail = {
  declaration: {
    id: pendingDeclaration.declaration_id,
    declaration_kind: "payment_only",
    status: "pending",
    declaration_date: pendingDeclaration.declaration_date,
    declared_amount: pendingDeclaration.declared_amount,
    payment_method_code: "cash",
    description: pendingDeclaration.description,
    enrollment_id: pendingDeclaration.enrollment_id,
    student_id: pendingDeclaration.student_id,
    consultant_user_id: pendingDeclaration.consultant_user_id,
  },
  student_name: "Tran Eligible",
  consultant_name: pendingDeclaration.consultant_name,
  canonical_finance: {
    course_outstanding_amount: 5_000_000,
    allocated_amount: 3_000_000,
    tuition_payment_state: "nop_phi",
  },
  periodic_effect_preview: null,
};

test.describe("CW2 accounting declaration review", () => {
  test.beforeEach(async ({ page }) => {
    await page.route("**/rest/v1/rpc/list_finance_consultant_declarations", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json; charset=utf-8",
        body: JSON.stringify([pendingDeclaration]),
      });
    });
    await page.route("**/rest/v1/rpc/get_cw2_finance_declaration_review_detail", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json; charset=utf-8",
        body: JSON.stringify(reviewDetail),
      });
    });
    await signIn(page, adminEmail);
    await page.goto("/finance/consultant-revenue?start=2026-01-01&end=2026-12-31");
    await expect(page.getByTestId("finance-consultant-declarations-table")).toBeVisible({
      timeout: 30_000,
    });
  });

  test("pending CW2 declaration shows review action", async ({ page }) => {
    await expect(page.getByTestId("finance-review-action")).toHaveCount(1);
  });

  test("review drawer loads RPC detail", async ({ page }) => {
    await page.getByTestId("finance-review-action").click();
    const drawer = page.getByTestId("finance-declaration-review-drawer");
    await expect(drawer).toBeVisible();
    await expect(drawer.getByTestId("finance-review-student")).toContainText("Tran Eligible");
    await expect(drawer.getByTestId("finance-review-amount")).toContainText(/2\.500\.000|2,500,000/);
    await expect(drawer.getByTestId("finance-review-confirm")).toBeVisible();
    await expect(drawer.getByTestId("finance-review-reject")).toBeVisible();
  });

  test("EN review labels", async ({ page }) => {
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("en");
    await page.getByTestId("finance-review-action").click();
    await expect(page.getByTestId("finance-review-confirm")).toContainText(/confirm payment/i);
    await expect(page.getByTestId("finance-review-reject")).toContainText(/^reject$/i);
  });

  test("VI review labels", async ({ page }) => {
    await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
    await page.getByTestId("finance-review-action").click();
    await expect(page.getByTestId("finance-review-confirm")).toContainText(/xác nhận thanh toán/i);
    await expect(page.getByTestId("finance-review-reject")).toContainText(/từ chối/i);
  });
});
