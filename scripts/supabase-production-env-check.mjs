#!/usr/bin/env node
/**
 * Verify production/staging Supabase env prerequisites (no secrets printed).
 */

import {
  assertProductionRuntimeEnv,
  assertProductionSupabaseUrl,
  parseProjectRefFromSupabaseUrl,
  requireExpectedProjectRef,
} from "./lib/supabase-production.mjs";

let failed = false;

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  failed = true;
}

try {
  const { url, publishable } = assertProductionRuntimeEnv();
  const urlRef = assertProductionSupabaseUrl(url);
  pass("NEXT_PUBLIC_SUPABASE_URL is a Supabase Cloud URL (not local)");
  pass("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is set");
  pass("SUPABASE_SECRET_KEY is set (value not logged)");

  if (publishable.includes("service_role")) {
    fail("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY must not be a service_role JWT");
  }

  try {
    requireExpectedProjectRef(urlRef);
    pass(`OLLI_SUPABASE_PROJECT_REF matches URL ref (${urlRef})`);
  } catch (error) {
    fail(error.message);
  }

  if (process.env.SUPABASE_ACCESS_TOKEN?.trim()) {
    pass("SUPABASE_ACCESS_TOKEN present (CLI/CI auth — value not logged)");
  } else {
    console.log("INFO: SUPABASE_ACCESS_TOKEN not set — use `npx supabase login` interactively on operator machine");
  }

  const implied = parseProjectRefFromSupabaseUrl(url);
  if (implied && implied !== urlRef) {
    fail("Internal URL ref parse mismatch");
  }
} catch (error) {
  fail(error.message);
}

if (failed) process.exit(1);
console.log("Production environment check complete.");
