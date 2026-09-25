/**
 * M8-T06: centralized browser security headers and Content-Security-Policy.
 * Consumed by next.config.ts and offline contract smokes.
 */

import { inferDeploymentTierFromEnv } from "./hosted-env-contract.mjs";

const LOCAL_ORIGIN = /localhost|127\.0\.0\.1/i;

/** @typedef {"development" | "preview" | "production" | "unknown"} SecurityPolicyTier */

/**
 * @param {Record<string, string | undefined>} env
 * @returns {SecurityPolicyTier}
 */
export function inferSecurityPolicyTier(env) {
  return inferDeploymentTierFromEnv(env);
}

/**
 * @param {string} csp
 * @returns {Record<string, string[]>}
 */
export function parseContentSecurityPolicy(csp) {
  /** @type {Record<string, string[]>} */
  const directives = {};
  for (const segment of csp.split(";")) {
    const trimmed = segment.trim();
    if (!trimmed) continue;
    const tokens = trimmed.split(/\s+/);
    const name = tokens[0];
    directives[name] = tokens.slice(1);
  }
  return directives;
}

/**
 * @param {string[]} values
 */
function joinDirective(values) {
  return values.filter(Boolean).join(" ");
}

/**
 * @param {Record<string, string | undefined>} env
 * @param {SecurityPolicyTier} tier
 */
export function buildContentSecurityPolicy(env, tier) {
  const isDevRuntime = tier === "development";

  /** @type {string[]} */
  const connectSrc = ["'self'"];
  const supabaseUrl = env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  if (supabaseUrl) {
    try {
      connectSrc.push(new URL(supabaseUrl).origin);
    } catch {
      // omit invalid URL; hosted env validation fails closed elsewhere
    }
  }
  if (isDevRuntime) {
    connectSrc.push(
      "http://127.0.0.1:54421",
      "http://localhost:54421",
      "ws://127.0.0.1:3000",
      "ws://localhost:3000",
    );
  }

  /**
   * Next.js App Router emits small inline bootstrap/hydration scripts in production.
   * Nonce middleware is not wired today; 'unsafe-inline' is required for script-src.
   */
  /** @type {string[]} */
  const scriptSrc = ["'self'"];
  if (isDevRuntime) {
    scriptSrc.push("'unsafe-eval'", "'unsafe-inline'");
  } else {
    scriptSrc.push("'unsafe-inline'");
  }

  /**
   * React/Next may attach inline style attributes; global CSS is served from 'self'.
   */
  const styleSrc = ["'self'", "'unsafe-inline'"];

  const directives = [
    `default-src 'self'`,
    `base-uri 'self'`,
    `object-src 'none'`,
    `frame-ancestors 'self'`,
    `form-action 'self'`,
    `script-src ${joinDirective(scriptSrc)}`,
    `style-src ${joinDirective(styleSrc)}`,
    `img-src 'self' data: blob:`,
    `font-src 'self'`,
    `connect-src ${joinDirective(connectSrc)}`,
    `worker-src 'self' blob:`,
  ];

  if (tier === "production") {
    directives.push("upgrade-insecure-requests");
  }

  return directives.join("; ");
}

/**
 * @param {Record<string, string | undefined>} env
 * @param {SecurityPolicyTier} tier
 * @returns {{ key: string, value: string }[]}
 */
export function buildBrowserSecurityHeaders(env, tier) {
  const csp = buildContentSecurityPolicy(env, tier);

  /** @type {{ key: string, value: string }[]} */
  const headers = [
    { key: "Content-Security-Policy", value: csp },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    {
      key: "Permissions-Policy",
      value: "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    },
  ];

  if (tier === "production") {
    headers.push({
      key: "Strict-Transport-Security",
      value: "max-age=63072000",
    });
  }

  return headers;
}

/**
 * @param {string} csp
 * @param {SecurityPolicyTier} tier
 */
export function assertProductionCspContract(csp, tier) {
  if (tier !== "production") {
    throw new Error("assertProductionCspContract requires tier production");
  }
  if (LOCAL_ORIGIN.test(csp)) {
    throw new Error("production CSP must not contain localhost or 127.0.0.1");
  }
  if (/\s\*(\s|;|$)/.test(csp)) {
    throw new Error("production CSP must not use wildcard source *");
  }
  if (csp.includes("'unsafe-eval'")) {
    throw new Error("production CSP must not include unsafe-eval");
  }

  const parsed = parseContentSecurityPolicy(csp);
  for (const required of [
    "default-src",
    "script-src",
    "object-src",
    "base-uri",
    "frame-ancestors",
    "connect-src",
  ]) {
    if (!parsed[required]?.length) {
      throw new Error(`production CSP missing directive ${required}`);
    }
  }
  if (parsed["object-src"]?.[0] !== "'none'") {
    throw new Error("production object-src must be 'none'");
  }
}
