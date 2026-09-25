#!/usr/bin/env node
/**
 * M8-T05: deterministic hosted env / secret boundary contract tests (offline-safe).
 */

import {
  inferDeploymentTierFromEnv,
  parsePublicEnvSnapshot,
  validateHostedRuntimeEnv,
} from "./lib/hosted-env-contract.mjs";

const cloudUrl = "https://abcdefghijklmnop.supabase.co";
const cloudPublishable = "eyJhbGci.test.publishable";
const cloudSecret = "eyJhbGci.test.service_role_secret";
const cloudRef = "abcdefghijklmnop";

function assertThrows(name, fn) {
  try {
    fn();
    console.error(`FAIL: ${name} (expected throw)`);
    process.exitCode = 1;
  } catch {
    console.log(`PASS: ${name}`);
  }
}

function assertPass(name, fn) {
  try {
    fn();
    console.log(`PASS: ${name}`);
  } catch (error) {
    console.error(`FAIL: ${name} — ${error.message}`);
    process.exitCode = 1;
  }
}

const productionBase = {
  OLLI_DEPLOYMENT_TIER: "production",
  NEXT_PUBLIC_SUPABASE_URL: cloudUrl,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: cloudPublishable,
  SUPABASE_SECRET_KEY: cloudSecret,
  OLLI_SUPABASE_PROJECT_REF: cloudRef,
  NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN: "https://olli.riuda.click",
};

assertThrows("production rejects localhost Supabase", () =>
  validateHostedRuntimeEnv(
    { ...productionBase, NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54421" },
    "production",
  ),
);

assertThrows("production rejects HTTP canonical origin", () =>
  validateHostedRuntimeEnv(
    {
      ...productionBase,
      NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN: "http://olli.riuda.click",
    },
    "production",
  ),
);

assertThrows("production requires OLLI_SUPABASE_PROJECT_REF", () =>
  validateHostedRuntimeEnv({ ...productionBase, OLLI_SUPABASE_PROJECT_REF: "" }, "production"),
);

assertThrows("production rejects mismatched project ref", () =>
  validateHostedRuntimeEnv({ ...productionBase, OLLI_SUPABASE_PROJECT_REF: "wrongref000000" }, "production"),
);

assertThrows("preview cannot masquerade as production on Vercel preview", () =>
  validateHostedRuntimeEnv(
    { ...productionBase, VERCEL_ENV: "preview", OLLI_DEPLOYMENT_TIER: "production" },
    "production",
  ),
);

assertThrows("preview blocked from production Supabase ref by default", () =>
  validateHostedRuntimeEnv(
    {
      OLLI_DEPLOYMENT_TIER: "preview",
      VERCEL_ENV: "preview",
      NEXT_PUBLIC_SUPABASE_URL: cloudUrl,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: cloudPublishable,
      SUPABASE_SECRET_KEY: cloudSecret,
      OLLI_PRODUCTION_SUPABASE_PROJECT_REF: cloudRef,
      NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN: "https://staging.example.com",
    },
    "preview",
  ),
);

assertPass("preview may use production ref with explicit override", () =>
  validateHostedRuntimeEnv(
    {
      OLLI_DEPLOYMENT_TIER: "preview",
      VERCEL_ENV: "preview",
      NEXT_PUBLIC_SUPABASE_URL: cloudUrl,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: cloudPublishable,
      SUPABASE_SECRET_KEY: cloudSecret,
      OLLI_PRODUCTION_SUPABASE_PROJECT_REF: cloudRef,
      OLLI_ALLOW_PREVIEW_PRODUCTION_SUPABASE: "1",
      NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN: "https://staging.example.com",
    },
    "preview",
  ),
);

assertThrows("publishable key cannot be service_role JWT", () =>
  validateHostedRuntimeEnv(
    {
      ...productionBase,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "eyJ.service_role.claim",
    },
    "production",
  ),
);

assertPass("public env snapshot excludes server secrets", () => {
  const snapshot = parsePublicEnvSnapshot({
    ...productionBase,
    SUPABASE_SECRET_KEY: cloudSecret,
    POSTGRES_PASSWORD: "postgres",
  });
  if (Object.keys(snapshot).some((k) => k.includes("SECRET") || k.includes("PASSWORD"))) {
    throw new Error("snapshot leaked server key names");
  }
});

assertThrows("public env snapshot rejects publishable equal to service role", () =>
  parsePublicEnvSnapshot({
    ...productionBase,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: cloudSecret,
    SUPABASE_SECRET_KEY: cloudSecret,
  }),
);

assertPass("tier inference prefers explicit OLLI_DEPLOYMENT_TIER", () => {
  const tier = inferDeploymentTierFromEnv({
    OLLI_DEPLOYMENT_TIER: "preview",
    VERCEL_ENV: "production",
  });
  if (tier !== "preview") throw new Error(`expected preview, got ${tier}`);
});

if (process.exitCode) {
  process.exit(process.exitCode);
}
console.log("Environment contract smoke complete.");
