#!/usr/bin/env node
/**
 * M7-T04 identity and server-layer commercial access smoke.
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";

const ORG_A = "a0000000-0000-4000-8000-000000000001";

function loadEnv() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

const statusEnv = loadEnv();
const URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? statusEnv.API_URL;
const PUBLISHABLE = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? statusEnv.PUBLISHABLE_KEY;
const SERVICE = process.env.SUPABASE_SECRET_KEY ?? statusEnv.SECRET_KEY;

const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} CA-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

async function authedClient(email) {
  const bootstrap = createClient(URL, PUBLISHABLE, { auth: { persistSession: false } });
  const { data, error } = await bootstrap.auth.signInWithPassword({
    email,
    password: "testpass123",
  });
  if (error || !data.session) throw new Error(error?.message ?? "sign-in failed");
  return createClient(URL, PUBLISHABLE, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function setOrgASubscriptionStatus(svc, status) {
  const patch =
    status === "active"
      ? { status: "active", activated_at: new Date().toISOString(), suspended_at: null, cancelled_at: null }
      : status === "provisioning"
        ? { status: "provisioning", activated_at: null, suspended_at: null, cancelled_at: null }
        : status === "suspended"
          ? { status: "suspended", suspended_at: new Date().toISOString() }
          : { status: "cancelled", cancelled_at: new Date().toISOString() };
  const { error } = await svc
    .from("organization_subscription")
    .update(patch)
    .eq("organization_id", ORG_A);
  if (error) throw error;
}

async function main() {
  const svc = createClient(URL, SERVICE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  await setOrgASubscriptionStatus(svc, "active");

  const owner = await authedClient("org-a-admin@olli.local");
  const staff = await authedClient("org-a-staff@olli.local");

  {
    const { data, error } = await owner.rpc("fetch_session_commercial_access");
    record(
      1,
      "active owner session allows_normal_use",
      !error && data?.allows_normal_use === true && data?.is_primary_owner === true,
      error?.message,
    );
  }

  {
    const { data, error } = await staff.rpc("fetch_session_commercial_access");
    record(
      2,
      "active staff session allows_normal_use",
      !error && data?.allows_normal_use === true && data?.is_primary_owner === false,
      error?.message,
    );
  }

  await setOrgASubscriptionStatus(svc, "provisioning");

  {
    const ownerProvisioning = await authedClient("org-a-admin@olli.local");
    const { data, error } = await ownerProvisioning.rpc("fetch_session_commercial_access");
    record(
      3,
      "provisioning owner blocked from normal use",
      !error && data?.allows_normal_use === false && data?.subscription_status === "provisioning",
      error?.message,
    );
  }

  {
    const staffProvisioning = await authedClient("org-a-staff@olli.local");
    const { data, error } = await staffProvisioning.rpc("fetch_session_commercial_access");
    record(
      4,
      "provisioning staff blocked",
      !error && data?.allows_normal_use === false,
      error?.message,
    );
  }

  await setOrgASubscriptionStatus(svc, "active");
  await svc.rpc("suspend_organization_subscription", { p_organization_id: ORG_A });

  {
    const ownerSuspended = await authedClient("org-a-admin@olli.local");
    const { data, error } = await ownerSuspended.rpc("fetch_session_commercial_access");
    record(
      5,
      "suspended owner session blocked from normal use",
      !error && data?.allows_normal_use === false && data?.subscription_status === "suspended",
      error?.message,
    );
  }

  {
    const ownerSuspended = await authedClient("org-a-admin@olli.local");
    const { data, error } = await ownerSuspended.rpc("fetch_owner_commercial_status");
    record(
      6,
      "suspended owner commercial status read",
      !error && data?.subscription_status === "suspended",
      error?.message,
    );
  }

  {
    const staffSuspended = await authedClient("org-a-staff@olli.local");
    const { data, error } = await staffSuspended.rpc("fetch_session_commercial_access");
    record(
      7,
      "suspended staff session blocked",
      !error && data?.allows_normal_use === false,
      error?.message,
    );
  }

  {
    const staffSuspended = await authedClient("org-a-staff@olli.local");
    const { error } = await staffSuspended.rpc("fetch_owner_commercial_status");
    record(8, "suspended staff cannot read owner commercial status", Boolean(error));
  }

  await svc.rpc("reactivate_organization_subscription", { p_organization_id: ORG_A });

  {
    const ownerReactivated = await authedClient("org-a-admin@olli.local");
    const { data, error } = await ownerReactivated.rpc("fetch_session_commercial_access");
    record(
      9,
      "reactivated owner session restored",
      !error && data?.allows_normal_use === true,
      error?.message,
    );
  }

  await setOrgASubscriptionStatus(svc, "cancelled");

  {
    const ownerCancelled = await authedClient("org-a-admin@olli.local");
    const { data, error } = await ownerCancelled.rpc("fetch_session_commercial_access");
    record(
      10,
      "cancelled owner session blocked",
      !error && data?.allows_normal_use === false && data?.subscription_status === "cancelled",
      error?.message,
    );
  }

  {
    const staffCancelled = await authedClient("org-a-staff@olli.local");
    const { data, error } = await staffCancelled.rpc("fetch_session_commercial_access");
    record(
      11,
      "cancelled staff session blocked",
      !error && data?.allows_normal_use === false,
      error?.message,
    );
  }

  await setOrgASubscriptionStatus(svc, "active");

  const failed = results.filter((r) => !r.passed);
  console.log(`\nCommercial access smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
