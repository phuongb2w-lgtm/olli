import { NextResponse } from "next/server";
import { resolvePublicCanonicalAppOrigin } from "@/lib/deployment/canonical-origin";
import { inferDeploymentTier } from "@/lib/env/deployment-tier";
import {
  assertCloudSupabasePublicUrl,
  isLocalSupabaseUrl,
} from "@/lib/env/supabase-public-url";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type HealthChecks = {
  process: "ok";
  publicEnv: "ok" | "missing" | "invalid";
  supabase: "ok" | "skipped" | "unreachable";
};

function resolveGitSha(): string {
  return (
    process.env.VERCEL_GIT_COMMIT_SHA?.trim() ||
    process.env.OLLI_GIT_SHA?.trim() ||
    "unknown"
  );
}

function evaluatePublicEnv(): HealthChecks["publicEnv"] {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const publishable = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !publishable) {
    return "missing";
  }
  if (isLocalSupabaseUrl(url)) {
    return "invalid";
  }
  try {
    assertCloudSupabasePublicUrl(url);
  } catch {
    return "invalid";
  }
  if (publishable.toLowerCase().includes("service_role")) {
    return "invalid";
  }
  return "ok";
}

async function pingSupabase(url: string): Promise<HealthChecks["supabase"]> {
  if (process.env.OLLI_HEALTH_CHECK_SUPABASE !== "1") {
    return "skipped";
  }
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    const response = await fetch(`${url.replace(/\/$/, "")}/auth/v1/health`, {
      method: "GET",
      signal: controller.signal,
      cache: "no-store",
    });
    clearTimeout(timeout);
    return response.ok ? "ok" : "unreachable";
  } catch {
    return "unreachable";
  }
}

export async function GET() {
  const checks: HealthChecks = {
    process: "ok",
    publicEnv: evaluatePublicEnv(),
    supabase: "skipped",
  };

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  if (url && checks.publicEnv === "ok") {
    checks.supabase = await pingSupabase(url);
  }

  const degraded =
    checks.publicEnv !== "ok" ||
    (process.env.OLLI_HEALTH_CHECK_SUPABASE === "1" && checks.supabase === "unreachable");

  const body = {
    status: degraded ? "degraded" : "ok",
    app: "olli",
    tier: inferDeploymentTier(),
    gitSha: resolveGitSha(),
    canonicalOrigin: resolvePublicCanonicalAppOrigin(),
    checks,
  };

  return NextResponse.json(body, {
    status: degraded ? 503 : 200,
    headers: {
      "Cache-Control": "no-store",
    },
  });
}
