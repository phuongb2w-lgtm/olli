import { expect, test, type Page } from "@playwright/test";
import { signIn } from "./sign-in";

const ownerEmail = "org-a-admin@olli.local";
const lockedEmail = "m6-t05-locked@olli.local";

async function readSeatUsage(page: Page): Promise<{ used: number; limit: number }> {
  const text = await page.getByText(/\d+\s*\/\s*\d+\s*(staff accounts|tài khoản nhân sự)/i).innerText();
  const match = text.match(/(\d+)\s*\/\s*(\d+)/);
  if (!match) {
    throw new Error(`Could not parse seat usage from: ${text}`);
  }
  return { used: Number(match[1]), limit: Number(match[2]) };
}

async function provisionLifecycleStaff(page: Page, email: string): Promise<void> {
  await page.locator("#staff-email").fill(email);
  await page.locator("#staff-display-name").fill("M6 T05 Lifecycle");
  await page.locator("#staff-role").selectOption("consultant");
  await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
  await expect(
    page.getByText(/staff account created|đã tạo tài khoản nhân sự/i),
  ).toBeVisible({ timeout: 90_000 });
  await expect(page.getByTestId(`staff-row-${email}`)).toBeVisible({ timeout: 45_000 });
}

async function provisionLifecycleStaffMobile(page: Page, email: string): Promise<void> {
  await page.locator("#staff-email").fill(email);
  await page.locator("#staff-display-name").fill("M6 T07 Mobile");
  await page.locator("#staff-role").selectOption("consultant");
  await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
  await expect(
    page.getByText(/staff account created|đã tạo tài khoản nhân sự/i),
  ).toBeVisible({ timeout: 90_000 });
  await expect(page.getByTestId(`staff-card-${email}`)).toBeVisible({ timeout: 45_000 });
}

test.describe("M6-T05 staff lifecycle", () => {
  test.describe.configure({ mode: "serial", timeout: 180_000 });

  test("1. primary Owner has no lifecycle controls; locked staff has none", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await expect(page.getByTestId("primary-owner-card")).toBeVisible({ timeout: 45_000 });
    await expect(page.getByTestId(`staff-actions-${ownerEmail}`)).toHaveCount(0);
    await expect(page.getByTestId(`staff-row-${lockedEmail}`)).toBeVisible();
    await expect(page.getByTestId(`action-suspend-${lockedEmail}`)).toHaveCount(0);
    await expect(page.getByTestId(`action-change-role-${lockedEmail}`)).toHaveCount(0);
    await expect(page.getByTestId(`action-remove-${lockedEmail}`)).toHaveCount(0);
    await expect(page.getByTestId(`action-reactivate-${lockedEmail}`)).toHaveCount(0);
    await expect(page.getByText(/access locked|khóa truy cập/i).first()).toBeVisible();
  });

  test("2. current staff actions, suspend, reactivate, role change, remove, restore", async ({
    page,
  }) => {
    const email = `m6-t05-e2e-${Date.now()}@olli.local`;
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await expect(page.locator("#staff-email")).toBeVisible({ timeout: 45_000 });

    await provisionLifecycleStaff(page, email);
    const seatsAfterCreate = await readSeatUsage(page);

    const currentRow = page.getByTestId(`staff-row-${email}`);
    await expect(currentRow.getByTestId(`action-change-role-${email}`)).toBeVisible();
    await expect(currentRow.getByTestId(`action-suspend-${email}`)).toBeVisible();
    await expect(currentRow.getByTestId(`action-remove-${email}`)).toBeVisible();
    await expect(currentRow.getByTestId(`action-reactivate-${email}`)).toHaveCount(0);

    await currentRow.getByTestId(`action-change-role-${email}`).click();
    await expect(page.getByTestId("confirm-change-role")).toBeVisible();
    await page.getByTestId("confirm-change-role").locator("select").selectOption("teacher");
    await page.getByTestId("confirm-change-role").locator("button").first().click();
    await expect(page.getByTestId("confirm-change-role")).toHaveCount(0);
    await expect(page.getByTestId(`staff-row-${email}`)).toContainText(/teacher|giáo viên/i);

    await currentRow.getByTestId(`action-suspend-${email}`).click();
    await expect(page.getByTestId("confirm-suspend")).toBeVisible();
    await expect(page.getByTestId("confirm-suspend")).toContainText(
      /not be able to use olli|cannot use olli|không dùng được olli/i,
    );
    await expect(page.getByTestId("confirm-suspend")).toContainText(
      /seat stays occupied|ghế nhân sự vẫn được giữ|does not free capacity|không giải phóng/i,
    );
    await page.getByTestId("confirm-suspend").locator("button").first().click();
    await expect(page.getByTestId(`staff-row-${email}`)).toContainText(
      /access suspended|tạm ngưng truy cập/i,
    );
    await expect(currentRow.getByTestId(`action-reactivate-${email}`)).toBeVisible();
    const seatsAfterSuspend = await readSeatUsage(page);
    expect(seatsAfterSuspend.used).toBe(seatsAfterCreate.used);

    await currentRow.getByTestId(`action-reactivate-${email}`).click();
    await page.getByTestId("confirm-reactivate").locator("button").first().click();
    await expect(page.getByTestId(`staff-row-${email}`)).toContainText(
      /active access|đang hoạt động/i,
    );
    await expect(currentRow.getByTestId(`action-suspend-${email}`)).toBeVisible();

    await currentRow.getByTestId(`action-remove-${email}`).click();
    await expect(page.getByTestId("confirm-remove")).toBeVisible();
    await expect(page.getByTestId("confirm-remove")).toContainText(
      /historical records remain|hồ sơ lịch sử được giữ nguyên/i,
    );
    await expect(page.getByTestId("confirm-remove")).not.toContainText(/delete user|xóa người dùng/i);
    await page.getByTestId("confirm-remove").locator("button").first().click();
    await expect(page.getByTestId(`removed-staff-${email}`)).toBeVisible({ timeout: 45_000 });
    await expect(page.getByTestId(`staff-row-${email}`)).toHaveCount(0);
    const seatsAfterRemove = await readSeatUsage(page);
    expect(seatsAfterRemove.used).toBe(seatsAfterCreate.used - 1);

    await page.getByTestId(`removed-staff-${email}`).getByTestId(`action-restore-${email}`).click();
    await expect(page.getByTestId("confirm-restore")).toBeVisible();
    await expect(page.getByTestId("confirm-restore")).toContainText(
      /available staff seat|ghế nhân sự còn trống/i,
    );
    await page.getByTestId(`restore-role-${email}`).selectOption("accountant");
    await page.getByTestId("confirm-restore").locator("button").first().click();
    await expect(page.getByTestId(`staff-row-${email}`)).toBeVisible({ timeout: 45_000 });
    await expect(page.getByTestId(`staff-row-${email}`)).toContainText(
      /accountant|kế toán/i,
    );
    const seatsAfterRestore = await readSeatUsage(page);
    expect(seatsAfterRestore.used).toBe(seatsAfterCreate.used);
  });

  test("4. mobile staff cards: lifecycle smoke and locked has no actions", async ({ page }) => {
    const email = `m6-t07-mobile-${Date.now()}@olli.local`;
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await expect(page.locator("#staff-email")).toBeVisible({ timeout: 45_000 });

    await provisionLifecycleStaffMobile(page, email);
    const card = page.getByTestId(`staff-card-${email}`);
    await expect(card).toBeVisible();
    await expect(page.getByTestId(`staff-row-${email}`)).toBeHidden();

    await expect(card.getByRole("button", { name: /^(Change role|Đổi vai trò)$/i })).toBeVisible();
    await expect(card.getByRole("button", { name: /^(Suspend|Tạm ngưng)$/i })).toBeVisible();
    await expect(
      card.getByRole("button", { name: /^(Remove from center|Gỡ khỏi trung tâm)$/i }),
    ).toBeVisible();

    const lockedCard = page.getByTestId(`staff-card-${lockedEmail}`);
    await expect(lockedCard).toBeVisible();
    await expect(lockedCard.getByRole("button", { name: /^(Suspend|Tạm ngưng)$/i })).toHaveCount(0);
    await expect(lockedCard.getByRole("button", { name: /^(Change role|Đổi vai trò)$/i })).toHaveCount(0);

    const suspendTrigger = card.getByRole("button", { name: /^(Suspend|Tạm ngưng)$/i });
    await suspendTrigger.click();
    await expect(suspendTrigger).toHaveAttribute("aria-expanded", "true");
    await expect(card.locator('[role="region"]')).toBeVisible();
    await card
      .locator('[role="region"]')
      .getByRole("button", { name: /confirm suspend|xác nhận tạm ngưng/i })
      .click();
    await expect(card.getByText(/access suspended|tạm ngưng truy cập/i)).toBeVisible({ timeout: 45_000 });
  });

  test("5. restore blocked when staff seats are full", async ({ page }) => {
    const ownerC = "m6-t04-org-c-owner@olli.local";
    const victimEmail = `m6-t07-removed-${Date.now()}@olli.local`;

    await signIn(page, ownerC);
    await page.goto("/users");
    await expect(page.locator("#staff-email")).toBeVisible({ timeout: 45_000 });

    const { limit: staffLimit } = await readSeatUsage(page);

    for (let i = 0; i < 8; i += 1) {
      const { used, limit } = await readSeatUsage(page);
      if (used >= limit - 1) break;
      const unique = `m6-t07-fill-${Date.now()}-${i}@olli.local`;
      await page.locator("#staff-email").fill(unique);
      await page.locator("#staff-display-name").fill(`Fill ${i}`);
      const submit = page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i });
      if (await submit.isDisabled()) break;
      await submit.click();
      await expect(
        page.getByText(/staff account created|đã tạo tài khoản nhân sự/i),
      ).toBeVisible({ timeout: 90_000 });
    }

    await page.locator("#staff-email").fill(victimEmail);
    await page.locator("#staff-display-name").fill("M6 T07 Removed Victim");
    await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
    await expect(
      page.getByText(/staff account created|đã tạo tài khoản nhân sự/i),
    ).toBeVisible({ timeout: 90_000 });
    await expect(page.getByTestId(`staff-row-${victimEmail}`)).toBeVisible({ timeout: 45_000 });

    const row = page.getByTestId(`staff-row-${victimEmail}`);
    await row.getByTestId(`action-remove-${victimEmail}`).click();
    await page.getByTestId("confirm-remove").locator("button").first().click();
    await expect(page.getByTestId(`removed-staff-${victimEmail}`)).toBeVisible({ timeout: 45_000 });

    for (let i = 0; i < 4; i += 1) {
      const { used, limit } = await readSeatUsage(page);
      if (used >= limit) break;
      const unique = `m6-t07-refill-${Date.now()}-${i}@olli.local`;
      await page.locator("#staff-email").fill(unique);
      await page.locator("#staff-display-name").fill(`Refill ${i}`);
      const submit = page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i });
      if (await submit.isDisabled()) break;
      await submit.click();
      await expect(
        page.getByText(/staff account created|đã tạo tài khoản nhân sự/i),
      ).toBeVisible({ timeout: 90_000 });
    }

    const seatsFull = await readSeatUsage(page);
    expect(seatsFull.used).toBe(seatsFull.limit);

    await page.getByTestId(`removed-staff-${victimEmail}`).getByTestId(`action-restore-${victimEmail}`).click();
    await page.getByTestId("confirm-restore").locator("button").first().click();

    await expect(
      page.getByText(
        /all staff seats are in use|free a seat before restoring|đã dùng hết ghế nhân sự|giải phóng ghế trước khi khôi phục/i,
      ),
    ).toBeVisible({ timeout: 45_000 });
    await expect(page.getByText(/staff_seat_limit_exceeded|permission_denied|42501|PostgREST/i)).toHaveCount(0);

    await expect(page.getByTestId(`removed-staff-${victimEmail}`)).toBeVisible();
    await expect(page.getByTestId(`staff-row-${victimEmail}`)).toHaveCount(0);
    const seatsAfter = await readSeatUsage(page);
    expect(seatsAfter.used).toBe(seatsFull.used);
    expect(seatsFull.limit).toBe(staffLimit);
  });

  test("3. removed-email provision surfaces restore-oriented error", async ({ page }) => {
    const email = `m6-t05-e2e-dup-${Date.now()}@olli.local`;
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await provisionLifecycleStaff(page, email);
    await page.getByTestId(`staff-row-${email}`).getByTestId(`action-remove-${email}`).click();
    await page.getByTestId("confirm-remove").locator("button").first().click();
    await expect(page.getByTestId(`removed-staff-${email}`)).toBeVisible({ timeout: 45_000 });

    await page.locator("#staff-email").fill(email);
    await page.locator("#staff-display-name").fill("Should Restore");
    await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
    await expect(
      page.getByText(/restore them from removed staff|khôi phục từ mục nhân sự đã gỡ/i),
    ).toBeVisible({ timeout: 60_000 });
  });
});
