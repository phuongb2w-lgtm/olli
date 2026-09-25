/**
 * Shared helpers for Next.js application hosting / deploy operator workflows (M8-T03).
 */

import { execSync } from "node:child_process";
import {
  assertProductionRuntimeEnv,
  assertProductionSupabaseUrl,
  parseProjectRefFromSupabaseUrl,
  requireExpectedProjectRef,
} from "./supabase-production.mjs";
import { repoRoot } from "./migration-inventory.mjs";

export const OLLI_CANONICAL_PRODUCTION_ORIGIN = "https://olli.riuda.click";

export function inferVercelDeploymentTier() {
  const explicit = process.env.OLLI_DEPLOYMENT_TIER?.trim().toLowerCase();
  if (explicit === "development" || explicit === "preview" || explicit === "production") {
    return explicit;
  }
  if (process.env.VERCEL_ENV === "production") return "production";
  if (process.env.VERCEL_ENV === "preview") return "preview";
  return "unknown";
}

export function resolveAppBaseUrl() {
  const explicit =
    process.env.OLLI_APP_BASE_URL?.trim() ||
    process.env.PLAYWRIGHT_BASE_URL?.trim() ||
    process.env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN?.trim();
  if (!explicit) {
    throw new Error(
      "Set OLLI_APP_BASE_URL (or PLAYWRIGHT_BASE_URL) to the deployed app origin for smoke checks.",
    );
  }
  return explicit.replace(/\/$/, "");
}

export function assertHostedAppRuntimeEnv() {
  const tier = inferVercelDeploymentTier();
  const { url, publishable } = assertProductionRuntimeEnv();
  const urlRef = assertProductionSupabaseUrl(url);

  if (publishable.toLowerCase().includes("service_role")) {
    throw new Error("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY must not be a service_role JWT");
  }

  try {
    requireExpectedProjectRef(urlRef);
  } catch (error) {
    if (tier === "production") {
      throw error;
    }
    console.log(`INFO: ${error.message}`);
  }

  const canonical =
    process.env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN?.trim() || OLLI_CANONICAL_PRODUCTION_ORIGIN;
  if (/localhost|127\.0\.0\.1/i.test(canonical)) {
    throw new Error("NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN must not be localhost on hosted tiers");
  }

  const productionRef = process.env.OLLI_PRODUCTION_SUPABASE_PROJECT_REF?.trim();
  if (tier === "preview" && productionRef && productionRef === parseProjectRefFromSupabaseUrl(url)) {
    throw new Error(
      "Preview deployment is pointed at the production Supabase project ref. Use a staging Supabase project for preview hosts.",
    );
  }

  if (tier === "production") {
    if (canonical !== OLLI_CANONICAL_PRODUCTION_ORIGIN) {
      console.log(
        `WARN: NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN is "${canonical}" (expected ${OLLI_CANONICAL_PRODUCTION_ORIGIN} on production).`,
      );
    }
  }

  return { url, publishable, urlRef, tier, canonical };
}

export function resolveReleaseGitSha() {
  return (
    process.env.OLLI_RELEASE_GIT_SHA?.trim() ||
    process.env.VERCEL_GIT_COMMIT_SHA?.trim() ||
    execSync("git rev-parse HEAD", { cwd: repoRoot, encoding: "utf8" }).trim()
  );
}
