#!/usr/bin/env node
/**
 * Creates dev Auth users via GoTrue admin API (fixture setup only).
 * Fixed UUIDs match supabase/seed.sql and security test fixtures.
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";

const users = [
  { id: "a1111111-1111-4111-8111-111111111111", email: "org-a-admin@olli.local" },
  { id: "a2222222-2222-4222-8222-222222222222", email: "org-a-staff@olli.local" },
  { id: "b1111111-1111-4111-8111-111111111111", email: "org-b-admin@olli.local" },
  { id: "b2222222-2222-4222-8222-222222222222", email: "org-b-staff@olli.local" },
  { id: "c1111111-1111-4111-8111-111111111111", email: "unmapped@olli.local" },
  { id: "c3333333-3333-4333-8333-333333333333", email: "m5-t03-academic@olli.local" },
  { id: "c2222222-2222-4222-8222-222222222222", email: "m5-t03-teacher@olli.local" },
  { id: "e2222222-2222-4222-8222-222222222222", email: "m5-t05-teacher@olli.local" },
  { id: "d1111111-1111-4111-8111-111111111111", email: "m5-t04-consultant-a@olli.local" },
  { id: "d2222222-2222-4222-8222-222222222222", email: "m5-t04-consultant-b@olli.local" },
  { id: "a3333333-3333-4333-8333-333333333333", email: "disabled@olli.local" },
  { id: "a4444444-4444-4444-8444-444444444444", email: "org-a-reader@olli.local" },
  { id: "a5555555-5555-4555-8555-555555555555", email: "org-a-no-student@olli.local" },
  { id: "a6660001-0000-4000-8000-000000000001", email: "m6-t04-accountant@olli.local" },
  { id: "a6660002-0000-4000-8000-000000000002", email: "m6-t04-consultant@olli.local" },
  { id: "a6660003-0000-4000-8000-000000000003", email: "m6-t04-academic-ops@olli.local" },
];

const password = "testpass123";

function loadEnv() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

function isTransientAuthError(message) {
  return /database error|connection|timeout|503|502|unavailable|starting/i.test(message ?? "");
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForAuthAdmin(admin, maxAttempts = 60) {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const { error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1 });
    if (!error) return;
    if (attempt === maxAttempts) {
      throw new Error(`Auth admin API not ready: ${error.message}`);
    }
    await sleep(2000);
  }
}

async function ensureUser(admin, user) {
  for (let attempt = 1; attempt <= 8; attempt++) {
    const { data: existing, error: getError } = await admin.auth.admin.getUserById(user.id);

    if (!getError && existing?.user) {
      const { error: updateError } = await admin.auth.admin.updateUserById(user.id, {
        email: user.email,
        password,
        email_confirm: true,
      });
      if (updateError) {
        if (isTransientAuthError(updateError.message) && attempt < 8) {
          await sleep(2000 * attempt);
          continue;
        }
        throw new Error(`Failed to update auth user ${user.email}: ${updateError.message}`);
      }
      return;
    }

    const { error: createError } = await admin.auth.admin.createUser({
      id: user.id,
      email: user.email,
      password,
      email_confirm: true,
    });

    if (!createError) return;

    if (isTransientAuthError(createError.message) && attempt < 8) {
      await sleep(2000 * attempt);
      continue;
    }

    throw new Error(`Failed to create auth user ${user.email}: ${createError.message}`);
  }
}

async function main() {
  const env = loadEnv();
  const admin = createClient(env.API_URL, env.SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  await waitForAuthAdmin(admin);

  for (const user of users) {
    await ensureUser(admin, user);
  }

  console.log(`Seeded ${users.length} Auth users for local sign-in.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
