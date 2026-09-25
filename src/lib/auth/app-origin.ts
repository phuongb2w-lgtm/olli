import { resolveSafeRedirectPath } from "@/lib/auth/safe-redirect";

export const OLLI_CANONICAL_PRODUCTION_ORIGIN = "https://olli.riuda.click";

/** Browser-facing app origin for Auth email links (not the Supabase API host). */
export function resolveAppOrigin(): string {
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

/** Supabase Auth redirect target after invite / recovery link (PKCE callback). */
export function buildPasswordSetupCallbackUrl(): string {
  const origin = resolveAppOrigin();
  const next = encodeURIComponent(resolveSafeRedirectPath("/update-password", "/update-password"));
  return `${origin}/auth/callback?next=${next}`;
}
