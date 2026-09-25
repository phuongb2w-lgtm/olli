#!/usr/bin/env node
/**
 * M8-T04: Auth redirect safety and callback URL contract (no live SMTP).
 */

import { resolveSafeRedirectPath } from "./lib/auth-safe-redirect.mjs";
import {
  buildPasswordSetupCallbackUrl,
  OLLI_CANONICAL_PRODUCTION_ORIGIN,
  resolveAppOrigin,
} from "./lib/auth-app-origin.mjs";

function assert(name, condition) {
  if (!condition) {
    console.error(`FAIL: ${name}`);
    process.exitCode = 1;
    return;
  }
  console.log(`PASS: ${name}`);
}

assert("internal path accepted", resolveSafeRedirectPath("/onboarding") === "/onboarding");
assert("external https rejected", resolveSafeRedirectPath("https://evil.example/x") === "/");
assert("protocol-relative rejected", resolveSafeRedirectPath("//evil.example") === "/");
assert("absolute path with query kept", resolveSafeRedirectPath("/login?x=1") === "/login?x=1");
assert("null uses fallback", resolveSafeRedirectPath(null, "/update-password") === "/update-password");

process.env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN = OLLI_CANONICAL_PRODUCTION_ORIGIN;
const callback = buildPasswordSetupCallbackUrl();
assert(
  "production callback uses canonical origin",
  callback.startsWith(`${OLLI_CANONICAL_PRODUCTION_ORIGIN}/auth/callback?next=`),
);
assert(
  "production callback targets update-password",
  callback.includes(encodeURIComponent("/update-password")),
);

delete process.env.NEXT_PUBLIC_OLLI_CANONICAL_APP_ORIGIN;
process.env.PLAYWRIGHT_BASE_URL = "http://127.0.0.1:3000";
assert("dev origin from PLAYWRIGHT_BASE_URL", resolveAppOrigin() === "http://127.0.0.1:3000");

if (process.exitCode) {
  process.exit(process.exitCode);
}
console.log("Auth redirect smoke complete.");
