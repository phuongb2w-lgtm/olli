#!/usr/bin/env node
/**
 * M8-T09: repository production-readiness smoke gate (static + optional critical Playwright).
 */

import { execSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { assertFoundationCiContract } from "./lib/ci-workflow-contract.mjs";
import { assertMigrationInventory } from "./lib/migration-inventory.mjs";
import { assertVerifyGateComposition } from "./lib/verify-gate-contract.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const staticOnly = process.argv.includes("--static-only");

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

function runStaticGate(name, fn) {
  try {
    fn();
    pass(name);
  } catch (error) {
    console.error(`FAIL: ${name} — ${error.message}`);
    process.exit(1);
  }
}

console.log("==> M8-T09 repository smoke gate (static contracts)");

runStaticGate("verify script composition", () => {
  assertVerifyGateComposition();
});

runStaticGate("Foundation CI workflow composition", () => {
  assertFoundationCiContract();
});

runStaticGate("migration inventory", () => {
  const { count, latest } = assertMigrationInventory();
  console.log(`INFO: migration count ${count}, latest ${latest}`);
});

if (staticOnly) {
  console.log("Repository smoke static gate PASSED.");
  process.exit(0);
}

console.log("==> M8-T09 critical application smoke (Playwright)");
try {
  execSync("npx playwright test --config=playwright.smoke.config.ts", {
    cwd: root,
    stdio: "inherit",
    shell: true,
  });
} catch {
  console.error("FAIL: critical Playwright smoke suite");
  process.exit(1);
}

console.log("Repository smoke gate PASSED.");
