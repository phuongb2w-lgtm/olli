import { expect, test, type Browser, type Locator, type Page } from "@playwright/test";
import { signIn } from "./sign-in";

const consultantEmail = "m6-t04-consultant@olli.local";
const academicEmail = "m6-t04-academic-ops@olli.local";
const accountantEmail = "m6-t04-accountant@olli.local";
const ownerEmail = "m6-t04-org-c-owner@olli.local";
const teacherEmail = "org-a-staff@olli.local";

/** Seeded by scripts/e2e-cw2-t13-fixture.sql (Org C, active enrollment, no charge). */
const fixtureStudentId = "c5130000-0000-4000-8000-000000000001";

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function ensureVietnamese(page: Page) {
  const lang = await page.locator("html").getAttribute("lang");
  if (lang === "vi") return;
  await page.getByRole("combobox", { name: /language|ngôn ngữ/i }).selectOption("vi");
  await expect(page.locator("html")).toHaveAttribute("lang", "vi", { timeout: 30_000 });
}

function manageCard(page: Page, label: string): Locator {
  return page.locator('[data-testid^="personal-column-manage-custom_"]').filter({
    has: page.locator('[data-testid^="personal-column-label-custom_"]', {
      hasText: new RegExp(`^${escapeRegExp(label)}$`),
    }),
  });
}

async function columnIdFor(page: Page, label: string): Promise<string> {
  const card = manageCard(page, label);
  await expect(card).toHaveCount(1);
  const testId = await card.getAttribute("data-testid");
  return testId!.replace("personal-column-manage-", "");
}

async function createColumn(page: Page, label: string): Promise<string> {
  await page.getByTestId("add-custom-column").click();
  await expect(page.getByTestId("add-custom-column-dialog")).toBeVisible();
  await page.getByTestId("custom-column-label").fill(label);
  await page.getByTestId("custom-column-data-type").selectOption("text");
  await page.getByTestId("custom-column-submit").click();
  await expect(page.getByTestId("add-custom-column-dialog")).toHaveCount(0);
  return columnIdFor(page, label);
}

async function renameColumn(page: Page, colId: string, label: string) {
  await page.getByTestId(`personal-column-rename-${colId}`).click();
  await page.getByTestId("personal-column-rename-input").fill(label);
  await page.getByTestId("personal-column-rename-submit").click();
  await expect(page.getByTestId("personal-column-rename-dialog")).toHaveCount(0);
  await expect(page.getByTestId(`personal-column-label-${colId}`)).toHaveText(label);
}

async function archiveColumn(page: Page, colId: string) {
  await page.getByTestId(`personal-column-archive-${colId}`).click();
  await page.getByTestId("personal-column-archive-confirm").click();
  await expect(page.getByTestId(`personal-column-manage-${colId}`)).toHaveCount(0);
  await expect(page.getByTestId(`column-header-${colId}`)).toHaveCount(0);
}

async function waitPrefsSaved(page: Page, statusTestId: string) {
  await expect(page.getByTestId(statusTestId)).toHaveAttribute("data-state", "saved");
}

async function headerOrder(page: Page, colIds: string[]): Promise<string[]> {
  const ids = await page
    .locator('[data-testid^="column-header-"]')
    .evaluateAll((els) => els.map((el) => el.getAttribute("data-testid")!.replace("column-header-", "")));
  return ids.filter((id) => colIds.includes(id));
}

async function openPersonalGrid(page: Page, path: string, surface: "students" | "finance_students") {
  await page.goto(path);
  await expect(page.getByTestId(`personal-fields-grid-${surface}`)).toHaveAttribute("data-ready", "true", {
    timeout: 30_000,
  });
}

async function openConsultant(page: Page) {
  await page.goto("/consultant");
  await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
}

test.describe("CW2-T13 consultant personal column lifecycle", () => {
  test.describe.configure({ timeout: 240_000 });

  test("production-like intake row and full custom-column lifecycle", async ({ page }) => {
    await signIn(page, consultantEmail);
    await openConsultant(page);
    await ensureVietnamese(page);
    await openConsultant(page);

    for (const col of ["student_code", "lifecycle_status", "guardian_name", "guardian_phone", "tuition"]) {
      await page.getByTestId(`column-toggle-${col}`).setChecked(true);
    }
    await page.getByTestId("column-toggle-personal_identification_number").setChecked(true);
    await waitPrefsSaved(page, "consultant-grid-prefs-status");

    const newRow = page.getByTestId("portfolio-new-row");
    await newRow.getByTestId("inline-family-name").fill("NGUYỄN VĂN");
    await newRow.getByTestId("inline-given-name").fill("AN");
    await newRow.getByTestId("inline-date-of-birth").fill("2017-06-09");
    await newRow.getByTestId("inline-guardian-name").fill("NGUYỄN VĂN B");
    await newRow.getByTestId("inline-guardian-phone").fill("0912345678");
    await newRow.getByTestId("inline-personal-id").fill("001234567890");
    await page.getByTestId("portfolio-save-new-row").click();

    const firstRow = page.getByTestId("portfolio-row").first();
    await expect(firstRow).toContainText("AN", { timeout: 30_000 });
    const entryId = (await firstRow.getAttribute("data-entry-id"))!;
    const row = page.locator(`[data-testid="portfolio-row"][data-entry-id="${entryId}"]`);

    const assertCoreRow = async () => {
      await expect(row.getByTestId("portfolio-lifecycle-status")).toHaveText("Tiềm năng");
      await expect(row.getByTestId("portfolio-date-of-birth")).toHaveText("09/06/2017");
      await expect(row).toContainText("NGUYỄN VĂN B");
      await expect(row).toContainText("0912345678");
      await expect(row.getByTestId("portfolio-student-code")).toHaveText("02170000");
      await expect(row).toContainText("001234567890");
      await expect(row.getByTestId("portfolio-tuition")).toContainText("Chưa nộp phí");
    };
    await assertCoreRow();
    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
    await assertCoreRow();

    // CREATE + EDIT VALUE
    const colId = await createColumn(page, "Ghi chú của tôi");
    expect(colId).toBe("custom_ghi_chu_cua_toi");
    await expect(page.getByTestId(`column-header-${colId}`)).toContainText("Ghi chú của tôi");
    await row.getByTestId("portfolio-edit-row").click();
    await row.getByTestId(`inline-custom-ghi_chu_cua_toi`).fill("Phụ huynh hẹn gọi lại ngày 10/10");
    await row.getByTestId("portfolio-save-edit-row").click();
    await expect(row.getByTestId("portfolio-custom-ghi_chu_cua_toi")).toHaveText(
      "Phụ huynh hẹn gọi lại ngày 10/10",
      { timeout: 30_000 },
    );

    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
    await expect(row.getByTestId("portfolio-custom-ghi_chu_cua_toi")).toHaveText("Phụ huynh hẹn gọi lại ngày 10/10");

    // RENAME keeps the value
    await renameColumn(page, colId, "Theo dõi của tôi");
    await expect(page.getByTestId(`column-header-${colId}`)).toContainText("Theo dõi của tôi");
    await expect(row.getByTestId("portfolio-custom-ghi_chu_cua_toi")).toHaveText("Phụ huynh hẹn gọi lại ngày 10/10");

    // WIDTH
    await page.getByTestId(`personal-column-width-${colId}`).fill("260");
    await expect(page.getByTestId(`column-header-${colId}`)).toHaveAttribute("style", /width:\s*260px/);

    // ORDER (second personal column to reorder against)
    const helperId = await createColumn(page, "Cột tạm");
    expect(await headerOrder(page, [colId, helperId])).toEqual([colId, helperId]);
    await page.getByTestId(`personal-column-move-right-${colId}`).click();
    expect(await headerOrder(page, [colId, helperId])).toEqual([helperId, colId]);

    // HIDE (value retained)
    await page.getByTestId(`column-toggle-${colId}`).setChecked(false);
    await expect(page.getByTestId(`column-header-${colId}`)).toHaveCount(0);
    await waitPrefsSaved(page, "consultant-grid-prefs-status");

    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
    await expect(page.getByTestId(`personal-column-label-${colId}`)).toHaveText("Theo dõi của tôi");
    await expect(page.getByTestId(`column-header-${colId}`)).toHaveCount(0);
    await expect(page.getByTestId(`column-toggle-${colId}`)).not.toBeChecked();

    // SHOW (value back, width/order persisted)
    await page.getByTestId(`column-toggle-${colId}`).setChecked(true);
    await expect(row.getByTestId("portfolio-custom-ghi_chu_cua_toi")).toHaveText("Phụ huynh hẹn gọi lại ngày 10/10");
    await expect(page.getByTestId(`column-header-${colId}`)).toHaveAttribute("style", /width:\s*260px/);
    expect(await headerOrder(page, [colId, helperId])).toEqual([helperId, colId]);
    await waitPrefsSaved(page, "consultant-grid-prefs-status");

    // FILTER (type-appropriate text filter on the personal column)
    const filter = page.getByTestId(`personal-column-filter-${colId}`);
    await filter.fill("hẹn gọi lại");
    await expect(row).toBeVisible();
    await filter.fill("không tồn tại");
    await expect(row).toHaveCount(0);
    await filter.fill("");
    await expect(row).toBeVisible();

    // ARCHIVE: column removed, core data intact, survives refresh
    await archiveColumn(page, colId);
    await archiveColumn(page, helperId);
    await assertCoreRow();
    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
    await expect(page.getByTestId(`personal-column-manage-${colId}`)).toHaveCount(0);
    await expect(page.getByTestId(`column-header-${colId}`)).toHaveCount(0);
    await assertCoreRow();
  });

  test("custom columns named like core fields never overwrite core identity", async ({ page }) => {
    await signIn(page, consultantEmail);
    await openConsultant(page);
    await ensureVietnamese(page);
    await openConsultant(page);
    await page.getByTestId("column-toggle-student_code").setChecked(true);

    const newRow = page.getByTestId("portfolio-new-row");
    await newRow.getByTestId("inline-family-name").fill("TÁCH");
    await newRow.getByTestId("inline-given-name").fill("BIỆT");
    await newRow.getByTestId("inline-date-of-birth").fill("2016-03-15");
    await page.getByTestId("portfolio-save-new-row").click();
    const firstRow = page.getByTestId("portfolio-row").first();
    await expect(firstRow).toContainText("BIỆT", { timeout: 30_000 });
    const entryId = (await firstRow.getAttribute("data-entry-id"))!;
    const row = page.locator(`[data-testid="portfolio-row"][data-entry-id="${entryId}"]`);

    const dobCol = await createColumn(page, "Ngày sinh");
    const codeCol = await createColumn(page, "Mã học viên");
    expect(dobCol).not.toBe("custom_date_of_birth");
    expect(codeCol).not.toBe("custom_student_code");
    const dobKey = dobCol.replace("custom_", "");
    const codeKey = codeCol.replace("custom_", "");

    await row.getByTestId("portfolio-edit-row").click();
    await row.getByTestId(`inline-custom-${dobKey}`).fill("01/01/2000");
    await row.getByTestId(`inline-custom-${codeKey}`).fill("XX999999");
    await row.getByTestId("portfolio-save-edit-row").click();
    await expect(row.getByTestId(`portfolio-custom-${codeKey}`)).toHaveText("XX999999", { timeout: 30_000 });

    await page.reload();
    await expect(page.getByTestId("portfolio-grid")).toBeVisible({ timeout: 30_000 });
    await expect(row.getByTestId("portfolio-date-of-birth")).toHaveText("15/03/2016");
    await expect(row.getByTestId("portfolio-student-code")).toHaveText("02160000");
    await expect(row.getByTestId(`portfolio-custom-${dobKey}`)).toHaveText("01/01/2000");
    await expect(row.getByTestId(`portfolio-custom-${codeKey}`)).toHaveText("XX999999");

    await archiveColumn(page, dobCol);
    await archiveColumn(page, codeCol);
    await expect(row.getByTestId("portfolio-date-of-birth")).toHaveText("15/03/2016");
  });
});

async function runListLifecycle(
  page: Page,
  options: {
    email: string;
    path: string;
    surface: "students" | "finance_students";
    rowTestId: string;
    label: string;
    renamed: string;
    value: string;
  },
) {
  await signIn(page, options.email);
  await openPersonalGrid(page, options.path, options.surface);
  await ensureVietnamese(page);
  await openPersonalGrid(page, options.path, options.surface);

  const row = page.locator(`[data-testid="${options.rowTestId}"][data-row-id="${fixtureStudentId}"]`);
  await expect(row).toBeVisible();

  const colId = await createColumn(page, options.label);
  await expect(page.getByTestId(`column-header-${colId}`)).toContainText(options.label);

  await page.getByTestId(`personal-row-edit-${fixtureStudentId}`).click();
  await page.getByTestId(`personal-input-${colId}-${fixtureStudentId}`).fill(options.value);
  await page.getByTestId(`personal-row-save-${fixtureStudentId}`).click();
  const value = page.getByTestId(`personal-value-${colId}-${fixtureStudentId}`);
  await expect(value).toHaveText(options.value);

  await openPersonalGrid(page, options.path, options.surface);
  await expect(value).toHaveText(options.value);

  await renameColumn(page, colId, options.renamed);
  await expect(page.getByTestId(`column-header-${colId}`)).toContainText(options.renamed);
  await expect(value).toHaveText(options.value);

  await page.getByTestId(`personal-column-width-${colId}`).fill("240");
  await expect(page.getByTestId(`column-header-${colId}`)).toHaveAttribute("style", /width:\s*240px/);

  const helperId = await createColumn(page, `${options.renamed} phụ`);
  expect(await headerOrder(page, [colId, helperId])).toEqual([colId, helperId]);
  await page.getByTestId(`personal-column-move-left-${helperId}`).click();
  expect(await headerOrder(page, [colId, helperId])).toEqual([helperId, colId]);

  await page.getByTestId(`column-toggle-${colId}`).setChecked(false);
  await expect(page.getByTestId(`column-header-${colId}`)).toHaveCount(0);
  await waitPrefsSaved(page, "personal-grid-prefs-status");

  await openPersonalGrid(page, options.path, options.surface);
  await expect(page.getByTestId(`personal-column-label-${colId}`)).toHaveText(options.renamed);
  await expect(page.getByTestId(`column-header-${colId}`)).toHaveCount(0);
  await expect(page.getByTestId(`column-toggle-${colId}`)).not.toBeChecked();

  await page.getByTestId(`column-toggle-${colId}`).setChecked(true);
  await expect(value).toHaveText(options.value);
  await expect(page.getByTestId(`column-header-${colId}`)).toHaveAttribute("style", /width:\s*240px/);
  expect(await headerOrder(page, [colId, helperId])).toEqual([helperId, colId]);
  await waitPrefsSaved(page, "personal-grid-prefs-status");

  const filter = page.getByTestId(`personal-column-filter-${colId}`);
  await filter.fill(options.value.slice(0, 6));
  await expect(row).toBeVisible();
  await filter.fill("không tồn tại");
  await expect(row).toHaveCount(0);
  await filter.fill("");
  await expect(row).toBeVisible();

  await archiveColumn(page, colId);
  await archiveColumn(page, helperId);
  await openPersonalGrid(page, options.path, options.surface);
  await expect(page.getByTestId(`personal-column-manage-${colId}`)).toHaveCount(0);
  await expect(row).toBeVisible();
}

test.describe("CW2-T13 Học vụ and Accounting personal column lifecycle", () => {
  test.describe.configure({ timeout: 240_000 });

  test("Học vụ manages personal columns on the student list", async ({ page }) => {
    await runListLifecycle(page, {
      email: academicEmail,
      path: "/students?q=Ghi%20Chu",
      surface: "students",
      rowTestId: "student-list-row",
      label: "Lưu ý xếp lớp",
      renamed: "Ghi chú xếp lớp",
      value: "Cần xếp lớp buổi tối",
    });
  });

  test("Accounting manages personal columns on student accounts (incl. zero-balance students)", async ({
    page,
  }) => {
    await runListLifecycle(page, {
      email: accountantEmail,
      path: "/finance/receivables",
      surface: "finance_students",
      rowTestId: "finance-student-row",
      label: "Lưu ý công nợ",
      renamed: "Theo dõi công nợ",
      value: "Đối chiếu hóa đơn tháng 10",
    });
    const row = page.locator(`[data-testid="finance-student-row"][data-row-id="${fixtureStudentId}"]`);
    await expect(row.getByTestId("finance-student-outstanding")).toHaveText(/^0/);
  });
});

async function rolePage(browser: Browser, email: string): Promise<Page> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await signIn(page, email);
  return page;
}

test.describe("CW2-T13 personal column isolation (UI)", () => {
  test.describe.configure({ timeout: 300_000 });

  test("consultant, Học vụ, Accounting, owner and teacher see only their own columns", async ({ browser }) => {
    const consultant = await rolePage(browser, consultantEmail);
    await openConsultant(consultant);
    const cwCol = await createColumn(consultant, "CW riêng tư");

    const academic = await rolePage(browser, academicEmail);
    await openPersonalGrid(academic, "/students?q=Ghi%20Chu", "students");
    const hvCol = await createColumn(academic, "HV riêng tư");

    const accountant = await rolePage(browser, accountantEmail);
    await openPersonalGrid(accountant, "/finance/receivables", "finance_students");
    const ktCol = await createColumn(accountant, "KT riêng tư");

    await openPersonalGrid(academic, "/students?q=Ghi%20Chu", "students");
    await expect(manageCard(academic, "HV riêng tư")).toHaveCount(1);
    await expect(manageCard(academic, "CW riêng tư")).toHaveCount(0);
    await expect(manageCard(academic, "KT riêng tư")).toHaveCount(0);

    await openPersonalGrid(accountant, "/finance/receivables", "finance_students");
    await expect(manageCard(accountant, "KT riêng tư")).toHaveCount(1);
    await expect(manageCard(accountant, "CW riêng tư")).toHaveCount(0);
    await expect(manageCard(accountant, "HV riêng tư")).toHaveCount(0);

    await openConsultant(consultant);
    await expect(manageCard(consultant, "CW riêng tư")).toHaveCount(1);
    await expect(manageCard(consultant, "HV riêng tư")).toHaveCount(0);
    await expect(manageCard(consultant, "KT riêng tư")).toHaveCount(0);

    const owner = await rolePage(browser, ownerEmail);
    for (const [path, surface] of [
      ["/students?q=Ghi%20Chu", "students"],
      ["/finance/receivables", "finance_students"],
    ] as const) {
      await openPersonalGrid(owner, path, surface);
      for (const label of ["CW riêng tư", "HV riêng tư", "KT riêng tư"]) {
        await expect(manageCard(owner, label)).toHaveCount(0);
      }
    }

    const teacher = await rolePage(browser, teacherEmail);
    for (const path of ["/students", "/consultant", "/finance/receivables"]) {
      await teacher.goto(path);
      await expect(teacher.locator("body")).toBeVisible();
      await expect(teacher.getByTestId("add-custom-column")).toHaveCount(0);
      await expect(teacher.locator('[data-testid^="personal-column-manage-"]')).toHaveCount(0);
    }
    await teacher.goto("/consultant");
    await expect(teacher.getByTestId("portfolio-grid")).toHaveCount(0);

    await archiveColumn(consultant, cwCol);
    await archiveColumn(academic, hvCol);
    await archiveColumn(accountant, ktCol);

    for (const p of [consultant, academic, accountant, owner, teacher]) {
      await p.context().close();
    }
  });
});
