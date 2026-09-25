/**
 * Shared hosted-tier env validation (M8-T05). Used by Next.js startup and offline contract smokes.
 */

import { OLLI_CANONICAL_PRODUCTION_ORIGIN } from "./app-production.mjs";
import {
  assertProductionSupabaseUrl,
  parseProjectRefFromSupabaseUrl,
} from "./supabase-production.mjs";

const LOCAL_ORIGIN = /localhost|127\.0\.0\.1/i;

export function inferDeploymentTierFromEnv(env) {
  const explicit = env.OLLI_DEPLOYMENT_TIER?.trim().toLowerCase();
  if (explicit === "development" || explicit === "preview" || explicit === "production") {
    return explicit;
  }
  if (env.VERCEL_ENV === "production") return "production";
  if (env.VERCEL_ENV === "preview") return "preview";
  if (env.NODE_ENV === "development") return "development";
  return "unknown";
}

function requireNonEmpty(env, name) {
  const value = env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is not configured`);
  }
  return value;
}

function assertHttpsAppOrigin(origin, label) {
  let parsed;
  try {
    parsed = new URL(origin);
  } catch {
    throw new Error(`${label} must be a valid absolute URL`);
  }
  if (parsed.protocol !== "https:") {
    throw new Error(`${label} must use HTTPS in production (${origin})`);
  }
  if (LOCAL_ORIGIN.test(parsed.hostname)) {
    throw new Error(`${label} must not be localhost`);
  }
}

function assertTierNotMasquerading(env, tier) {
  if (tier === "production" && env.VERCEL_ENV === "preview") {
    throw new Error(
      "OLLI_DEPLOYMENT_TIER=production cannot be used when VERCEL_ENV=preview (preview must not masquerade as production)",
    );
  }
}

function assertPreviewSupabaseIsolation(env, urlRef) {
  const productionRef = env.OLLI_PRODUCTION_SUPABASE_PROJECT_REF?.trim();
  if (!productionRef || productionRef !== urlRef) {
    return;
  }
  if (env.OLLI_ALLOW_PREVIEW_PRODUCTION_SUPABASE === "1") {
    return;
  }
  throw new Error(
    "Preview deployment is pointed at the production Supabase project ref. Use a staging Supabase project for preview hosts.",
  );
}

/** Fail-closed validation for Vercel production and preview Node runtimes. */
export function validateHostedRuntimeEnv(env, tier) {
  assertTierNotMasquerading(env, tier);

  const urlRef = assertProductionSupabaseUrl(env.NEXT_PUBLIC_SUPABASE_URL);
  const publishable = requireNonEmpty(env, "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  requireNonEmpty(env, "SUPABASE_SECRET_KEY");

  if (publishable.toLowerCase().includes("service_role")) {
    throw new Error("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY must not be a service_role JWT");
  }

  const canonical =
    env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN?.trim() || OLLI_CANONICAL_PRODUCTION_ORIGIN;
  if (LOCAL_ORIGIN.test(canonical)) {
    throw new Error("NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN must not be localhost");
  }

  if (tier === "production") {
    assertHttpsAppOrigin(canonical, "NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN");
    const expectedRef = requireNonEmpty(env, "OLLI_SUPABASE_PROJECT_REF");
    if (expectedRef !== urlRef) {
      throw new Error(
        `OLLI_SUPABASE_PROJECT_REF (${expectedRef}) does not match NEXT_PUBLIC_SUPABASE_URL ref (${urlRef})`,
      );
    }
  }

  if (tier === "preview") {
    assertPreviewSupabaseIsolation(env, urlRef);
    const configuredRef = env.OLLI_SUPABASE_PROJECT_REF?.trim();
    if (configuredRef && configuredRef !== urlRef) {
      throw new Error(
        `OLLI_SUPABASE_PROJECT_REF (${configuredRef}) does not match NEXT_PUBLIC_SUPABASE_URL ref (${urlRef})`,
      );
    }
  }
}

export function parsePublicEnvSnapshot(env) {
  const allowed = {
    NEXT_PUBLIC_SUPABASE_URL: env.NEXT_PUBLIC_SUPABASE_URL?.trim() ?? "",
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim() ?? "",
    NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN:
      env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN?.trim() || OLLI_CANONICAL_PRODUCTION_ORIGIN,
  };
  for (const [key, value] of Object.entries(allowed)) {
    if (key.includes("SECRET") || key.includes("SERVICE_ROLE") || key.includes("PASSWORD")) {
      throw new Error(`Public env snapshot must not include ${key}`);
    }
    if (value.toLowerCase().includes("service_role")) {
      throw new Error(`${key} must not contain a service_role credential`);
    }
  }
  const ref = parseProjectRefFromSupabaseUrl(allowed.NEXT_PUBLIC_SUPABASE_URL);
  if (env.SUPABASE_SECRET_KEY?.trim() && ref && allowed.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY) {
    if (allowed.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY === env.SUPABASE_SECRET_KEY.trim()) {
      throw new Error("Publishable key must not equal SUPABASE_SECRET_KEY");
    }
  }
  return allowed;
}
