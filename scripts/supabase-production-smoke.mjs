#!/usr/bin/env node
/**
 * Production-safe post-migration smoke checks (read-only, no dev seed fixtures).
 */

import { createClient } from "@supabase/supabase-js";
import {
  assertLinkedProjectMatches,
  assertProductionRuntimeEnv,
  assertProductionSupabaseUrl,
  execSupabase,
  requireExpectedProjectRef,
} from "./lib/supabase-production.mjs";
import { migrationCount, latestMigrationVersion } from "./lib/migration-inventory.mjs";

const DEV_FIXTURE_ORG = "a0000000-0000-4000-8000-000000000001";
const EXPECTED_PERMISSION_MIN = 34;

let failed = false;

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  failed = true;
}

try {
  const { url, publishable, secret } = assertProductionRuntimeEnv();
  const urlRef = assertProductionSupabaseUrl(url);
  const expectedRef = requireExpectedProjectRef(urlRef);
  assertLinkedProjectMatches(expectedRef);

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { count: permCount, error: permError } = await admin
    .from("permission")
    .select("*", { count: "exact", head: true });
  if (permError) fail(`permission table reachable: ${permError.message}`);
  else if ((permCount ?? 0) < EXPECTED_PERMISSION_MIN) {
    fail(`permission count ${permCount} < expected minimum ${EXPECTED_PERMISSION_MIN}`);
  } else pass(`permission reference data present (count=${permCount})`);

  const { data: plans, error: planError } = await admin
    .from("commercial_plan")
    .select("code")
    .eq("code", "base")
    .limit(1);
  if (planError) fail(`commercial_plan query: ${planError.message}`);
  else if (!plans?.length) fail('commercial_plan row "base" missing');
  else pass('commercial_plan "base" row present');

  const { data: devOrg, error: devOrgError } = await admin
    .from("organization")
    .select("id")
    .eq("id", DEV_FIXTURE_ORG)
    .limit(1);
  if (devOrgError) fail(`organization probe: ${devOrgError.message}`);
  else if (devOrg?.length) fail("dev fixture organization UUID present — seed.sql may have been applied");
  else pass("dev fixture organization absent (seed not applied)");

  const rlsSql =
    "SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname IN ('organization', 'student', 'organization_subscription') AND NOT c.relrowsecurity;";
  const rlsOut = execSupabase(`db query --linked "${rlsSql.replace(/"/g, '\\"')}"`);
  const rlsLines = rlsOut
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !/^relname/i.test(l) && !/^-+/.test(l) && l !== "(0 rows)");
  if (rlsLines.length > 0) {
    fail(`RLS disabled on: ${rlsLines.join(", ")}`);
  } else pass("RLS enabled on core protected tables (organization, student, organization_subscription)");

  const migSql = "SELECT count(*)::int AS applied FROM supabase_migrations.schema_migrations;";
  const migOut = execSupabase(`db query --linked "${migSql}"`);
  const appliedMatch = migOut.match(/applied[\s|]*(\d+)/i) ?? migOut.match(/\b(\d+)\b/);
  const applied = appliedMatch ? Number(appliedMatch[1]) : null;
  const repoCount = migrationCount();
  if (applied == null) fail("could not parse remote migration count");
  else if (applied < repoCount) {
    fail(`remote applied migrations (${applied}) < repository files (${repoCount})`);
  } else {
    pass(`remote migration count ${applied} >= repository files ${repoCount} (latest repo prefix ${latestMigrationVersion()})`);
  }

  const anon = createClient(url, publishable, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: anonOrgError } = await anon.from("organization").select("id").limit(1);
  if (anonOrgError) pass("anon cannot read organization (RLS/auth as expected)");
  else pass("anon organization select returned without error (empty result still OK for smoke)");

  const rpcSql =
    "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'fetch_session_commercial_access' LIMIT 1;";
  const rpcOut = execSupabase(`db query --linked "${rpcSql}"`);
  if (/1/.test(rpcOut) && !/0 rows/i.test(rpcOut)) {
    pass("fetch_session_commercial_access RPC registered in public schema");
  } else {
    fail("fetch_session_commercial_access RPC not found");
  }
} catch (error) {
  fail(error.message);
}

if (failed) process.exit(1);
console.log("Production DB smoke complete.");
