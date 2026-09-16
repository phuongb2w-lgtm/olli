import { expect, test } from "@playwright/test";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const readerEmail = "org-a-reader@olli.local";
const password = "testpass123";
const leadFixtureId = "a6100000-0000-4000-8000-000000000001";
const transitionLeadFixtureId = "a6100000-0000-4000-8000-000000000002";
const trialLeadFixtureId = "a6100000-0000-4000-8000-000000000002";

async function signIn(page: import("@playwright/test").Page, email: string) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(email);
  await page.locator('input[name="password"]').fill(password);
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
  await expect(page).toHaveURL("/");
}

test.describe.configure({ mode: "serial" });

test.describe("M3 CRM leads", () => {
  test("1. admin can access lead list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/crm/leads?q=Linh&pageSize=100");
    await expect(page.getByRole("heading", { level: 1, name: /^(Leads|Lead)$/i })).toBeVisible();
    await expect(page.locator(`a[href="/crm/leads/${leadFixtureId}"]`)).toBeVisible();
  });

  test("2. staff without lead.read is denied", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/crm/leads");
    await expect(
      page.getByText(/do not have permission to read leads|không có quyền đọc lead/i),
    ).toBeVisible();
  });

  test("3. reader without lead.read is denied", async ({ page }) => {
    await signIn(page, readerEmail);
    await page.goto("/crm/leads");
    await expect(
      page.getByText(/do not have permission to read leads|không có quyền đọc lead/i),
    ).toBeVisible();
  });

  test("4. status filter works", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/crm/leads?status=new&pageSize=100");
    await expect(page.getByRole("table")).toBeVisible();
    await expect(page.locator(`a[href="/crm/leads/${leadFixtureId}"]`)).toBeVisible();
  });

  test("5. admin can open lead detail", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${leadFixtureId}`);
    await expect(page.getByRole("heading", { name: /Lead detail|Chi tiết lead/i })).toBeVisible();
    await expect(page.getByText("Walk-in")).toBeVisible();
    await expect(page.getByRole("heading", { name: /Candidates|Học viên tiềm năng/i })).toBeVisible();
  });

  test("6. admin can log activity from detail", async ({ page }) => {
    const activityNote = `Playwright activity ${Date.now()}`;
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${leadFixtureId}`);
    await page.locator("#activityContent").fill(activityNote);
    await page.getByRole("button", { name: /Add activity|Thêm hoạt động/i }).click();
    await expect(page.getByText(activityNote).first()).toBeVisible();
  });

  test("7. admin can transition lead status", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${transitionLeadFixtureId}`);
    const statusSelect = page.locator("#toStatus");
    const targetValue = await statusSelect.locator("option").nth(1).getAttribute("value");
    if (!targetValue) {
      test.skip();
    }
    await statusSelect.selectOption(targetValue!);
    await page.getByRole("button", { name: /Apply transition|Áp dụng chuyển trạng thái/i }).click();
    await expect(
      page
        .locator("section")
        .filter({ has: page.getByRole("heading", { name: /Timeline|Dòng thời gian/i }) })
        .getByText(/→/)
        .first(),
    ).toBeVisible();
  });

  test("8. admin can assign and filter owned leads", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${leadFixtureId}`);
    await page.locator("#assignedUserId").selectOption({ index: 1 });
    await page.getByRole("button", { name: /Assign|Reassign|Phân công|Chuyển phụ trách/i }).first().click();
    await expect(
      page.getByText(/Unassigned → Org A Admin|Chưa phân công → Org A Admin/).first(),
    ).toBeVisible();

    await page.goto("/crm/leads?owner=me&pageSize=100");
    await expect(page.locator(`a[href="/crm/leads/${leadFixtureId}"]`)).toBeVisible();

    await page.goto("/crm/leads?owner=unassigned&pageSize=100");
    await expect(page.locator(`a[href="/crm/leads/${leadFixtureId}"]`)).not.toBeVisible();
  });

  test("9. admin can schedule and complete a trial", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${trialLeadFixtureId}`);
    await expect(page.getByRole("heading", { name: /Trials|Học thử/i })).toBeVisible();

    const trialSection = page
      .locator("section")
      .filter({ has: page.getByRole("heading", { name: /Trials|Học thử/i }) });

    await page.locator("#trialCandidateId").selectOption({ index: 1 });
    const classSelect = page.locator("#trialClassId");
    const classOption = classSelect.locator("option").filter({ hasText: /Class A1|Renamed Seed Class/i });
    const preferredClassValue = await classOption.first().getAttribute("value");
    if (preferredClassValue) {
      await classSelect.selectOption(preferredClassValue);
    } else {
      await classSelect.selectOption({ index: 1 });
    }
    const start = new Date(Date.now() + 86400000 * 5);
    const end = new Date(start.getTime() + 90 * 60 * 1000);
    const toLocal = (d: Date) => {
      const pad = (n: number) => String(n).padStart(2, "0");
      return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    };
    await page.locator("#trialStartAt").fill(toLocal(start));
    await page.locator("#trialEndAt").fill(toLocal(end));
    await page.getByRole("button", { name: /Schedule trial|Lên lịch học thử/i }).click();
    await expect(trialSection.getByText(/Scheduled|Đã lên lịch/i).first()).toBeVisible({
      timeout: 15_000,
    });

    const outcomeNote = `E2E trial outcome ${Date.now()}`;
    await trialSection.getByPlaceholder(/Brief outcome|Kết quả ngắn gọn/i).first().fill(outcomeNote);
    await trialSection.getByRole("button", { name: /Mark completed|Đánh dấu hoàn thành/i }).first().click();
    await expect(page.getByText(outcomeNote).first()).toBeVisible({ timeout: 15_000 });
  });

  test("10. Vietnamese CRM labels render", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/crm/leads");
    await page.getByLabel(/language|ngôn ngữ/i).selectOption("vi");
    await expect(page.getByRole("heading", { level: 1, name: "Lead" })).toBeVisible({
      timeout: 15_000,
    });
  });
});
