import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";
import path from "node:path";

function restorePlaywrightFixtures() {
  execSync("node scripts/playwright-restore-fixtures.mjs", {
    cwd: path.join(__dirname, "../.."),
    stdio: "pipe",
  });
}

const ORG_A = "a0000000-0000-4000-8000-000000000001";
const adminEmail = "org-a-admin@olli.local";
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

async function ensureOrgAActive(svc: ReturnType<typeof serviceClient>) {
  const { error } = await svc
    .from("organization_subscription")
    .update({
      status: "active",
      activated_at: new Date().toISOString(),
      suspended_at: null,
      cancelled_at: null,
    })
    .eq("organization_id", ORG_A);
  expect(error).toBeNull();
}

async function suspendOrgA(svc: ReturnType<typeof serviceClient>) {
  await ensureOrgAActive(svc);
  const { error } = await svc.rpc("suspend_organization_subscription", {
    p_organization_id: ORG_A,
  });
  expect(error).toBeNull();
  const { data } = await svc
    .from("organization_subscription")
    .select("status")
    .eq("organization_id", ORG_A)
    .single();
  expect(data?.status).toBe("suspended");
}

test.describe.configure({ mode: "serial" });

test.describe("M7-T04 commercial access", () => {
  test.beforeAll(async () => {
    await ensureOrgAActive(serviceClient());
  });

  test.afterEach(async () => {
    await ensureOrgAActive(serviceClient());
    restorePlaywrightFixtures();
  });

  test.afterAll(async () => {
    restorePlaywrightFixtures();
  });

  test("suspended owner reaches subscription status, not workspace shell", async ({ page }) => {
    const svc = serviceClient();
    await suspendOrgA(svc);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(adminEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);
    await expect(
      page.getByRole("heading", { name: /subscription|đăng ký/i }),
    ).toBeVisible();

    await page.goto("/");
    await expect(page).toHaveURL(/\/subscription-status/);
  });

  test("suspended staff blocked from workspace shell", async ({ page }) => {
    const svc = serviceClient();
    await suspendOrgA(svc);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(staffEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/commercial-access/);
    await expect(page.getByText(/workspace unavailable|không gian làm việc không khả dụng/i)).toBeVisible();
  });

  test("reactivation restores owner workspace without re-login", async ({ page }) => {
    const svc = serviceClient();
    await suspendOrgA(svc);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(adminEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);

    await svc.rpc("reactivate_organization_subscription", { p_organization_id: ORG_A });
    await page.goto("/");
    await expect(page.getByText("Olli Test Org A")).toBeVisible();
    await expect(page.getByText("Org A Admin")).toBeVisible();
  });

  test("cancelled owner stable restricted surface without redirect loop", async ({ page }) => {
    const svc = serviceClient();
    await ensureOrgAActive(svc);
    await svc
      .from("organization_subscription")
      .update({ status: "cancelled", cancelled_at: new Date().toISOString() })
      .eq("organization_id", ORG_A);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(adminEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);
    await page.goto("/subscription-status");
    await expect(page).toHaveURL(/\/subscription-status/);
  });

  test("mobile viewport renders restricted owner surface", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    const svc = serviceClient();
    await suspendOrgA(svc);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(adminEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);
    await expect(page.getByRole("heading", { name: "Olli Test Org A" })).toBeVisible();
  });
});
