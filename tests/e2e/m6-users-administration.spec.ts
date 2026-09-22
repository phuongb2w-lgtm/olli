import { expect, test } from "@playwright/test";
import { signIn } from "./sign-in";

const ownerEmail = "org-a-admin@olli.local";
const teacherEmail = "org-a-staff@olli.local";
const accountantEmail = "m6-t04-accountant@olli.local";
const consultantEmail = "m6-t04-consultant@olli.local";
const academicOpsEmail = "m6-t04-academic-ops@olli.local";

const deniedUsers = [teacherEmail, accountantEmail, consultantEmail, academicOpsEmail];

test.describe("M6-T04 users administration", () => {
  test.describe.configure({ timeout: 120_000 });

  test("1. primary Owner sees users nav and workspace", async ({ page }) => {
    await signIn(page, ownerEmail);
    await expect(page.locator('nav a[href="/users"]')).toBeVisible();
    await page.goto("/users");
    await expect(
      page.getByRole("heading", { level: 1, name: /users & team|người dùng & đội ngũ/i }),
    ).toBeVisible({ timeout: 45_000 });
    await expect(page.getByText(/primary owner|chủ sở hữu chính/i)).toBeVisible();
    await expect(page.getByText(/org-a-admin@olli\.local/i)).toBeVisible();
    await expect(page.getByText(/\d+\s*\/\s*\d+\s*(staff accounts|tài khoản nhân sự)/i)).toBeVisible();
    await expect(page.getByRole("cell", { name: "org-a-staff@olli.local" })).toBeVisible();
  });

  for (const email of deniedUsers) {
    test(`2. ${email} denied /users nav and direct URL`, async ({ page }) => {
      await signIn(page, email);
      await expect(page.locator('nav a[href="/users"]')).toHaveCount(0);
      await page.goto("/users");
      await expect(
        page.getByText(
          /primary owner only|chủ sở hữu chính/i,
        ),
      ).toBeVisible();
    });
  }

  test("3. provision form has no password and no center_manager role", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await expect(page.getByLabel(/email/i)).toBeVisible({ timeout: 45_000 });
    await expect(page.locator('input[type="password"]')).toHaveCount(0);
    const roleSelect = page.locator("#staff-role");
    const options = roleSelect.locator("option");
    await expect(options).toHaveCount(4);
    const values = await options.evaluateAll((nodes) =>
      nodes.map((node) => (node as HTMLOptionElement).value),
    );
    expect(values).not.toContain("center_manager");
  });

  test("4. successful staff provisioning refreshes list and seats", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await expect(page.getByLabel(/email/i)).toBeVisible({ timeout: 45_000 });

    const unique = `m6-t04-${Date.now()}@olli.local`;
    await page.locator("#staff-email").fill(unique);
    await page.locator("#staff-display-name").fill("M6 E2E Staff");
    await page.locator("#staff-role").selectOption("consultant");
    await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();

    await expect(
      page.getByText(/staff account created|đã tạo tài khoản nhân sự/i),
    ).toBeVisible({ timeout: 90_000 });
    await expect(page.getByText(unique)).toBeVisible({ timeout: 45_000 });
  });

  test("5. duplicate member maps to localized error", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await page.locator("#staff-email").fill("org-a-staff@olli.local");
    await page.locator("#staff-display-name").fill("Duplicate");
    await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
    await expect(
      page.getByText(/already belongs to your center|đã thuộc nhân sự/i),
    ).toBeVisible({ timeout: 60_000 });
  });

  test("6. idempotency key stable while submission in flight", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/users");
    const unique = `m6-t04-idem-${Date.now()}@olli.local`;
    await page.locator("#staff-email").fill(unique);
    await page.locator("#staff-display-name").fill("Idem Staff");
    await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
    await expect(page.getByTestId("provision-idempotency-key")).toBeVisible({ timeout: 10_000 });
    const keyDuring = await page.getByTestId("provision-idempotency-key").innerText();
    await expect(
      page.getByRole("button", { name: /creating account|đang tạo tài khoản|continue setup|tiếp tục thiết lập/i }),
    ).toBeVisible({ timeout: 5_000 });
    const keyStill = await page.getByTestId("provision-idempotency-key").innerText();
    expect(keyStill).toBe(keyDuring);
  });

  test("7. new logical attempt rotates idempotency key after terminal error", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await page.locator("#staff-email").fill("org-a-staff@olli.local");
    await page.locator("#staff-display-name").fill("Dup");
    await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
    await expect(page.getByTestId("provision-idempotency-key")).toBeVisible({ timeout: 30_000 });
    const firstKey = await page.getByTestId("provision-idempotency-key").innerText();
    await page.getByRole("button", { name: /start a new request|bắt đầu yêu cầu mới/i }).click();
    const unique = `m6-t04-new-${Date.now()}@olli.local`;
    await page.locator("#staff-email").fill(unique);
    await page.locator("#staff-display-name").fill("Fresh Staff");
    await page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }).click();
    await expect(page.getByTestId("provision-idempotency-key")).toBeVisible({ timeout: 10_000 });
    const secondKey = await page.getByTestId("provision-idempotency-key").innerText();
    expect(secondKey).not.toBe(firstKey);
  });

  test("8. seat full disables new submission", async ({ page }) => {
    await signIn(page, "org-b-admin@olli.local");
    await page.goto("/users");
    await expect(page.getByText(/\d+\s*\/\s*\d+/i)).toBeVisible({ timeout: 45_000 });

    for (let i = 0; i < 8; i += 1) {
      const unique = `m6-t04-seat-${Date.now()}-${i}@olli.local`;
      await page.locator("#staff-email").fill(unique);
      await page.locator("#staff-display-name").fill(`Seat Fill ${i}`);
      const submit = page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i });
      if (await submit.isDisabled()) break;
      await submit.click();
      const success = page.getByText(/staff account created|đã tạo tài khoản nhân sự/i);
      const full = page.getByText(/seat limit reached|giới hạn ghế/i);
      await expect(success.or(full)).toBeVisible({ timeout: 90_000 });
      if (await full.isVisible()) break;
    }

    await expect(
      page
        .getByText(/seat limit reached|giới hạn ghế|all staff seats are in use|đã dùng hết ghế/i)
        .first(),
    ).toBeVisible({ timeout: 45_000 });
    await expect(
      page.getByRole("button", { name: /create staff|tạo tài khoản nhân sự/i }),
    ).toBeDisabled();
  });
});
