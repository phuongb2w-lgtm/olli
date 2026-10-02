import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const adminEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";
const academicOpsEmail = "m6-t04-academic-ops@olli.local";
const orgCClassRosterPath = "/classes/c0000000-0000-4000-8000-0000000000c1/roster";

test.describe("M1-T06 enrollment and roster", () => {
  test("admin can open class roster from classes list", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /roster|danh sách lớp/i }).first().click();
    await expect(page.getByRole("heading", { name: /roster|danh sách lớp/i })).toBeVisible();
  });

  test("staff can view roster but not enroll", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /roster|danh sách lớp/i }).first().click();
    await expect(page.getByRole("heading", { name: /roster|danh sách lớp/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /enroll student|ghi danh học viên/i })).toHaveCount(0);
  });

  test("admin can open student enrollment history", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/students");
    await page.getByRole("link", { name: /enrollment history|lịch sử ghi danh/i }).first().click();
    await expect(
      page.getByRole("heading", { name: /enrollment history|lịch sử ghi danh/i }),
    ).toBeVisible();
  });

  test("admin can enroll student from roster flow", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /roster|danh sách lớp/i }).first().click();
    await page.getByRole("link", { name: /enroll student|ghi danh học viên/i }).click();
    await expect(page.getByRole("heading", { name: /enroll student|ghi danh học viên/i })).toBeVisible();
  });
});

test.describe("CW2-T11 roster operational tuition visibility", () => {
  test("elevated staff sees operational tuition badge without payment history columns", async ({ page }) => {
    await signIn(page, adminEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /roster|danh sách lớp/i }).first().click();
    await expect(page.getByTestId("roster-operational-tuition").first()).toBeVisible();
    await expect(page.locator("th").filter({ hasText: /tuition status|trạng thái học phí/i })).toBeVisible();
  });

  test("teacher-only staff does not see operational tuition column", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/classes");
    await page.getByRole("link", { name: /roster|danh sách lớp/i }).first().click();
    await expect(page.getByTestId("roster-operational-tuition")).toHaveCount(0);
  });

  test("academic operations sees operational tuition on org C roster", async ({ page }) => {
    await signIn(page, academicOpsEmail);
    await page.goto(orgCClassRosterPath);
    await expect(page.getByRole("heading", { name: /roster|danh sách lớp/i })).toBeVisible();
    await expect(page.getByTestId("roster-operational-tuition").first()).toBeVisible();
  });
});
