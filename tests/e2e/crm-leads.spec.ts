import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const readerEmail = "org-a-reader@olli.local";
const leadFixtureId = "a6100000-0000-4000-8000-000000000001";
const transitionLeadFixtureId = "a6100000-0000-4000-8000-000000000002";
const trialLeadFixtureId = "a6100000-0000-4000-8000-000000000002";

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
    ).toBeVisible({ timeout: 15_000 });
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
    await expect(page.getByText("Walk-in").first()).toBeVisible();
    await expect(
      page.getByRole("heading", { level: 2, name: /Candidates|Học viên tiềm năng/i }),
    ).toBeVisible();
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
      page.getByRole("button", { name: /Apply transition|Áp dụng chuyển trạng thái/i }),
    ).toBeEnabled({ timeout: 15_000 });
    await expect(
      page
        .locator("section")
        .filter({ has: page.getByRole("heading", { name: /Timeline|Dòng thời gian/i }) })
        .getByText(/→/)
        .first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  test("8. admin can assign and filter owned leads", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${leadFixtureId}`);
    await page.locator("#assignedUserId").selectOption({ label: "Org A Admin" });
    await page.getByRole("button", { name: /Assign|Reassign|Phân công|Chuyển phụ trách/i }).first().click();
    await expect(
      page.getByRole("button", { name: /Assign|Reassign|Phân công|Chuyển phụ trách/i }).first(),
    ).toBeEnabled({ timeout: 15_000 });
    await expect(
      page
        .locator("section")
        .filter({ has: page.getByRole("heading", { name: /Assignment history|Lịch sử phân công/i }) })
        .getByText(/→/)
        .first(),
    ).toBeVisible({ timeout: 15_000 });

    await page.goto("/crm/leads?owner=me&pageSize=100");
    await expect(page.locator(`a[href="/crm/leads/${leadFixtureId}"]`)).toBeVisible();

    await page.goto("/crm/leads?owner=unassigned&pageSize=100");
    await expect(page.locator(`a[href="/crm/leads/${leadFixtureId}"]`)).not.toBeVisible();
  });

  test("9. admin can schedule and complete a trial", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${trialLeadFixtureId}`);
    await expect(page.getByRole("heading", { level: 2, name: /Trials|Học thử/i })).toBeVisible();

    const trialSection = page
      .locator("section")
      .filter({ has: page.getByRole("heading", { level: 2, name: /Trials|Học thử/i }) });

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

  test("11. admin can resolve lead identity", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto(`/crm/leads/${leadFixtureId}`);
    await expect(
      page.getByRole("heading", { level: 2, name: /^Identity resolution$|^Xác định danh tính$/i }),
    ).toBeVisible();

    const identitySection = page
      .locator("section")
      .filter({
        has: page.getByRole("heading", { level: 2, name: /^Identity resolution$|^Xác định danh tính$/i }),
      });

    await expect(
      identitySection.getByRole("button", { name: /Create new at conversion|Tạo mới khi chuyển đổi/i }).first(),
    ).toBeVisible();
    await identitySection
      .getByRole("button", { name: /Create new at conversion|Tạo mới khi chuyển đổi/i })
      .first()
      .click();
    await expect(identitySection.getByText(/Unresolved|Create new|Chưa xác định|Tạo mới/i).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test("12. admin can create lead via intake workflow", async ({ page }) => {
    const unique = Date.now();
    const givenName = `E2E${unique}`;
    await signIn(page, adminEmail);
    await page.goto("/crm/leads/new");
    await expect(page.getByRole("heading", { name: /New lead|Lead mới/i })).toBeVisible();
    await page.locator("#intake-notes").fill(`Intake note ${unique}`);
    await page.locator("#candidate-given-0").fill(givenName);
    await page.locator("#candidate-family-0").fill("Nguyen");
    await page.locator("#contact-given-0").fill("Parent");
    await page.locator("#contact-family-0").fill("Nguyen");
    await page.locator("#contact-phone-0").fill("0900888777");
    await page.getByRole("button", { name: /Create lead|Tạo lead/i }).click();
    await expect(page.getByRole("heading", { name: /Lead detail|Chi tiết lead/i })).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByText(givenName).first()).toBeVisible();
    await page.goto(`/crm/leads?q=${givenName}&pageSize=100`);
    await expect(page.getByRole("table")).toBeVisible();
  });

  test("13. staff without lead.create does not see new lead control", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/crm/leads");
    await expect(page.getByRole("link", { name: /New lead|Lead mới/i })).not.toBeVisible();
    await page.goto("/crm/leads/new");
    await expect(
      page.getByText(/do not have permission to create leads|không có quyền tạo lead/i),
    ).toBeVisible();
  });

  test("14. worklist preset link applies filter", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/crm/leads");
    await page.getByRole("link", { name: /My leads|Lead của tôi/i }).click();
    await expect(page).toHaveURL(/preset=my/);
    await expect(page.getByRole("table")).toBeVisible();
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
