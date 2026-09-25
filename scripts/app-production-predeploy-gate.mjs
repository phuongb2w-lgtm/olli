#!/usr/bin/env node
/**
 * Release gates before deploying the Next.js application to production/staging.
 * Does not deploy; validates repository + optional hosted env when configured.
 */

import { execSync } from "node:child_process";
import { migrationCount, repoRoot } from "./lib/migration-inventory.mjs";

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
if (dirty) fail("working tree not clean — commit or stash before app deploy");
else pass("working tree clean");

run("environment secrets audit", "npm run test:env");
run("lint", "npm run lint");
run("typecheck", "npm run typecheck");
run("production build", "npm run build");

if (process.env.OLLI_APP_PREDEPLOY_INCLUDE_HOST_ENV === "1") {
  run("hosted app env check", "node scripts/app-production-env-check.mjs");
} else {
  console.log(
    "INFO: Skipping hosted env check (set OLLI_APP_PREDEPLOY_INCLUDE_HOST_ENV=1 when production/staging secrets are loaded).",
  );
}

if (failed) {
  console.error("Application pre-deploy gate FAILED.");
  process.exit(1);
}
console.log("Application pre-deploy gate PASSED.");
