/**
 * M8-T10 — recovery/restore target guards (local/disposable by default).
 */

import { assertProductionSupabaseUrl, parseProjectRefFromSupabaseUrl } from "./supabase-production.mjs";

export const LOCAL_DB_CONTAINER = "supabase_db_olli-local";
export const RECOVERY_DATABASE_NAME = "olli_m8_t10_recovery";

const LOCAL_HOST_PATTERNS = [
  /^https?:\/\/127\.0\.0\.1/i,
  /^https?:\/\/localhost/i,
  /^http:\/\/127\.0\.0\.1:54421/i,
  /^http:\/\/kong:8000/i,
];

export function isLocalSupabaseUrl(url) {
  if (!url?.trim()) return false;
  for (const pattern of LOCAL_HOST_PATTERNS) {
    if (pattern.test(url.trim())) return true;
  }
  return false;
}

export function isCloudSupabaseTarget() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.API_URL;
  if (!url?.trim()) return false;
  try {
    assertProductionSupabaseUrl(url);
    return true;
  } catch {
    return false;
  }
}

/** Default recovery tooling runs only against local Supabase. */
export function assertLocalRecoveryTarget() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.API_URL;
  if (!url?.trim()) {
    throw new Error(
      "Recovery drill requires local Supabase. Start stack and set NEXT_PUBLIC_SUPABASE_URL from `supabase status -o env`.",
    );
  }
  if (isCloudSupabaseTarget()) {
    throw new Error(
      "Refusing recovery drill against Supabase Cloud URL. Use local Supabase or staging with explicit human-controlled restore runbook.",
    );
  }
  if (!isLocalSupabaseUrl(url)) {
    throw new Error(
      `Recovery drill target is not recognized as local Supabase: ${url}. Set API_URL to local stack before running repository DR tooling.`,
    );
  }
}

/**
 * Destructive restore against Cloud requires explicit confirmation + project pin.
 * Repository tests never set this.
 */
export function assertProductionRestoreAllowed() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.API_URL;
  if (!isCloudSupabaseTarget()) return;
  const ref = parseProjectRefFromSupabaseUrl(url) ?? assertProductionSupabaseUrl(url);
  if (process.env.OLLI_CONFIRM_PRODUCTION_RESTORE !== "yes") {
    throw new Error(
      `Refusing restore against Supabase Cloud project ${ref}. Set OLLI_CONFIRM_PRODUCTION_RESTORE=yes only during a human-controlled incident.`,
    );
  }
  const expectedRef = process.env.OLLI_SUPABASE_PROJECT_REF?.trim();
  if (expectedRef && expectedRef !== ref) {
    throw new Error(
      `OLLI_SUPABASE_PROJECT_REF (${expectedRef}) does not match URL ref (${ref}).`,
    );
  }
}

export function resolveRecoveryDatabaseName() {
  const override = process.env.OLLI_RECOVERY_DATABASE?.trim();
  if (override) {
    if (!/^[a-z][a-z0-9_]{0,62}$/.test(override)) {
      throw new Error(`Invalid OLLI_RECOVERY_DATABASE: ${override}`);
    }
    if (override === "postgres") {
      throw new Error("OLLI_RECOVERY_DATABASE must not be the primary postgres database.");
    }
    return override;
  }
  return RECOVERY_DATABASE_NAME;
}
