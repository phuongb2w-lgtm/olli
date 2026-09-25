export type OlliDeploymentTier = "development" | "preview" | "production" | "unknown";

export function inferDeploymentTier(): OlliDeploymentTier {
  const explicit = process.env.OLLI_DEPLOYMENT_TIER?.trim().toLowerCase();
  if (explicit === "development" || explicit === "preview" || explicit === "production") {
    return explicit;
  }
  if (process.env.VERCEL_ENV === "production") return "production";
  if (process.env.VERCEL_ENV === "preview") return "preview";
  if (process.env.NODE_ENV === "development") return "development";
  return "unknown";
}

export function shouldEnforceHostedProductionEnv(): boolean {
  return inferDeploymentTier() === "production";
}
