/**
 * Mirrors src/lib/auth/app-origin.ts for Node orchestration scripts.
 */

import { resolveSafeRedirectPath } from "./auth-safe-redirect.mjs";

export const OLLI_CANONICAL_PRODUCTION_ORIGIN = "https://olli.riuda.click";

export function resolveAppOrigin() {
  const explicit =
    process.env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN?.trim() ||
    process.env.OLLI_APP_BASE_URL?.trim() ||
    process.env.PLAYWRIGHT_BASE_URL?.trim();

  if (explicit) {
    return explicit.replace(/\/$/, "");
  }

  if (process.env.NODE_ENV === "development") {
    return "http://127.0.0.1:3000";
  }

  return OLLI_CANONICAL_PRODUCTION_ORIGIN;
}

export function buildPasswordSetupCallbackUrl() {
  const origin = resolveAppOrigin();
  const next = encodeURIComponent(resolveSafeRedirectPath("/update-password", "/update-password"));
  return `${origin}/auth/callback?next=${next}`;
}
