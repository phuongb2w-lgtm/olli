import { inferDeploymentTier } from "@/lib/env/deployment-tier";
import { validateHostedRuntimeEnv } from "@/lib/env/hosted-env-contract";

/** Called at server startup on managed production/preview hosts only. */
export function assertProductionAppEnv(): void {
  const tier = inferDeploymentTier();
  if (tier === "production" || tier === "preview") {
    validateHostedRuntimeEnv(process.env, tier);
  }
}
