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
import { extractDiffSql, isEffectiveDiffEmpty } from "./lib/drift-diff-parse.mjs";

/** Application schema scope (matches supabase/config.toml [api] schemas). */
const DRIFT_SCHEMA_SCOPE = "public";

try {
  const { url } = assertProductionRuntimeEnv();
  const urlRef = assertProductionSupabaseUrl(url);
  const expectedRef = requireExpectedProjectRef(urlRef);
  assertLinkedProjectMatches(expectedRef);

  console.log(`Drift check for linked project ${expectedRef}`);
  console.log("Rule: production schema changes must come from reviewed repository migrations.");
  console.log(
    `==> supabase db diff --linked --schema ${DRIFT_SCHEMA_SCOPE} (migration shadow vs remote, app schema only):`,
  );
  console.log(
    "Note: Unscoped db diff includes Supabase-managed storage/auth/realtime objects and local verify test helpers — not used for cutover gate.",
  );
  const diff = execSupabase(`db diff --linked --schema ${DRIFT_SCHEMA_SCOPE}`, { allowFailure: true });
  const diffSql = extractDiffSql(diff);
  if (isEffectiveDiffEmpty(diffSql)) {
    console.log("(no effective diff in public schema)");
    console.log("PASS: No schema diff reported between migration baseline and linked remote (public).");
  } else {
    console.log(diffSql);
    console.error(
      "DRIFT SUSPECTED: Non-empty public schema diff. Do not edit production manually. Reconcile via new reviewed migration or incident restore per docs/m8/04 and docs/m8/06.",
    );
    process.exit(2);
  }
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exit(1);
}
