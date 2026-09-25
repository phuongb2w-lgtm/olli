#!/usr/bin/env node
/**
 * Verify Next.js host runtime env before production/staging deploy (no secrets printed).
 */

import { assertHostedAppRuntimeEnv } from "./lib/app-production.mjs";

let failed = false;

function pass(msg) {
  console.log(`PASS: ${msg}`);
}

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  failed = true;
}

try {
  const { urlRef, tier, canonical } = assertHostedAppRuntimeEnv();
  pass(`deployment tier inferred as ${tier}`);
  pass(`NEXT_PUBLIC_SUPABASE_URL is Supabase Cloud (ref ${urlRef})`);
  pass("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is set");
  pass("SUPABASE_SECRET_KEY is set (value not logged)");
  pass(`canonical app origin configured (${canonical})`);
} catch (error) {
  fail(error.message);
}

if (failed) process.exit(1);
console.log("Application production environment check complete.");
