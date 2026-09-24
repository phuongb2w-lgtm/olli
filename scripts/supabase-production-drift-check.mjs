#!/usr/bin/env node
/**
 * Investigate schema drift: repository migrations baseline vs linked remote.
 * Read-only — does not apply changes or auto-repair production.
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

  console.log(`Drift check for linked project ${expectedRef}`);
  console.log("Rule: production schema changes must come from reviewed repository migrations.");
  console.log("==> supabase db diff --linked (migrations shadow vs remote):");
  const diff = execSupabase("db diff --linked", { allowFailure: true });
  const trimmed = (diff ?? "").trim();
  if (!trimmed || /no changes/i.test(trimmed)) {
    console.log(trimmed || "(no diff output — treat as no drift detected by CLI)");
    console.log("PASS: No schema diff reported between migration baseline and linked remote.");
  } else {
    console.log(trimmed);
    console.error(
      "DRIFT SUSPECTED: Non-empty diff. Do not edit production manually. Reconcile via new reviewed migration or incident restore per docs/m8/04 and docs/m8/06.",
    );
    process.exit(2);
  }
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exit(1);
}
