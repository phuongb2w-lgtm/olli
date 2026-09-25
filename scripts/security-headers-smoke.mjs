#!/usr/bin/env node
/**
 * M8-T06: deterministic browser security header / CSP contract tests (offline-safe).
 */

import {
  assertProductionCspContract,
  buildBrowserSecurityHeaders,
  buildContentSecurityPolicy,
  inferSecurityPolicyTier,
  parseContentSecurityPolicy,
} from "./lib/browser-security-policy.mjs";

const cloudUrl = "https://abcdefghijklmnop.supabase.co";
const cloudPublishable = "eyJhbGci.test.publishable";

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

const productionEnv = {
  OLLI_DEPLOYMENT_TIER: "production",
  VERCEL_ENV: "production",
  NODE_ENV: "production",
  NEXT_PUBLIC_SUPABASE_URL: cloudUrl,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: cloudPublishable,
  NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN: "https://olli.riuda.click",
};

const developmentEnv = {
  OLLI_DEPLOYMENT_TIER: "development",
  NODE_ENV: "development",
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54421",
};

assertPass("inferSecurityPolicyTier production", () => {
  if (inferSecurityPolicyTier(productionEnv) !== "production") {
    throw new Error("expected production");
  }
});

assertPass("inferSecurityPolicyTier development", () => {
  if (inferSecurityPolicyTier(developmentEnv) !== "development") {
    throw new Error("expected development");
  }
});

assertPass("production CSP contract", () => {
  const csp = buildContentSecurityPolicy(productionEnv, "production");
  assertProductionCspContract(csp, "production");
  const parsed = parseContentSecurityPolicy(csp);
  if (!parsed["connect-src"]?.includes(cloudUrl)) {
    throw new Error("connect-src must include Supabase origin");
  }
  if (parsed["frame-ancestors"]?.[0] !== "'self'") {
    throw new Error("frame-ancestors must be self");
  }
});

assertPass("development CSP allows local Supabase and HMR", () => {
  const csp = buildContentSecurityPolicy(developmentEnv, "development");
  if (!csp.includes("127.0.0.1:54421")) {
    throw new Error("development CSP must allow local Supabase");
  }
  if (!csp.includes("'unsafe-eval'")) {
    throw new Error("development CSP must allow unsafe-eval for Next dev HMR");
  }
});

assertPass("preview CSP excludes localhost dev origins", () => {
  const csp = buildContentSecurityPolicy(productionEnv, "preview");
  if (/localhost|127\.0\.0\.1/i.test(csp)) {
    throw new Error("preview CSP must not include localhost");
  }
});

assertPass("production headers include HSTS without preload", () => {
  const headers = buildBrowserSecurityHeaders(productionEnv, "production");
  const map = Object.fromEntries(headers.map((h) => [h.key, h.value]));
  if (!map["Strict-Transport-Security"]?.startsWith("max-age=")) {
    throw new Error("production must set HSTS max-age");
  }
  if (/preload|includeSubDomains/i.test(map["Strict-Transport-Security"])) {
    throw new Error("HSTS must not include preload or includeSubDomains by default");
  }
  if (map["X-Content-Type-Options"] !== "nosniff") {
    throw new Error("nosniff required");
  }
  if (!map["Content-Security-Policy"]) {
    throw new Error("CSP required");
  }
  if (!map["Referrer-Policy"]) {
    throw new Error("Referrer-Policy required");
  }
  if (!map["Permissions-Policy"]?.includes("camera=()")) {
    throw new Error("Permissions-Policy required");
  }
});

assertPass("development headers omit HSTS", () => {
  const headers = buildBrowserSecurityHeaders(developmentEnv, "development");
  if (headers.some((h) => h.key === "Strict-Transport-Security")) {
    throw new Error("development must not emit HSTS");
  }
});

assertPass("header generation is deterministic", () => {
  const a = buildBrowserSecurityHeaders(productionEnv, "production");
  const b = buildBrowserSecurityHeaders(productionEnv, "production");
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error("production headers must be deterministic");
  }
});

assertThrows("production CSP rejects accidental dev connect-src", () => {
  const csp = buildContentSecurityPolicy(
    { ...productionEnv, NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54421" },
    "production",
  );
  assertProductionCspContract(csp, "production");
});

if (process.exitCode) {
  console.error("\nSecurity headers smoke: FAILED");
  process.exit(process.exitCode);
}

console.log("\nSecurity headers smoke: all checks passed");
