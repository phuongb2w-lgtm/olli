/**
 * Authoritative migration file inventory (repository order).
 */

import { readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const migrationsDir = join(root, "supabase", "migrations");

export function listMigrationFiles() {
  return readdirSync(migrationsDir)
    .filter((name) => name.endsWith(".sql"))
    .sort();
}

export function migrationCount() {
  return listMigrationFiles().length;
}

/** Ordered, unique migration filenames; optional pin via OLLI_EXPECTED_MIGRATION_COUNT. */
export function assertMigrationInventory() {
  const files = listMigrationFiles();
  if (files.length === 0) {
    throw new Error("no migration files under supabase/migrations");
  }

  const seen = new Set();
  let prevNumeric = -1;
  for (const name of files) {
    if (seen.has(name)) {
      throw new Error(`duplicate migration filename: ${name}`);
    }
    seen.add(name);
    const match = name.match(/^(\d+)_/);
    if (!match) {
      throw new Error(`migration filename missing numeric prefix: ${name}`);
    }
    const numeric = Number(match[1]);
    if (numeric <= prevNumeric) {
      throw new Error(`migration files not strictly ordered: ${name}`);
    }
    prevNumeric = numeric;
  }

  const expectedRaw = process.env.OLLI_EXPECTED_MIGRATION_COUNT?.trim();
  if (expectedRaw) {
    const expected = Number(expectedRaw);
    if (!Number.isFinite(expected) || expected < 1) {
      throw new Error(`invalid OLLI_EXPECTED_MIGRATION_COUNT: ${expectedRaw}`);
    }
    if (files.length !== expected) {
      throw new Error(
        `migration count ${files.length} != OLLI_EXPECTED_MIGRATION_COUNT ${expected}`,
      );
    }
  }

  return { count: files.length, latest: files[files.length - 1] };
}

export function latestMigrationVersion() {
  const files = listMigrationFiles();
  if (files.length === 0) return null;
  const match = files[files.length - 1].match(/^(\d+)/);
  return match ? match[1] : null;
}

export const repoRoot = root;
