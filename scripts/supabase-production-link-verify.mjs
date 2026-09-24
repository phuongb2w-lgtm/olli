#!/usr/bin/env node
/**
 * Confirm Supabase CLI link + env agree on the intended Cloud project.
 */

import {
  assertLinkedProjectMatches,
  assertProductionRuntimeEnv,
  assertProductionSupabaseUrl,
  execSupabase,
  requireExpectedProjectRef,
} from "./lib/supabase-production.mjs";

try {
  const { url } = assertProductionRuntimeEnv();
  const urlRef = assertProductionSupabaseUrl(url);
  const expectedRef = requireExpectedProjectRef(urlRef);
  assertLinkedProjectMatches(expectedRef);

  console.log(`Linked project ref: ${expectedRef}`);
  console.log(`Supabase API URL: ${url}`);
  console.log("==> Remote migration history (linked):");
  console.log(execSupabase("migration list --linked").trimEnd());
  console.log("PASS: Supabase CLI link matches OLLI_SUPABASE_PROJECT_REF and env URL.");
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exit(1);
}
