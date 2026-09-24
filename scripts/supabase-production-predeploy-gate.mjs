#!/usr/bin/env node
/**
 * Local/release gates before operator runs production migration deploy.
 * Does not contact Supabase Cloud unless OLLI_PREDEPLOY_INCLUDE_REMOTE=1.
 */

import { execSync } from "node:child_process";
import { migrationCount } from "./lib/migration-inventory.mjs";
import { repoRoot } from "./lib/migration-inventory.mjs";

let failed = false;

function run(label, cmd) {
  console.log(`==> ${label}`);
  try {
    execSync(cmd, { cwd: repoRoot, stdio: "inherit", shell: true });
    console.log(`PASS: ${label}`);
  } catch {
    console.error(`FAIL: ${label}`);
    failed = true;
  }
}

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  failed = true;
}

const expectedCount = Number(process.env.OLLI_EXPECTED_MIGRATION_COUNT ?? migrationCount());
const actualCount = migrationCount();
if (actualCount !== expectedCount) {
  fail(`migration count ${actualCount} != OLLI_EXPECTED_MIGRATION_COUNT/default ${expectedCount}`);
} else {
  pass(`migration count ${actualCount}`);
}

const releaseSha = process.env.OLLI_RELEASE_GIT_SHA?.trim();
if (releaseSha) {
  const head = execSync("git rev-parse HEAD", { cwd: repoRoot, encoding: "utf8" }).trim();
  if (head !== releaseSha) fail(`HEAD ${head} != OLLI_RELEASE_GIT_SHA ${releaseSha}`);
  else pass(`release SHA matches HEAD (${head.slice(0, 12)})`);
} else {
  console.log("INFO: OLLI_RELEASE_GIT_SHA not set — skipping exact SHA pin");
}

const dirty = execSync("git status --porcelain", { cwd: repoRoot, encoding: "utf8" }).trim();
if (dirty) fail("working tree not clean — commit or stash before production DB deploy");
else pass("working tree clean");

run("environment secrets audit", "npm run test:env");
run("generated types stale check (local Supabase)", "npm run test:types:stale");
run("database verification suite (local reset+seed+SQL tests)", "npm run db:verify");

if (process.env.OLLI_PREDEPLOY_INCLUDE_REMOTE === "1") {
  run("production env check", "node scripts/supabase-production-env-check.mjs");
  run("link verify", "node scripts/supabase-production-link-verify.mjs");
  run("remote migration status", "node scripts/supabase-production-migration-status.mjs");
} else {
  console.log(
    "INFO: Skipping remote Supabase checks (set OLLI_PREDEPLOY_INCLUDE_REMOTE=1 when linked credentials available).",
  );
}

if (failed) {
  console.error("Pre-deploy gate FAILED.");
  process.exit(1);
}
console.log("Pre-deploy gate PASSED (local gates).");
