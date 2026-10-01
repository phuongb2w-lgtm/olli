#!/usr/bin/env node
/**
 * Local contract: migration shadow vs local DB on public schema only (read-only).
 * Expect empty diff immediately after supabase db reset (no verify test SQL applied).
 */

import { execSync } from "node:child_process";
import { repoRoot } from "./lib/migration-inventory.mjs";
import { extractDiffSql, isEffectiveDiffEmpty } from "./lib/drift-diff-parse.mjs";

try {
  const out = execSync("npx supabase db diff --local --schema public", {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
  });
  const diffSql = extractDiffSql(out);
  if (!isEffectiveDiffEmpty(diffSql)) {
    console.error("FAIL: Expected empty public schema diff after local migrations baseline.");
    console.error(diffSql.slice(0, 2000));
    process.exit(1);
  }
  console.log("PASS: Local public schema matches migration shadow (drift-check contract).");
} catch (error) {
  const stdout = error.stdout?.toString?.() ?? "";
  const diffSql = extractDiffSql(stdout);
  if (isEffectiveDiffEmpty(diffSql)) {
    console.log("PASS: Local public schema matches migration shadow (drift-check contract).");
    process.exit(0);
  }
  console.error(`FAIL: ${error.message}`);
  if (diffSql) console.error(diffSql.slice(0, 2000));
  process.exit(1);
}
