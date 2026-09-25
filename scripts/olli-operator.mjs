#!/usr/bin/env node
/**
 * M8-T08 — RIUDA operator CLI (provision, commercial status, subscription lifecycle).
 */

import { randomUUID } from "node:crypto";
import {
  assertProductionOperatorMutationAllowed,
  assertSubscriptionActionConfirmed,
  fetchOperatorOrganizationStatus,
  invokeSubscriptionLifecycle,
  loadEnvFromSupabaseStatus,
  operatorUsage,
  parseFlagArgs,
  printJson,
  requireOperatorAdminClient,
  resolveOrganizationTarget,
} from "./lib/operator-cli.mjs";
import { orchestrateCustomerCenterProvisioning } from "./lib/center-provisioning-orchestrate.mjs";

const DESTRUCTIVE_ACTIONS = new Set(["suspend", "cancel"]);

async function cmdProvision(flags) {
  assertProductionOperatorMutationAllowed();
  const organizationName = flags["org-name"];
  const ownerEmail = flags["owner-email"];
  const ownerDisplayName = flags["owner-name"];
  if (!organizationName || !ownerEmail || !ownerDisplayName) {
    throw new Error("provision requires --org-name --owner-email --owner-name");
  }

  const admin = requireOperatorAdminClient();
  const idempotencyKey = flags["idempotency-key"] ?? randomUUID();
  const result = await orchestrateCustomerCenterProvisioning(admin, {
    idempotencyKey,
    organizationName,
    ownerEmail,
    ownerDisplayName,
    ownerPreferredLocale: flags.locale,
  });

  if (!result.ok) {
    printJson({ ok: false, action: "provision", error: result.error, requestId: result.requestId ?? null });
    process.exit(1);
  }

  printJson({
    ok: true,
    action: "provision",
    idempotencyKey,
    requestId: result.requestId,
    organizationId: result.organizationId,
    ownerAppUserId: result.ownerAppUserId,
    authUserId: result.authUserId,
    ownerEmail: result.ownerEmail,
    resumed: result.resumed,
    note: "Subscription remains provisioning until operator activates (subscription activate command).",
  });
}

async function cmdStatus(flags) {
  const admin = requireOperatorAdminClient();
  const org = await resolveOrganizationTarget(admin, {
    organizationId: flags["organization-id"],
    organizationName: flags["organization-name"],
  });
  const status = await fetchOperatorOrganizationStatus(admin, org.id);
  printJson({ ok: true, action: "status", target: org, ...status });
}

async function cmdSubscription(action, flags) {
  assertProductionOperatorMutationAllowed();
  const admin = requireOperatorAdminClient();
  const org = await resolveOrganizationTarget(admin, {
    organizationId: flags["organization-id"],
    organizationName: flags["organization-name"],
  });

  assertSubscriptionActionConfirmed(action, org.id);

  if (action === "cancel") {
    console.error(
      "cancel is terminal in M7: cancelled subscriptions cannot reactivate. Confirm OLLI_CONFIRM_SUBSCRIPTION_ACTION=cancel.",
    );
  }
  if (DESTRUCTIVE_ACTIONS.has(action) && !process.env.OLLI_CONFIRM_ORGANIZATION_ID?.trim()) {
    console.error(
      `Warning: set OLLI_CONFIRM_ORGANIZATION_ID=${org.id} to pin this ${action} to the resolved organization.`,
    );
  }

  const outcome = await invokeSubscriptionLifecycle(admin, action, org.id);
  if (!outcome.ok) {
    printJson({
      ok: false,
      action: `subscription.${action}`,
      organizationId: org.id,
      organizationName: org.name,
      stage: outcome.stage,
      error: outcome.error,
    });
    process.exit(1);
  }

  const status = await fetchOperatorOrganizationStatus(admin, org.id);
  printJson({
    ok: true,
    action: `subscription.${action}`,
    organizationId: org.id,
    organizationName: org.name,
    rpc_result: outcome.result,
    subscription: status.subscription,
    entitlement: status.entitlement,
  });
}

async function main() {
  loadEnvFromSupabaseStatus();
  const [command, subcommand, ...rest] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h") {
    console.log(operatorUsage());
    return;
  }

  try {
    if (command === "provision") {
      const flags = parseFlagArgs(rest, {
        "org-name": "string",
        "owner-email": "string",
        "owner-name": "string",
        "idempotency-key": "string",
        locale: "string",
      });
      await cmdProvision(flags);
      return;
    }

    if (command === "status") {
      const flags = parseFlagArgs(rest, {
        "organization-id": "string",
        "organization-name": "string",
      });
      await cmdStatus(flags);
      return;
    }

    if (command === "subscription") {
      const action = subcommand;
      if (!action || !["activate", "suspend", "reactivate", "cancel"].includes(action)) {
        throw new Error("subscription requires activate|suspend|reactivate|cancel");
      }
      const flags = parseFlagArgs(rest, {
        "organization-id": "string",
        "organization-name": "string",
      });
      await cmdSubscription(action, flags);
      return;
    }

    throw new Error(`Unknown command: ${command}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    printJson({ ok: false, error: message });
    process.exit(1);
  }
}

main();
