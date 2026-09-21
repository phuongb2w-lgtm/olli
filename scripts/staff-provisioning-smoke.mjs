#!/usr/bin/env node
/**
 * M6-T03 staff provisioning integration smoke (Auth Admin + RPC boundary).
 */

import { createClient } from "@supabase/supabase-js";
import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";

const METADATA_KEY = "olli_provisioning_request_id";
const MAX_PAGES = 5;
const PER_PAGE = 200;

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
const SERVICE_ROLE_KEY =
  process.env.SUPABASE_SECRET_KEY ?? statusEnv.SECRET_KEY;

process.env.OLLI_STAFF_PROVISION_USE_INVITE = "false";

const ORG_B = "b0000000-0000-4000-8000-000000000001";

const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} SP-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

function adminClient() {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

async function signInOwner(email = "org-b-admin@olli.local") {
  const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password: "testpass123",
  });
  if (error || !data.session?.access_token) {
    throw new Error(`Owner sign-in failed: ${error?.message ?? "no token"}`);
  }
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function signInStaff() {
  const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email: "org-a-staff@olli.local",
    password: "testpass123",
  });
  if (error || !data.session?.access_token) {
    throw new Error(`Staff sign-in failed: ${error?.message ?? "no token"}`);
  }
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

async function verifyAuthCorrelation(admin, authUserId, requestId, normalizedEmail) {
  const { data, error } = await admin.auth.admin.getUserById(authUserId);
  if (error || !data.user) return false;
  const meta = data.user.user_metadata ?? {};
  return meta[METADATA_KEY] === requestId && normalizeEmail(data.user.email ?? "") === normalizedEmail;
}

async function findAuthByRequest(admin, requestId, normalizedEmail) {
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: PER_PAGE });
    if (error) throw error;
    const users = data.users ?? [];
    for (const user of users) {
      const meta = user.user_metadata ?? {};
      if (meta[METADATA_KEY] === requestId && normalizeEmail(user.email ?? "") === normalizedEmail) {
        return user;
      }
    }
    if (users.length < PER_PAGE) break;
  }
  return null;
}

async function runProvision(userClient, admin, input) {
  const { data: beginData, error: beginError } = await userClient.rpc("begin_staff_provisioning", {
    p_idempotency_key: input.idempotencyKey,
    p_email: input.email,
    p_display_name: input.displayName,
    p_canonical_role: input.canonicalRole,
    p_preferred_locale: input.preferredLocale ?? "vi",
  });
  if (beginError) {
    return { ok: false, error: beginError.message };
  }
  const row = beginData;
  if (row.status === "completed" && row.app_user_id) {
    return { ok: true, row };
  }

  const requestId = row.request_id;
  const { data: claimData, error: claimError } = await userClient.rpc(
    "claim_provisioning_auth_execution",
    { p_request_id: requestId, p_processing_token: null },
  );
  if (claimError) {
    return { ok: false, error: claimError.message, requestId };
  }
  if (claimData.outcome === "provisioning_pending") {
    return { ok: false, pending: true, requestId, row: claimData };
  }
  if (claimData.outcome === "completed" && claimData.app_user_id) {
    return { ok: true, row: claimData };
  }

  const token = claimData.processing_token;
  if (!token) {
    return { ok: false, pending: true, requestId };
  }

  let authUserId = claimData.auth_user_id;
  if (!authUserId) {
    const correlated = await findAuthByRequest(admin, requestId, row.normalized_email);
    if (correlated) {
      authUserId = correlated.id;
    } else {
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email: row.normalized_email,
        email_confirm: true,
        user_metadata: { [METADATA_KEY]: requestId },
      });
      if (createError) {
        return { ok: false, error: createError.message, requestId };
      }
      authUserId = created.user?.id;
    }
  }

  if (!authUserId || !(await verifyAuthCorrelation(admin, authUserId, requestId, row.normalized_email))) {
    return { ok: false, error: "auth_correlation_failed", requestId };
  }

  const { error: recordError } = await admin.rpc("record_provisioning_auth_created", {
    p_request_id: requestId,
    p_auth_user_id: authUserId,
    p_processing_token: token,
  });
  if (recordError) {
    return { ok: false, error: recordError.message, requestId };
  }

  const { data: finalData, error: finalError } = await admin.rpc("finalize_staff_provisioning", {
    p_request_id: requestId,
  });
  if (!finalError && finalData?.outcome === "staff_seat_limit_exceeded") {
    if (authUserId && (await verifyAuthCorrelation(admin, authUserId, requestId, row.normalized_email))) {
      await admin.auth.admin.deleteUser(authUserId);
      await admin.rpc("mark_provisioning_compensated", { p_request_id: requestId });
    }
    return { ok: false, error: "staff_seat_limit_exceeded", requestId };
  }
  if (finalError) {
    if (await verifyAuthCorrelation(admin, authUserId, requestId, row.normalized_email)) {
      const { error: delError } = await admin.auth.admin.deleteUser(authUserId);
      if (!delError) {
        await admin.rpc("mark_provisioning_compensated", { p_request_id: requestId });
      }
    }
    return { ok: false, error: finalError.message, requestId };
  }

  return {
    ok: true,
    row: finalData,
    authUserId: finalData.auth_user_id ?? authUserId,
    requestId,
  };
}

async function countAuthForRequest(admin, requestId) {
  let count = 0;
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const { data } = await admin.auth.admin.listUsers({ page, perPage: PER_PAGE });
    const users = data?.users ?? [];
    count += users.filter((u) => (u.user_metadata ?? {})[METADATA_KEY] === requestId).length;
    if (users.length < PER_PAGE) break;
  }
  return count;
}

async function fillOrgBSeats(admin) {
  const { data: rows } = await admin
    .from("app_user")
    .select("id")
    .eq("organization_id", ORG_B)
    .eq("membership_status", "member");
  const primary = "b1000000-0000-4000-8000-000000000001";
  const staff = (rows ?? []).filter((r) => r.id !== primary);
  const need = Math.max(0, 4 - staff.length);
  for (let i = 0; i < need; i += 1) {
    await admin.rpc("create_staff_membership_record", {
      p_organization_id: ORG_B,
      p_email: `m6-fill-${randomUUID()}@olli.local`,
      p_display_name: "Fill",
      p_preferred_locale: "vi",
    });
  }
}

async function main() {
  const admin = adminClient();
  const owner = await signInOwner("org-b-admin@olli.local");
  const ownerA = await signInOwner("org-a-admin@olli.local");
  const staff = await signInStaff();

  // SP-1 Owner success
  const email1 = `m6-sp1-${randomUUID()}@olli.local`;
  const key1 = `sp1-${randomUUID()}`;
  const r1 = await runProvision(owner, admin, {
    email: email1,
    displayName: "SP1 User",
    canonicalRole: "consultant",
    idempotencyKey: key1,
  });
  record(1, "Owner provisions staff successfully", r1.ok && r1.row?.app_user_id);

  // SP-2 non-owner denied
  const r2 = await staff.rpc("begin_staff_provisioning", {
    p_idempotency_key: `sp2-${randomUUID()}`,
    p_email: `m6-sp2-${randomUUID()}@olli.local`,
    p_display_name: "X",
    p_canonical_role: "teacher",
  });
  record(2, "non-Owner begin denied", Boolean(r2.error));

  // SP-3 center_manager rejected
  const r3 = await ownerA.rpc("begin_staff_provisioning", {
    p_idempotency_key: `sp3-${randomUUID()}`,
    p_email: `m6-sp3-${randomUUID()}@olli.local`,
    p_display_name: "X",
    p_canonical_role: "center_manager",
  });
  record(3, "center_manager rejected", Boolean(r3.error));

  // SP-4 same key converge
  const email4 = `m6-sp4-${randomUUID()}@olli.local`;
  const key4 = `sp4-${randomUUID()}`;
  const [a4, b4] = await Promise.all([
    runProvision(owner, admin, {
      email: email4,
      displayName: "SP4",
      canonicalRole: "teacher",
      idempotencyKey: key4,
    }),
    runProvision(owner, admin, {
      email: email4,
      displayName: "SP4",
      canonicalRole: "teacher",
      idempotencyKey: key4,
    }),
  ]);
  let finalA = a4;
  let finalB = b4;
  if (!finalA.ok && finalA.pending) {
    finalA = await runProvision(owner, admin, {
      email: email4,
      displayName: "SP4",
      canonicalRole: "teacher",
      idempotencyKey: key4,
    });
  }
  if (!finalB.ok && finalB.pending) {
    finalB = await runProvision(owner, admin, {
      email: email4,
      displayName: "SP4",
      canonicalRole: "teacher",
      idempotencyKey: key4,
    });
  }
  const app4 = finalA.row?.app_user_id ?? finalB.row?.app_user_id;
  const requestId4 = finalA.row?.request_id ?? finalB.requestId;
  const authCount4 = requestId4 ? await countAuthForRequest(admin, requestId4) : 0;
  const appMatch =
    finalA.row?.app_user_id &&
    finalB.row?.app_user_id &&
    finalA.row.app_user_id === finalB.row.app_user_id;
  record(
    4,
    "same-key race converges to one Auth and one app_user",
    Boolean(app4) &&
      authCount4 === 1 &&
      (finalA.ok || finalB.ok) &&
      (!finalA.row?.app_user_id || !finalB.row?.app_user_id || appMatch),
  );

  // SP-5 unrelated Auth same email -> identity_conflict
  const email5 = `m6-sp5-${randomUUID()}@olli.local`;
  await admin.auth.admin.createUser({ email: email5, email_confirm: true, user_metadata: {} });
  const r5 = await runProvision(owner, admin, {
    email: email5,
    displayName: "SP5",
    canonicalRole: "teacher",
    idempotencyKey: `sp5-${randomUUID()}`,
  });
  const { data: auth5 } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  const stillThere = (auth5?.users ?? []).some((u) => normalizeEmail(u.email ?? "") === email5);
  record(5, "unrelated existing Auth yields conflict and leaves Auth untouched", !r5.ok && stillThere);

  // SP-6 crash window recovery
  const email6 = `m6-sp6-${randomUUID()}@olli.local`;
  const key6 = `sp6-${randomUUID()}`;
  const begin6 = await owner.rpc("begin_staff_provisioning", {
    p_idempotency_key: key6,
    p_email: email6,
    p_display_name: "SP6",
    p_canonical_role: "teacher",
  });
  const req6 = begin6.data.request_id;
  await owner.rpc("claim_provisioning_auth_execution", {
    p_request_id: req6,
    p_processing_token: null,
  });
  const created6 = await admin.auth.admin.createUser({
    email: normalizeEmail(email6),
    email_confirm: true,
    user_metadata: { [METADATA_KEY]: req6 },
  });
  if (created6.error || !created6.data?.user?.id) {
    record(6, "crash-window retry reconciles Auth without second identity", false, created6.error?.message);
  } else {
  const auth6 = created6.data.user.id;
  await admin
    .from("staff_provisioning_request")
    .update({ processing_started_at: new Date(Date.now() - 60_000).toISOString() })
    .eq("id", req6);
  const retry6 = await runProvision(owner, admin, {
    email: email6,
    displayName: "SP6",
    canonicalRole: "teacher",
    idempotencyKey: key6,
  });
  const authCount6 = await countAuthForRequest(admin, req6);
  record(
    6,
    "crash-window retry reconciles Auth without second identity",
    retry6.ok && authCount6 === 1 && (retry6.authUserId === auth6 || retry6.row?.auth_user_id === auth6),
    retry6.ok ? "" : String(retry6.error ?? "unknown"),
  );
  }

  // SP-7 final seat race org B (after other org B provisions; fill to one remaining seat)
  await fillOrgBSeats(admin);
  const email7a = `m6-sp7a-${randomUUID()}@olli.local`;
  const email7b = `m6-sp7b-${randomUUID()}@olli.local`;
  const [w7a, w7b] = await Promise.all([
    runProvision(owner, admin, {
      email: email7a,
      displayName: "SP7A",
      canonicalRole: "teacher",
      idempotencyKey: `sp7a-${randomUUID()}`,
    }),
    runProvision(owner, admin, {
      email: email7b,
      displayName: "SP7B",
      canonicalRole: "teacher",
      idempotencyKey: `sp7b-${randomUUID()}`,
    }),
  ]);
  const successes7 = [w7a, w7b].filter((r) => r.ok).length;
  const seatErrors7 = [w7a, w7b].filter(
    (r) => !r.ok && String(r.error).includes("staff_seat_limit_exceeded"),
  ).length;
  record(7, "final-seat different-key race", successes7 === 1 && seatErrors7 === 1);

  // SP-8 authenticated cannot finalize
  const r8 = await ownerA.rpc("finalize_staff_provisioning", { p_request_id: randomUUID() });
  record(8, "authenticated cannot finalize", Boolean(r8.error));

  const failed = results.filter((r) => !r.passed);
  if (failed.length) {
    console.error("Staff provisioning smoke failures:", failed);
    process.exit(1);
  }
  console.log(`Staff provisioning smoke complete (${results.length}/${results.length} passed).`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
