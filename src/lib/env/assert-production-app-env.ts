import { resolvePublicCanonicalAppOrigin } from "@/lib/deployment/canonical-origin";
import {
  assertCloudSupabasePublicUrl,
  isLocalSupabaseUrl,
} from "@/lib/env/supabase-public-url";
import { shouldEnforceHostedProductionEnv } from "@/lib/env/deployment-tier";

function requireNonEmpty(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is not configured`);
  }
  return value;
}

/** Called at server startup on managed production hosts only. */
export function assertProductionAppEnv(): void {
  if (!shouldEnforceHostedProductionEnv()) {
    return;
  }

  assertCloudSupabasePublicUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const publishable = requireNonEmpty("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  requireNonEmpty("SUPABASE_SECRET_KEY");

  if (publishable.toLowerCase().includes("service_role")) {
    throw new Error("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY must not be a service_role JWT");
  }

  const canonical = resolvePublicCanonicalAppOrigin();
  if (isLocalSupabaseUrl(canonical)) {
    throw new Error("NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN must not be localhost");
  }

  const expectedRef = process.env.OLLI_SUPABASE_PROJECT_REF?.trim();
  if (expectedRef) {
    const urlRef = assertCloudSupabasePublicUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
    if (urlRef !== expectedRef) {
      throw new Error(
        `OLLI_SUPABASE_PROJECT_REF (${expectedRef}) does not match NEXT_PUBLIC_SUPABASE_URL ref (${urlRef})`,
      );
    }
  }
}
