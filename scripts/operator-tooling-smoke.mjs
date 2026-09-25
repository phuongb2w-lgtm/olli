#!/usr/bin/env node
/**
 * M8-T08 operator tooling contract smokes (local Supabase + static guards).
 */

import { execSync, spawnSync } from "node:child_process";
import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { orchestrateCustomerCenterProvisioning } from "./lib/center-provisioning-orchestrate.mjs";
import {
  SUBSCRIPTION_RPC,
  loadEnvFromSupabaseStatus,
  redactSecretsDeep,
  requireOperatorAdminClient,
  resolveOrganizationTarget,
} from "./lib/operator-cli.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} OP-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

function loadEnvFromSupabaseStatusLocal() {
  const raw = execSync("npx supabase status -o env", { encoding: "utf8", cwd: root });
  const env = {};
  for (const line of raw.split("\n")) {
    const match = line.match(/^([A-Z0-9_]+)="?(.*?)"?$/);
    if (match) env[match[1]] = match[2];
  }
  return env;
}

function runStaticChecks() {
  const operatorEntry = join(root, "scripts", "olli-operator.mjs");
  const orchestrate = join(root, "scripts", "lib", "center-provisioning-orchestrate.mjs");
  const operatorLib = join(root, "scripts", "lib", "operator-cli.mjs");

  record(1, "operator CLI entry exists", existsSync(operatorEntry));

  const orchestrateSrc = readFileSync(orchestrate, "utf8");
  record(
    2,
    "provisioning orchestration uses begin_center_provisioning RPC",
    orchestrateSrc.includes('rpc("begin_center_provisioning"'),
  );
  record(
    3,
    "provisioning orchestration uses finalize_center_provisioning RPC",
    orchestrateSrc.includes('rpc("finalize_center_provisioning"'),
  );
  record(
    4,
    "provisioning orchestration avoids direct organization_subscription DML",
    !orchestrateSrc.includes(".from(\"organization_subscription\")"),
  );

  const operatorSrc = readFileSync(operatorLib, "utf8");
  for (const rpc of Object.values(SUBSCRIPTION_RPC)) {
    if (!operatorSrc.includes(rpc)) {
      record(5, `subscription RPC mapped: ${rpc}`, false);
      return;
    }
  }
  record(5, "subscription lifecycle uses authoritative RPC names", true);

  function walkTsFiles(dir, acc = []) {
    if (!existsSync(dir)) return acc;
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry);
      const st = statSync(full);
      if (st.isDirectory()) walkTsFiles(full, acc);
      else if (/\.(ts|tsx)$/.test(entry)) acc.push(full);
    }
    return acc;
  }
  let appImportsOperator = false;
  for (const file of walkTsFiles(join(root, "src"))) {
    const content = readFileSync(file, "utf8");
    if (/scripts\/lib\/operator-cli|scripts\/olli-operator/.test(content)) {
      appImportsOperator = true;
      break;
    }
  }
  record(6, "app source does not import operator CLI modules", !appImportsOperator);

  const cliSrc = readFileSync(join(root, "scripts", "olli-operator.mjs"), "utf8");
  const statusFn = cliSrc.match(/async function cmdStatus[\s\S]*?(?=async function cmdSubscription)/)?.[0] ?? "";
  record(
    19,
    "status command does not require production mutation confirm",
    statusFn.length > 0 && !statusFn.includes("assertProductionOperatorMutationAllowed"),
  );
  record(
    20,
    "subscription mutations require production mutation confirm",
    /cmdSubscription[\s\S]*assertProductionOperatorMutationAllowed/.test(cliSrc),
  );

  const secret = "test-service-role-secret-value-123456789";
  process.env.SUPABASE_SECRET_KEY = secret;
  const redacted = redactSecretsDeep({ message: `prefix-${secret}-suffix` });
  record(7, "operator output redacts configured service role secret", redacted.message === "[redacted-secret]");
  delete process.env.SUPABASE_SECRET_KEY;
}

function runMissingEnvFailsClosed() {
  const child = spawnSync(process.execPath, [join(root, "scripts", "olli-operator.mjs"), "status"], {
    cwd: root,
    env: {
      ...process.env,
      NEXT_PUBLIC_SUPABASE_URL: "",
      SUPABASE_SECRET_KEY: "",
      SECRET_KEY: "",
      SERVICE_ROLE_KEY: "",
      OLLI_OPERATOR_SKIP_SUPABASE_STATUS: "1",
    },
    encoding: "utf8",
  });
  const combined = `${child.stdout}\n${child.stderr}`;
  record(
    8,
    "missing credentials fail closed",
    child.status !== 0 && /Missing trusted Supabase credentials/i.test(combined),
    `exit=${child.status}`,
  );
}

async function runLocalIntegration() {
  loadEnvFromSupabaseStatus();
  const statusEnv = loadEnvFromSupabaseStatusLocal();
  process.env.NEXT_PUBLIC_SUPABASE_URL =
    process.env.NEXT_PUBLIC_SUPABASE_URL ?? statusEnv.API_URL;
  process.env.SUPABASE_SECRET_KEY =
    process.env.SUPABASE_SECRET_KEY ?? statusEnv.SECRET_KEY ?? statusEnv.SERVICE_ROLE_KEY;

  const admin = requireOperatorAdminClient();

  try {
    await resolveOrganizationTarget(admin, { organizationName: "__op_smoke_nonexistent__" });
    record(9, "missing organization rejected", false);
  } catch (error) {
    record(
      9,
      "missing organization rejected",
      /organization_not_found/.test(error.message),
      error.message,
    );
  }

  const dupName = `OP Dup ${randomUUID().slice(0, 8)}`;
  const ids = [];
  for (let i = 0; i < 2; i += 1) {
    const { data, error } = await admin
      .from("organization")
      .insert({ name: dupName, status: "active", default_locale: "vi" })
      .select("id")
      .single();
    if (error) throw error;
    ids.push(data.id);
  }
  try {
    await resolveOrganizationTarget(admin, { organizationName: dupName });
    record(10, "ambiguous organization name rejected", false);
  } catch (error) {
    record(
      10,
      "ambiguous organization name rejected",
      /ambiguous_organization_name/.test(error.message),
      error.message,
    );
  } finally {
    await admin.from("organization").delete().in("id", ids);
  }

  process.env.OLLI_CENTER_PROVISION_USE_INVITE = "false";
  const tempOrgName = `OP Sub ${randomUUID().slice(0, 8)}`;
  const ownerEmail = `op-smoke-${randomUUID().slice(0, 8)}@olli.local`;
  const provisioned = await orchestrateCustomerCenterProvisioning(admin, {
    idempotencyKey: `op-smoke-${randomUUID()}`,
    organizationName: tempOrgName,
    ownerEmail,
    ownerDisplayName: "OP Smoke Owner",
  });
  const orgId = provisioned.ok ? provisioned.organizationId : null;
  record(
    11,
    "fixture org provisioned for lifecycle smokes",
    Boolean(orgId),
    provisioned.ok ? orgId : provisioned.error,
  );
  if (!orgId) {
    throw new Error("provisioning fixture failed");
  }

  process.env.OLLI_CONFIRM_SUBSCRIPTION_ACTION = "activate";
  const { error: actErr } = await admin.rpc(SUBSCRIPTION_RPC.activate, { p_organization_id: orgId });
  record(12, "activate uses authoritative RPC", !actErr, actErr?.message);

  process.env.OLLI_CONFIRM_SUBSCRIPTION_ACTION = "suspend";
  const { error: suspErr } = await admin.rpc(SUBSCRIPTION_RPC.suspend, { p_organization_id: orgId });
  record(13, "suspend uses authoritative RPC", !suspErr, suspErr?.message);

  process.env.OLLI_CONFIRM_SUBSCRIPTION_ACTION = "reactivate";
  const { error: reactErr } = await admin.rpc(SUBSCRIPTION_RPC.reactivate, { p_organization_id: orgId });
  record(14, "reactivate uses authoritative RPC", !reactErr, reactErr?.message);

  const { data: reactActiveData, error: reactActiveErr } = await admin.rpc(SUBSCRIPTION_RPC.reactivate, {
    p_organization_id: orgId,
  });
  record(
    15,
    "reactivate on active is idempotent no-op",
    !reactActiveErr && reactActiveData?.status === "active",
    reactActiveErr?.message,
  );

  process.env.OLLI_CONFIRM_SUBSCRIPTION_ACTION = "cancel";
  const { error: cancelErr } = await admin.rpc(SUBSCRIPTION_RPC.cancel, { p_organization_id: orgId });
  record(16, "cancel uses authoritative RPC", !cancelErr, cancelErr?.message);

  process.env.OLLI_CONFIRM_SUBSCRIPTION_ACTION = "reactivate";
  const { error: reactivateCancelledErr } = await admin.rpc(SUBSCRIPTION_RPC.reactivate, {
    p_organization_id: orgId,
  });
  record(
    17,
    "cancelled terminal transition preserved (reactivate denied)",
    Boolean(reactivateCancelledErr),
    reactivateCancelledErr?.message,
  );

  const child = spawnSync(
    process.execPath,
    [
      join(root, "scripts", "olli-operator.mjs"),
      "subscription",
      "suspend",
      "--organization-id",
      orgId,
    ],
    {
      cwd: root,
      env: {
        ...process.env,
        OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION: "",
        OLLI_CONFIRM_SUBSCRIPTION_ACTION: "",
      },
      encoding: "utf8",
    },
  );
  record(
    18,
    "destructive CLI requires confirmation env",
    child.status !== 0 && /OLLI_CONFIRM_SUBSCRIPTION_ACTION/.test(`${child.stdout}${child.stderr}`),
    `exit=${child.status}`,
  );

  const cloudMut = spawnSync(
    process.execPath,
    [
      join(root, "scripts", "olli-operator.mjs"),
      "subscription",
      "activate",
      "--organization-id",
      orgId,
    ],
    {
      cwd: root,
      env: {
        ...process.env,
        NEXT_PUBLIC_SUPABASE_URL: "https://exampleproject.supabase.co",
        SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY,
        OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION: "",
        OLLI_CONFIRM_SUBSCRIPTION_ACTION: "activate",
      },
      encoding: "utf8",
    },
  );
  record(
    21,
    "cloud mutation blocked without OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION",
    cloudMut.status !== 0 && /OLLI_CONFIRM_PRODUCTION_OPERATOR_ACTION/.test(`${cloudMut.stdout}${cloudMut.stderr}`),
    `exit=${cloudMut.status}`,
  );
}

async function main() {
  runStaticChecks();
  runMissingEnvFailsClosed();
  await runLocalIntegration();

  const failed = results.filter((r) => !r.passed);
  console.log(`\nOperator tooling smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
