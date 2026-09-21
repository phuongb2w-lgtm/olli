#!/usr/bin/env node
/**
 * M0-T05 HTTP/API security smoke tests (6 scenarios).
 * Uses publishable key + Auth JWT only for data requests.
 * Requires local Supabase with dev seed applied.
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";

function loadEnvFromSupabaseStatus() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

const statusEnv = loadEnvFromSupabaseStatus();
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? statusEnv.API_URL;
const PUBLISHABLE_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? statusEnv.PUBLISHABLE_KEY;

if (!SUPABASE_URL || !PUBLISHABLE_KEY) {
  console.error("Missing Supabase URL or publishable key.");
  process.exit(1);
}

const ORG_A = "a0000000-0000-4000-8000-000000000001";
const ORG_B = "b0000000-0000-4000-8000-000000000001";

const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} API-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

async function restGet(path, accessToken) {
  const headers = {
    apikey: PUBLISHABLE_KEY,
    Authorization: `Bearer ${accessToken ?? PUBLISHABLE_KEY}`,
  };
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers });
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: response.status, body };
}

async function restPost(path, payload, accessToken) {
  const headers = {
    apikey: PUBLISHABLE_KEY,
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
    Prefer: "return=representation",
  };
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  return { status: response.status, body };
}

async function signIn(email, password) {
  const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error || !data.session?.access_token) {
    throw new Error(`Sign-in failed for ${email}: ${error?.message ?? "no token"}`);
  }
  return data.session.access_token;
}

async function main() {
  // API-1: unauthenticated cannot read student
  {
    const { status, body } = await restGet("student?select=id&limit=1");
    const rows = Array.isArray(body) ? body.length : 0;
    record(1, "unauthenticated cannot read Student", status === 200 ? rows === 0 : status >= 400);
  }

  const orgAAdminToken = await signIn("org-a-admin@olli.local", "testpass123");
  const orgAStaffToken = await signIn("org-a-staff@olli.local", "testpass123");

  // API-2: org A admin reads org A student
  {
    const { status, body } = await restGet(
      `student?select=id,organization_id&organization_id=eq.${ORG_A}&limit=5`,
      orgAAdminToken,
    );
    const rows = Array.isArray(body) ? body : [];
    record(
      2,
      "org A admin reads org A Student",
      status === 200 && rows.length >= 1 && rows.every((r) => r.organization_id === ORG_A),
    );
  }

  // API-3: org A cannot read org B student
  {
    const { status, body } = await restGet(
      `student?select=id&organization_id=eq.${ORG_B}`,
      orgAAdminToken,
    );
    const rows = Array.isArray(body) ? body : [];
    record(3, "org A cannot read org B Student", status === 200 && rows.length === 0);
  }

  // API-4: org A cannot read org B charge
  {
    const { status, body } = await restGet(
      `charge?select=id&organization_id=eq.${ORG_B}`,
      orgAAdminToken,
    );
    const rows = Array.isArray(body) ? body : [];
    record(4, "org A cannot read org B Charge", status === 200 && rows.length === 0);
  }

  // API-5: staff without student.create cannot insert student
  {
    await restPost(
      "student",
      { organization_id: ORG_A, given_name: "Blocked", family_name: "Insert" },
      orgAStaffToken,
    );
    const verify = await restGet(
      "student?select=id&given_name=eq.Blocked&family_name=eq.Insert",
      orgAAdminToken,
    );
    const created = Array.isArray(verify.body) ? verify.body.length : 0;
    record(5, "staff without student.create cannot insert Student", created === 0);
  }

  // API-7: authenticated Data API cannot invoke SQL test fixture helpers
  {
    const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${orgAAdminToken}` } },
    });
    const { data, error } = await client.rpc("test_fixture_insert_app_user", {
      p_organization_id: ORG_A,
      p_email: "fixture-api-abuse@olli.local",
      p_display_name: "API Abuse",
    });
    const blocked =
      data == null &&
      error != null &&
      (error.code === "42501" ||
        /permission denied|test_fixture_only|not found|PGRST/i.test(error.message ?? ""));
    record(
      7,
      "authenticated Data API cannot call test_fixture_insert_app_user",
      blocked,
      error?.message ?? "",
    );
  }

  // API-6: admin with permission can mutate allowed test data (organization name round-trip)
  {
    const before = await restGet(
      `organization?select=name&id=eq.${ORG_A}`,
      orgAAdminToken,
    );
    const originalName = before.body?.[0]?.name;
    const tempName = `${originalName} API6`;
    const update = await fetch(
      `${SUPABASE_URL}/rest/v1/organization?id=eq.${ORG_A}`,
      {
        method: "PATCH",
        headers: {
          apikey: PUBLISHABLE_KEY,
          Authorization: `Bearer ${orgAAdminToken}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify({ name: tempName }),
      },
    );
    const restore = await fetch(
      `${SUPABASE_URL}/rest/v1/organization?id=eq.${ORG_A}`,
      {
        method: "PATCH",
        headers: {
          apikey: PUBLISHABLE_KEY,
          Authorization: `Bearer ${orgAAdminToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ name: originalName }),
      },
    );
    const updatedBody = update.status === 200 ? await update.json() : [];
    record(
      6,
      "authorized user can perform allowed mutation",
      update.status === 200 && updatedBody[0]?.name === tempName && restore.status === 204,
    );
  }

  const unique = new Map();
  for (const r of results) unique.set(r.id, r);
  const finalPassed = [...unique.values()].filter((r) => r.passed).length;
  const total = unique.size;

  console.log(`\nAPI security smoke: ${finalPassed}/${total} passed`);
  if (finalPassed !== total) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
