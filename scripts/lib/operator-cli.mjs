/**
 * M8-T08 — shared RIUDA operator CLI helpers (service_role only; never imported by app).
 */

import { execSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";
import { assertProductionSupabaseUrl, parseProjectRefFromSupabaseUrl } from "./supabase-production.mjs";
import { adminClientFromEnv } from "./center-provisioning-orchestrate.mjs";

const SECRET_ENV_NAMES = [
  "SUPABASE_SECRET_KEY",
  "SECRET_KEY",
  "SERVICE_ROLE_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
  "SUPABASE_ACCESS_TOKEN",
];

export const SUBSCRIPTION_RPC = {
  activate: "activate_organization_subscription",
  suspend: "suspend_organization_subscription",
  reactivate: "reactivate_organization_subscription",
  cancel: "cancel_organization_subscription",
};

export function loadEnvFromSupabaseStatus() {
  if (process.env.OLLI_OPERATOR_SKIP_SUPABASE_STATUS === "1") return;
  try {
    const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
    for (const line of raw.split("\n")) {
      const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
      if (!match) continue;
      const [, key, value] = match;
      if (key === "API_URL" && !process.env.NEXT_PUBLIC_SUPABASE_URL) {
        process.env.NEXT_PUBLIC_SUPABASE_URL = value;
      }
      if ((key === "SECRET_KEY" || key === "SERVICE_ROLE_KEY") && !process.env.SUPABASE_SECRET_KEY) {
        process.env.SUPABASE_SECRET_KEY = value;
      }
    }
  } catch {
    // optional when env vars already set
  }
}

export function requireOperatorAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.API_URL;
  const key = process.env.SUPABASE_SECRET_KEY ?? process.env.SECRET_KEY ?? process.env.SERVICE_ROLE_KEY;
  if (!url?.trim() || !key?.trim()) {
    throw new Error(
      "Missing trusted Supabase credentials. Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SECRET_KEY (service role).",
    );
  }
  return adminClientFromEnv();
}

export function isCloudSupabaseTarget() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.API_URL;
  if (!url?.trim()) return false;
  try {
    assertProductionSupabaseUrl(url);
    return true;
  } catch {
    return false;
  }
}

/** Fail closed before mutating Cloud Supabase (M8-T05 contract). */
export function assertProductionOperatorMutationAllowed() {
  if (!isCloudSupabaseTarget()) return;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.API_URL;
  const ref = parseProjectRefFromSupabaseUrl(url) ?? assertProductionSupabaseUrl(url);
  if (process.env.OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION !== "yes") {
    throw new Error(
      `Refusing operator mutation against Supabase Cloud project ${ref}. Set OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION=yes after verifying target identity.`,
    );
  }
  const expectedRef = process.env.OLLI_SUPABASE_PROJECT_REF?.trim();
  if (expectedRef && expectedRef !== ref) {
    throw new Error(
      `OLLI_SUPABASE_PROJECT_REF (${expectedRef}) does not match NEXT_PUBLIC_SUPABASE_URL ref (${ref}).`,
    );
  }
}

export function assertSubscriptionActionConfirmed(action, organizationId) {
  const flag = process.env.OLLI_CONFIRM_SUBSCRIPTION_ACTION?.trim();
  if (flag !== action) {
    throw new Error(
      `Subscription ${action} requires OLLI_CONFIRM_SUBSCRIPTION_ACTION=${action} for organization ${organizationId}.`,
    );
  }
  const orgFlag = process.env.OLLI_CONFIRM_ORGANIZATION_ID?.trim();
  if (orgFlag && orgFlag !== organizationId) {
    throw new Error(
      `OLLI_CONFIRM_ORGANIZATION_ID (${orgFlag}) does not match resolved organization ${organizationId}.`,
    );
  }
}

export function parseFlagArgs(argv, spec) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--") {
      out._.push(...argv.slice(i + 1));
      break;
    }
    if (!arg.startsWith("--")) {
      out._.push(arg);
      continue;
    }
    const key = arg.slice(2);
    const def = spec[key];
    if (def === "boolean") {
      out[key] = true;
    } else if (def === "string") {
      const next = argv[i + 1];
      if (!next || next.startsWith("--")) {
        throw new Error(`Missing value for --${key}`);
      }
      out[key] = next;
      i += 1;
    } else {
      throw new Error(`Unknown flag: --${key}`);
    }
  }
  return out;
}

/**
 * Resolve organization by UUID or exact name (case-sensitive trim match).
 * Rejects ambiguous name matches.
 */
export async function resolveOrganizationTarget(admin, { organizationId, organizationName }) {
  if (organizationId?.trim()) {
    const id = organizationId.trim();
    const { data, error } = await admin.from("organization").select("id, name, status").eq("id", id).maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) throw new Error(`organization_not_found:${id}`);
    return data;
  }

  const name = organizationName?.trim();
  if (!name) {
    throw new Error("Provide --organization-id or --organization-name");
  }

  const { data, error } = await admin.from("organization").select("id, name, status").eq("name", name);
  if (error) throw new Error(error.message);
  if (!data?.length) throw new Error(`organization_not_found:name:${name}`);
  if (data.length > 1) {
    throw new Error(
      `ambiguous_organization_name:${name} (${data.length} matches). Use --organization-id instead.`,
    );
  }
  return data[0];
}

export async function fetchOperatorOrganizationStatus(admin, organizationId) {
  const { data: org, error: orgErr } = await admin
    .from("organization")
    .select("id, name, status")
    .eq("id", organizationId)
    .maybeSingle();
  if (orgErr) throw new Error(orgErr.message);
  if (!org) throw new Error(`organization_not_found:${organizationId}`);

  const { data: sub, error: subErr } = await admin
    .from("organization_subscription")
    .select("id, status, activated_at, suspended_at, cancelled_at, commercial_plan_id")
    .eq("organization_id", organizationId)
    .maybeSingle();
  if (subErr) throw new Error(subErr.message);

  let plan = null;
  if (sub?.commercial_plan_id) {
    const { data: planRow } = await admin
      .from("commercial_plan")
      .select("code, name")
      .eq("id", sub.commercial_plan_id)
      .maybeSingle();
    plan = planRow;
  }

  const { data: ent, error: entErr } = await admin
    .from("organization_entitlement")
    .select("staff_limit, primary_app_user_id")
    .eq("organization_id", organizationId)
    .maybeSingle();
  if (entErr) throw new Error(entErr.message);

  let primaryOwner = null;
  if (ent?.primary_app_user_id) {
    const { data: ownerUser } = await admin
      .from("app_user")
      .select("id, email, display_name, status, membership_status")
      .eq("id", ent.primary_app_user_id)
      .maybeSingle();
    primaryOwner = ownerUser;
  }

  const { data: seatsUsed, error: seatsErr } = await admin.rpc("count_member_staff_seats", {
    p_organization_id: organizationId,
  });
  if (seatsErr) throw new Error(seatsErr.message);

  const { data: provisioningRows } = await admin
    .from("center_provisioning_request")
    .select("id, status, result_code, idempotency_key, updated_at")
    .eq("organization_id", organizationId)
    .order("updated_at", { ascending: false })
    .limit(3);

  const staffLimit = ent?.staff_limit ?? null;
  const used = typeof seatsUsed === "number" ? seatsUsed : Number(seatsUsed);
  const remaining = staffLimit == null ? null : Math.max(0, staffLimit - used);

  return {
    organization: org,
    subscription: sub
      ? {
          id: sub.id,
          status: sub.status,
          plan_code: plan?.code ?? null,
          plan_name: plan?.name ?? null,
          activated_at: sub.activated_at,
          suspended_at: sub.suspended_at,
          cancelled_at: sub.cancelled_at,
        }
      : null,
    entitlement: ent
      ? {
          staff_limit: staffLimit,
          staff_seats_used: used,
          staff_seats_remaining: remaining,
        }
      : null,
    primary_owner: primaryOwner
      ? {
          app_user_id: primaryOwner.id,
          email: primaryOwner.email,
          display_name: primaryOwner.display_name,
          status: primaryOwner.status,
          membership_status: primaryOwner.membership_status,
        }
      : null,
    recent_provisioning_requests: provisioningRows ?? [],
  };
}

export async function invokeSubscriptionLifecycle(admin, action, organizationId) {
  const rpc = SUBSCRIPTION_RPC[action];
  if (!rpc) throw new Error(`unsupported_action:${action}`);
  const { data, error } = await admin.rpc(rpc, { p_organization_id: organizationId });
  if (error) {
    return { ok: false, stage: rpc, organizationId, error: error.message };
  }
  return { ok: true, stage: rpc, organizationId, result: data };
}

export function printJson(payload) {
  console.log(JSON.stringify(redactSecretsDeep(payload), null, 2));
}

export function redactSecretsDeep(value) {
  if (value == null) return value;
  if (typeof value === "string") {
    if (value.length > 40 && /^eyJ/.test(value)) return "[redacted-jwt]";
    for (const name of SECRET_ENV_NAMES) {
      const secret = process.env[name];
      if (secret && secret.length > 8 && value.includes(secret)) return "[redacted-secret]";
    }
    return value;
  }
  if (Array.isArray(value)) return value.map(redactSecretsDeep);
  if (typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (/secret|password|token|service_role|authorization/i.test(k)) {
        out[k] = "[redacted]";
      } else {
        out[k] = redactSecretsDeep(v);
      }
    }
    return out;
  }
  return value;
}

export function operatorUsage() {
  return `Olli operator CLI (service_role; trusted workstation only)

Usage:
  node scripts/olli-operator.mjs provision --org-name "..." --owner-email "..." --owner-name "..."
  node scripts/olli-operator.mjs status --organization-id <uuid>
  node scripts/olli-operator.mjs status --organization-name "Exact Name"
  node scripts/olli-operator.mjs subscription activate|suspend|reactivate|cancel --organization-id <uuid>

Production Cloud mutations also require:
  OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION=yes
  OLLI_SUPABASE_PROJECT_REF=<ref> (recommended)

Subscription mutations also require:
  OLLI_CONFIRM_SUBSCRIPTION_ACTION=<activate|suspend|reactivate|cancel>
  OLLI_CONFIRM_ORGANIZATION_ID=<uuid> (recommended for suspend/cancel)

See docs/m8/17-operator-tooling-runbook.md`;
}
