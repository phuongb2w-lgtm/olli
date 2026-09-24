import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";
import path from "node:path";
import { signIn } from "./sign-in";

const ORG_A = "a0000000-0000-4000-8000-000000000001";
const ownerEmail = "org-a-admin@olli.local";
const staffEmail = "org-a-staff@olli.local";

function serviceClient() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env: Record<string, string> = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? env.API_URL;
  const key = process.env.SUPABASE_SECRET_KEY ?? env.SECRET_KEY;
  return createClient(url!, key!, { auth: { persistSession: false } });
}

function restoreFixtures() {
  execSync("node scripts/playwright-restore-fixtures.mjs", {
    cwd: path.join(__dirname, "../.."),
    stdio: "pipe",
  });
}

async function ownerSignIn(page: import("@playwright/test").Page) {
  await page.goto("/login");
  await page.locator('input[name="email"]').fill(ownerEmail);
  await page.locator('input[name="password"]').fill("testpass123");
  await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
}

test.describe.configure({ mode: "serial" });

test.describe("M7-T07 commercialization integration", () => {
  test.beforeEach(() => {
    restoreFixtures();
  });

  test.afterEach(() => {
    restoreFixtures();
  });

  test("provisioning owner with incomplete setup cannot bypass onboarding via subscription-status", async ({
    page,
  }) => {
    const svc = serviceClient();
    await svc.from("organization").update({ setup_completed_at: null }).eq("id", ORG_A);
    await svc
      .from("organization_subscription")
      .update({
        status: "provisioning",
        activated_at: null,
        suspended_at: null,
        cancelled_at: null,
      })
      .eq("organization_id", ORG_A);

    await ownerSignIn(page);
    await expect(page).toHaveURL(/\/onboarding/, { timeout: 45_000 });

    await page.goto("/subscription-status");
    await expect(page).toHaveURL(/\/onboarding/);
  });

  test("operator activation after onboarding opens normal workspace", async ({ page }) => {
    const svc = serviceClient();
    await svc.from("organization").update({ setup_completed_at: null }).eq("id", ORG_A);
    await svc
      .from("organization_subscription")
      .update({
        status: "provisioning",
        activated_at: null,
        suspended_at: null,
        cancelled_at: null,
      })
      .eq("organization_id", ORG_A);

    await ownerSignIn(page);
    await expect(page).toHaveURL(/\/onboarding/);
    await page.locator('input[name="name"]').fill("Olli Test Org A");
    await page.getByRole("button", { name: /complete setup|hoàn tất thiết lập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);

    await svc.rpc("activate_organization_subscription", { p_organization_id: ORG_A });
    await page.goto("/");
    await expect(page.getByText("Org A Admin")).toBeVisible({ timeout: 45_000 });
    await expect(page.getByText("Olli Test Org A")).toBeVisible();
  });

  test("subscription and users surfaces show consistent seat semantics for owner", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/subscription");
    await expect(
      page.getByRole("heading", { level: 1, name: /subscription|đăng ký/i }),
    ).toBeVisible({ timeout: 45_000 });
    await expect(page.getByText(/staff seat limit|giới hạn ghế nhân sự/i)).toBeVisible();
    await expect(page.getByText(/staff seats in use|ghế nhân sự đang dùng/i)).toBeVisible();

    await page.goto("/users");
    await expect(page.getByText(/\d+\s*\/\s*\d+/i)).toBeVisible({ timeout: 45_000 });
  });

  test("suspended staff direct finance route stays commercially restricted", async ({ page }) => {
    const svc = serviceClient();
    await svc.rpc("suspend_organization_subscription", { p_organization_id: ORG_A });

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(staffEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/commercial-access/);

    await page.goto("/finance");
    await expect(page).not.toHaveURL(/\/finance/);
  });
});
