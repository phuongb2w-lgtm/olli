#!/usr/bin/env node
/**
 * M5-T01 foundation smoke: permissions, executive boundary, period helpers, consultant revenue.
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";

function loadEnv() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

const env = loadEnv();
const url = env.API_URL;
const key = env.PUBLISHABLE_KEY;
const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} M5-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

async function signIn(email) {
  const client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password: "testpass123",
  });
  if (error) throw new Error(`${email}: ${error.message}`);
  return createClient(url, key, {
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function isIsoLocalDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return (
    date.getUTCFullYear() === y &&
    date.getUTCMonth() === m - 1 &&
    date.getUTCDate() === d
  );
}

function validateLocalDateRange(startDate, endDate) {
  if (!isIsoLocalDate(startDate) || !isIsoLocalDate(endDate)) {
    return { ok: false, error: "invalid_date" };
  }
  if (startDate > endDate) return { ok: false, error: "invalid_range" };
  return { ok: true, period: { startDate, endDate } };
}

async function main() {
  // 1–2: deterministic period helper (application layer)
  record(
    1,
    "validateLocalDateRange accepts inclusive range",
    validateLocalDateRange("2026-01-01", "2026-01-31").ok,
  );
  record(
    2,
    "validateLocalDateRange rejects inverted range",
    validateLocalDateRange("2026-02-01", "2026-01-01").error === "invalid_range",
  );

  const admin = await signIn("org-a-admin@olli.local");
  const staff = await signIn("org-a-staff@olli.local");

  // 3: admin list_my_permissions includes executive
  const { data: adminPerms, error: adminPermErr } = await admin.rpc("list_my_permissions");
  record(
    3,
    "admin list_my_permissions includes report.executive.read",
    !adminPermErr && adminPerms.includes("report.executive.read"),
  );

  // 4: staff lacks executive permission
  const { data: staffPerms } = await staff.rpc("list_my_permissions");
  record(
    4,
    "staff lacks report.executive.read",
    Array.isArray(staffPerms) && !staffPerms.includes("report.executive.read"),
  );

  // 5: admin executive RPC succeeds
  const { error: execOkErr } = await admin.rpc("get_executive_reporting_access");
  record(5, "admin executive RPC succeeds", !execOkErr, execOkErr?.message ?? "");

  // 6: staff executive RPC denied
  const { error: execFailErr } = await staff.rpc("get_executive_reporting_access");
  record(
    6,
    "staff executive RPC denied",
    execFailErr?.code === "42501" || execFailErr?.message?.includes("permission"),
    execFailErr?.message ?? "",
  );

  // 7: resolve_reporting_period RPC
  const { data: bounds, error: boundsErr } = await admin.rpc("resolve_reporting_period", {
    p_start_date: "2026-01-01",
    p_end_date: "2026-01-31",
  });
  const boundsRow = Array.isArray(bounds) ? bounds[0] : bounds;
  record(
    7,
    "resolve_reporting_period returns UTC bounds",
    !boundsErr &&
      boundsRow?.start_date === "2026-01-01" &&
      boundsRow?.end_date === "2026-01-31" &&
      Boolean(boundsRow?.start_at_utc),
    boundsErr?.message ?? "",
  );

  // 8: pending vs canonical revenue distinction
  const { data: pending, error: pendingErr } = await admin.rpc(
    "sum_pending_consultant_declarations",
    { p_start_date: "2020-01-01", p_end_date: "2099-12-31" },
  );
  const { data: canonical, error: canonicalErr } = await admin.rpc(
    "count_canonical_financial_revenue",
    { p_start_date: "2020-01-01", p_end_date: "2099-12-31" },
  );
  record(
    8,
    "pending declarations and canonical revenue RPCs callable",
    !pendingErr && !canonicalErr && Number(pending) >= 0 && Number(canonical) >= 0,
  );

  // 9–11: semantic boundaries (T01.1)
  const { data: matCount } = await admin.rpc("count_materialized_teaching_sessions", {
    p_date_from: "2020-01-01",
    p_date_to: "2099-12-31",
    p_class_id: null,
  });
  const { data: delCount } = await admin.rpc("count_delivered_teaching_sessions", {
    p_date_from: "2020-01-01",
    p_date_to: "2099-12-31",
    p_class_id: null,
  });
  record(
    9,
    "materialized session count >= delivered session count",
    Number(matCount) >= Number(delCount),
  );

  const { data: approvedDecl } = await admin.rpc("sum_approved_consultant_declarations", {
    p_start_date: "2020-01-01",
    p_end_date: "2099-12-31",
  });
  const { data: cashCollected } = await admin.rpc("sum_canonical_cash_collected", {
    p_start_date: "2020-01-01",
    p_end_date: "2099-12-31",
  });
  record(
    10,
    "approved declarations and cash collected are separate RPCs",
    Number(approvedDecl) >= 0 && Number(cashCollected) >= 0,
  );

  const { data: isDelivered } = await admin.rpc("teaching_session_is_delivered", {
    p_status: "scheduled",
  });
  record(
    11,
    "scheduled status is not delivered",
    isDelivered === false,
  );

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM5 foundation smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
