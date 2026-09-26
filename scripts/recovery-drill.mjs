#!/usr/bin/env node
/**
 * M8-T10 local synthetic backup → isolated database → restore → semantic verify.
 * Never targets Supabase Cloud unless OLLI_CONFIRM_PRODUCTION_RESTORE=yes (human incident only).
 */

import { execSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  LOCAL_DB_CONTAINER,
  assertLocalRecoveryTarget,
  assertProductionRestoreAllowed,
  resolveRecoveryDatabaseName,
} from "./lib/recovery-target.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const DATA_SCHEMAS = ["public", "supabase_migrations"];
const SCHEMA_DUMP_SCHEMAS = ["auth", "public", "supabase_migrations"];

function dockerPsql(sql, { database = "postgres" } = {}) {
  execSync(
    `docker exec -i ${LOCAL_DB_CONTAINER} psql -U postgres -d ${database} -v ON_ERROR_STOP=1`,
    { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
  );
}

function dockerExecFile(hostPath, containerPath, database) {
  execSync(
    `docker exec -i ${LOCAL_DB_CONTAINER} psql -U postgres -d ${database} -v ON_ERROR_STOP=1 -f ${containerPath}`,
    { encoding: "utf8", stdio: "inherit" },
  );
}

function assertLocalStackRunning() {
  try {
    execSync(`docker inspect ${LOCAL_DB_CONTAINER}`, { stdio: "pipe" });
  } catch {
    throw new Error(
      `Local Supabase database container ${LOCAL_DB_CONTAINER} is not running. Run: npm run supabase:start`,
    );
  }
}

function loadLocalSupabaseEnv() {
  if (process.env.OLLI_RECOVERY_SKIP_SUPABASE_STATUS === "1") return;
  const raw = execSync("npx supabase status -o env", { encoding: "utf8", cwd: root });
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (!match) continue;
    const [, key, value] = match;
    if (key === "API_URL" && !process.env.NEXT_PUBLIC_SUPABASE_URL) {
      process.env.NEXT_PUBLIC_SUPABASE_URL = value;
    }
  }
}

function stripCreateSchemaStatements(sql) {
  return sql
    .split("\n")
    .filter((line) => !/^CREATE SCHEMA (auth|public|supabase_migrations);/.test(line.trim()))
    .join("\n");
}

function pgDumpArgs(kind) {
  const schemas = kind === "schema" ? SCHEMA_DUMP_SCHEMAS : DATA_SCHEMAS;
  const schemaFlags = schemas.flatMap((s) => ["-n", s]).join(" ");
  if (kind === "schema") {
    return `pg_dump -U postgres -d postgres ${schemaFlags} --schema-only --no-owner --no-privileges`;
  }
  return `pg_dump -U postgres -d postgres ${schemaFlags} --data-only --no-owner --no-privileges`;
}

export function runRecoveryDrill({ quiet = false } = {}) {
  loadLocalSupabaseEnv();
  assertLocalRecoveryTarget();
  assertProductionRestoreAllowed();
  assertLocalStackRunning();

  const recoveryDb = resolveRecoveryDatabaseName();
  const workDir = mkdtempSync(join(tmpdir(), "olli-m8-t10-"));
  const schemaFile = join(workDir, "schema.sql");
  const dataFile = join(workDir, "data.sql");

  const log = quiet ? () => {} : (msg) => console.log(msg);

  try {
    log("==> Apply M8-T10 synthetic DR fixture on source database");
    const fixturePath = join(root, "supabase", "tests", "m8_t10_recovery_fixture.sql");
    execSync(
      `docker exec -i ${LOCAL_DB_CONTAINER} psql -U postgres -d postgres -v ON_ERROR_STOP=1`,
      { input: readFileSync(fixturePath, "utf8"), encoding: "utf8" },
    );

    log("==> Export schema (public + supabase_migrations)");
    const schemaSql = execSync(`docker exec ${LOCAL_DB_CONTAINER} ${pgDumpArgs("schema")}`, {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      shell: true,
    });
    writeFileSync(schemaFile, schemaSql, "utf8");

    log("==> Export data (public + supabase_migrations)");
    const dataSql = execSync(`docker exec ${LOCAL_DB_CONTAINER} ${pgDumpArgs("data")}`, {
      encoding: "utf8",
      maxBuffer: 128 * 1024 * 1024,
      shell: true,
    });
    writeFileSync(dataFile, dataSql, "utf8");

    log(`==> Prepare isolated recovery database: ${recoveryDb}`);
    dockerPsql(
      `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${recoveryDb}' AND pid <> pg_backend_pid();`,
    );
    dockerPsql(`DROP DATABASE IF EXISTS ${recoveryDb} WITH (FORCE);`);
    dockerPsql(`CREATE DATABASE ${recoveryDb};`);

    log("==> Reset recovery target schemas before restore");
    dockerPsql(
      `
      DROP SCHEMA IF EXISTS auth CASCADE;
      CREATE SCHEMA auth;
      GRANT ALL ON SCHEMA auth TO postgres;
      DROP SCHEMA IF EXISTS public CASCADE;
      CREATE SCHEMA public;
      GRANT ALL ON SCHEMA public TO postgres;
      GRANT ALL ON SCHEMA public TO public;
      DROP SCHEMA IF EXISTS supabase_migrations CASCADE;
      CREATE SCHEMA supabase_migrations;
      GRANT ALL ON SCHEMA supabase_migrations TO postgres;
      CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
      CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;
      `,
      { database: recoveryDb },
    );

    log("==> Restore schema to recovery target");
    const schemaForRestore = stripCreateSchemaStatements(schemaSql);
    execSync(
      `docker exec -i ${LOCAL_DB_CONTAINER} psql -U postgres -d ${recoveryDb} -v ON_ERROR_STOP=1`,
      { input: schemaForRestore, encoding: "utf8" },
    );

    log("==> Restore data to recovery target");
    const dataRestoreSql = `SET session_replication_role = replica;\n${dataSql}\nSET session_replication_role = DEFAULT;\n`;
    execSync(
      `docker exec -i ${LOCAL_DB_CONTAINER} psql -U postgres -d ${recoveryDb} -v ON_ERROR_STOP=1`,
      { input: dataRestoreSql, encoding: "utf8" },
    );

    log("==> Semantic verification on recovery target");
    const verifyHost = join(workDir, "verify.sql");
    writeFileSync(verifyHost, readFileSync(join(root, "supabase", "tests", "m8_t10_recovery_verify.sql"), "utf8"));
    const verifyContainer = `/tmp/olli_m8_t10_verify_${Date.now()}.sql`;
    execSync(`docker cp "${verifyHost}" ${LOCAL_DB_CONTAINER}:${verifyContainer}`, { stdio: "pipe" });
    dockerExecFile(verifyHost, verifyContainer, recoveryDb);
    execSync(`docker exec ${LOCAL_DB_CONTAINER} rm -f ${verifyContainer}`, { stdio: "pipe" });

    log("==> Drop isolated recovery database");
    dockerPsql(
      `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${recoveryDb}' AND pid <> pg_backend_pid();`,
    );
    dockerPsql(`DROP DATABASE IF EXISTS ${recoveryDb} WITH (FORCE);`);

    log("M8-T10 recovery drill PASSED.");
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    runRecoveryDrill();
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    process.exit(1);
  }
}
