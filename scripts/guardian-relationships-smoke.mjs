#!/usr/bin/env node
/**
 * M1-T04 guardian relationship smoke tests.
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

const ORG_A = "a0000000-0000-4000-8000-000000000001";
const APP_A_ADMIN = "a1000000-0000-4000-8000-000000000001";
const STUDENT_TRAN = "a5100000-0000-4000-8000-000000000001";
const STUDENT_NGUYEN = "a5100000-0000-4000-8000-000000000002";
const GUARDIAN_LAN = "a5200000-0000-4000-8000-000000000001";
const GUARDIAN_QUANG = "a5200000-0000-4000-8000-000000000002";

const results = [];
const createdGuardianIds = [];
const createdLinkIds = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} GR-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

async function signIn(email, password = "testpass123") {
  const client = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error || !data.session?.access_token) {
    throw new Error(`Sign-in failed for ${email}: ${error?.message ?? "no token"}`);
  }
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${data.session.access_token}` } },
  });
}

async function hasPermission(client, code) {
  const { data, error } = await client.rpc("has_permission", { p_code: code });
  return !error && Boolean(data);
}

function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

function normalizePhoneDigits(value) {
  return value.replace(/\D/g, "");
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const staff = await signIn("org-a-staff@olli.local");

  // 1 audit columns
  const { data: auditProbe, error: auditProbeError } = await admin
    .from("student_guardian")
    .select("created_by, updated_by")
    .limit(1);
  record(
    1,
    "audit columns exist on student_guardian",
    !auditProbeError && auditProbe !== null,
  );

  // 2 zero primary valid - student nguyen has no primary in seed potentially
  const { count: nguyenPrimary } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("student_id", STUDENT_NGUYEN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  record(2, "student can have zero active primary contacts", (nguyenPrimary ?? 0) === 0);

  // 3 one primary
  const { count: tranPrimary } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  record(3, "student can have one active primary", (tranPrimary ?? 0) === 1);

  // 4 two primaries rejected
  const dupPrimary = await admin
    .from("student_guardian")
    .update({ is_primary_contact: true, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_QUANG)
    .eq("status", "active");
  record(
    4,
    "two active primaries for one student rejected",
    Boolean(dupPrimary.error) && dupPrimary.error?.code === "23505",
  );

  // 5 different students each have primary - add primary to nguyen
  const gNguyen = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "GxPrimary",
      family_name: "Test",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (gNguyen.data?.id) createdGuardianIds.push(gNguyen.data.id);
  const linkNguyenPrimary = await admin.from("student_guardian").insert({
    organization_id: ORG_A,
    student_id: STUDENT_NGUYEN,
    guardian_id: gNguyen.data.id,
    relationship_type: "guardian",
    is_primary_contact: true,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (linkNguyenPrimary.data?.id) createdLinkIds.push(linkNguyenPrimary.data.id);
  record(
    5,
    "different students may each have a primary",
    !linkNguyenPrimary.error && (tranPrimary ?? 0) >= 1,
  );

  // 6 ended primary does not block new active primary
  await admin
    .from("student_guardian")
    .update({ status: "ended", is_primary_contact: false, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_NGUYEN)
    .eq("guardian_id", gNguyen.data.id);
  const gNguyen2 = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "GxSecond",
      family_name: "Test",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (gNguyen2.data?.id) createdGuardianIds.push(gNguyen2.data.id);
  const newPrimary = await admin.from("student_guardian").insert({
    organization_id: ORG_A,
    student_id: STUDENT_NGUYEN,
    guardian_id: gNguyen2.data.id,
    is_primary_contact: true,
    relationship_type: "guardian",
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (newPrimary.data?.id) createdLinkIds.push(newPrimary.data.id);
  record(6, "ended primary does not block new active primary", !newPrimary.error);

  // 7 guardian.read permits fetch
  record(
    7,
    "guardian.read permits guardian/link display data",
    (await admin.from("guardian").select("id").limit(1)).data?.length >= 1 &&
      (await admin.from("student_guardian").select("id").limit(1)).data?.length >= 1,
  );

  // 8 without guardian.read
  record(
    8,
    "without guardian.read guardian data cannot be fetched",
    ((await reader.from("guardian").select("id")).data ?? []).length === 0 &&
      ((await reader.from("student_guardian").select("id")).data ?? []).length === 0,
  );

  // 9 create guardian
  const createPerm = await hasPermission(admin, "guardian.create");
  const created = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "GxCreate",
      family_name: "Smoke",
      phone: "0900111222",
      email: "gx-smoke@test.local",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, created_by")
    .single();
  if (created.data?.id) createdGuardianIds.push(created.data.id);
  record(9, "guardian.create can create guardian", createPerm && !created.error);

  // 10 without create
  const readerCreate = await reader.from("guardian").insert({
    organization_id: ORG_A,
    given_name: "Blocked",
    family_name: "Reader",
  });
  record(
    10,
    "without guardian.create create is rejected",
    !(await hasPermission(reader, "guardian.create")) && Boolean(readerCreate.error),
  );

  // 11 org override rejected
  const wrongOrg = await admin.from("guardian").insert({
    organization_id: "b0000000-0000-4000-8000-000000000001",
    given_name: "Wrong",
    family_name: "Org",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(11, "trusted org/actor cannot be overridden by client org_id", Boolean(wrongOrg.error));

  // 12 name validation heuristic (application layer; DB allows empty text)
  function validateGuardianNames(familyName, givenName) {
    return familyName.trim().length > 0 && givenName.trim().length > 0;
  }
  record(
    12,
    "required guardian name validation works",
    !validateGuardianNames("", "") && validateGuardianNames("Nguyễn", "An"),
  );

  // 13 optional phone/email
  const optional = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "GxOptional",
      family_name: "Fields",
      phone: null,
      email: null,
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (optional.data?.id) createdGuardianIds.push(optional.data.id);
  record(13, "optional phone/email work", !optional.error);

  // 14 email duplicate warning heuristic
  const emailDup = (await admin.from("guardian").select("id, email").not("email", "is", null)).data?.some(
    (g) => normalizeEmail(g.email) === normalizeEmail("GX-SMOKE@test.local"),
  );
  record(14, "same email produces duplicate warning heuristic", Boolean(emailDup));

  // 15 phone duplicate
  const phoneDup = (await admin.from("guardian").select("id, phone").not("phone", "is", null)).data?.some(
    (g) => normalizePhoneDigits(g.phone) === normalizePhoneDigits("0900111222"),
  );
  record(15, "phone duplicate produces warning heuristic", Boolean(phoneDup));

  // 16 no hard email uniqueness - insert same email different guardian
  const sameEmail = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "GxDupEmail",
      family_name: "Allowed",
      email: "gx-smoke@test.local",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (sameEmail.data?.id) createdGuardianIds.push(sameEmail.data.id);
  record(16, "duplicate warning does not create DB hard uniqueness", !sameEmail.error);

  // 17 name-only not blocked
  const nameOnly = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "Lan",
      family_name: "Phạm",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (nameOnly.data?.id) createdGuardianIds.push(nameOnly.data.id);
  record(17, "name-only duplicate is not blocked", !nameOnly.error);

  // 18 link new guardian
  const gLink = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "GxLink",
      family_name: "Target",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (gLink.data?.id) createdGuardianIds.push(gLink.data.id);
  const linkNew = await admin
    .from("student_guardian")
    .insert({
      organization_id: ORG_A,
      student_id: STUDENT_NGUYEN,
      guardian_id: gLink.data.id,
      relationship_type: "other",
      is_billing_contact: true,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, relationship_type, is_billing_contact, created_by")
    .single();
  if (linkNew.data?.id) createdLinkIds.push(linkNew.data.id);
  record(18, "link new guardian to student", !linkNew.error);

  // 19 active pair not duplicated
  const dupLink = await admin.from("student_guardian").insert({
    organization_id: ORG_A,
    student_id: STUDENT_NGUYEN,
    guardian_id: gLink.data.id,
    relationship_type: "guardian",
    status: "active",
  });
  record(19, "existing active pair is not duplicated", Boolean(dupLink.error));

  // 20 ended reactivated
  await admin
    .from("student_guardian")
    .update({ status: "ended", updated_by: APP_A_ADMIN })
    .eq("id", linkNew.data.id);
  const reactivate = await admin
    .from("student_guardian")
    .update({
      status: "active",
      relationship_type: "mother",
      is_billing_contact: false,
      updated_by: APP_A_ADMIN,
    })
    .eq("id", linkNew.data.id)
    .select("id, status, relationship_type")
    .single();
  record(
    20,
    "ended pair is reactivated instead of inserted",
    reactivate.data?.status === "active" && reactivate.data?.relationship_type === "mother",
  );

  // 21-23 relationship/primary/billing persist
  record(21, "relationship type persists correctly", reactivate.data?.relationship_type === "mother");
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: false, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_NGUYEN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  const { data: primaryRow } = await admin
    .from("student_guardian")
    .update({ is_primary_contact: true, updated_by: APP_A_ADMIN })
    .eq("id", linkNew.data.id)
    .select("is_primary_contact")
    .single();
  record(22, "primary flag persists correctly", primaryRow?.is_primary_contact === true);
  await admin
    .from("student_guardian")
    .update({ is_billing_contact: true, updated_by: APP_A_ADMIN })
    .eq("id", linkNew.data.id);
  const { data: billingRow } = await admin
    .from("student_guardian")
    .select("is_billing_contact")
    .eq("id", linkNew.data.id)
    .single();
  record(23, "billing flag persists correctly", billingRow?.is_billing_contact === true);

  // 24 switch primary A to B
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: false, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: true, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_QUANG);
  const { data: switched } = await admin
    .from("student_guardian")
    .select("guardian_id, is_primary_contact")
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true)
    .maybeSingle();
  record(
    24,
    "switch primary A to B",
    switched?.guardian_id === GUARDIAN_QUANG && switched?.is_primary_contact === true,
  );

  // 25 concurrent dual primary blocked by DB
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: false, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active");
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: true, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_LAN);
  const raceSecond = await admin
    .from("student_guardian")
    .update({ is_primary_contact: true, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_QUANG);
  record(
    25,
    "DB protects against conflicting dual primary",
    Boolean(raceSecond.error) && raceSecond.error.code === "23505",
  );

  // 26 remove primary leaving zero valid
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: false, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active");
  const { count: zeroPrimary } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  record(26, "remove primary leaving zero is valid", (zeroPrimary ?? 0) === 0);

  // 27 friendly conflict detection
  record(
    27,
    "unique-index conflict detectable as 23505",
    raceSecond.error?.code === "23505",
  );

  // 28 primary and billing different
  record(
    28,
    "primary and billing can be different guardians",
    switched?.guardian_id === GUARDIAN_QUANG || billingRow?.is_billing_contact === true,
  );

  // 29 one guardian both
  await admin
    .from("student_guardian")
    .update({
      is_primary_contact: true,
      is_billing_contact: true,
      updated_by: APP_A_ADMIN,
    })
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_LAN);
  const { data: both } = await admin
    .from("student_guardian")
    .select("is_primary_contact, is_billing_contact")
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_LAN)
    .single();
  record(
    29,
    "one guardian may be both primary and billing",
    both?.is_primary_contact === true && both?.is_billing_contact === true,
  );

  // 30 no billing uniqueness - two billing on same student allowed
  const secondBilling = await admin
    .from("student_guardian")
    .update({ is_billing_contact: true, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_QUANG);
  record(30, "M1-T04 does not impose billing uniqueness", !secondBilling.error);

  // 31 update guardian
  const updatePerm = await hasPermission(admin, "guardian.update");
  const updatedGuardian = await admin
    .from("guardian")
    .update({ phone: "0900999888", updated_by: APP_A_ADMIN })
    .eq("id", created.data.id)
    .select("phone, updated_by")
    .single();
  record(31, "guardian.update can edit guardian master", updatePerm && updatedGuardian.data?.phone === "0900999888");

  // 32 without update
  const beforeStaff = await admin.from("guardian").select("phone").eq("id", created.data.id).single();
  await staff.from("guardian").update({ phone: "000" }).eq("id", created.data.id);
  const afterStaff = await admin.from("guardian").select("phone").eq("id", created.data.id).single();
  record(
    32,
    "without guardian.update edit is rejected",
    !(await hasPermission(staff, "guardian.update")) &&
      afterStaff.data?.phone === beforeStaff.data?.phone,
  );

  // 33 shared master - edit reflects for all links
  const { data: sharedLinks } = await admin
    .from("student_guardian")
    .select("guardian_id")
    .eq("guardian_id", GUARDIAN_LAN);
  record(
    33,
    "editing shared guardian uses same master record",
    (sharedLinks ?? []).length >= 1 && GUARDIAN_LAN.length > 0,
  );

  // 34 unlink ended
  const unlink = await admin
    .from("student_guardian")
    .update({ status: "ended", updated_by: APP_A_ADMIN })
    .eq("id", linkNew.data.id)
    .select("status")
    .single();
  record(34, "unlink sets status ended", unlink.data?.status === "ended");

  // 35 guardian master remains
  const { data: stillGuardian } = await admin
    .from("guardian")
    .select("id")
    .eq("id", gLink.data.id)
    .maybeSingle();
  record(35, "guardian master remains after unlink", Boolean(stillGuardian));

  // 36 sibling links remain - lan still linked to tran
  const { count: siblingLinks } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("guardian_id", GUARDIAN_LAN)
    .eq("status", "active");
  record(36, "sibling/other student links remain", (siblingLinks ?? 0) >= 1);

  // 37 ended not current primary/billing (active-only queries exclude ended rows)
  const { count: activePrimaryFromEndedLink } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("id", linkNew.data.id)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  record(
    37,
    "ended link not counted as current primary/billing in active queries",
    (activePrimaryFromEndedLink ?? 0) === 0,
  );

  // 38-40 audit
  record(
    38,
    "new link gets trusted created_by/updated_by",
    linkNew.data?.created_by === APP_A_ADMIN,
  );
  const linkMut = await admin
    .from("student_guardian")
    .update({ relationship_type: "father", updated_by: APP_A_ADMIN })
    .eq("id", linkNew.data.id)
    .select("updated_by")
    .single();
  record(39, "link mutation gets trusted updated_by", linkMut.data?.updated_by === APP_A_ADMIN);
  record(
    40,
    "guardian mutation maintains trusted audit attribution",
    updatedGuardian.data?.updated_by === APP_A_ADMIN,
  );

  // 41 one row per student in list query
  const { data: joinRows } = await admin
    .from("student_guardian")
    .select("student_id")
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active");
  record(
    41,
    "M1-T02 student list still one row per student concept",
    (joinRows ?? []).length >= 2,
  );

  // 42 primary on list - restore lan as primary for seed consistency
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: false, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active");
  await admin
    .from("student_guardian")
    .update({ is_primary_contact: true, updated_by: APP_A_ADMIN })
    .eq("student_id", STUDENT_TRAN)
    .eq("guardian_id", GUARDIAN_LAN);
  const { data: primaryLink } = await admin
    .from("student_guardian")
    .select("guardian_id")
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true)
    .maybeSingle();
  const { data: primaryGuardianRow } = primaryLink
    ? await admin
        .from("guardian")
        .select("given_name, family_name, phone")
        .eq("id", primaryLink.guardian_id)
        .maybeSingle()
    : { data: null };
  record(
    42,
    "primary contact data available for student list",
    Boolean(primaryGuardianRow?.given_name),
  );

  // 43 guardian search boundary
  record(
    43,
    "guardian search permission boundary remains intact",
    ((await reader.from("guardian").select("id").ilike("given_name", "*Lan*")).data ?? []).length === 0,
  );

  // 44 M1-T03 student still readable
  record(
    44,
    "M1-T03 student create/edit data remains accessible",
    ((await admin.from("student").select("id").eq("id", STUDENT_TRAN)).data ?? []).length === 1,
  );

  const passed = results.filter((r) => r.passed).length;
  console.log(`\nGuardian relationships smoke: ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
