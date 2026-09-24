#!/usr/bin/env node
/**
 * M7-T03 operator commercial subscription smoke (service_role RPC boundary).
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";

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
  console.log(`${passed ? "PASS" : "FAIL"} SC-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

function admin() {
  return createClient(URL, SERVICE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function ownerClient() {
  const c = createClient(URL, PUBLISHABLE, { auth: { persistSession: false } });
  const { data, error } = await c.auth.signInWithPassword({
    email: "org-a-admin@olli.local",
    password: "testpass123",
  });
  if (error || !data.session) throw new Error(error?.message ?? "sign-in failed");
  return createClient(URL, PUBLISHABLE, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function main() {
  const svc = admin();
  const owner = await ownerClient();

  const { data: planRow } = await svc.from("commercial_plan").select("id").eq("code", "base").single();
  record(1, "base plan readable via service_role", Boolean(planRow?.id));

  const { error: ownerSuspendErr } = await owner.rpc("suspend_organization_subscription", {
    p_organization_id: ORG_A,
  });
  record(2, "Owner cannot suspend subscription", Boolean(ownerSuspendErr));

  const { data: statusData, error: statusErr } = await owner.rpc("fetch_owner_commercial_status");
  record(
    3,
    "Owner fetch_owner_commercial_status",
    !statusErr &&
      statusData?.plan_code === "base" &&
      statusData?.subscription_status === "active" &&
      typeof statusData?.staff_limit === "number" &&
      typeof statusData?.staff_seats_used === "number",
    statusErr?.message,
  );

  const tempOrgName = `SC Temp ${randomUUID().slice(0, 8)}`;
  const { data: begin } = await svc.rpc("begin_center_provisioning", {
    p_idempotency_key: `sc-${randomUUID()}`,
    p_organization_name: tempOrgName,
    p_owner_email: `sc-${randomUUID()}@olli.local`,
    p_owner_display_name: "SC Temp Owner",
  });

  let tempOrgId = begin?.organization_id;
  if (!tempOrgId && begin?.request_id) {
    const email = begin.owner_normalized_email;
    const { data: created } = await svc.auth.admin.createUser({
      email,
      email_confirm: true,
    });
    await svc.rpc("record_center_provisioning_auth_created", {
      p_request_id: begin.request_id,
      p_auth_user_id: created.user.id,
      p_auth_created_by_this_request: true,
    });
    const { data: fin } = await svc.rpc("finalize_center_provisioning", {
      p_request_id: begin.request_id,
    });
    tempOrgId = fin?.organization_id;
  }

  if (!tempOrgId) {
    record(4, "provision temp org for commercial ops", false, "no org");
    record(5, "activate provisioning subscription", false, "skipped");
    record(6, "suspend and reactivate", false, "skipped");
  } else {
    const { data: subBefore } = await svc
      .from("organization_subscription")
      .select("status")
      .eq("organization_id", tempOrgId)
      .single();
    record(4, "new center subscription starts provisioning", subBefore?.status === "provisioning");

    const { data: orgRow } = await svc
      .from("organization")
      .select("setup_completed_at")
      .eq("id", tempOrgId)
      .single();
    record(7, "new center starts with setup incomplete", orgRow?.setup_completed_at == null);

    const { error: actErr } = await svc.rpc("activate_organization_subscription", {
      p_organization_id: tempOrgId,
    });
    record(5, "operator activate subscription", !actErr);

    await svc.rpc("suspend_organization_subscription", { p_organization_id: tempOrgId });
    const { error: reactErr } = await svc.rpc("reactivate_organization_subscription", {
      p_organization_id: tempOrgId,
    });
    record(6, "suspend then reactivate", !reactErr);
  }

  const failed = results.filter((r) => !r.passed);
  console.log(`\nSubscription commercial smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
