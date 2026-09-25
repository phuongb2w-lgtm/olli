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

async function ensureOrgAActive() {
  const svc = serviceClient();
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

test.describe.configure({ mode: "serial", timeout: 120_000 });

test.describe("M8-T09 production-critical smoke", () => {
  test.beforeAll(async () => {
    await ensureOrgAActive();
  });

  test.afterEach(async () => {
    await ensureOrgAActive();
    execSync("node scripts/playwright-restore-fixtures.mjs", {
      cwd: path.join(__dirname, "../.."),
      stdio: "pipe",
    });
  });

  test("authentication entry and unauthenticated redirect", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByRole("button", { name: /sign in|đăng nhập/i })).toBeVisible();
    await page.goto("/");
    await expect(page).toHaveURL(/\/login/);
  });

  test("primary Owner reaches workspace shell", async ({ page }) => {
    await signIn(page, ownerEmail);
    await expect(page.getByText("Olli Test Org A")).toBeVisible();
  });

  test("staff role reaches workspace shell", async ({ page }) => {
    await signIn(page, staffEmail);
    await expect(page.getByText("Olli Test Org A")).toBeVisible();
  });

  test("Owner users administration workspace", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/users");
    await expect(
      page.getByRole("heading", { level: 1, name: /users & team|người dùng & đội ngũ/i }),
    ).toBeVisible({ timeout: 45_000 });
  });

  test("staff denied direct /users URL", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/users");
    await expect(page.getByText(/primary owner only|chủ sở hữu chính/i)).toBeVisible();
  });

  test("Owner subscription workspace", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/subscription");
    await expect(
      page.getByRole("heading", { level: 1, name: /subscription|đăng ký/i }),
    ).toBeVisible({ timeout: 45_000 });
  });

  test("representative operational workspace", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/operations");
    await expect(page.getByTestId("daily-operations-view")).toBeVisible();
  });

  test("representative executive reporting route", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/executive");
    await expect(
      page.getByRole("heading", { level: 1, name: /executive overview|tổng quan điều hành/i }),
    ).toBeVisible({ timeout: 45_000 });
  });

  test("completed onboarding Owner leaves /onboarding", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/onboarding");
    await expect(page).not.toHaveURL(/\/onboarding/);
  });

  test("suspended Owner commercial restriction path", async ({ page }) => {
    const svc = serviceClient();
    await ensureOrgAActive();
    const { error } = await svc.rpc("suspend_organization_subscription", {
      p_organization_id: ORG_A,
    });
    expect(error).toBeNull();

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);
    await expect(
      page.getByRole("heading", { name: /subscription|đăng ký/i }),
    ).toBeVisible();
  });
});
