#!/usr/bin/env node
/**
 * M0-T06: detect obviously stale database.generated.ts vs live local schema.
 */

import { execSync } from "node:child_process";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const currentPath = join(root, "types", "database.generated.ts");
const current = readFileSync(currentPath, "utf8");

const tmpDir = mkdtempSync(join(tmpdir(), "olli-types-"));
const freshPath = join(tmpDir, "database.generated.ts");

try {
  execSync(`npx supabase gen types typescript --local > "${freshPath}"`, {
    cwd: root,
    encoding: "utf8",
    shell: true,
  });
} catch (error) {
  console.error("FAIL: could not regenerate types from local Supabase:", error.message);
  process.exit(1);
}

const fresh = readFileSync(freshPath, "utf8");

function normalize(content) {
  return content.replace(/\r\n/g, "\n").trim();
}

if (normalize(current) !== normalize(fresh)) {
  console.error("FAIL: types/database.generated.ts appears stale.");
  console.error("Run: npm run db:types");
  rmSync(tmpDir, { recursive: true, force: true });
  process.exit(1);
}

rmSync(tmpDir, { recursive: true, force: true });
console.log("PASS: database.generated.ts matches live local schema");
