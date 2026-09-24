/**
 * Shared helpers for Supabase Cloud operator workflows (M8-T02).
 * Never runs db reset or seed against linked/production targets.
 */

import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { repoRoot } from "./migration-inventory.mjs";

const LOCAL_HOST_PATTERNS = [
  /^https?:\/\/127\.0\.0\.1/i,
  /^https?:\/\/localhost/i,
  /^http:\/\/127\.0\.0\.1:54421/i,
];

export function parseProjectRefFromSupabaseUrl(url) {
  if (!url) return null;
  try {
    const host = new URL(url.trim()).hostname;
    const match = host.match(/^([a-z0-9]+)\.supabase\.co$/i);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

export function assertProductionSupabaseUrl(url, label = "NEXT_PUBLIC_SUPABASE_URL") {
  if (!url) {
    throw new Error(`${label} is required for production operator commands.`);
  }
  for (const pattern of LOCAL_HOST_PATTERNS) {
    if (pattern.test(url)) {
      throw new Error(
        `${label} points at local Supabase (${url}). Set production/staging URL before running production operator commands.`,
      );
    }
  }
  const ref = parseProjectRefFromSupabaseUrl(url);
  if (!ref) {
    throw new Error(`${label} must be a Supabase Cloud URL (https://<ref>.supabase.co). Got: ${url}`);
  }
  return ref;
}

export function requireExpectedProjectRef(urlRef) {
  const expected = process.env.OLLI_SUPABASE_PROJECT_REF?.trim();
  if (!expected) {
    throw new Error(
      "Set OLLI_SUPABASE_PROJECT_REF to the intended Supabase project ref before schema-changing operations.",
    );
  }
  if (urlRef !== expected) {
    throw new Error(
      `Project ref mismatch: NEXT_PUBLIC_SUPABASE_URL implies "${urlRef}" but OLLI_SUPABASE_PROJECT_REF is "${expected}".`,
    );
  }
  return expected;
}

export function requireProductionDeployConfirmation() {
  if (process.env.OLLI_CONFIRM_PRODUCTION_DEPLOY !== "yes") {
    throw new Error(
      'Refusing production migration deploy: set OLLI_CONFIRM_PRODUCTION_DEPLOY=yes after verifying project identity and backup.',
    );
  }
}

export function execSupabase(args, { allowFailure = false } = {}) {
  const cmd = `npx supabase ${args}`;
  try {
    return execSync(cmd, {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
      shell: true,
    });
  } catch (error) {
    if (allowFailure) {
      return error.stdout?.toString?.() ?? error.message;
    }
    const stderr = error.stderr?.toString?.() ?? "";
    const stdout = error.stdout?.toString?.() ?? "";
    throw new Error(`${cmd} failed:\n${stdout}\n${stderr}`.trim());
  }
}

export function readLinkedProjectRefFromDisk() {
  const path = join(repoRoot, "supabase", ".temp", "project-ref");
  if (!existsSync(path)) return null;
  return readFileSync(path, "utf8").trim() || null;
}

export function assertLinkedProjectMatches(expectedRef) {
  const linked = readLinkedProjectRefFromDisk();
  if (!linked) {
    throw new Error(
      "No linked Supabase project found. Run: npx supabase login && npx supabase link --project-ref <OLLI_SUPABASE_PROJECT_REF>",
    );
  }
  if (linked !== expectedRef) {
    throw new Error(
      `CLI link ref "${linked}" does not match OLLI_SUPABASE_PROJECT_REF "${expectedRef}". Re-link or fix env.`,
    );
  }
}

export function loadProductionEnvFromProcess() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishable = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  const secret = process.env.SUPABASE_SECRET_KEY;
  return { url, publishable, secret };
}

export function assertProductionRuntimeEnv() {
  const { url, publishable, secret } = loadProductionEnvFromProcess();
  assertProductionSupabaseUrl(url);
  if (!publishable?.trim()) {
    throw new Error("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is required.");
  }
  if (!secret?.trim()) {
    throw new Error("SUPABASE_SECRET_KEY is required for operator verification scripts.");
  }
  return { url, publishable, secret };
}
