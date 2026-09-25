export type EnvMap = Record<string, string | undefined>;

export {
  inferDeploymentTierFromEnv,
  parsePublicEnvSnapshot,
  validateHostedRuntimeEnv,
} from "../../../scripts/lib/hosted-env-contract.mjs";
