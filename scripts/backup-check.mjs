#!/usr/bin/env node
/**
 * M8-T10 backup readiness checklist (static + local stack probe; no Cloud export).
 */

import { execSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { assertMigrationInventory } from "./lib/migration-inventory.mjs";
import { LOCAL_DB_CONTAINER, assertLocalRecoveryTarget } from "./lib/recovery-target.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
}

function checkDocs() {
  const required = [
    join(root, "docs", "m8", "06-backup-recovery-contract.md"),
    join(root, "docs", "m8", "19-backup-restore-dr-runbook.md"),
  ];
  for (const path of required) {
    if (!existsSync(path)) fail(`missing doc: ${path}`);
  }
  pass("backup/recovery documentation present");
}

function checkNoDumpArtifactsInRepo() {
  const forbidden = [".pgdump", ".dump", ".sql.gz"];
  const walk = (dir, acc = []) => {
    for (const name of readdirSync(dir, { withFileTypes: true })) {
      if (name.name === "node_modules" || name.name === ".git") continue;
      const full = join(dir, name.name);
      if (name.isDirectory()) walk(full, acc);
      else acc.push(full);
    }
    return acc;
  };
  const hits = walk(root).filter((file) =>
    forbidden.some((ext) => file.endsWith(ext) && !file.includes("node_modules")),
  );
  if (hits.length) fail(`forbidden backup artifact in repository: ${hits.join(", ")}`);
  pass("no database dump artifacts committed");
}

function checkRecoveryScripts() {
  const drill = readFileSync(join(root, "scripts", "recovery-drill.mjs"), "utf8");
  if (!drill.includes("assertLocalRecoveryTarget")) {
    fail("recovery-drill.mjs missing local target guard");
  }
  if (!drill.includes("assertProductionRestoreAllowed")) {
    fail("recovery-drill.mjs missing production restore guard");
  }
  pass("recovery drill script guards present");
}

function checkMigrationInventory() {
  const { count } = assertMigrationInventory();
  const expected = Number(process.env.OLLI_EXPECTED_MIGRATION_COUNT ?? "59");
  if (count !== expected) {
    fail(`migration count ${count} != expected ${expected}`);
  }
  pass(`migration inventory count ${count}`);
}

function optionalLocalProbe() {
  if (process.argv.includes("--static-only")) return;
  try {
    execSync(`docker inspect ${LOCAL_DB_CONTAINER}`, { stdio: "pipe" });
  } catch {
    console.log("SKIP: local Supabase container not running (static backup check only)");
    return;
  }
  try {
    execSync("npx supabase status -o env", { encoding: "utf8", cwd: root, stdio: "pipe" });
    assertLocalRecoveryTarget();
    pass("local Supabase target recognized for backup tooling");
  } catch (error) {
    fail(error.message);
  }
}

console.log("==> M8-T10 backup check");
checkDocs();
checkNoDumpArtifactsInRepo();
checkRecoveryScripts();
checkMigrationInventory();
optionalLocalProbe();
console.log("Backup check PASSED.");
