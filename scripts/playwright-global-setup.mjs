#!/usr/bin/env node
/**
 * Ensures fixture orgs A/B are commercially active and Auth fixture users exist before E2E runs.
 */

import { execSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { restoreFixtureOrgCommercialState } from "./playwright-fixture-orgs.mjs";
import { waitForKongAuthAdminReady } from "./lib/local-supabase-auth-ready.mjs";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function applySqlFile(relativePath) {
  const sqlPath = path.join(projectRoot, relativePath);
  if (!fs.existsSync(sqlPath)) {
    console.warn(`[playwright globalSetup] ${relativePath} missing; skipping`);
    return;
  }
  const buf = fs.readFileSync(sqlPath);
  const sql =
    buf.length >= 2 && buf[1] === 0 && buf[0] !== 0
      ? buf.toString("utf16le")
      : buf.toString("utf8");
  const result = spawnSync(
    "docker",
    ["exec", "-i", "supabase_db_olli-local", "psql", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
    { input: sql, encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || `${relativePath} apply failed`);
  }
}

function applyDevSeedSql() {
  applySqlFile("supabase/seed.sql");
}

export default async function globalSetup() {
  try {
    await waitForKongAuthAdminReady();
    let seedOk = false;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        execSync("node scripts/seed-auth-users.mjs", {
          cwd: projectRoot,
          stdio: "inherit",
        });
        seedOk = true;
        break;
      } catch (error) {
        if (attempt < 3) {
          console.warn(
            `[playwright globalSetup] seed-auth-users failed (attempt ${attempt}/3); waiting for Auth…`,
          );
          await waitForKongAuthAdminReady();
        } else {
          throw error;
        }
      }
    }
    if (!seedOk) {
      throw new Error("seed-auth-users.mjs failed after 3 attempts");
    }
    applyDevSeedSql();
    applySqlFile("scripts/e2e-roster-tuition-fixture.sql");
    applySqlFile("scripts/e2e-cw2-t13-fixture.sql");
    restoreFixtureOrgCommercialState();
  } catch (error) {
    console.warn("[playwright globalSetup] auth seed skipped:", error?.message ?? error);
  }
}
