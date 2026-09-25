#!/usr/bin/env node
/**
 * M8-T07 rate-limit smoke tests (Node + service_role RPC).
 * Requires local Supabase with M8-T07 migration applied.
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

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
const SERVICE_KEY = process.env.SUPABASE_SECRET_KEY ?? statusEnv.SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("Missing Supabase URL or service role key.");
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} RL-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

function bucketKey(actionId, subject) {
  return `v1:${actionId}:${subject}`;
}

function hashSubject(value) {
  return createHash("sha256").update(value, "utf8").digest("hex").slice(0, 40);
}

async function consume(key, max, windowSeconds) {
  const { data, error } = await admin.rpc("consume_app_rate_limit", {
    p_bucket_key: key,
    p_max_attempts: max,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    throw new Error(error.message);
  }
  return data;
}

async function run() {
  const key = `smoke-${Date.now()}-below`;
  const first = await consume(key, 5, 60);
  record(1, "requests below limit succeed", first?.allowed === true);

  const boundaryKey = `smoke-${Date.now()}-boundary`;
  await consume(boundaryKey, 2, 60);
  const atMax = await consume(boundaryKey, 2, 60);
  record(2, "boundary at max succeeds", atMax?.allowed === true);

  const blockKey = `smoke-${Date.now()}-block`;
  await consume(blockKey, 1, 60);
  const blocked = await consume(blockKey, 1, 60);
  record(3, "above limit blocked", blocked?.allowed === false);
  record(
    4,
    "blocked response does not leak internal thresholds in payload",
    blocked?.allowed === false &&
      Object.keys(blocked ?? {}).every((k) => ["allowed", "retry_after_seconds"].includes(k)),
  );

  const isolationSalt = String(Date.now());
  const orgA = bucketKey("staff.provision.org", hashSubject(`org:a:actor:1:${isolationSalt}`));
  const orgB = bucketKey("staff.provision.org", hashSubject(`org:b:actor:1:${isolationSalt}`));
  await consume(orgA, 1, 60);
  const blockedA = await consume(orgA, 1, 60);
  const allowedB = await consume(orgB, 1, 60);
  record(
    5,
    "different organizations do not share counters",
    blockedA?.allowed === false && allowedB?.allowed === true,
  );

  const actor1 = bucketKey(
    "staff.lifecycle.org_actor",
    hashSubject(`org:x:actor:1:${isolationSalt}`),
  );
  const actor2 = bucketKey(
    "staff.lifecycle.org_actor",
    hashSubject(`org:x:actor:2:${isolationSalt}`),
  );
  await consume(actor1, 1, 60);
  const blockedActor1 = await consume(actor1, 1, 60);
  const allowedActor2 = await consume(actor2, 1, 60);
  record(
    6,
    "different users do not share actor counters",
    blockedActor1?.allowed === false && allowedActor2?.allowed === true,
  );

  const publishable =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? statusEnv.PUBLISHABLE_KEY;
  const anonClient = createClient(SUPABASE_URL, publishable, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error: anonError } = await anonClient.rpc("consume_app_rate_limit", {
    p_bucket_key: "smoke-anon-denied",
    p_max_attempts: 1,
    p_window_seconds: 60,
  });
  record(
    7,
    "anon client cannot invoke rate limit rpc",
    Boolean(anonError) && /permission|denied|42501/i.test(anonError.message),
  );

  const enforceSource = readFileSync(
    join(__dirname, "..", "src", "lib", "rate-limit", "enforce.ts"),
    "utf8",
  );
  record(
    8,
    "production enforce path uses admin rpc not process memory maps",
    !/\bnew Map\b/.test(enforceSource) && enforceSource.includes("createAdminClient"),
  );

  record(
    9,
    "rate limit enforce module is server-only",
    enforceSource.includes('"server-only"') && enforceSource.includes("createAdminClient"),
  );

  const failed = results.filter((r) => !r.passed);
  if (failed.length > 0) {
    console.error(`\n${failed.length} rate-limit smoke(s) failed.`);
    process.exit(1);
  }
  console.log(`\nSUCCESS: ${results.length}/${results.length} M8-T07 rate-limit smokes passed.`);
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
