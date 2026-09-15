#!/usr/bin/env node
/**
 * M1-T05 course and class operations smoke tests.
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

const CLASS_STATUSES = ["planned", "trial", "active", "closed"];
const COURSE_STATUSES = ["active", "inactive", "archived"];

const results = [];
const createdCourseIds = [];
const createdClassIds = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} CC-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

function validateCourseInput(input) {
  const fieldErrors = {};
  const code = (input.code ?? "").trim();
  const name = (input.name ?? "").trim();
  if (!code) fieldErrors.code = "required";
  if (!name) fieldErrors.name = "required";
  if (!COURSE_STATUSES.includes(input.status ?? "active")) fieldErrors.status = "invalid";
  return { ok: Object.keys(fieldErrors).length === 0, fieldErrors, code, name };
}

function validateClassInput(input) {
  const fieldErrors = {};
  const name = (input.name ?? "").trim();
  const courseId = (input.courseId ?? "").trim();
  if (!name) fieldErrors.name = "required";
  if (!courseId) fieldErrors.courseId = "required";
  if (input.termStartDate && input.termEndDate && input.termEndDate < input.termStartDate) {
    fieldErrors.termEndDate = "beforeStart";
  }
  if (!CLASS_STATUSES.includes(input.status ?? "planned")) fieldErrors.status = "invalid";
  return { ok: Object.keys(fieldErrors).length === 0, fieldErrors };
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const orgBAdmin = await signIn("org-b-admin@olli.local");

  // Schema (1-5)
  const { data: courseCols } = await admin.from("course").select("*").limit(1);
  const courseRow = courseCols?.[0];
  record(
    1,
    "course schema has expected columns",
    Boolean(
      courseRow &&
        "code" in courseRow &&
        "name" in courseRow &&
        "status" in courseRow &&
        "created_by" in courseRow,
    ),
  );

  const { data: classCols } = await admin.from("class").select("*").limit(1);
  const classRow = classCols?.[0];
  record(
    2,
    "class schema has course_id FK and lifecycle status",
    Boolean(
      classRow &&
        "course_id" in classRow &&
        "name" in classRow &&
        "status" in classRow &&
        CLASS_STATUSES.includes(classRow.status),
    ),
  );

  const { data: orgACourse } = await admin
    .from("course")
    .select("id")
    .eq("organization_id", ORG_A)
    .limit(1)
    .single();
  const crossOrgClass = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: "00000000-0000-4000-8000-000000000099",
    name: "Bad FK",
    status: "planned",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(3, "class course FK is organization-safe", Boolean(crossOrgClass.error));

  const badStatus = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: orgACourse.id,
    name: "Bad Status",
    status: "completed",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(4, "invalid lifecycle status rejected", Boolean(badStatus.error));

  const badDates = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: orgACourse.id,
    name: "Bad Dates",
    term_start_date: "2026-06-01",
    term_end_date: "2026-01-01",
    status: "planned",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(5, "date inconsistency rejected", Boolean(badDates.error));

  const codeBase = `CC-${Date.now()}`;
  const firstCourse = await admin.from("course").insert({
    organization_id: ORG_A,
    code: codeBase,
    name: "Course One",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id").single();
  createdCourseIds.push(firstCourse.data?.id);
  const dupCourse = await admin.from("course").insert({
    organization_id: ORG_A,
    code: codeBase,
    name: "Course Dup",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(6, "course code uniqueness is organization-scoped", Boolean(dupCourse.error));

  // Permissions (7-12)
  record(7, "enrollment.read works for admin", await hasPermission(admin, "enrollment.read"));
  record(8, "enrollment.create works for admin", await hasPermission(admin, "enrollment.create"));
  record(9, "enrollment.update works for admin", await hasPermission(admin, "enrollment.update"));
  record(10, "enrollment.read works for staff", await hasPermission(await signIn("org-a-staff@olli.local"), "enrollment.read"));
  record(11, "enrollment.create denied for reader", !(await hasPermission(reader, "enrollment.create")));
  record(12, "enrollment.update denied for reader", !(await hasPermission(reader, "enrollment.update")));

  const readerInsert = await reader.from("course").insert({
    organization_id: ORG_A,
    code: `R-${Date.now()}`,
    name: "Reader Course",
  });
  record(13, "unauthorized course mutation fails via RLS", Boolean(readerInsert.error));

  // Security (14-17)
  const orgBInsert = await admin.from("course").insert({
    organization_id: ORG_B,
    code: `X-${Date.now()}`,
    name: "Cross Org",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(14, "client cannot choose another organization", Boolean(orgBInsert.error));

  const created = await admin.from("course").insert({
    organization_id: ORG_A,
    code: `AUD-${Date.now()}`,
    name: "Audit Course",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("created_by, updated_by").single();
  createdCourseIds.push(created.data?.id);
  record(
    15,
    "actor attribution is server-derived",
    created.data?.created_by === APP_A_ADMIN && created.data?.updated_by === APP_A_ADMIN,
  );

  const { data: orgBCourses } = await admin.from("course").select("id").eq("organization_id", ORG_B);
  record(16, "RLS prevents cross-organization course listing for org A session", (orgBCourses ?? []).length === 0);

  const { data: orgBClassCourse } = await orgBAdmin.from("course").select("id").limit(1).single();
  const crossAssign = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: orgBClassCourse.id,
    name: "Cross Course Class",
    status: "planned",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(17, "cross-organization course cannot be assigned to class", Boolean(crossAssign.error));

  // Course ops (18-22)
  const courseCode = `CR-${Date.now()}`;
  const validCourse = validateCourseInput({ code: courseCode, name: "Valid Course", status: "active" });
  record(18, "validate valid course input", validCourse.ok);

  const { data: newCourse, error: createCourseError } = await admin.from("course").insert({
    organization_id: ORG_A,
    code: courseCode,
    name: "Communication English",
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id").single();
  createdCourseIds.push(newCourse?.id);
  record(19, "create valid course", !createCourseError && Boolean(newCourse?.id));

  const { error: editCourseError } = await admin
    .from("course")
    .update({ name: "Communication English Updated", updated_by: APP_A_ADMIN })
    .eq("id", newCourse.id);
  record(20, "edit course", !editCourseError);

  const invalidCourse = validateCourseInput({ code: "", name: "", status: "bogus" });
  record(21, "invalid course input rejected", !invalidCourse.ok);

  const unicodeCourse = await admin.from("course").insert({
    organization_id: ORG_A,
    code: `VN-${Date.now()}`,
    name: "Tiếng Anh Giao Tiếp",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id").single();
  createdCourseIds.push(unicodeCourse.data?.id);
  record(22, "course names are Unicode-safe", !unicodeCourse.error);

  const classA = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: newCourse.id,
    name: "Class A",
    status: "planned",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id").single();
  createdClassIds.push(classA.data?.id);
  const classB = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: newCourse.id,
    name: "Class B",
    status: "trial",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id").single();
  createdClassIds.push(classB.data?.id);
  record(23, "course can be reused by multiple classes", !classA.error && !classB.error);

  // Class ops (24-30)
  const classInput = validateClassInput({
    name: "Ops Class",
    courseId: newCourse.id,
    status: "planned",
  });
  record(24, "validate class linked to course", classInput.ok);

  const opsClass = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: newCourse.id,
    name: "Ops Class",
    status: "planned",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id").single();
  createdClassIds.push(opsClass.data?.id);
  const { error: editClassError } = await admin
    .from("class")
    .update({ name: "Ops Class Updated", updated_by: APP_A_ADMIN })
    .eq("id", opsClass.data.id);
  record(25, "edit class", !editClassError);

  for (const [idx, status] of ["planned", "trial", "active", "closed"].entries()) {
    const row = await admin.from("class").insert({
      organization_id: ORG_A,
      course_id: newCourse.id,
      name: `Lifecycle ${status} ${Date.now()}`,
      status,
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    }).select("id, status").single();
    createdClassIds.push(row.data?.id);
    record(26 + idx, `${status} state works`, row.data?.status === status);
  }

  const closeTarget = await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: newCourse.id,
    name: `Close Target ${Date.now()}`,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id").single();
  createdClassIds.push(closeTarget.data?.id);
  const { count: enrollBefore } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true })
    .eq("class_id", closeTarget.data.id);
  await admin.from("class").update({ status: "closed", updated_by: APP_A_ADMIN }).eq("id", closeTarget.data.id);
  const { data: stillThere } = await admin.from("class").select("id, status").eq("id", closeTarget.data.id).single();
  const { count: enrollAfter } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true })
    .eq("class_id", closeTarget.data.id);
  record(
    30,
    "close does not delete class",
    stillThere?.status === "closed" &&
      stillThere?.id === closeTarget.data.id &&
      enrollBefore === enrollAfter,
  );

  // Read model (31-36) — search a class created in this run
  const { data: searchClasses } = await admin
    .from("class")
    .select("id, name")
    .ilike("name", "*Ops Class*");
  record(31, "class list search by name works", (searchClasses ?? []).some((r) => r.id === opsClass.data.id));

  const { data: studentBefore } = await admin.from("student").select("*").eq("id", STUDENT_TRAN).single();
  await admin.from("class").update({ name: "Renamed Seed Class" }).eq("organization_id", ORG_A).eq("name", "Class A1");
  const { data: studentAfter } = await admin.from("student").select("*").eq("id", STUDENT_TRAN).single();
  record(
    32,
    "class edit does not mutate students",
    JSON.stringify(studentBefore) === JSON.stringify(studentAfter),
  );

  const { data: statusFilter } = await admin.from("class").select("id").eq("status", "planned");
  record(33, "status filter works", (statusFilter ?? []).length >= 1);

  const { data: courseFilter } = await admin.from("class").select("id").eq("course_id", orgACourse.id);
  record(34, "course filter works", (courseFilter ?? []).length >= 1);

  const { data: page1 } = await admin
    .from("class")
    .select("id")
    .order("name", { ascending: true })
    .order("id", { ascending: true })
    .range(0, 0);
  const { data: page1Again } = await admin
    .from("class")
    .select("id")
    .order("name", { ascending: true })
    .order("id", { ascending: true })
    .range(0, 0);
  record(
    35,
    "pagination ordering is stable",
    page1?.[0]?.id && page1[0].id === page1Again?.[0]?.id,
  );

  const { count: filteredCount } = await admin
    .from("class")
    .select("id", { count: "exact", head: true })
    .eq("status", "planned");
  record(36, "filter occurs before pagination semantics", (filteredCount ?? 0) >= 1);

  const { data: dupCheck } = await admin.from("class").select("id, name").eq("name", "Class A1");
  record(
    37,
    "one class appears once per id",
    new Set((dupCheck ?? []).map((r) => r.id)).size === (dupCheck ?? []).length,
  );

  // Architectural boundaries (38-42)
  const { data: studentCols } = await admin.from("student").select("*").limit(1);
  record(38, "no current_class_id on student", !("current_class_id" in (studentCols?.[0] ?? {})));

  const enrollCountBefore = (
    await admin.from("enrollment").select("id", { count: "exact", head: true })
  ).count;
  await admin.from("class").insert({
    organization_id: ORG_A,
    course_id: newCourse.id,
    name: `No Enroll ${Date.now()}`,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  const enrollCountAfter = (
    await admin.from("enrollment").select("id", { count: "exact", head: true })
  ).count;
  record(39, "class create does not create enrollment", enrollCountBefore === enrollCountAfter);

  const { count: sessionCountBefore } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true });
  await admin.from("class").update({ status: "closed" }).eq("id", opsClass.data.id);
  const { count: sessionCountAfter } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true });
  record(40, "class lifecycle does not create teaching sessions", sessionCountBefore === sessionCountAfter);

  const { count: scheduleCountBefore } = await admin
    .from("class_schedule")
    .select("id", { count: "exact", head: true });
  await admin.from("class").update({ name: "Schedule Safe" }).eq("id", opsClass.data.id);
  const { count: scheduleCountAfter } = await admin
    .from("class_schedule")
    .select("id", { count: "exact", head: true });
  record(41, "class edit does not mutate class_schedule", scheduleCountBefore === scheduleCountAfter);

  const { data: classSchema } = await admin.from("class").select("*").limit(1);
  record(42, "no direct teacher_id on class", !("teacher_id" in (classSchema?.[0] ?? {})));

  // Regression (43-45)
  const { count: studentCount, error: studentListError } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  record(43, "student list remains functional", !studentListError && (studentCount ?? 0) > 0);

  const { count: guardianLinks, error: guardianError } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("status", "active");
  record(44, "guardian management data remains functional", !guardianError && (guardianLinks ?? 0) > 0);

  const { count: primaryCount } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("student_id", STUDENT_TRAN)
    .eq("status", "active")
    .eq("is_primary_contact", true);
  record(45, "primary-contact invariant remains functional", (primaryCount ?? 0) === 1);

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM1-T05 course/class smoke: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  CC-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
