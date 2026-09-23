#!/usr/bin/env node
/**
 * RIUDA/operator CLI: provision a new customer center + primary Owner.
 * Requires local or deployed Supabase with SUPABASE_SECRET_KEY (service role).
 *
 * Usage:
 *   node scripts/provision-customer-center.mjs \
 *     --idempotency-key <unique-key> \
 *     --org-name "Center Name" \
 *     --owner-email owner@example.com \
 *     --owner-name "Owner Display"
 */

import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  adminClientFromEnv,
  orchestrateCustomerCenterProvisioning,
} from "./lib/center-provisioning-orchestrate.mjs";

function loadEnvFromSupabaseStatus() {
  try {
    const raw = execSync("npx supabase status -o env", { encoding: "utf8" });
    const env = {};
    for (const line of raw.split("\n")) {
      const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
      if (match) env[match[1]] = match[2];
    }
    if (env.API_URL && !process.env.NEXT_PUBLIC_SUPABASE_URL) {
      process.env.NEXT_PUBLIC_SUPABASE_URL = env.API_URL;
    }
    if (env.SECRET_KEY && !process.env.SUPABASE_SECRET_KEY) {
      process.env.SUPABASE_SECRET_KEY = env.SECRET_KEY;
    }
  } catch {
    // optional when env vars already set
  }
}

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--idempotency-key") out.idempotencyKey = argv[++i];
    else if (arg === "--org-name") out.organizationName = argv[++i];
    else if (arg === "--owner-email") out.ownerEmail = argv[++i];
    else if (arg === "--owner-name") out.ownerDisplayName = argv[++i];
    else if (arg === "--locale") out.ownerPreferredLocale = argv[++i];
  }
  return out;
}

async function main() {
  loadEnvFromSupabaseStatus();
  const args = parseArgs(process.argv);

  if (!args.organizationName || !args.ownerEmail || !args.ownerDisplayName) {
    console.error(
      "Required: --org-name --owner-email --owner-name (optional: --idempotency-key --locale vi|en)",
    );
    process.exit(1);
  }

  const idempotencyKey = args.idempotencyKey ?? randomUUID();
  const admin = adminClientFromEnv();

  const result = await orchestrateCustomerCenterProvisioning(admin, {
    idempotencyKey,
    organizationName: args.organizationName,
    ownerEmail: args.ownerEmail,
    ownerDisplayName: args.ownerDisplayName,
    ownerPreferredLocale: args.ownerPreferredLocale,
  });

  if (!result.ok) {
    console.error(JSON.stringify({ ok: false, error: result.error, requestId: result.requestId }, null, 2));
    process.exit(1);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        idempotencyKey,
        requestId: result.requestId,
        organizationId: result.organizationId,
        ownerAppUserId: result.ownerAppUserId,
        authUserId: result.authUserId,
        ownerEmail: result.ownerEmail,
        resumed: result.resumed,
      },
      null,
      2,
    ),
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
