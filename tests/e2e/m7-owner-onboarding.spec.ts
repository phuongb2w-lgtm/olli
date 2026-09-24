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

async function markOrgASetupPendingProvisioning(svc: ReturnType<typeof serviceClient>) {
  const { error: orgErr } = await svc
    .from("organization")
    .update({ setup_completed_at: null })
    .eq("id", ORG_A);
  expect(orgErr).toBeNull();
  const { error: subErr } = await svc
    .from("organization_subscription")
    .update({
      status: "provisioning",
      activated_at: null,
      suspended_at: null,
      cancelled_at: null,
    })
    .eq("organization_id", ORG_A);
  expect(subErr).toBeNull();
}

async function markOrgASetupPendingActive(svc: ReturnType<typeof serviceClient>) {
  const { error: orgErr } = await svc
    .from("organization")
    .update({ setup_completed_at: null })
    .eq("id", ORG_A);
  expect(orgErr).toBeNull();
  const { error: subErr } = await svc
    .from("organization_subscription")
    .update({
      status: "active",
      activated_at: new Date().toISOString(),
      suspended_at: null,
      cancelled_at: null,
    })
    .eq("organization_id", ORG_A);
  expect(subErr).toBeNull();
}

test.describe.configure({ mode: "serial" });

test.describe("M7-T06 Owner onboarding", () => {
  test.afterEach(() => {
    restoreFixtures();
  });

  test("provisioning owner lands on onboarding and completes setup", async ({ page }) => {
    const svc = serviceClient();
    await markOrgASetupPendingProvisioning(svc);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/onboarding/, { timeout: 45_000 });
    await expect(
      page.getByRole("heading", { name: /center setup|thiết lập trung tâm/i }),
    ).toBeVisible();

    await page.locator('input[name="name"]').fill("Olli Test Org A Ready");
    await page.getByRole("button", { name: /complete setup|hoàn tất thiết lập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/, { timeout: 45_000 });

    const { data: org } = await svc
      .from("organization")
      .select("setup_completed_at, name")
      .eq("id", ORG_A)
      .single();
    expect(org?.setup_completed_at).not.toBeNull();
    expect(org?.name).toBe("Olli Test Org A Ready");
  });

  test("active owner with incomplete setup completes and reaches workspace", async ({ page }) => {
    const svc = serviceClient();
    await markOrgASetupPendingActive(svc);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/onboarding/, { timeout: 45_000 });

    await page.locator('input[name="name"]').fill("Olli Test Org A");
    await page.getByRole("button", { name: /complete setup|hoàn tất thiết lập/i }).click();
    await expect(page).toHaveURL((url) => url.pathname === "/", { timeout: 45_000 });
    await expect(page.getByText("Olli Test Org A")).toBeVisible();
    await expect(page.getByText("Org A Admin")).toBeVisible();

    await page.goto("/onboarding");
    await expect(page).not.toHaveURL(/\/onboarding/);
  });

  test("staff cannot use onboarding route", async ({ page }) => {
    const svc = serviceClient();
    await markOrgASetupPendingActive(svc);

    await signIn(page, staffEmail);
    await expect(page).not.toHaveURL(/\/onboarding/);

    await page.goto("/onboarding");
    await expect(page).not.toHaveURL(/\/onboarding/);
  });

  test("cancelled owner cannot bypass via onboarding", async ({ page }) => {
    const svc = serviceClient();
    await markOrgASetupPendingActive(svc);
    await svc
      .from("organization_subscription")
      .update({
        status: "cancelled",
        cancelled_at: new Date().toISOString(),
        suspended_at: null,
      })
      .eq("organization_id", ORG_A);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);

    await page.goto("/onboarding");
    await expect(page).not.toHaveURL(/\/onboarding/);
  });

  test("suspended owner cannot bypass via onboarding", async ({ page }) => {
    const svc = serviceClient();
    await markOrgASetupPendingActive(svc);
    await svc.rpc("suspend_organization_subscription", { p_organization_id: ORG_A });

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);

    await page.goto("/onboarding");
    await expect(page).not.toHaveURL(/\/onboarding/);
  });
});
