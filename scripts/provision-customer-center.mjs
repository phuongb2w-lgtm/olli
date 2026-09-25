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

import { randomUUID } from "node:crypto";
import { orchestrateCustomerCenterProvisioning } from "./lib/center-provisioning-orchestrate.mjs";
import {
  assertProductionOperatorMutationAllowed,
  loadEnvFromSupabaseStatus,
  requireOperatorAdminClient,
} from "./lib/operator-cli.mjs";

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
  assertProductionOperatorMutationAllowed();
  const args = parseArgs(process.argv);

  if (!args.organizationName || !args.ownerEmail || !args.ownerDisplayName) {
    console.error(
      "Required: --org-name --owner-email --owner-name (optional: --idempotency-key --locale vi|en)",
    );
    process.exit(1);
  }

  const idempotencyKey = args.idempotencyKey ?? randomUUID();
  const admin = requireOperatorAdminClient();

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
