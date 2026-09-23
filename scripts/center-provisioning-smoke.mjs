#!/usr/bin/env node
/**
 * M7-T02 center provisioning integration smoke (Auth Admin + service_role RPC).
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  adminClientFromEnv,
  orchestrateCustomerCenterProvisioning,
} from "./lib/center-provisioning-orchestrate.mjs";

const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} CP-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

function loadEnvFromSupabaseStatus() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

const statusEnv = loadEnvFromSupabaseStatus();
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? statusEnv.API_URL;
const PUBLISHABLE_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? statusEnv.PUBLISHABLE_KEY;
const SERVICE_ROLE_KEY =
  process.env.SUPABASE_SECRET_KEY ?? statusEnv.SECRET_KEY;

async function signInOwner() {
  const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email: "org-a-admin@olli.local",
    password: "testpass123",
  });
  if (error || !data.session?.access_token) {
    throw new Error(`Owner sign-in failed: ${error?.message ?? "no token"}`);
  }
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function signInStaff() {
  const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email: "org-a-staff@olli.local",
    password: "testpass123",
  });
  if (error || !data.session?.access_token) {
    throw new Error(`Staff sign-in failed: ${error?.message ?? "no token"}`);
  }
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function main() {
  process.env.NEXT_PUBLIC_SUPABASE_URL = SUPABASE_URL;
  process.env.SUPABASE_SECRET_KEY = SERVICE_ROLE_KEY;

  const admin = adminClientFromEnv();
  const ownerClient = await signInOwner();
  const staffClient = await signInStaff();

  // CP-1: authenticated owner cannot begin
  {
    const { error } = await ownerClient.rpc("begin_center_provisioning", {
      p_idempotency_key: "cp-deny-owner",
      p_organization_name: "Denied",
      p_owner_email: "deny-owner@olli.local",
      p_owner_display_name: "Denied",
    });
    record(1, "center Owner cannot begin_center_provisioning", Boolean(error));
  }

  // CP-2: staff cannot begin
  {
    const { error } = await staffClient.rpc("begin_center_provisioning", {
      p_idempotency_key: "cp-deny-staff",
      p_organization_name: "Denied",
      p_owner_email: "deny-staff@olli.local",
      p_owner_display_name: "Denied",
    });
    record(2, "staff cannot begin_center_provisioning", Boolean(error));
  }

  // CP-3: anonymous cannot begin
  {
    const anon = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await anon.rpc("begin_center_provisioning", {
      p_idempotency_key: "cp-deny-anon",
      p_organization_name: "Denied",
      p_owner_email: "deny-anon@olli.local",
      p_owner_display_name: "Denied",
    });
    record(3, "anonymous cannot begin_center_provisioning", Boolean(error));
  }

  const idemKey = `cp-smoke-${randomUUID()}`;
  const ownerEmail = `cp-owner-${randomUUID()}@olli.local`;

  // CP-4: successful provision
  const first = await orchestrateCustomerCenterProvisioning(admin, {
    idempotencyKey: idemKey,
    organizationName: "CP Smoke Center",
    ownerEmail,
    ownerDisplayName: "CP Smoke Owner",
  });
  record(
    4,
    "service orchestration provisions center graph",
    first.ok === true,
    first.ok ? first.organizationId : first.error,
  );

  let orgId = first.ok ? first.organizationId : null;

  // CP-5: idempotent retry
  if (first.ok) {
    const second = await orchestrateCustomerCenterProvisioning(admin, {
      idempotencyKey: idemKey,
      organizationName: "CP Smoke Center",
      ownerEmail,
      ownerDisplayName: "CP Smoke Owner",
    });
    record(
      5,
      "idempotent retry returns same organization",
      second.ok && second.organizationId === first.organizationId && second.resumed === true,
    );
  } else {
    record(5, "idempotent retry returns same organization", false, "skipped");
  }

  // CP-6: entitlement and role graph
  if (orgId && first.ok) {
    const { data: ent, error: entError } = await admin
      .from("organization_entitlement")
      .select("staff_limit, primary_app_user_id")
      .eq("organization_id", orgId)
      .single();
    const { data: assignments } = await admin
      .from("user_role")
      .select("role_id")
      .eq("organization_id", orgId)
      .eq("user_id", first.ownerAppUserId)
      .eq("status", "active");
    const roleIds = (assignments ?? []).map((a) => a.role_id);
    const { data: roleRows } = await admin
      .from("role")
      .select("canonical_code")
      .in("id", roleIds.length ? roleIds : ["00000000-0000-0000-0000-000000000000"]);
    const hasCenterManager = (roleRows ?? []).some((r) => r.canonical_code === "center_manager");
    record(
      6,
      "Owner is primary with staff_limit 5 and center_manager",
      !entError &&
        ent?.staff_limit === 5 &&
        ent?.primary_app_user_id === first.ownerAppUserId &&
        hasCenterManager,
      entError?.message,
    );
  } else {
    record(6, "Owner is primary with staff_limit 5 and center_manager", false, "skipped");
  }

  // CP-7: idempotency conflict
  {
    const { error } = await admin.rpc("begin_center_provisioning", {
      p_idempotency_key: idemKey,
      p_organization_name: "CP Smoke Center",
      p_owner_email: ownerEmail,
      p_owner_display_name: "Different Name",
    });
    record(7, "idempotency_conflict on payload change", error?.message?.includes("idempotency_conflict"));
  }

  const failed = results.filter((r) => !r.passed);
  console.log(`\nCenter provisioning smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
