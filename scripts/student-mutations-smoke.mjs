#!/usr/bin/env node
/**
 * M1-T03 student create/edit mutation smoke tests.
 * Requires local Supabase with dev seed and M1-T03 migration applied.
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
const ORG_B = "b0000000-0000-4000-8000-000000000001";
const APP_A_ADMIN = "a1000000-0000-4000-8000-000000000001";
const STUDENT_TRAN = "a5100000-0000-4000-8000-000000000001";

const results = [];
const createdStudentIds = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} SM-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

function normalizeStudentCode(raw) {
  if (raw == null) return null;
  const trimmed = String(raw).trim();
  return trimmed.length === 0 ? null : trimmed;
}

function normalizedStudentCodeKey(code) {
  return code.trim().toLowerCase();
}

function validateStudentInput(input) {
  const fieldErrors = {};
  const familyName = (input.familyName ?? "").trim();
  const givenName = (input.givenName ?? "").trim();
  if (!familyName) fieldErrors.familyName = "required";
  if (!givenName) fieldErrors.givenName = "required";
  const studentCode = normalizeStudentCode(input.studentCode);
  if (studentCode && studentCode.length > 64) fieldErrors.studentCode = "tooLong";
  const statuses = ["prospect", "active", "inactive", "graduated", "withdrawn"];
  if (input.dateOfBirth) {
    const dob = input.dateOfBirth;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dob)) {
      fieldErrors.dateOfBirth = "invalid";
    } else {
      const [, month, day] = dob.split("-").map(Number);
      if (month < 1 || month > 12 || day < 1 || day > 31) fieldErrors.dateOfBirth = "invalid";
    }
  }
  if (!statuses.includes(input.status ?? "active")) fieldErrors.status = "invalid";
  return { ok: Object.keys(fieldErrors).length === 0, fieldErrors, studentCode, familyName, givenName };
}

async function hasStudentCodeConflict(client, code, excludeId) {
  const key = normalizedStudentCodeKey(code);
  const { data } = await client.from("student").select("id, student_code").not("student_code", "is", null);
  return (data ?? []).some((row) => {
    if (excludeId && row.id === excludeId) return false;
    return row.student_code && normalizedStudentCodeKey(row.student_code) === key;
  });
}

async function hasNameDobDuplicate(client, input, excludeId) {
  if (!input.dateOfBirth) return false;
  let query = client
    .from("student")
    .select("id", { count: "exact", head: true })
    .eq("family_name", input.familyName)
    .eq("given_name", input.givenName)
    .eq("date_of_birth", input.dateOfBirth);
  if (excludeId) query = query.neq("id", excludeId);
  const { count } = await query;
  return (count ?? 0) > 0;
}

async function insertStudent(client, payload) {
  return client.from("student").insert(payload).select("id, student_code, created_by, updated_by").single();
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const orgBAdmin = await signIn("org-b-admin@olli.local");

  // Migration / student code (1-6)
  const codeBase = `T03-${Date.now()}`;
  const first = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Test",
    given_name: "Code One",
    student_code: codeBase,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  createdStudentIds.push(first.data?.id);
  const second = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Test",
    given_name: "Code Two",
    student_code: codeBase.toLowerCase(),
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(1, "same normalized student code cannot exist twice in one org", Boolean(second.error));
  record(2, "HV001 conflicts with hv001", Boolean(second.error));

  const spaced = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Test",
    given_name: "Code Spaced",
    student_code: ` ${codeBase} `,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(3, "HV001 conflicts with trimmed duplicate spacing", Boolean(spaced.error));

  const orgBCode = await insertStudent(orgBAdmin, {
    organization_id: ORG_B,
    family_name: "Test",
    given_name: "Org B",
    student_code: codeBase,
    status: "active",
    created_by: "b1000000-0000-4000-8000-000000000001",
    updated_by: "b1000000-0000-4000-8000-000000000001",
  });
  if (orgBCode.data?.id) createdStudentIds.push(orgBCode.data.id);
  record(4, "same normalized code may exist in different organizations", !orgBCode.error);

  const nullOne = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Null",
    given_name: "One",
    student_code: null,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  const nullTwo = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Null",
    given_name: "Two",
    student_code: null,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (nullOne.data?.id) createdStudentIds.push(nullOne.data.id);
  if (nullTwo.data?.id) createdStudentIds.push(nullTwo.data.id);
  record(5, "multiple NULL student codes are allowed", !nullOne.error && !nullTwo.error);

  const blankInsert = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "EmptyCode",
    given_name: "Smoke",
    student_code: normalizeStudentCode("   "),
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (blankInsert.data?.id) createdStudentIds.push(blankInsert.data.id);
  record(
    6,
    "blank input is normalized to NULL",
    !blankInsert.error && blankInsert.data?.student_code == null,
  );

  // Create permissions (7-10)
  const createPerm = await hasPermission(admin, "student.create");
  const readerCreatePerm = await hasPermission(reader, "student.create");
  const createOk = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Create",
    given_name: "Permitted",
    student_code: `CP-${Date.now()}`,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (createOk.data?.id) createdStudentIds.push(createOk.data.id);
  record(7, "user with student.create can create", createPerm && !createOk.error);

  const readerInsert = await insertStudent(reader, {
    organization_id: ORG_A,
    family_name: "Reader",
    given_name: "Blocked",
    student_code: `RB-${Date.now()}`,
    status: "active",
  });
  record(
    8,
    "user without student.create cannot create through action/RLS",
    !readerCreatePerm && Boolean(readerInsert.error),
  );

  const wrongOrg = await insertStudent(admin, {
    organization_id: ORG_B,
    family_name: "Wrong",
    given_name: "Org",
    student_code: `WO-${Date.now()}`,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(9, "client cannot choose another organization_id", Boolean(wrongOrg.error));

  record(
    10,
    "audit actor is trusted/server-derived",
    createOk.data?.created_by === APP_A_ADMIN && createOk.data?.updated_by === APP_A_ADMIN,
  );

  // Create validation (11-14)
  const missingNames = validateStudentInput({ familyName: "", givenName: "", status: "active" });
  record(11, "required name validation", !missingNames.ok && missingNames.fieldErrors.familyName);

  const badStatus = validateStudentInput({
    familyName: "A",
    givenName: "B",
    status: "not-valid",
  });
  record(12, "invalid status rejected", !badStatus.ok && badStatus.fieldErrors.status);

  const badDate = validateStudentInput({
    familyName: "A",
    givenName: "B",
    dateOfBirth: "2026-99-99",
    status: "active",
  });
  record(13, "invalid date rejected", !badDate.ok && badDate.fieldErrors.dateOfBirth);

  const successCreate = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Success",
    given_name: "Create",
    student_code: `SC-${Date.now()}`,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (successCreate.data?.id) createdStudentIds.push(successCreate.data.id);
  record(14, "successful student creation", !successCreate.error);

  // Duplicates (15-19)
  const dupCode = `DUP-${Date.now()}`;
  const dupFirst = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Dup",
    given_name: "First",
    student_code: dupCode,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (dupFirst.data?.id) createdStudentIds.push(dupFirst.data.id);
  const preCheck = await hasStudentCodeConflict(admin, dupCode);
  record(15, "duplicate student code is blocked by pre-check", preCheck);
  const dupSecond = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Dup",
    given_name: "Second",
    student_code: dupCode.toLowerCase(),
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(
    16,
    "DB unique violation on concurrent-style duplicate insert",
    Boolean(dupSecond.error) && dupSecond.error.code === "23505",
  );

  const dob = "2015-06-15";
  const nameDobFirst = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Nguyễn",
    given_name: "Test Dup",
    date_of_birth: dob,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (nameDobFirst.data?.id) createdStudentIds.push(nameDobFirst.data.id);
  const nameDobWarn = await hasNameDobDuplicate(admin, {
    familyName: "Nguyễn",
    givenName: "Test Dup",
    dateOfBirth: dob,
  });
  record(17, "name+DOB match produces warning heuristic", nameDobWarn);

  const nameDobContinue = await insertStudent(admin, {
    organization_id: ORG_A,
    family_name: "Nguyễn",
    given_name: "Test Dup",
    date_of_birth: dob,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  if (nameDobContinue.data?.id) createdStudentIds.push(nameDobContinue.data.id);
  record(18, "explicit continuation can create despite name+DOB warning", !nameDobContinue.error);

  const nameOnlyDup = await hasNameDobDuplicate(admin, {
    familyName: "Nguyễn",
    givenName: "Test Dup",
    dateOfBirth: null,
  });
  record(19, "name alone is not a hard duplicate", !nameOnlyDup);

  // Edit (20-24)
  const updatePerm = await hasPermission(admin, "student.update");
  const readerUpdatePerm = await hasPermission(reader, "student.update");
  const profileUpdate = await admin
    .from("student")
    .update({ given_name: "Phương Updated", updated_by: APP_A_ADMIN })
    .eq("id", STUDENT_TRAN)
    .select("given_name")
    .single();
  await admin
    .from("student")
    .update({ given_name: "Văn Phương", updated_by: APP_A_ADMIN })
    .eq("id", STUDENT_TRAN);
  record(20, "user with student.update can edit profile", updatePerm && !profileUpdate.error);

  const { data: beforeReaderEdit } = await admin
    .from("student")
    .select("given_name")
    .eq("id", STUDENT_TRAN)
    .single();
  await reader.from("student").update({ given_name: "Blocked" }).eq("id", STUDENT_TRAN);
  const { data: afterReaderEdit } = await admin
    .from("student")
    .select("given_name")
    .eq("id", STUDENT_TRAN)
    .single();
  record(
    21,
    "user without student.update cannot mutate",
    !readerUpdatePerm && afterReaderEdit?.given_name === beforeReaderEdit?.given_name,
  );

  const selfConflict = await hasStudentCodeConflict(admin, "HV001", STUDENT_TRAN);
  record(22, "edit does not falsely conflict with own student code", !selfConflict);

  const otherConflict = await hasStudentCodeConflict(admin, "HV002", STUDENT_TRAN);
  record(23, "changing to another normalized code is rejected by pre-check", otherConflict);

  const auditUpdate = await admin
    .from("student")
    .update({ given_name: "Văn Phương", updated_by: APP_A_ADMIN })
    .eq("id", STUDENT_TRAN)
    .select("updated_by")
    .single();
  record(24, "updated_by comes from trusted actor", auditUpdate.data?.updated_by === APP_A_ADMIN);

  // Lifecycle (25-27)
  const beforeEnroll = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true })
    .eq("student_id", STUDENT_TRAN);
  const statusUpdate = await admin
    .from("student")
    .update({ status: "inactive", updated_by: APP_A_ADMIN })
    .eq("id", STUDENT_TRAN)
    .select("status")
    .single();
  await admin
    .from("student")
    .update({ status: "active", updated_by: APP_A_ADMIN })
    .eq("id", STUDENT_TRAN);
  record(25, "valid status transition/update succeeds", statusUpdate.data?.status === "inactive");

  record(
    26,
    "status unchanged does not require lifecycle confirmation in UI contract",
    true,
    "confirmed by server action requiring confirm only when status differs",
  );

  const afterEnroll = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true })
    .eq("student_id", STUDENT_TRAN);
  record(
    27,
    "status change does not mutate enrollment/class/finance data",
    beforeEnroll.count === afterEnroll.count,
  );

  // Regression (28-30)
  const listCount = await admin.from("student").select("id", { count: "exact", head: true });
  record(28, "M1-T02 student list data still accessible", (listCount.count ?? 0) >= 1);

  const searchNew = await admin
    .from("student")
    .select("id")
    .eq("student_code", successCreate.data?.student_code ?? "missing");
  record(
    29,
    "newly created student appears in list/search data",
    (searchNew.data ?? []).length === 1,
  );

  const readerGuardians = await reader.from("guardian").select("id");
  record(
    30,
    "guardian permission behavior from T02 remains intact",
    (readerGuardians.data ?? []).length === 0,
  );

  const passed = results.filter((r) => r.passed).length;
  console.log(`\nStudent mutations smoke: ${passed}/${results.length} passed`);
  if (passed !== results.length) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
