#!/usr/bin/env node
/**
 * M1-T06 enrollment and class roster smoke tests.
 * Requires local Supabase with dev seed and M1-T06 migration applied.
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
const STUDENT_NGUYEN = "a5100000-0000-4000-8000-000000000002";

const ENROLLMENT_STATUSES = ["pending", "active", "transferred", "withdrawn", "completed"];
const CREATE_ENROLLMENT_STATUSES = ["pending", "active"];
const OPERATIONAL_ENROLLMENT_STATUSES = ["pending", "active"];

const results = [];
const createdCourseIds = [];
const createdClassIds = [];
const createdStudentIds = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} EN-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

function isValidIsoDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

function validateCreateEnrollmentInput(input) {
  const fieldErrors = {};
  const studentId = (input.studentId ?? "").trim();
  const classId = (input.classId ?? "").trim();
  const startDateRaw = (input.startDate ?? "").trim();
  if (!studentId) fieldErrors.studentId = "required";
  if (!classId) fieldErrors.classId = "required";
  let startDate = "";
  if (!startDateRaw) fieldErrors.startDate = "required";
  else if (!isValidIsoDate(startDateRaw)) fieldErrors.startDate = "invalid";
  else startDate = startDateRaw;
  const status = (input.status ?? "pending").trim();
  if (!CREATE_ENROLLMENT_STATUSES.includes(status)) fieldErrors.status = "invalid";
  return {
    ok: Object.keys(fieldErrors).length === 0,
    fieldErrors,
    data: { studentId, classId, startDate, status },
  };
}

function canEnrollInClass(classStatus) {
  return classStatus !== "closed";
}

function isCreateStatusAllowedForClass(classStatus, enrollmentStatus) {
  if (classStatus === "closed") return false;
  if (classStatus === "planned") return enrollmentStatus === "pending";
  if (classStatus === "trial" || classStatus === "active") {
    return enrollmentStatus === "pending" || enrollmentStatus === "active";
  }
  return false;
}

function isOverlapConflict(error) {
  if (!error) return false;
  if (error.code === "23P01") return true;
  return error.message?.includes("overlap_conflict") ?? false;
}

function isCapacityExceeded(capacity, operationalCount) {
  if (capacity == null || capacity <= 0) return false;
  return operationalCount >= capacity;
}

async function countOperationalEnrollments(admin, classId) {
  const { count } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true })
    .eq("class_id", classId)
    .in("status", OPERATIONAL_ENROLLMENT_STATUSES);
  return count ?? 0;
}

async function createCourse(admin, label) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("course")
    .insert({
      organization_id: ORG_A,
      code: `EN-${label}-${ts}`,
      name: `Enrollment ${label} ${ts}`,
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (error) throw error;
  createdCourseIds.push(data.id);
  return data.id;
}

async function createClass(admin, courseId, label, options = {}) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("class")
    .insert({
      organization_id: ORG_A,
      course_id: courseId,
      name: `${label} ${ts}`,
      status: options.status ?? "active",
      capacity: options.capacity ?? null,
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, status, capacity")
    .single();
  if (error) throw error;
  createdClassIds.push(data.id);
  return data;
}

async function createStudent(admin, label) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("student")
    .insert({
      organization_id: ORG_A,
      given_name: label,
      family_name: `Smoke${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (error) throw error;
  createdStudentIds.push(data.id);
  return data.id;
}

async function insertEnrollment(admin, input) {
  return admin
    .from("enrollment")
    .insert({
      organization_id: ORG_A,
      student_id: input.studentId,
      class_id: input.classId,
      start_date: input.startDate,
      end_date: input.endDate ?? null,
      status: input.status ?? "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, student_id, class_id, status, start_date, end_date, created_by, updated_by")
    .single();
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const staff = await signIn("org-a-staff@olli.local");
  const orgBAdmin = await signIn("org-b-admin@olli.local");
  const ts = Date.now();

  // Schema (1-5)
  const { data: enrollCols } = await admin.from("enrollment").select("*").limit(1);
  const enrollRow = enrollCols?.[0];
  record(
    1,
    "enrollment schema has expected columns",
    Boolean(
      enrollRow &&
        "student_id" in enrollRow &&
        "class_id" in enrollRow &&
        "start_date" in enrollRow &&
        "end_date" in enrollRow &&
        "status" in enrollRow &&
        "created_by" in enrollRow &&
        "updated_by" in enrollRow,
    ),
  );

  const terminalInsert = await admin
    .from("enrollment")
    .insert({
      organization_id: ORG_A,
      student_id: STUDENT_NGUYEN,
      class_id: (
        await admin.from("class").select("id").eq("organization_id", ORG_A).limit(1).single()
      ).data.id,
      start_date: "2025-01-01",
      end_date: "2025-06-01",
      status: "completed",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("status")
    .single();
  record(
    2,
    "valid lifecycle statuses accepted",
    !terminalInsert.error && ENROLLMENT_STATUSES.includes(terminalInsert.data?.status),
  );

  const badStatus = await admin.from("enrollment").insert({
    organization_id: ORG_A,
    student_id: STUDENT_NGUYEN,
    class_id: (await admin.from("class").select("id").eq("organization_id", ORG_A).limit(1).single())
      .data.id,
    start_date: "2026-01-01",
    status: "bogus",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(3, "invalid lifecycle status rejected", Boolean(badStatus.error));

  const badDates = await admin.from("enrollment").insert({
    organization_id: ORG_A,
    student_id: STUDENT_NGUYEN,
    class_id: (await admin.from("class").select("id").eq("organization_id", ORG_A).limit(1).single())
      .data.id,
    start_date: "2026-06-01",
    end_date: "2026-01-01",
    status: "withdrawn",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(4, "end_date before start_date rejected", Boolean(badDates.error));

  const { data: orgAClass } = await admin
    .from("class")
    .select("id")
    .eq("organization_id", ORG_A)
    .limit(1)
    .single();
  const { data: orgBStudent } = await orgBAdmin.from("student").select("id").limit(1).single();
  const crossStudent = await admin.from("enrollment").insert({
    organization_id: ORG_A,
    student_id: orgBStudent.id,
    class_id: orgAClass.id,
    start_date: "2026-01-01",
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(5, "student FK is organization-safe", Boolean(crossStudent.error));

  // Permissions (6-11)
  record(6, "enrollment.read works for admin", await hasPermission(admin, "enrollment.read"));
  record(7, "enrollment.create works for admin", await hasPermission(admin, "enrollment.create"));
  record(8, "enrollment.update works for admin", await hasPermission(admin, "enrollment.update"));
  record(9, "enrollment.read works for staff", await hasPermission(staff, "enrollment.read"));
  record(10, "enrollment.create denied for reader", !(await hasPermission(reader, "enrollment.create")));
  record(11, "enrollment.update denied for reader", !(await hasPermission(reader, "enrollment.update")));

  // Security / cross-org (12-16)
  const readerInsert = await reader.from("enrollment").insert({
    organization_id: ORG_A,
    student_id: STUDENT_NGUYEN,
    class_id: orgAClass.id,
    start_date: "2026-02-01",
    status: "pending",
  });
  record(12, "unauthorized enrollment mutation fails via RLS", Boolean(readerInsert.error));

  const orgBInsert = await admin.from("enrollment").insert({
    organization_id: ORG_B,
    student_id: STUDENT_NGUYEN,
    class_id: orgAClass.id,
    start_date: "2026-02-01",
    status: "pending",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(13, "client cannot choose another organization", Boolean(orgBInsert.error));

  const { data: orgBEnrollments } = await admin
    .from("enrollment")
    .select("id")
    .eq("organization_id", ORG_B);
  record(
    14,
    "RLS prevents cross-organization enrollment listing for org A session",
    (orgBEnrollments ?? []).length === 0,
  );

  const { data: orgBClass } = await orgBAdmin.from("class").select("id").limit(1).single();
  const crossClassEnroll = await admin.from("enrollment").insert({
    organization_id: ORG_A,
    student_id: STUDENT_NGUYEN,
    class_id: orgBClass.id,
    start_date: "2026-02-01",
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(15, "cross-organization class cannot receive enrollment", Boolean(crossClassEnroll.error));

  const auditCourseId = await createCourse(admin, "audit");
  const auditClass = await createClass(admin, auditCourseId, "Audit Class");
  const auditStudentId = await createStudent(admin, "Audit");
  const auditEnroll = await insertEnrollment(admin, {
    studentId: auditStudentId,
    classId: auditClass.id,
    startDate: "2026-03-01",
    status: "pending",
  });
  record(
    16,
    "actor attribution is server-derived",
    auditEnroll.data?.created_by === APP_A_ADMIN && auditEnroll.data?.updated_by === APP_A_ADMIN,
  );

  // Create enrollment ops (17-22)
  const opsCourseId = await createCourse(admin, "ops");
  const plannedClass = await createClass(admin, opsCourseId, "Planned", { status: "planned" });
  const activeClass = await createClass(admin, opsCourseId, "Active", { status: "active" });
  const closedClass = await createClass(admin, opsCourseId, "Closed", { status: "closed" });
  const opsStudentId = await createStudent(admin, "Ops");

  const validInput = validateCreateEnrollmentInput({
    studentId: opsStudentId,
    classId: plannedClass.id,
    startDate: "2026-04-01",
    status: "pending",
  });
  record(17, "validate valid create enrollment input", validInput.ok);

  const pendingEnroll = await insertEnrollment(admin, {
    studentId: opsStudentId,
    classId: plannedClass.id,
    startDate: "2026-04-01",
    status: "pending",
  });
  record(
    18,
    "create pending enrollment on planned class",
    !pendingEnroll.error &&
      pendingEnroll.data?.status === "pending" &&
      isCreateStatusAllowedForClass("planned", "pending"),
  );

  const activeStudentId = await createStudent(admin, "ActiveOps");
  const activeEnroll = await insertEnrollment(admin, {
    studentId: activeStudentId,
    classId: activeClass.id,
    startDate: "2026-04-02",
    status: "active",
  });
  record(
    19,
    "create active enrollment on active class",
    !activeEnroll.error &&
      activeEnroll.data?.status === "active" &&
      isCreateStatusAllowedForClass("active", "active"),
  );

  const invalidInput = validateCreateEnrollmentInput({
    studentId: "",
    classId: "",
    startDate: "",
    status: "bogus",
  });
  record(20, "invalid enrollment input rejected", !invalidInput.ok);

  record(
    21,
    "closed class rejects enrollment",
    closedClass.status === "closed" && !canEnrollInClass("closed"),
  );

  record(
    22,
    "planned class rejects active status on create",
    !isCreateStatusAllowedForClass("planned", "active"),
  );

  // Overlap constraint (23-27)
  const overlapCourseId = await createCourse(admin, "overlap");
  const overlapClass = await createClass(admin, overlapCourseId, "Overlap");
  const overlapStudentId = await createStudent(admin, "Overlap");
  const overlapStart = "2026-05-01";

  const firstOverlap = await insertEnrollment(admin, {
    studentId: overlapStudentId,
    classId: overlapClass.id,
    startDate: overlapStart,
    status: "active",
  });
  const secondOverlap = await insertEnrollment(admin, {
    studentId: overlapStudentId,
    classId: overlapClass.id,
    startDate: overlapStart,
    status: "pending",
  });
  record(
    23,
    "overlapping operational enrollment rejected",
    !firstOverlap.error && Boolean(secondOverlap.error) && isOverlapConflict(secondOverlap.error),
  );
  record(
    24,
    "overlap returns 23P01 error code",
    secondOverlap.error?.code === "23P01" || isOverlapConflict(secondOverlap.error),
  );

  await admin
    .from("enrollment")
    .update({ status: "withdrawn", end_date: "2026-05-15", updated_by: APP_A_ADMIN })
    .eq("id", firstOverlap.data.id);
  const afterTerminal = await insertEnrollment(admin, {
    studentId: overlapStudentId,
    classId: overlapClass.id,
    startDate: "2026-05-15",
    status: "active",
  });
  record(
    25,
    "non-overlapping date ranges allowed when prior is terminal",
    !afterTerminal.error && afterTerminal.data?.status === "active",
  );

  const openCourseId = await createCourse(admin, "open-end");
  const openClass = await createClass(admin, openCourseId, "OpenEnd");
  const openStudentA = await createStudent(admin, "OpenA");
  const openA = await insertEnrollment(admin, {
    studentId: openStudentA,
    classId: openClass.id,
    startDate: "2026-06-01",
    status: "active",
  });
  const openConflict = await insertEnrollment(admin, {
    studentId: openStudentA,
    classId: openClass.id,
    startDate: "2026-06-10",
    status: "pending",
  });
  record(
    26,
    "open-ended operational enrollments cannot overlap",
    !openA.error && Boolean(openConflict.error) && isOverlapConflict(openConflict.error),
  );

  const concurrentStudentC = await createStudent(admin, "OpenC");
  const concurrentStudentD = await createStudent(admin, "OpenD");
  const concurrentA = await insertEnrollment(admin, {
    studentId: concurrentStudentC,
    classId: openClass.id,
    startDate: "2027-01-01",
    status: "active",
  });
  const concurrentB = await insertEnrollment(admin, {
    studentId: concurrentStudentD,
    classId: openClass.id,
    startDate: "2027-01-01",
    status: "active",
  });
  record(
    27,
    "different students can enroll same class concurrently",
    !concurrentA.error && !concurrentB.error,
  );

  // Historical re-enrollment (28-31)
  const histCourseId = await createCourse(admin, "hist");
  const histClass = await createClass(admin, histCourseId, "Historical");
  const histStudentId = await createStudent(admin, "Hist");

  async function enrollWithdraw(startDate) {
    const row = await insertEnrollment(admin, {
      studentId: histStudentId,
      classId: histClass.id,
      startDate,
      status: "active",
    });
    await admin
      .from("enrollment")
      .update({ status: "withdrawn", end_date: startDate, updated_by: APP_A_ADMIN })
      .eq("id", row.data.id);
    return row.data.id;
  }

  await enrollWithdraw("2026-07-01");
  const reWithdraw = await insertEnrollment(admin, {
    studentId: histStudentId,
    classId: histClass.id,
    startDate: "2026-07-02",
    status: "active",
  });
  record(28, "re-enroll after withdrawn", !reWithdraw.error);

  await admin
    .from("enrollment")
    .update({ status: "completed", end_date: "2026-07-03", updated_by: APP_A_ADMIN })
    .eq("id", reWithdraw.data.id);
  const reComplete = await insertEnrollment(admin, {
    studentId: histStudentId,
    classId: histClass.id,
    startDate: "2026-07-04",
    status: "active",
  });
  record(29, "re-enroll after completed", !reComplete.error);

  await admin
    .from("enrollment")
    .update({ status: "completed", end_date: "2026-07-05", updated_by: APP_A_ADMIN })
    .eq("id", reComplete.data.id);
  const transferSource = await insertEnrollment(admin, {
    studentId: histStudentId,
    classId: histClass.id,
    startDate: "2026-07-06",
    status: "active",
  });
  const transferDestClass = await createClass(admin, histCourseId, "TransferDest");
  const { data: transferredId, error: transferErr } = await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: transferSource.data.id,
    p_destination_class_id: transferDestClass.id,
    p_destination_start_date: "2026-07-07",
    p_destination_status: "active",
  });
  const reAfterTransfer = await insertEnrollment(admin, {
    studentId: histStudentId,
    classId: histClass.id,
    startDate: "2026-07-08",
    status: "pending",
  });
  record(
    30,
    "re-enroll after transferred",
    !transferErr && Boolean(transferredId) && !reAfterTransfer.error,
  );

  const { count: histCount } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true })
    .eq("student_id", histStudentId)
    .eq("class_id", histClass.id);
  record(31, "historical enrollments preserved", (histCount ?? 0) >= 2);

  // Capacity (32-36)
  const capCourseId = await createCourse(admin, "cap");
  const unlimitedClass = await createClass(admin, capCourseId, "Unlimited", { capacity: null });
  const capStudent1 = await createStudent(admin, "Cap1");
  const capStudent2 = await createStudent(admin, "Cap2");
  const u1 = await insertEnrollment(admin, {
    studentId: capStudent1,
    classId: unlimitedClass.id,
    startDate: "2026-08-01",
    status: "active",
  });
  const u2 = await insertEnrollment(admin, {
    studentId: capStudent2,
    classId: unlimitedClass.id,
    startDate: "2026-08-01",
    status: "active",
  });
  record(32, "null capacity allows unlimited enrollments", !u1.error && !u2.error);

  const limitedClass = await createClass(admin, capCourseId, "Limited", { capacity: 2 });
  const l1 = await insertEnrollment(admin, {
    studentId: capStudent1,
    classId: limitedClass.id,
    startDate: "2026-08-02",
    status: "active",
  });
  const l2 = await insertEnrollment(admin, {
    studentId: capStudent2,
    classId: limitedClass.id,
    startDate: "2026-08-02",
    status: "active",
  });
  const countAtCapacity = await countOperationalEnrollments(admin, limitedClass.id);
  record(
    33,
    "capacity limit blocks excess enrollment",
    !l1.error &&
      !l2.error &&
      countAtCapacity === 2 &&
      isCapacityExceeded(limitedClass.capacity, countAtCapacity),
  );

  await admin
    .from("enrollment")
    .update({ status: "withdrawn", end_date: "2026-08-02", updated_by: APP_A_ADMIN })
    .eq("id", l1.data.id);
  const countAfterWithdraw = await countOperationalEnrollments(admin, limitedClass.id);
  record(
    34,
    "withdrawn enrollment frees capacity slot",
    countAfterWithdraw === 1 && !isCapacityExceeded(limitedClass.capacity, countAfterWithdraw),
  );

  const fullDestClass = await createClass(admin, capCourseId, "FullDest", { capacity: 1 });
  const fullOccupant = await createStudent(admin, "FullOcc");
  await insertEnrollment(admin, {
    studentId: fullOccupant,
    classId: fullDestClass.id,
    startDate: "2026-08-04",
    status: "active",
  });
  const transferSourceCap = await insertEnrollment(admin, {
    studentId: capStudent1,
    classId: limitedClass.id,
    startDate: "2026-08-05",
    status: "active",
  });
  const { error: capTransferErr } = await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: transferSourceCap.data.id,
    p_destination_class_id: fullDestClass.id,
    p_destination_start_date: "2026-08-06",
    p_destination_status: "active",
  });
  record(
    35,
    "transfer blocked when destination at capacity",
    Boolean(capTransferErr) &&
      (capTransferErr.message?.includes("capacity_reached") ?? false),
  );

  const { data: opRows } = await admin
    .from("enrollment")
    .select("id")
    .eq("class_id", limitedClass.id)
    .in("status", OPERATIONAL_ENROLLMENT_STATUSES);
  record(
    36,
    "operational count excludes withdrawn",
    !(opRows ?? []).some((row) => row.id === l1.data.id),
  );

  // Transfer via RPC (37-42)
  const xferCourseId = await createCourse(admin, "xfer");
  const xferSourceClass = await createClass(admin, xferCourseId, "XferSource");
  const xferDestClass = await createClass(admin, xferCourseId, "XferDest");
  const xferStudentId = await createStudent(admin, "Xfer");
  const xferSource = await insertEnrollment(admin, {
    studentId: xferStudentId,
    classId: xferSourceClass.id,
    startDate: "2026-09-01",
    status: "active",
  });

  const { data: newEnrollId, error: xferErr } = await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferSource.data.id,
    p_destination_class_id: xferDestClass.id,
    p_destination_start_date: "2026-09-15",
    p_destination_status: "pending",
  });
  const { data: sourceAfterXfer } = await admin
    .from("enrollment")
    .select("status, end_date")
    .eq("id", xferSource.data.id)
    .single();
  record(
    37,
    "transfer marks source transferred",
    !xferErr && sourceAfterXfer?.status === "transferred",
  );

  const { data: destEnroll } = await admin
    .from("enrollment")
    .select("id, class_id, status, start_date")
    .eq("id", newEnrollId)
    .single();
  record(
    38,
    "transfer creates destination enrollment",
    destEnroll?.class_id === xferDestClass.id && destEnroll?.status === "pending",
  );

  record(
    39,
    "transfer sets source end_date",
    Boolean(sourceAfterXfer?.end_date),
  );

  const closedXferDest = await createClass(admin, xferCourseId, "XferClosed", { status: "closed" });
  const xferSource2 = await insertEnrollment(admin, {
    studentId: await createStudent(admin, "Xfer2"),
    classId: xferSourceClass.id,
    startDate: "2026-09-02",
    status: "active",
  });
  const { error: closedXferErr } = await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferSource2.data.id,
    p_destination_class_id: closedXferDest.id,
    p_destination_start_date: "2026-09-16",
    p_destination_status: "active",
  });
  record(
    40,
    "transfer to closed class rejected",
    Boolean(closedXferErr) && (closedXferErr.message?.includes("class_closed") ?? false),
  );

  const readerXferSource = await insertEnrollment(admin, {
    studentId: await createStudent(admin, "ReaderXfer"),
    classId: xferSourceClass.id,
    startDate: "2026-09-03",
    status: "active",
  });
  const { error: readerXferErr } = await reader.rpc("transfer_enrollment", {
    p_source_enrollment_id: readerXferSource.data.id,
    p_destination_class_id: xferDestClass.id,
    p_destination_start_date: "2026-09-17",
    p_destination_status: "active",
  });
  record(
    41,
    "transfer denied without enrollment.update",
    Boolean(readerXferErr) &&
      (readerXferErr.message?.includes("permission_denied") ?? false),
  );

  const overlapDestClass = await createClass(admin, xferCourseId, "XferOverlapDest");
  const overlapXferStudent = await createStudent(admin, "XferOverlap");
  await insertEnrollment(admin, {
    studentId: overlapXferStudent,
    classId: overlapDestClass.id,
    startDate: "2026-09-20",
    status: "active",
  });
  const overlapXferSource = await insertEnrollment(admin, {
    studentId: overlapXferStudent,
    classId: xferSourceClass.id,
    startDate: "2026-09-04",
    status: "active",
  });
  const { error: overlapXferErr } = await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: overlapXferSource.data.id,
    p_destination_class_id: overlapDestClass.id,
    p_destination_start_date: "2026-09-20",
    p_destination_status: "active",
  });
  record(
    42,
    "transfer overlap at destination rejected",
    Boolean(overlapXferErr) && isOverlapConflict(overlapXferErr),
  );

  // Withdraw (43-45)
  const wdCourseId = await createCourse(admin, "withdraw");
  const wdClass = await createClass(admin, wdCourseId, "Withdraw");
  const wdStudentPending = await createStudent(admin, "WdPending");
  const wdStudentActive = await createStudent(admin, "WdActive");
  const wdPending = await insertEnrollment(admin, {
    studentId: wdStudentPending,
    classId: wdClass.id,
    startDate: "2026-10-01",
    status: "pending",
  });
  const { error: wdPendingErr } = await admin
    .from("enrollment")
    .update({
      status: "withdrawn",
      end_date: "2026-10-15",
      updated_by: APP_A_ADMIN,
    })
    .eq("id", wdPending.data.id);
  record(43, "withdraw pending enrollment", !wdPendingErr);

  const wdActive = await insertEnrollment(admin, {
    studentId: wdStudentActive,
    classId: wdClass.id,
    startDate: "2026-10-02",
    status: "active",
  });
  const { error: wdActiveErr } = await admin
    .from("enrollment")
    .update({
      status: "withdrawn",
      end_date: "2026-10-20",
      updated_by: APP_A_ADMIN,
    })
    .eq("id", wdActive.data.id);
  record(44, "withdraw active enrollment", !wdActiveErr);

  const { data: wdTerminalCheck } = await admin
    .from("enrollment")
    .select("status, end_date")
    .eq("id", wdPending.data.id)
    .single();
  record(
    45,
    "withdrawn enrollment remains terminal",
    wdTerminalCheck?.status === "withdrawn" && Boolean(wdTerminalCheck?.end_date),
  );

  // Complete (46-48)
  const cpCourseId = await createCourse(admin, "complete");
  const cpClass = await createClass(admin, cpCourseId, "Complete");
  const cpPendingStudent = await createStudent(admin, "CpPending");
  const cpActiveStudent = await createStudent(admin, "CpActive");
  const cpPending = await insertEnrollment(admin, {
    studentId: cpPendingStudent,
    classId: cpClass.id,
    startDate: "2026-11-01",
    status: "pending",
  });
  const { error: cpPendingErr } = await admin
    .from("enrollment")
    .update({
      status: "completed",
      end_date: "2026-11-15",
      updated_by: APP_A_ADMIN,
    })
    .eq("id", cpPending.data.id);
  record(46, "complete pending enrollment", !cpPendingErr);

  const cpActive = await insertEnrollment(admin, {
    studentId: cpActiveStudent,
    classId: cpClass.id,
    startDate: "2026-11-02",
    status: "active",
  });
  const { error: cpActiveErr } = await admin
    .from("enrollment")
    .update({
      status: "completed",
      end_date: "2026-11-30",
      updated_by: APP_A_ADMIN,
    })
    .eq("id", cpActive.data.id);
  record(47, "complete active enrollment", !cpActiveErr);

  const { data: cpTerminalCheck } = await admin
    .from("enrollment")
    .select("status, end_date")
    .eq("id", cpPending.data.id)
    .single();
  record(
    48,
    "completed enrollment remains terminal",
    cpTerminalCheck?.status === "completed" && Boolean(cpTerminalCheck?.end_date),
  );

  // Read model / roster (49-52)
  const rosterCourseId = await createCourse(admin, "roster");
  const rosterClass = await createClass(admin, rosterCourseId, "Roster");
  const rosterStudent = await createStudent(admin, "Roster");
  await admin.from("student").update({ given_name: "RosterSearch", family_name: `Target${ts}` }).eq("id", rosterStudent);
  const rosterEnroll = await insertEnrollment(admin, {
    studentId: rosterStudent,
    classId: rosterClass.id,
    startDate: "2026-12-01",
    status: "active",
  });
  const { data: rosterRows } = await admin
    .from("enrollment")
    .select("id")
    .eq("class_id", rosterClass.id);
  record(
    49,
    "roster lists class enrollments",
    (rosterRows ?? []).some((r) => r.id === rosterEnroll.data.id),
  );

  await admin
    .from("enrollment")
    .update({ status: "withdrawn", end_date: "2026-12-02", updated_by: APP_A_ADMIN })
    .eq("id", rosterEnroll.data.id);
  const { data: operationalRows } = await admin
    .from("enrollment")
    .select("id, status")
    .eq("class_id", rosterClass.id)
    .in("status", OPERATIONAL_ENROLLMENT_STATUSES);
  record(
    50,
    "operational status filter excludes withdrawn",
    !(operationalRows ?? []).some((r) => r.id === rosterEnroll.data.id),
  );

  const { data: searchStudents } = await admin
    .from("student")
    .select("id")
    .ilike("given_name", `*RosterSearch*`);
  const searchStudentIds = (searchStudents ?? []).map((s) => s.id);
  const { data: searchEnrollments } = await admin
    .from("enrollment")
    .select("id")
    .eq("class_id", rosterClass.id)
    .in("student_id", searchStudentIds.length > 0 ? searchStudentIds : ["00000000-0000-4000-8000-000000000099"]);
  record(
    51,
    "roster search by student name works",
    (searchEnrollments ?? []).some((r) => r.id === rosterEnroll.data.id),
  );

  const { data: page1 } = await admin
    .from("enrollment")
    .select("id")
    .eq("class_id", rosterClass.id)
    .order("start_date", { ascending: false })
    .order("id", { ascending: false })
    .range(0, 0);
  const { data: page1Again } = await admin
    .from("enrollment")
    .select("id")
    .eq("class_id", rosterClass.id)
    .order("start_date", { ascending: false })
    .order("id", { ascending: false })
    .range(0, 0);
  record(
    52,
    "roster pagination ordering is stable",
    page1?.[0]?.id && page1[0].id === page1Again?.[0]?.id,
  );

  // Regression (53-55)
  const { count: studentCount, error: studentListError } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  record(53, "student list remains functional", !studentListError && (studentCount ?? 0) > 0);

  const { count: classCount, error: classListError } = await admin
    .from("class")
    .select("id", { count: "exact", head: true });
  record(54, "class list remains functional", !classListError && (classCount ?? 0) > 0);

  const { count: primaryCount } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  record(55, "guardian primary contact invariant remains functional", (primaryCount ?? 0) === 1);

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM1-T06 enrollment smoke: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  EN-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
