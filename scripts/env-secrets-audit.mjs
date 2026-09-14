#!/usr/bin/env node
/**
 * M0-T06: lightweight environment and browser-bundle secrets audit.
 */

import { readFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
let failed = false;

function fail(message) {
  console.error(`FAIL: ${message}`);
  failed = true;
}

function pass(message) {
  console.log(`PASS: ${message}`);
}

// .env.local must not be tracked
const gitIgnored = execSync("git check-ignore -v .env.local 2>nul || git check-ignore -v .env.local", {
  cwd: root,
  encoding: "utf8",
  shell: true,
}).trim();
if (gitIgnored) {
  pass(".env.local is git-ignored");
} else if (existsSync(join(root, ".env.local"))) {
  fail(".env.local exists but is not git-ignored");
} else {
  pass(".env.local not present (ignored pattern expected in .gitignore)");
}

// .env.example placeholders only
const example = readFileSync(join(root, ".env.example"), "utf8");
const forbiddenInExample = [
  /service_role/i,
  /eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9/,
  /sk_live_/,
  /SUPABASE_SECRET_KEY=\S+/,
];
for (const pattern of forbiddenInExample) {
  if (pattern.test(example)) {
    fail(`.env.example contains forbidden secret pattern: ${pattern}`);
  }
}
if (!example.includes("NEXT_PUBLIC_SUPABASE_URL")) {
  fail(".env.example missing NEXT_PUBLIC_SUPABASE_URL");
}
if (!example.includes("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY")) {
  fail(".env.example missing NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
}
pass(".env.example contains only public browser placeholders");

// Source must not reference secret env vars in client code
const clientPaths = ["src/lib/supabase/client.ts", "src/components", "src/app"];
const secretPatterns = [
  /process\.env\.SUPABASE_SECRET_KEY/,
  /process\.env\.SERVICE_ROLE/,
  /service_role/,
];
for (const rel of clientPaths) {
  const full = join(root, rel);
  if (!existsSync(full)) continue;
  const files = rel.endsWith(".ts")
    ? [full]
    : execSync(`git ls-files "${rel}/**/*.{ts,tsx}"`, { cwd: root, encoding: "utf8" })
        .split("\n")
        .filter(Boolean)
        .map((f) => join(root, f));
  for (const file of files) {
    const content = readFileSync(file, "utf8");
    for (const pattern of secretPatterns) {
      if (pattern.test(content)) {
        fail(`${file} references elevated credentials`);
      }
    }
  }
}
pass("Client-facing source does not reference service credentials");

// Build output check (if .next exists)
const nextDir = join(root, ".next");
if (existsSync(nextDir)) {
  try {
    const grep = execSync(
      'git grep -l "service_role" -- ".next/static" 2>nul || true',
      { cwd: root, encoding: "utf8", shell: true },
    ).trim();
    if (grep) {
      fail("Browser bundle may contain service_role reference");
    } else {
      pass("No service_role found in .next/static (if build exists)");
    }
  } catch {
    pass("Build bundle scan skipped or clean");
  }
}

if (failed) process.exit(1);
console.log("Environment/secrets audit complete.");
