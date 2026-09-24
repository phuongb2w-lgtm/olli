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

export function latestMigrationVersion() {
  const files = listMigrationFiles();
  if (files.length === 0) return null;
  const match = files[files.length - 1].match(/^(\d+)/);
  return match ? match[1] : null;
}

export const repoRoot = root;
