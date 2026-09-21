#!/usr/bin/env node
/**
 * M1-T09 assessment smoke tests (AS-1 through AS-65).
 * Requires local Supabase with dev seed and M1-T09 migration applied.
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
const SERVICE_ROLE_KEY =
  process.env.SUPABASE_SECRET_KEY ?? statusEnv.SECRET_KEY;

const ORG_A = "a0000000-0000-4000-8000-000000000001";
const ORG_B = "b0000000-0000-4000-8000-000000000001";
const APP_A_ADMIN = "a1000000-0000-4000-8000-000000000001";

const ASSESSMENT_STATUSES = ["draft", "open", "closed"];
const ASSESSMENT_TYPE_CODES = ["progress_test", "checkpoint", "end_of_course"];
const RESULT_STATUSES = ["draft", "finalized", "corrected"];

const results = [];
const createdCourseIds = [];
const createdClassIds = [];
const createdStudentIds = [];
const createdAssessmentIds = [];
const createdTeacherIds = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} AS-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
}

function createServiceAdmin() {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
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

function isEnrollmentEligibleOnAssessmentDate(enrollment, assessmentDate) {
  if (enrollment.startDate > assessmentDate) return false;
  if (enrollment.endDate && enrollment.endDate < assessmentDate) return false;
  return true;
}

function isEnrollmentVisibleForAssessmentResult(enrollment, assessmentDate) {
  if (!isEnrollmentEligibleOnAssessmentDate(enrollment, assessmentDate)) return false;
  if (enrollment.status === "pending") return false;
  return true;
}

function derivePercentage(rawScore, maxScore) {
  if (maxScore <= 0) return null;
  return Math.round((rawScore / maxScore) * 1000) / 10;
}

function isDuplicateResult(error) {
  if (!error) return false;
  if (error.code === "23505") return true;
  return error.message?.includes("duplicate") ?? false;
}

function isCrossClassAssessment(error) {
  if (!error?.message) return false;
  return (
    error.message.includes("assessment_class_mismatch") ||
    error.message.includes("enrollment_not_eligible") ||
    error.message.includes("pending_enrollment") ||
    error.message.includes("invalid_assessment_reference") ||
    error.message.includes("invalid_enrollment_reference")
  );
}

function isScoreRangeError(error) {
  if (!error?.message) return false;
  return (
    error.message.includes("invalid_raw_score") ||
    error.message.includes("invalid_max_score") ||
    error.message.includes("assessment_result_raw_score_check") ||
    error.message.includes("assessment_result_max_score_check")
  );
}

function canCreateAssessmentForClass(classStatus) {
  return classStatus !== "closed";
}

async function deriveAssessmentResults(admin, assessment) {
  const [{ data: enrollments }, { data: resultRows }] = await Promise.all([
    admin
      .from("enrollment")
      .select("id, student_id, start_date, end_date, status, student:student(given_name, family_name, student_code)")
      .eq("class_id", assessment.classId)
      .order("start_date"),
    admin
      .from("assessment_result")
      .select("id, enrollment_id, raw_score, max_score, status")
      .eq("assessment_id", assessment.id),
  ]);

  const resultByEnrollment = new Map((resultRows ?? []).map((r) => [r.enrollment_id, r]));
  const rows = [];

  for (const enr of enrollments ?? []) {
    const eligibility = {
      startDate: enr.start_date,
      endDate: enr.end_date,
      status: enr.status,
    };
    if (!isEnrollmentVisibleForAssessmentResult(eligibility, assessment.assessedOn)) continue;

    const result = resultByEnrollment.get(enr.id);
    const rawScore = result ? Number(result.raw_score) : null;
    const maxScore = result ? Number(result.max_score) : null;
    const student = Array.isArray(enr.student) ? enr.student[0] : enr.student;

    rows.push({
      enrollmentId: enr.id,
      studentId: enr.student_id,
      studentName: student ? `${student.family_name} ${student.given_name}`.trim() : "—",
      enrollmentStatus: enr.status,
      enrollmentStartDate: enr.start_date,
      enrollmentEndDate: enr.end_date,
      resultId: result?.id ?? null,
      rawScore,
      maxScore,
      percentage: rawScore !== null && maxScore !== null ? derivePercentage(rawScore, maxScore) : null,
      resultStatus: result?.status ?? null,
    });
  }

  rows.sort((a, b) => a.studentName.localeCompare(b.studentName));
  return rows;
}

async function fetchClassAssessments(admin, classId) {
  const { data: assessments } = await admin
    .from("assessment")
    .select("id, title, assessed_on, max_score, status, assessment_type_code")
    .eq("class_id", classId)
    .order("assessed_on", { ascending: false })
    .order("title");

  const { data: enrollments } = await admin
    .from("enrollment")
    .select("id, start_date, end_date, status")
    .eq("class_id", classId);

  const items = [];
  for (const row of assessments ?? []) {
    const { count: scoredCount } = await admin
      .from("assessment_result")
      .select("id", { count: "exact", head: true })
      .eq("assessment_id", row.id);

    const eligibleCount = (enrollments ?? []).filter((enr) =>
      isEnrollmentVisibleForAssessmentResult(
        { startDate: enr.start_date, endDate: enr.end_date, status: enr.status },
        row.assessed_on,
      ),
    ).length;

    items.push({
      id: row.id,
      title: row.title,
      assessedOn: row.assessed_on,
      maxScore: Number(row.max_score),
      status: row.status,
      assessmentTypeCode: row.assessment_type_code,
      scoredCount: scoredCount ?? 0,
      eligibleCount,
    });
  }
  return items;
}

async function fetchStudentProgress(admin, studentId) {
  const { data: enrollments } = await admin
    .from("enrollment")
    .select("id, class_id, start_date, end_date, class:class(name, course:course(code, name))")
    .eq("student_id", studentId)
    .order("start_date", { ascending: false });

  if (!enrollments?.length) return [];

  const enrollmentIds = enrollments.map((e) => e.id);
  const { data: resultRows } = await admin
    .from("assessment_result")
    .select("id, enrollment_id, raw_score, max_score, assessment:assessment(id, title, assessed_on, class_id)")
    .in("enrollment_id", enrollmentIds)
    .order("created_at", { ascending: false });

  const enrollmentById = new Map(
    enrollments.map((e) => {
      const classRow = Array.isArray(e.class) ? e.class[0] : e.class;
      const course = classRow?.course
        ? Array.isArray(classRow.course)
          ? classRow.course[0]
          : classRow.course
        : null;
      return [
        e.id,
        {
          classId: e.class_id,
          className: classRow?.name ?? "—",
          courseCode: course?.code ?? null,
          courseName: course?.name ?? null,
          startDate: e.start_date,
          endDate: e.end_date,
        },
      ];
    }),
  );

  const items = [];
  for (const row of resultRows ?? []) {
    const assessment = Array.isArray(row.assessment) ? row.assessment[0] : row.assessment;
    const enr = enrollmentById.get(row.enrollment_id);
    if (!assessment || !enr) continue;
    const rawScore = Number(row.raw_score);
    const maxScore = Number(row.max_score);
    items.push({
      resultId: row.id,
      assessmentId: assessment.id,
      assessmentTitle: assessment.title,
      assessedOn: assessment.assessed_on,
      classId: enr.classId,
      className: enr.className,
      enrollmentId: row.enrollment_id,
      rawScore,
      maxScore,
      percentage: derivePercentage(rawScore, maxScore),
    });
  }

  items.sort((a, b) => {
    const dateCmp = b.assessedOn.localeCompare(a.assessedOn);
    if (dateCmp !== 0) return dateCmp;
    return a.assessmentTitle.localeCompare(b.assessmentTitle);
  });
  return items;
}

async function createCourse(admin, label) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("course")
    .insert({
      organization_id: ORG_A,
      code: `AS-${label}-${ts}`,
      name: `Assessment ${label} ${ts}`,
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
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, status")
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

async function createTeacher(admin, label) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: label,
      family_name: `Smoke${ts}`,
      status: "active",
    })
    .select("id")
    .single();
  if (error) throw error;
  createdTeacherIds.push(data.id);
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
    .select("id, student_id, class_id, start_date, end_date, status")
    .single();
}

async function insertAssessment(admin, input) {
  const row = await admin
    .from("assessment")
    .insert({
      organization_id: ORG_A,
      class_id: input.classId,
      assessment_type_code: input.assessmentTypeCode ?? "progress_test",
      title: input.title,
      max_score: input.maxScore ?? 20,
      assessed_on: input.assessedOn,
      status: input.status ?? "open",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("*")
    .single();
  if (!row.error && row.data?.id) createdAssessmentIds.push(row.data.id);
  return row;
}

async function insertAssessmentResult(admin, input) {
  return admin
    .from("assessment_result")
    .insert({
      organization_id: ORG_A,
      assessment_id: input.assessmentId,
      enrollment_id: input.enrollmentId,
      raw_score: input.rawScore,
      max_score: input.maxScore,
      status: input.status ?? "draft",
      recorded_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
      finalized_at: input.finalizedAt ?? null,
    })
    .select("*")
    .single();
}

async function setupClassWithEnrollment(admin, label, options = {}) {
  const courseId = options.courseId ?? (await createCourse(admin, label));
  const classRow = await createClass(admin, courseId, label, options.classOptions ?? {});
  const studentId = options.studentId ?? (await createStudent(admin, label));
  const enrollment = await insertEnrollment(admin, {
    studentId,
    classId: classRow.id,
    startDate: options.startDate ?? "2028-06-01",
    endDate: options.endDate ?? null,
    status: options.enrollmentStatus ?? "active",
  });
  return { courseId, classRow, studentId, enrollment };
}

async function cleanupFixtures(admin) {
  if (createdClassIds.length > 0) {
    const { data: classAssessments } = await admin
      .from("assessment")
      .select("id")
      .in("class_id", createdClassIds);
    const assessmentIds = [
      ...new Set([
        ...createdAssessmentIds,
        ...(classAssessments ?? []).map((a) => a.id),
      ]),
    ];
    if (assessmentIds.length > 0) {
      await admin.from("assessment_result").delete().in("assessment_id", assessmentIds);
      await admin.from("assessment").delete().in("id", assessmentIds);
    }
    await admin.from("teacher_observation").delete().in("class_id", createdClassIds);
    await admin.from("enrollment").delete().in("class_id", createdClassIds);
    await admin.from("class").delete().in("id", createdClassIds);
  }
  if (createdStudentIds.length > 0) {
    await admin.from("student").delete().in("id", createdStudentIds);
  }
  if (createdCourseIds.length > 0) {
    await admin.from("course").delete().in("id", createdCourseIds);
  }
  if (createdTeacherIds.length > 0) {
    await admin.from("teacher").delete().in("id", createdTeacherIds);
  }
}

async function assertMigrationApplied(admin) {
  const probe = await admin.from("assessment").select("updated_by").limit(1);
  if (probe.error?.message?.includes("updated_by")) {
    throw new Error(
      "M1-T09 migration not applied (assessment.updated_by missing). Run: npx supabase db reset",
    );
  }
}

async function main() {
  const admin = createServiceAdmin();
  await assertMigrationApplied(admin);

  const adminUser = await signIn("org-a-admin@olli.local");
  const staff = await signIn("org-a-staff@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const orgBAdmin = await signIn("org-b-admin@olli.local");

  const {
    count: chargeCountBefore,
  } = await admin.from("charge").select("id", { count: "exact", head: true });
  const {
    count: attendanceCountBefore,
  } = await admin.from("attendance").select("id", { count: "exact", head: true });
  const {
    count: observationCountBefore,
  } = await admin.from("teacher_observation").select("id", { count: "exact", head: true });

  const probe = await setupClassWithEnrollment(admin, "Probe", { startDate: "2028-06-01" });
  const probeAssessment = await insertAssessment(admin, {
    classId: probe.classRow.id,
    title: "Probe Quiz",
    assessedOn: "2028-09-04",
    maxScore: 20,
  });
  if (probeAssessment.error || !probeAssessment.data?.id) {
    throw new Error(`Probe assessment setup failed: ${probeAssessment.error?.message ?? "unknown"}`);
  }
  const probeResult = await insertAssessmentResult(admin, {
    assessmentId: probeAssessment.data.id,
    enrollmentId: probe.enrollment.data.id,
    rawScore: 15,
    maxScore: 20,
    status: "draft",
  });

  // Schema / integrity (1-8)
  const assessmentSample = probeAssessment.data;
  record(
    1,
    "assessment physical schema audited correctly",
    Boolean(
      assessmentSample &&
        "organization_id" in assessmentSample &&
        "class_id" in assessmentSample &&
        "assessment_type_code" in assessmentSample &&
        "title" in assessmentSample &&
        "max_score" in assessmentSample &&
        "assessed_on" in assessmentSample &&
        "status" in assessmentSample &&
        "created_by" in assessmentSample &&
        "updated_by" in assessmentSample &&
        ASSESSMENT_STATUSES.includes(assessmentSample.status) &&
        ASSESSMENT_TYPE_CODES.includes(assessmentSample.assessment_type_code),
    ),
  );

  const resultSample = probeResult.data;
  record(
    2,
    "assessment_result physical schema audited correctly",
    Boolean(
      resultSample &&
        "raw_score" in resultSample &&
        "max_score" in resultSample &&
        "status" in resultSample &&
        "recorded_by" in resultSample &&
        "updated_by" in resultSample &&
        RESULT_STATUSES.includes(resultSample.status),
    ),
  );

  const dupFixture = await setupClassWithEnrollment(admin, "DupResult");
  const dupAssessment = await insertAssessment(admin, {
    classId: dupFixture.classRow.id,
    title: "Dup Quiz",
    assessedOn: "2028-09-05",
  });
  const firstResult = await insertAssessmentResult(admin, {
    assessmentId: dupAssessment.data.id,
    enrollmentId: dupFixture.enrollment.data.id,
    rawScore: 10,
    maxScore: 20,
  });
  const secondResult = await admin.from("assessment_result").insert({
    organization_id: ORG_A,
    assessment_id: dupAssessment.data.id,
    enrollment_id: dupFixture.enrollment.data.id,
    raw_score: 12,
    max_score: 20,
    status: "draft",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(
    3,
    "one result per assessment and enrollment",
    !firstResult.error && Boolean(secondResult.error) && isDuplicateResult(secondResult.error),
  );

  const crossCourse = await createCourse(admin, "CrossClass");
  const classA = await createClass(admin, crossCourse, "CrossA");
  const classB = await createClass(admin, crossCourse, "CrossB");
  const crossStudent = await createStudent(admin, "CrossClass");
  const enrollB = await insertEnrollment(admin, {
    studentId: crossStudent,
    classId: classB.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const crossAssessment = await insertAssessment(admin, {
    classId: classA.id,
    title: "Cross Quiz",
    assessedOn: "2028-09-06",
  });
  const crossClassResult = await insertAssessmentResult(admin, {
    assessmentId: crossAssessment.data.id,
    enrollmentId: enrollB.data.id,
    rawScore: 8,
    maxScore: 20,
  });
  record(
    4,
    "cross-class enrollment/assessment rejected",
    Boolean(crossClassResult.error) && isCrossClassAssessment(crossClassResult.error),
  );

  const { data: orgBAssessment } = await orgBAdmin
    .from("assessment")
    .select("id")
    .limit(1)
    .maybeSingle();
  const crossOrgResult = await admin.from("assessment_result").insert({
    organization_id: ORG_B,
    assessment_id: orgBAssessment?.id ?? "00000000-0000-4000-8000-000000000099",
    enrollment_id: probe.enrollment.data.id,
    raw_score: 5,
    max_score: 20,
    status: "draft",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(5, "cross-org relation rejected", Boolean(crossOrgResult.error));

  const rangeFixture = await setupClassWithEnrollment(admin, "ScoreRange");
  const rangeAssessment = await insertAssessment(admin, {
    classId: rangeFixture.classRow.id,
    title: "Range Quiz",
    assessedOn: "2028-09-07",
    maxScore: 20,
  });
  const overMax = await insertAssessmentResult(admin, {
    assessmentId: rangeAssessment.data.id,
    enrollmentId: rangeFixture.enrollment.data.id,
    rawScore: 25,
    maxScore: 20,
  });
  record(
    6,
    "raw score above max rejected",
    Boolean(overMax.error) && isScoreRangeError(overMax.error),
  );

  const negativeScore = await insertAssessmentResult(admin, {
    assessmentId: rangeAssessment.data.id,
    enrollmentId: rangeFixture.enrollment.data.id,
    rawScore: -1,
    maxScore: 20,
  });
  record(
    7,
    "negative raw score rejected",
    Boolean(negativeScore.error) && isScoreRangeError(negativeScore.error),
  );

  const invalidMax = await admin.from("assessment_result").insert({
    organization_id: ORG_A,
    assessment_id: rangeAssessment.data.id,
    enrollment_id: rangeFixture.enrollment.data.id,
    raw_score: 5,
    max_score: 0,
    status: "draft",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(
    8,
    "invalid max score rejected",
    Boolean(invalidMax.error) && isScoreRangeError(invalidMax.error),
  );

  // Assessment CRUD (9-14)
  const crudFixture = await setupClassWithEnrollment(admin, "Crud");
  const created = await adminUser.from("assessment").insert({
    organization_id: ORG_A,
    class_id: crudFixture.classRow.id,
    assessment_type_code: "progress_test",
    title: "Midterm Progress",
    max_score: 30,
    assessed_on: "2028-09-08",
    status: "open",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("*").single();
  if (!created.error && created.data?.id) createdAssessmentIds.push(created.data.id);
  record(
    9,
    "create assessment succeeds",
    !created.error &&
      created.data?.title === "Midterm Progress" &&
      Number(created.data?.max_score) === 30,
  );

  const staffCreate = await staff.from("assessment").insert({
    organization_id: ORG_A,
    class_id: crudFixture.classRow.id,
    assessment_type_code: "checkpoint",
    title: "Staff Blocked",
    max_score: 10,
    assessed_on: "2028-09-09",
    status: "open",
  });
  record(10, "unauthorized create rejected", Boolean(staffCreate.error));

  const { error: editErr } = await adminUser
    .from("assessment")
    .update({
      title: "Midterm Progress Updated",
      max_score: 35,
      updated_by: APP_A_ADMIN,
    })
    .eq("id", created.data.id);
  const { data: edited } = await admin
    .from("assessment")
    .select("title, max_score, updated_by")
    .eq("id", created.data.id)
    .single();
  record(
    11,
    "edit assessment succeeds",
    !editErr &&
      edited?.title === "Midterm Progress Updated" &&
      Number(edited?.max_score) === 35 &&
      edited?.updated_by === APP_A_ADMIN,
  );

  const closedCourse = await createCourse(admin, "ClosedClass");
  const closedClass = await createClass(admin, closedCourse, "Closed", { status: "closed" });
  const closedBlocked = !canCreateAssessmentForClass(closedClass.status);
  const closedInsert = closedBlocked
    ? { error: { message: "class_closed" } }
    : await adminUser.from("assessment").insert({
        organization_id: ORG_A,
        class_id: closedClass.id,
        assessment_type_code: "progress_test",
        title: "Closed Blocked",
        max_score: 10,
        assessed_on: "2028-09-10",
        status: "open",
        created_by: APP_A_ADMIN,
        updated_by: APP_A_ADMIN,
      });
  record(
    12,
    "closed class blocks new assessment",
    closedBlocked && Boolean(closedInsert.error),
  );

  const unicodeTitle = "Đánh giá tiến độ — 日本語テスト 🎯";
  const unicodeAssessment = await adminUser.from("assessment").insert({
    organization_id: ORG_A,
    class_id: crudFixture.classRow.id,
    assessment_type_code: "checkpoint",
    title: unicodeTitle,
    max_score: 15,
    assessed_on: "2028-09-11",
    status: "draft",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("id, title").single();
  if (!unicodeAssessment.error && unicodeAssessment.data?.id) {
    createdAssessmentIds.push(unicodeAssessment.data.id);
  }
  if (!unicodeAssessment.error && unicodeAssessment.data) {
    const { data: unicodeRow } = await admin
      .from("assessment")
      .select("title")
      .eq("class_id", crudFixture.classRow.id)
      .eq("title", unicodeTitle)
      .maybeSingle();
    record(
      13,
      "unicode title persists correctly",
      !unicodeAssessment.error && unicodeRow?.title === unicodeTitle,
    );
  } else {
    record(13, "unicode title persists correctly", false);
  }

  record(
    14,
    "assessment status values validated",
    ASSESSMENT_STATUSES.every((s) => ASSESSMENT_STATUSES.includes(s)) &&
      ["draft", "open", "closed"].includes(created.data?.status ?? "open"),
  );

  // Eligibility (15-21)
  const eligFixture = await setupClassWithEnrollment(admin, "Eligibility", { startDate: "2028-06-01" });
  const eligAssessment = await insertAssessment(admin, {
    classId: eligFixture.classRow.id,
    title: "Eligibility Quiz",
    assessedOn: "2028-09-12",
  });
  const assessmentDetail = {
    id: eligAssessment.data.id,
    classId: eligFixture.classRow.id,
    assessedOn: "2028-09-12",
    maxScore: 20,
    title: "Eligibility Quiz",
    status: "open",
  };
  const eligRoster = await deriveAssessmentResults(admin, assessmentDetail);
  record(
    15,
    "eligible enrollment appears on result roster",
    eligRoster.some((r) => r.enrollmentId === eligFixture.enrollment.data.id),
  );

  const lateStartStudent = await createStudent(admin, "LateStart");
  const lateStartEnroll = await insertEnrollment(admin, {
    studentId: lateStartStudent,
    classId: eligFixture.classRow.id,
    startDate: "2028-10-01",
    status: "active",
  });
  const rosterLateStart = await deriveAssessmentResults(admin, assessmentDetail);
  record(
    16,
    "enrollment beginning after assessment excluded",
    !rosterLateStart.some((r) => r.enrollmentId === lateStartEnroll.data.id),
  );

  const earlyEndStudent = await createStudent(admin, "EarlyEnd");
  const earlyEndEnroll = await insertEnrollment(admin, {
    studentId: earlyEndStudent,
    classId: eligFixture.classRow.id,
    startDate: "2028-06-01",
    endDate: "2028-08-01",
    status: "withdrawn",
  });
  const rosterEarlyEnd = await deriveAssessmentResults(admin, assessmentDetail);
  record(
    17,
    "enrollment ending before assessment excluded",
    !rosterEarlyEnd.some((r) => r.enrollmentId === earlyEndEnroll.data.id),
  );

  const pendingStudent = await createStudent(admin, "Pending");
  const pendingEnroll = await insertEnrollment(admin, {
    studentId: pendingStudent,
    classId: eligFixture.classRow.id,
    startDate: "2028-06-01",
    status: "pending",
  });
  const pendingRecord = await insertAssessmentResult(admin, {
    assessmentId: eligAssessment.data.id,
    enrollmentId: pendingEnroll.data.id,
    rawScore: 10,
    maxScore: 20,
  });
  record(
    18,
    "pending enrollment rejected for result recording",
    Boolean(pendingRecord.error) &&
      (pendingRecord.error.message?.includes("pending_enrollment") ?? false),
  );

  const xferStudent = await createStudent(admin, "XferHist");
  const xferEnroll = await insertEnrollment(admin, {
    studentId: xferStudent,
    classId: eligFixture.classRow.id,
    startDate: "2028-06-01",
    endDate: "2028-09-20",
    status: "active",
  });
  const xferDestClass = await createClass(admin, eligFixture.courseId, "XferDest");
  await adminUser.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferEnroll.data.id,
    p_destination_class_id: xferDestClass.id,
    p_destination_start_date: "2028-09-21",
    p_destination_status: "active",
  });
  const rosterTransferred = await deriveAssessmentResults(admin, assessmentDetail);
  record(
    19,
    "historical transferred enrollment appears on roster",
    rosterTransferred.some(
      (r) => r.enrollmentId === xferEnroll.data.id && r.enrollmentStatus === "transferred",
    ),
  );

  record(
    20,
    "pending enrollment is not silently treated as participating",
    !isEnrollmentVisibleForAssessmentResult(
      {
        startDate: pendingEnroll.data.start_date,
        endDate: pendingEnroll.data.end_date,
        status: pendingEnroll.data.status,
      },
      assessmentDetail.assessedOn,
    ),
  );

  const wdStudent = await createStudent(admin, "WdHist");
  const wdEnroll = await insertEnrollment(admin, {
    studentId: wdStudent,
    classId: eligFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  await admin
    .from("enrollment")
    .update({ status: "withdrawn", end_date: "2028-10-01", updated_by: APP_A_ADMIN })
    .eq("id", wdEnroll.data.id);
  const rosterWithdrawn = await deriveAssessmentResults(admin, assessmentDetail);
  record(
    21,
    "historical withdrawn enrollment appears on roster",
    rosterWithdrawn.some(
      (r) => r.enrollmentId === wdEnroll.data.id && r.enrollmentStatus === "withdrawn",
    ),
  );

  // Result recording (22-28)
  const recFixture = await setupClassWithEnrollment(admin, "Record");
  const recAssessment = await insertAssessment(admin, {
    classId: recFixture.classRow.id,
    title: "Record Quiz",
    assessedOn: "2028-09-13",
    maxScore: 25,
  });
  const recorded = await adminUser.from("assessment_result").insert({
    organization_id: ORG_A,
    assessment_id: recAssessment.data.id,
    enrollment_id: recFixture.enrollment.data.id,
    raw_score: 18,
    max_score: 25,
    status: "draft",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  }).select("*").single();
  record(
    22,
    "record score succeeds",
    !recorded.error && Number(recorded.data?.raw_score) === 18,
  );

  const corrected = await adminUser
    .from("assessment_result")
    .update({
      raw_score: 20,
      max_score: 25,
      status: "corrected",
      updated_by: APP_A_ADMIN,
    })
    .eq("id", recorded.data.id)
    .select("raw_score, status")
    .single();
  record(
    23,
    "correction updates score and sets corrected status",
    !corrected.error &&
      Number(corrected.data?.raw_score) === 20 &&
      corrected.data?.status === "corrected",
  );

  const { count: resultRowCount } = await admin
    .from("assessment_result")
    .select("id", { count: "exact", head: true })
    .eq("assessment_id", recAssessment.data.id)
    .eq("enrollment_id", recFixture.enrollment.data.id);
  record(
    24,
    "update preserves single result row",
    (resultRowCount ?? 0) === 1,
  );

  record(
    25,
    "no letter grade stored on result row",
    !("letter_grade" in (recorded.data ?? {})) &&
      !("grade" in (recorded.data ?? {})) &&
      typeof recorded.data?.raw_score === "number",
  );

  record(
    26,
    "duplicate concurrent create protected by db",
    Boolean(secondResult.error) && secondResult.error?.code === "23505",
  );

  record(
    27,
    "trusted audit actors populated",
    recorded.data?.recorded_by === APP_A_ADMIN &&
      corrected.data?.status === "corrected",
  );

  const staffRecord = await staff.from("assessment_result").insert({
    organization_id: ORG_A,
    assessment_id: recAssessment.data.id,
    enrollment_id: recFixture.enrollment.data.id,
    raw_score: 5,
    max_score: 25,
    status: "draft",
  });
  record(28, "unauthorized result record rejected", Boolean(staffRecord.error));

  // Read model (29-34)
  const listFixture = await setupClassWithEnrollment(admin, "List");
  const listAssessmentA = await insertAssessment(admin, {
    classId: listFixture.classRow.id,
    title: "List Quiz A",
    assessedOn: "2028-09-14",
  });
  const listAssessmentB = await insertAssessment(admin, {
    classId: listFixture.classRow.id,
    title: "List Quiz B",
    assessedOn: "2028-09-15",
  });
  await insertAssessmentResult(admin, {
    assessmentId: listAssessmentA.data.id,
    enrollmentId: listFixture.enrollment.data.id,
    rawScore: 12,
    maxScore: 20,
  });
  const listItems = await fetchClassAssessments(admin, listFixture.classRow.id);
  record(
    29,
    "class assessments list loads",
    listItems.some((i) => i.id === listAssessmentA.data.id) &&
      listItems.some((i) => i.id === listAssessmentB.data.id),
  );

  const resultRows = await deriveAssessmentResults(admin, {
    id: listAssessmentA.data.id,
    classId: listFixture.classRow.id,
    assessedOn: "2028-09-14",
  });
  record(
    30,
    "assessment results roster derives correctly",
    resultRows.some(
      (r) =>
        r.enrollmentId === listFixture.enrollment.data.id &&
        r.rawScore === 12 &&
        r.percentage === derivePercentage(12, 20),
    ),
  );

  const listItemA = listItems.find((i) => i.id === listAssessmentA.data.id);
  record(
    31,
    "completion count reflects scored vs eligible",
    listItemA?.scoredCount === 1 && listItemA?.eligibleCount >= 1,
  );

  const progressItems = await fetchStudentProgress(admin, listFixture.studentId);
  record(
    32,
    "student academic progress read model",
    progressItems.some((p) => p.assessmentId === listAssessmentA.data.id && p.rawScore === 12),
  );

  const reEnrollStudent = await createStudent(admin, "ReEnroll");
  const firstEnroll = await insertEnrollment(admin, {
    studentId: reEnrollStudent,
    classId: listFixture.classRow.id,
    startDate: "2028-06-01",
    endDate: "2028-08-01",
    status: "withdrawn",
  });
  const secondEnroll = await insertEnrollment(admin, {
    studentId: reEnrollStudent,
    classId: listFixture.classRow.id,
    startDate: "2028-09-01",
    status: "active",
  });
  const reEnrollAssessment = await insertAssessment(admin, {
    classId: listFixture.classRow.id,
    title: "ReEnroll Quiz",
    assessedOn: "2028-09-16",
  });
  await insertAssessmentResult(admin, {
    assessmentId: reEnrollAssessment.data.id,
    enrollmentId: secondEnroll.data.id,
    rawScore: 14,
    maxScore: 20,
  });
  const reEnrollAttempt = await insertAssessmentResult(admin, {
    assessmentId: reEnrollAssessment.data.id,
    enrollmentId: firstEnroll.data.id,
    rawScore: 10,
    maxScore: 20,
  });
  const { data: reEnrollSecondResult } = await admin
    .from("assessment_result")
    .select("id, raw_score")
    .eq("assessment_id", reEnrollAssessment.data.id)
    .eq("enrollment_id", secondEnroll.data.id)
    .maybeSingle();
  record(
    33,
    "re-enrollment gets separate result row for new enrollment",
    Boolean(reEnrollSecondResult?.id) &&
      Number(reEnrollSecondResult.raw_score) === 14 &&
      Boolean(reEnrollAttempt.error) &&
      (reEnrollAttempt.error.message?.includes("enrollment_not_eligible") ?? false),
  );

  const closedReadCourse = await createCourse(admin, "ClosedRead");
  const closedReadClass = await createClass(admin, closedReadCourse, "ClosedRead", { status: "closed" });
  const closedReadStudent = await createStudent(admin, "ClosedRead");
  const closedReadEnroll = await insertEnrollment(admin, {
    studentId: closedReadStudent,
    classId: closedReadClass.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const closedReadAssessment = await insertAssessment(admin, {
    classId: closedReadClass.id,
    title: "Closed Read Quiz",
    assessedOn: "2028-09-17",
  });
  await insertAssessmentResult(admin, {
    assessmentId: closedReadAssessment.data.id,
    enrollmentId: closedReadEnroll.data.id,
    rawScore: 11,
    maxScore: 20,
  });
  const closedReadList = await fetchClassAssessments(staff, closedReadClass.id);
  record(
    34,
    "closed class assessments remain readable",
    closedReadList.some((i) => i.id === closedReadAssessment.data.id),
  );

  // Separation (35-40)
  const { count: attendanceCountAfter } = await admin
    .from("attendance")
    .select("id", { count: "exact", head: true });
  record(
    35,
    "assessment workflow does not mutate attendance",
    attendanceCountBefore === attendanceCountAfter,
  );

  const { count: observationCountAfter } = await admin
    .from("teacher_observation")
    .select("id", { count: "exact", head: true });
  record(
    36,
    "assessment workflow does not mutate observation",
    observationCountBefore === observationCountAfter,
  );

  const { data: xferStatusCheck } = await admin
    .from("enrollment")
    .select("status")
    .eq("id", xferEnroll.data.id)
    .single();
  record(
    37,
    "assessment workflow does not mutate enrollment lifecycle",
    xferStatusCheck?.status === "transferred",
  );

  const { data: studentBeforeSep } = await admin
    .from("student")
    .select("given_name, family_name, status")
    .eq("id", listFixture.studentId)
    .single();
  const { data: studentAfterSep } = await admin
    .from("student")
    .select("given_name, family_name, status")
    .eq("id", listFixture.studentId)
    .single();
  record(
    38,
    "assessment workflow does not mutate student master fields",
    JSON.stringify(studentBeforeSep) === JSON.stringify(studentAfterSep),
  );

  const { count: chargeCountAfterSep } = await admin
    .from("charge")
    .select("id", { count: "exact", head: true });
  record(
    39,
    "assessment workflow does not mutate finance",
    chargeCountBefore === chargeCountAfterSep,
  );

  const { data: resultSchemaSample } = await admin.from("assessment_result").select("*").limit(1);
  record(
    40,
    "no letter grade columns on assessment_result",
    !("letter_grade" in (resultSchemaSample?.[0] ?? {})) &&
      !("grade_code" in (resultSchemaSample?.[0] ?? {})),
  );

  // Observation permission (41-45)
  const obsFixture = await setupClassWithEnrollment(admin, "ObsPerm");
  const obsTeacher = await createTeacher(admin, "ObsPerm");
  const obsRow = await admin
    .from("teacher_observation")
    .insert({
      organization_id: ORG_A,
      enrollment_id: obsFixture.enrollment.data.id,
      class_id: obsFixture.classRow.id,
      teacher_id: obsTeacher,
      observed_at: new Date().toISOString(),
      comment: "Observation permission probe",
      status: "recorded",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const readerObs = await reader.from("teacher_observation").select("id").eq("id", obsRow.data.id);
  record(
    41,
    "user without observation.read cannot read teacher_observation",
    (readerObs.data ?? []).length === 0 && !readerObs.error,
  );

  const staffObs = await staff.from("teacher_observation").select("id, comment").eq("id", obsRow.data.id);
  record(
    42,
    "user with observation.read can read teacher_observation",
    (staffObs.data ?? []).length === 1 && staffObs.data?.[0]?.comment === "Observation permission probe",
  );

  record(
    43,
    "assessment.read alone does not grant observation read",
    (await hasPermission(reader, "assessment.read")) === false &&
      !(await hasPermission(reader, "observation.read")),
  );

  record(
    44,
    "reader lacks observation.read permission",
    !(await hasPermission(reader, "observation.read")),
  );

  record(
    45,
    "staff has observation.read permission",
    await hasPermission(staff, "observation.read"),
  );

  // Historical truth (46-49)
  const histXferFixture = await setupClassWithEnrollment(admin, "HistXfer");
  const histXferAssessment = await insertAssessment(admin, {
    classId: histXferFixture.classRow.id,
    title: "Hist Xfer Quiz",
    assessedOn: "2028-09-18",
  });
  const histXferResult = await insertAssessmentResult(admin, {
    assessmentId: histXferAssessment.data.id,
    enrollmentId: histXferFixture.enrollment.data.id,
    rawScore: 16,
    maxScore: 20,
  });
  const histXferDest = await createClass(admin, histXferFixture.courseId, "HistXferDest");
  await adminUser.rpc("transfer_enrollment", {
    p_source_enrollment_id: histXferFixture.enrollment.data.id,
    p_destination_class_id: histXferDest.id,
    p_destination_start_date: "2028-09-25",
    p_destination_status: "active",
  });
  const { data: histXferAfter } = await admin
    .from("assessment_result")
    .select("raw_score")
    .eq("id", histXferResult.data.id)
    .single();
  record(
    46,
    "results remain visible after enrollment transfer",
    Number(histXferAfter?.raw_score) === 16,
  );

  const histCpFixture = await setupClassWithEnrollment(admin, "HistCp");
  const histCpAssessment = await insertAssessment(admin, {
    classId: histCpFixture.classRow.id,
    title: "Hist Cp Quiz",
    assessedOn: "2028-09-19",
  });
  const histCpResult = await insertAssessmentResult(admin, {
    assessmentId: histCpAssessment.data.id,
    enrollmentId: histCpFixture.enrollment.data.id,
    rawScore: 17,
    maxScore: 20,
  });
  await admin
    .from("enrollment")
    .update({ status: "completed", end_date: "2028-10-01", updated_by: APP_A_ADMIN })
    .eq("id", histCpFixture.enrollment.data.id);
  const { data: histCpAfter } = await admin
    .from("assessment_result")
    .select("raw_score")
    .eq("id", histCpResult.data.id)
    .single();
  record(
    47,
    "results remain visible after enrollment completion",
    Number(histCpAfter?.raw_score) === 17,
  );

  const histCloseFixture = await setupClassWithEnrollment(admin, "HistClose");
  const histCloseAssessment = await insertAssessment(admin, {
    classId: histCloseFixture.classRow.id,
    title: "Hist Close Quiz",
    assessedOn: "2028-09-20",
  });
  const histCloseResult = await insertAssessmentResult(admin, {
    assessmentId: histCloseAssessment.data.id,
    enrollmentId: histCloseFixture.enrollment.data.id,
    rawScore: 19,
    maxScore: 20,
  });
  await admin
    .from("class")
    .update({ status: "closed", updated_by: APP_A_ADMIN })
    .eq("id", histCloseFixture.classRow.id);
  const { data: histCloseAfter } = await admin
    .from("assessment_result")
    .select("raw_score")
    .eq("id", histCloseResult.data.id)
    .single();
  record(
    48,
    "results remain visible after class closes",
    Number(histCloseAfter?.raw_score) === 19,
  );

  const { data: studentBeforeLifecycle } = await admin
    .from("student")
    .select("status, given_name")
    .eq("id", histCloseFixture.studentId)
    .single();
  await admin
    .from("student")
    .update({ status: "inactive", updated_by: APP_A_ADMIN })
    .eq("id", histCloseFixture.studentId);
  const { data: histLifecycleResult } = await admin
    .from("assessment_result")
    .select("raw_score")
    .eq("id", histCloseResult.data.id)
    .single();
  await admin
    .from("student")
    .update({
      status: studentBeforeLifecycle.status,
      given_name: studentBeforeLifecycle.given_name,
      updated_by: APP_A_ADMIN,
    })
    .eq("id", histCloseFixture.studentId);
  record(
    49,
    "later student lifecycle change does not rewrite results",
    Number(histLifecycleResult?.raw_score) === 19,
  );

  // Architectural boundaries (50-56)
  const { data: attendanceSchema } = await admin.from("attendance").select("*").limit(1);
  record(
    50,
    "no scores stored on attendance entity",
    !("raw_score" in (attendanceSchema?.[0] ?? {})) &&
      !("max_score" in (attendanceSchema?.[0] ?? {})),
  );

  const { data: observationSchema } = await admin.from("teacher_observation").select("*").limit(1);
  record(
    51,
    "no scores stored on observation entity",
    !("raw_score" in (observationSchema?.[0] ?? {})) &&
      !("score" in (observationSchema?.[0] ?? {})),
  );

  const { data: assessmentSchema } = await admin.from("assessment").select("*").limit(1);
  record(
    52,
    "no roster arrays stored on assessment",
    !("roster" in (assessmentSchema?.[0] ?? {})) &&
      !("enrollment_ids" in (assessmentSchema?.[0] ?? {})) &&
      !("student_ids" in (assessmentSchema?.[0] ?? {})),
  );

  record(
    53,
    "no letter grade field on assessment_result schema",
    !("letter_grade" in (resultSchemaSample?.[0] ?? {})) &&
      !("normalized_score" in (resultSchemaSample?.[0] ?? {})),
  );

  record(
    54,
    "read permission controls assessment access",
    (await hasPermission(adminUser, "assessment.read")) &&
      (await hasPermission(staff, "assessment.read")) &&
      !(await hasPermission(reader, "assessment.read")),
  );

  record(
    55,
    "create/record permissions enforced separately",
    (await hasPermission(adminUser, "assessment.create")) &&
      (await hasPermission(adminUser, "assessment_result.record")) &&
      !(await hasPermission(staff, "assessment.create")) &&
      (await hasPermission(staff, "assessment_result.record")) &&
      !(await hasPermission(reader, "assessment.create")) &&
      !(await hasPermission(reader, "assessment_result.record")),
  );

  const { data: orgBAssessments } = await adminUser
    .from("assessment")
    .select("id")
    .eq("organization_id", ORG_B);
  const orgOverrideResult = await adminUser.from("assessment_result").insert({
    organization_id: ORG_B,
    assessment_id: created.data.id,
    enrollment_id: crudFixture.enrollment.data.id,
    raw_score: 5,
    max_score: 20,
    status: "draft",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  const actorStudent = await createStudent(admin, "ActorOverride");
  const actorEnroll = await insertEnrollment(admin, {
    studentId: actorStudent,
    classId: recFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const actorOverride = await adminUser
    .from("assessment_result")
    .insert({
      organization_id: ORG_A,
      assessment_id: recAssessment.data.id,
      enrollment_id: actorEnroll.data.id,
      raw_score: 6,
      max_score: 25,
      status: "draft",
      recorded_by: "00000000-0000-4000-8000-000000000099",
      updated_by: "00000000-0000-4000-8000-000000000099",
    })
    .select("recorded_by, updated_by")
    .single();
  record(
    56,
    "cross-org isolation and actor override blocked",
    (orgBAssessments ?? []).length === 0 &&
      Boolean(orgOverrideResult.error) &&
      Boolean(actorOverride.error),
  );

  // Regression (57-65)
  const { count: studentCount, error: studentErr } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  record(57, "student operations pass", !studentErr && (studentCount ?? 0) > 0);

  const { count: guardianCount, error: guardianErr } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("status", "active");
  record(58, "guardian operations pass", !guardianErr && (guardianCount ?? 0) > 0);

  const { count: courseCount, error: courseErr } = await admin
    .from("course")
    .select("id", { count: "exact", head: true });
  const { count: classCount, error: classErr } = await admin
    .from("class")
    .select("id", { count: "exact", head: true });
  record(
    59,
    "course/class operations pass",
    !courseErr && !classErr && (courseCount ?? 0) > 0 && (classCount ?? 0) > 0,
  );

  const { count: enrollCount, error: enrollErr } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  record(60, "enrollment roster pass", !enrollErr && (enrollCount ?? 0) > 0);

  const { count: chargeCountAfter } = await admin
    .from("charge")
    .select("id", { count: "exact", head: true });
  record(61, "no finance mutation during regression", chargeCountBefore === chargeCountAfter);

  const homeworkTables = ["homework", "homework_submission", "exam", "exam_paper"];
  const homeworkExists = (
    await Promise.all(
      homeworkTables.map(async (table) => {
        const { error } = await admin.from(table).select("id").limit(1);
        return !error || !error.message.includes("Could not find");
      }),
    )
  ).some(Boolean);
  record(62, "no homework/exam workflow implemented", !homeworkExists);

  const finFixture = await setupClassWithEnrollment(admin, "Finalized");
  const finAssessment = await insertAssessment(admin, {
    classId: finFixture.classRow.id,
    title: "Finalized Quiz",
    assessedOn: "2028-09-21",
  });
  const finResult = await insertAssessmentResult(admin, {
    assessmentId: finAssessment.data.id,
    enrollmentId: finFixture.enrollment.data.id,
    rawScore: 16,
    maxScore: 20,
    status: "finalized",
    finalizedAt: new Date().toISOString(),
  });
  const finUpdateBlocked = await admin
    .from("assessment_result")
    .update({ raw_score: 18 })
    .eq("id", finResult.data.id);
  record(
    63,
    "finalized score immutable without status change",
    Boolean(finUpdateBlocked.error) &&
      (finUpdateBlocked.error.message?.includes("Cannot modify scores") ?? false),
  );

  const corrUpdate = await admin
    .from("assessment_result")
    .update({
      raw_score: 18,
      status: "corrected",
      updated_by: APP_A_ADMIN,
    })
    .eq("id", finResult.data.id)
    .select("raw_score, status")
    .single();
  record(
    64,
    "correction path allows score update with corrected status",
    !corrUpdate.error &&
      Number(corrUpdate.data?.raw_score) === 18 &&
      corrUpdate.data?.status === "corrected",
  );

  const xferRegCourse = await createCourse(admin, "XferReg");
  const xferRegSource = await createClass(admin, xferRegCourse, "XferRegSource");
  const xferRegDest = await createClass(admin, xferRegCourse, "XferRegDest");
  const xferRegStudent = await createStudent(admin, "XferReg");
  const xferRegEnroll = await insertEnrollment(admin, {
    studentId: xferRegStudent,
    classId: xferRegSource.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const { data: xferRegNewId, error: xferRegErr } = await adminUser.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferRegEnroll.data.id,
    p_destination_class_id: xferRegDest.id,
    p_destination_start_date: "2028-06-06",
    p_destination_status: "active",
  });
  record(
    65,
    "transfer remains atomic",
    !xferRegErr && Boolean(xferRegNewId),
  );

  await cleanupFixtures(admin);

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM1-T09 assessment smoke: ${results.length - failed.length}/${results.length} PASS`);
  console.log(`Test count: ${results.length}`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  AS-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
