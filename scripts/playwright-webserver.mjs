#!/usr/bin/env node
/**
 * Start Next.js for Playwright with local Supabase admin credentials.
 * Loads SUPABASE_SECRET_KEY from `supabase status` when not already set (same as integration smokes).
 */

import { execSync, spawn } from "node:child_process";

function loadEnvFromSupabaseStatus() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

const port = process.env.PLAYWRIGHT_PORT ?? "3001";
const statusEnv = loadEnvFromSupabaseStatus();

const childEnv = {
  ...process.env,
  NEXT_PUBLIC_SUPABASE_URL:
    process.env.NEXT_PUBLIC_SUPABASE_URL ?? statusEnv.API_URL ?? "http://127.0.0.1:54421",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? statusEnv.PUBLISHABLE_KEY,
  SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY ?? statusEnv.SECRET_KEY,
  OLLI_STAFF_PROVISION_USE_INVITE: "false",
};

if (!childEnv.SUPABASE_SECRET_KEY) {
  console.error("playwright-webserver: SUPABASE_SECRET_KEY unavailable (is Supabase running?)");
  process.exit(1);
}

const child = spawn("npm", ["run", "start", "--", "-p", port], {
  stdio: "inherit",
  env: childEnv,
  shell: true,
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
  } else {
    process.exit(code ?? 0);
  }
});
