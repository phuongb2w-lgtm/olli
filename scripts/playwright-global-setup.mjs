#!/usr/bin/env node
/**
 * Ensures fixture org A has an active commercial subscription before E2E runs.
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";

const ORG_A = "a0000000-0000-4000-8000-000000000001";

function loadEnv() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

export default async function globalSetup() {
  const statusEnv = loadEnv();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? statusEnv.API_URL;
  const key = process.env.SUPABASE_SECRET_KEY ?? statusEnv.SECRET_KEY;
  if (!url || !key) {
    throw new Error("playwright-global-setup: missing Supabase env");
  }

  const svc = createClient(url, key, { auth: { persistSession: false } });
  const { error } = await svc
    .from("organization_subscription")
    .update({
      status: "active",
      activated_at: new Date().toISOString(),
      suspended_at: null,
      cancelled_at: null,
    })
    .eq("organization_id", ORG_A);

  if (error) {
    throw new Error(`playwright-global-setup: restore org A subscription failed: ${error.message}`);
  }

  const { error: entErr } = await svc
    .from("organization_entitlement")
    .update({ staff_limit: 100 })
    .eq("organization_id", ORG_A);

  if (entErr) {
    throw new Error(`playwright-global-setup: org A seat headroom failed: ${entErr.message}`);
  }
}
