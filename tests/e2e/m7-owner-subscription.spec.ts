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

test.describe.configure({ mode: "serial" });

test.describe("M7-T05 Owner subscription UX", () => {
  test.beforeAll(() => {
    restoreFixtures();
  });

  test.afterEach(async () => {
    restoreFixtures();
  });

  test("active owner sees subscription workspace with plan, status, and seats", async ({ page }) => {
    await signIn(page, ownerEmail);
    await page.goto("/subscription");
    await expect(
      page.getByRole("heading", { level: 1, name: /subscription|đăng ký/i }),
    ).toBeVisible({ timeout: 45_000 });
    await expect(page.getByText(/active|đang hoạt động/i).first()).toBeVisible();
    await expect(page.getByText(/staff seats in use|ghế nhân sự đang dùng/i)).toBeVisible();
    await expect(page.getByText(/staff seat limit|giới hạn ghế nhân sự/i)).toBeVisible();
    await expect(page.getByText(/staff seats remaining|ghế nhân sự còn lại/i)).toBeVisible();
    await expect(page.getByRole("button", { name: /suspend|tạm ngưng|cancel|hủy/i })).toHaveCount(0);
  });

  test("staff denied on /subscription", async ({ page }) => {
    await signIn(page, staffEmail);
    await page.goto("/subscription");
    await expect(page.getByText(/primary owner|chủ sở hữu chính/i)).toBeVisible({ timeout: 45_000 });
  });

  test("owner nav includes subscription; staff nav does not", async ({ page }) => {
    await signIn(page, ownerEmail);
    await expect(page.locator('nav a[href="/subscription"]')).toBeVisible();
    await page.getByRole("button", { name: /sign out|đăng xuất/i }).click();
    await expect(page).toHaveURL(/\/login/);
    await signIn(page, staffEmail);
    await expect(page.locator('nav a[href="/subscription"]')).toHaveCount(0);
  });

  test("suspended owner restricted surface shows explicit suspended messaging", async ({ page }) => {
    const svc = serviceClient();
    await svc.rpc("suspend_organization_subscription", { p_organization_id: ORG_A });

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);
    await expect(page.getByText(/suspended|tạm ngưng/i).first()).toBeVisible();
    await expect(page.getByText(/forbidden|something went wrong|lỗi/i)).toHaveCount(0);
  });

  test("provisioning owner sees provisioning messaging on restricted surface", async ({ page }) => {
    const svc = serviceClient();
    await svc
      .from("organization_subscription")
      .update({
        status: "provisioning",
        activated_at: null,
        suspended_at: null,
        cancelled_at: null,
      })
      .eq("organization_id", ORG_A);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);
    await expect(page.getByText(/provisioning|thiết lập/i).first()).toBeVisible();
  });

  test("cancelled owner sees cancelled messaging", async ({ page }) => {
    const svc = serviceClient();
    await svc
      .from("organization_subscription")
      .update({
        status: "cancelled",
        cancelled_at: new Date().toISOString(),
      })
      .eq("organization_id", ORG_A);

    await page.goto("/login");
    await page.locator('input[name="email"]').fill(ownerEmail);
    await page.locator('input[name="password"]').fill("testpass123");
    await page.getByRole("button", { name: /sign in|đăng nhập/i }).click();
    await expect(page).toHaveURL(/\/subscription-status/);
    await expect(page.getByText(/cancelled|đã hủy/i).first()).toBeVisible();
  });
});
