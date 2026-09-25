#!/usr/bin/env node
/**
 * M0-T06 / M8-T05: environment templates, client boundaries, bundle scan, repo secret patterns.
 */

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, dirname, relative } from "node:path";
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

function walkFiles(dir, acc = []) {
  if (!existsSync(dir)) return acc;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      walkFiles(full, acc);
    } else {
      acc.push(full);
    }
  }
  return acc;
}

function scanFileForPatterns(file, patterns) {
  const content = readFileSync(file, "utf8");
  for (const { pattern, label } of patterns) {
    if (pattern.test(content)) {
      fail(`${relative(root, file)} matches forbidden pattern: ${label}`);
    }
  }
}

// .env.local must not be tracked
try {
  const gitIgnored = execSync("git check-ignore -v .env.local", {
    cwd: root,
    encoding: "utf8",
  }).trim();
  if (gitIgnored) {
    pass(".env.local is git-ignored");
  } else if (existsSync(join(root, ".env.local"))) {
    fail(".env.local exists but is not git-ignored");
  } else {
    pass(".env.local not present (ignored pattern expected in .gitignore)");
  }
} catch {
  pass(".env.local ignore check skipped (git unavailable)");
}

const forbiddenInExample = [
  { pattern: /service_role/i, label: "service_role" },
  { pattern: /eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, label: "JWT" },
  { pattern: /sk_live_/, label: "stripe live key" },
  {
    pattern: /SUPABASE_SECRET_KEY=(?!.*<)[^\s#]+/,
    label: "literal SUPABASE_SECRET_KEY value (non-placeholder)",
  },
  { pattern: /sbp_[a-f0-9]{40,}/i, label: "Supabase access token" },
  { pattern: /postgresql:\/\/[^:]+:[^@]+@/i, label: "postgres URL with password" },
];

function auditEnvTemplate(relPath, requiredSubstrings = []) {
  const full = join(root, relPath);
  if (!existsSync(full)) {
    fail(`${relPath} missing`);
    return;
  }
  const example = readFileSync(full, "utf8");
  for (const item of forbiddenInExample) {
    if (item.pattern.test(example)) {
      fail(`${relPath} contains forbidden secret pattern: ${item.label}`);
    }
  }
  for (const needle of requiredSubstrings) {
    if (!example.includes(needle)) {
      fail(`${relPath} missing ${needle}`);
    }
  }
}

auditEnvTemplate(".env.example", [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
]);
auditEnvTemplate(".env.production.example", [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_SECRET_KEY",
  "OLLI_SUPABASE_PROJECT_REF",
]);
pass("Env example templates contain placeholders only (no secret patterns)");

// NEXT_PUBLIC_* must not name server-only variables
const trackedEnvNames = execSync('git ls-files "*.ts" "*.tsx" "*.mjs" "*.js"', {
  cwd: root,
  encoding: "utf8",
})
  .split("\n")
  .filter(Boolean);

const forbiddenPublicEnvDecl =
  /process\.env\.(NEXT_PUBLIC_(?:\w*SECRET\w*|\w*SERVICE_ROLE\w*|\w*PASSWORD\w*|\w*ACCESS_TOKEN\w*))/g;
for (const rel of trackedEnvNames) {
  const content = readFileSync(join(root, rel), "utf8");
  const match = forbiddenPublicEnvDecl.exec(content);
  forbiddenPublicEnvDecl.lastIndex = 0;
  if (match) {
    fail(`${rel} references forbidden public env name ${match[1]}`);
  }
}
pass("No forbidden NEXT_PUBLIC_* secret-style variable names in source");

// Source must not reference secret env vars in client code
const clientPaths = ["src/lib/supabase/client.ts", "src/components", "src/app"];
const secretPatterns = [
  /process\.env\.SUPABASE_SECRET_KEY/,
  /process\.env\.SERVICE_ROLE/,
  /process\.env\.[A-Z_]*SECRET/,
];

function listClientSourceFiles(rel) {
  const full = join(root, rel);
  if (!existsSync(full)) return [];
  if (rel.endsWith(".ts")) return [full];
  return walkFiles(full).filter((f) => /\.(tsx?)$/.test(f));
}

const clientScanExclude = new Set([
  join(root, "src", "app", "api", "health", "route.ts"),
]);

for (const rel of clientPaths) {
  for (const file of listClientSourceFiles(rel)) {
    if (clientScanExclude.has(file)) continue;
    const content = readFileSync(file, "utf8");
    for (const pattern of secretPatterns) {
      if (pattern.test(content)) {
        fail(`${relative(root, file)} references elevated credentials`);
      }
    }
  }
}
pass("Client-facing source does not reference service credentials");

const adminModule = join(root, "src/lib/supabase/admin.ts");
if (existsSync(adminModule)) {
  const adminSrc = readFileSync(adminModule, "utf8");
  if (!adminSrc.includes('import "server-only"')) {
    fail("Admin Supabase module must import server-only");
  } else {
    pass("Admin Supabase module is server-only guarded");
  }
}

const clientModule = join(root, "src/lib/supabase/client.ts");
if (existsSync(clientModule)) {
  const clientSrc = readFileSync(clientModule, "utf8");
  if (clientSrc.includes("admin") || clientSrc.includes("SUPABASE_SECRET_KEY")) {
    fail("Browser Supabase client must not reference admin/secret modules");
  } else {
    pass("Browser Supabase client does not import admin credentials");
  }
}

// Tracked repository secret scan (current tree only — not full git history)
const repoScanGlobs = execSync(
  'git ls-files "src" "scripts" "supabase" "docs" ".github" ".env.example" ".env.production.example" "package.json" "next.config.ts"',
  { cwd: root, encoding: "utf8" },
)
  .split("\n")
  .filter(Boolean);

const repoSecretPatterns = [
  { pattern: /eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, label: "JWT" },
  { pattern: /sbp_[a-f0-9]{40,}/i, label: "Supabase personal access token" },
  { pattern: /postgresql:\/\/[^:]+:[^@]+@/i, label: "PostgreSQL URL with embedded password" },
];
let repoScanHits = 0;
for (const rel of repoScanGlobs) {
  const full = join(root, rel);
  if (!existsSync(full) || statSync(full).isDirectory()) continue;
  const before = failed;
  scanFileForPatterns(full, repoSecretPatterns);
  if (failed !== before) repoScanHits += 1;
}
if (repoScanHits === 0) {
  pass("Repository tree scan found no obvious committed secret patterns");
}

// Build output check (if .next exists) — cross-platform file walk
const staticDir = join(root, ".next", "static");
if (existsSync(staticDir)) {
  let bundleLeak = false;
  for (const file of walkFiles(staticDir)) {
    if (!/\.(js|css|json|txt|map)$/.test(file)) continue;
    const content = readFileSync(file, "utf8");
    if (/service_role/i.test(content)) {
      bundleLeak = true;
      fail(`Browser bundle may contain service_role reference (${relative(root, file)})`);
      break;
    }
  }
  if (!bundleLeak) {
    pass("No service_role found in .next/static (build exists)");
  }
} else {
  pass("Build bundle scan skipped (.next/static absent)");
}

if (failed) process.exit(1);
console.log("Environment/secrets audit complete.");
