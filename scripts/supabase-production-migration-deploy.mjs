#!/usr/bin/env node
/**
 * Apply pending repository migrations to the linked Supabase Cloud project.
 * Fails closed without OLLI_CONFIRM_PRODUCTION_DEPLOY=yes. Never includes seed.
 */

import {
  assertLinkedProjectMatches,
  assertProductionRuntimeEnv,
  assertProductionSupabaseUrl,
  execSupabase,
  requireExpectedProjectRef,
  requireProductionDeployConfirmation,
} from "./lib/supabase-production.mjs";
import { migrationCount } from "./lib/migration-inventory.mjs";

const dryRunOnly = process.argv.includes("--dry-run");

try {
  const { url } = assertProductionRuntimeEnv();
  const urlRef = assertProductionSupabaseUrl(url);
  const expectedRef = requireExpectedProjectRef(urlRef);
  assertLinkedProjectMatches(expectedRef);

  console.log(`Target project ref: ${expectedRef}`);
  console.log(`Repository migration files: ${migrationCount()}`);
  console.log("Seed policy: supabase/seed.sql and db:seed:auth are NEVER applied by this script.");

  if (dryRunOnly || process.env.OLLI_MIGRATION_DRY_RUN === "1") {
    console.log("==> Dry run (supabase db push --linked --dry-run, no seed):");
    console.log(execSupabase("db push --linked --dry-run").trimEnd());
    console.log("PASS: Dry run completed.");
    process.exit(0);
  }

  requireProductionDeployConfirmation();

  console.log("==> Applying pending migrations (supabase db push --linked --yes):");
  console.log(execSupabase("db push --linked --yes").trimEnd());

  console.log("==> Lint linked database:");
  console.log(execSupabase("db lint --linked --fail-on error").trimEnd());

  console.log("PASS: Production migration deploy completed.");
} catch (error) {
  console.error(`FAIL: ${error.message}`);
  process.exit(1);
}
