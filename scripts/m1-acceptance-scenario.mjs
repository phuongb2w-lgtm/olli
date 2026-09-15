#!/usr/bin/env node
/**
 * M1-T11 vertical-slice acceptance scenario (AC-1 through AC-19).
 * Chains student → guardian → course/class → enrollment → teaching → session →
 * attendance/observation → assessment → reports → transfer → history preservation.
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
const APP_A_ADMIN = "a1000000-0000-4000-8000-000000000001";

const results = [];
const cleanup = {
  studentIds: [],
  guardianIds: [],
  courseIds: [],
  classIds: [],
  teacherIds: [],
  scheduleIds: [],
  sessionIds: [],
  assessmentIds: [],
};

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} AC-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

async function cleanupFixtures(admin) {
  if (cleanup.assessmentIds.length) {
    await admin.from("assessment_result").delete().in("assessment_id", cleanup.assessmentIds);
    await admin.from("assessment").delete().in("id", cleanup.assessmentIds);
  }
  if (cleanup.sessionIds.length) {
    await admin.from("attendance").delete().in("teaching_session_id", cleanup.sessionIds);
    await admin.from("teacher_observation").delete().in("teaching_session_id", cleanup.sessionIds);
    await admin.from("teaching_session").delete().in("id", cleanup.sessionIds);
  }
  if (cleanup.scheduleIds.length) {
    await admin.from("class_schedule").delete().in("id", cleanup.scheduleIds);
  }
  if (cleanup.classIds.length) {
    await admin.from("enrollment").delete().in("class_id", cleanup.classIds);
    await admin.from("class_teacher_assignment").delete().in("class_id", cleanup.classIds);
    await admin.from("class").delete().in("id", cleanup.classIds);
  }
  if (cleanup.studentIds.length) {
    await admin.from("student_guardian").delete().in("student_id", cleanup.studentIds);
    await admin.from("student").delete().in("id", cleanup.studentIds);
  }
  if (cleanup.guardianIds.length) {
    await admin.from("guardian").delete().in("id", cleanup.guardianIds);
  }
  if (cleanup.courseIds.length) {
    await admin.from("course").delete().in("id", cleanup.courseIds);
  }
  if (cleanup.teacherIds.length) {
    await admin.from("teacher").delete().in("id", cleanup.teacherIds);
  }
}

async function main() {
  const admin = createServiceAdmin();
  const adminUser = await signIn("org-a-admin@olli.local");
  const ts = Date.now();
  const ctx = {};
  try {

  // AC-1: Create Student
  const { data: student, error: studentErr } = await admin
    .from("student")
    .insert({
      organization_id: ORG_A,
      given_name: "Accept",
      family_name: `Slice${ts}`,
      student_code: `AC${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, student_code")
    .single();
  record(1, "create student", !studentErr && Boolean(student?.id));
  cleanup.studentIds.push(student.id);
  ctx.studentId = student.id;

  // AC-2: Create Guardian
  const { data: guardian, error: guardianErr } = await admin
    .from("guardian")
    .insert({
      organization_id: ORG_A,
      given_name: "Guardian",
      family_name: `Slice${ts}`,
      email: `ac-guardian-${ts}@example.local`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  record(2, "create guardian", !guardianErr && Boolean(guardian?.id));
  cleanup.guardianIds.push(guardian.id);

  // AC-3: Link Guardian
  const { error: linkErr } = await admin.from("student_guardian").insert({
    organization_id: ORG_A,
    student_id: student.id,
    guardian_id: guardian.id,
    relationship_type: "mother",
    is_primary_contact: true,
    is_billing_contact: false,
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(3, "link guardian to student", !linkErr);

  // AC-4: Create Course
  const { data: course, error: courseErr } = await admin
    .from("course")
    .insert({
      organization_id: ORG_A,
      code: `AC-C-${ts}`,
      name: `Acceptance Course ${ts}`,
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  record(4, "create course", !courseErr && Boolean(course?.id));
  cleanup.courseIds.push(course.id);

  // AC-5: Create Class A
  const { data: classA, error: classAErr } = await admin
    .from("class")
    .insert({
      organization_id: ORG_A,
      course_id: course.id,
      name: `Acceptance Class A ${ts}`,
      status: "active",
      term_start_date: "2028-06-01",
      term_end_date: "2028-12-31",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  record(5, "create class", !classAErr && Boolean(classA?.id));
  cleanup.classIds.push(classA.id);
  ctx.classAId = classA.id;

  // AC-6: Enroll Student
  const { data: enrollmentA, error: enrollErr } = await admin
    .from("enrollment")
    .insert({
      organization_id: ORG_A,
      student_id: student.id,
      class_id: classA.id,
      start_date: "2028-06-01",
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  record(6, "enroll student in class", !enrollErr && Boolean(enrollmentA?.id));
  ctx.enrollmentAId = enrollmentA.id;

  // AC-7: Assign Teacher
  const { data: teacherRow } = await admin
    .from("teacher")
    .select("id")
    .eq("organization_id", ORG_A)
    .limit(1)
    .single();
  const teacherId = teacherRow.id;
  const { error: assignErr } = await admin.from("class_teacher_assignment").insert({
    organization_id: ORG_A,
    class_id: classA.id,
    teacher_id: teacherId,
    role_code: "primary",
    effective_from: "2028-06-01",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(7, "assign teacher to class", !assignErr);

  // AC-8: Configure recurring schedule
  const { data: schedule, error: scheduleErr } = await admin
    .from("class_schedule")
    .insert({
      organization_id: ORG_A,
      class_id: classA.id,
      teacher_id: teacherId,
      weekday_code: "mon",
      start_time: "09:00:00",
      end_time: "10:30:00",
      effective_from: "2028-06-01",
      effective_to: "2028-12-31",
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  record(8, "configure recurring schedule", !scheduleErr && Boolean(schedule?.id));
  cleanup.scheduleIds.push(schedule.id);

  // AC-9: Generate TeachingSession
  const { data: genCount, error: genErr } = await adminUser.rpc("generate_teaching_sessions", {
    p_class_schedule_id: schedule.id,
    p_range_start: "2028-09-04",
    p_range_end: "2028-09-04",
  });
  const { data: session } = await admin
    .from("teaching_session")
    .select("id, status, scheduled_start_at, occurrence_date")
    .eq("class_id", classA.id)
    .eq("occurrence_date", "2028-09-04")
    .maybeSingle();
  record(
    9,
    "generate teaching session",
    !genErr && (genCount ?? 0) >= 1 && Boolean(session?.id),
  );
  if (!session?.id) {
    await cleanupFixtures(admin);
    throw new Error(`Session generation failed: ${genErr?.message ?? "no session row"}`);
  }
  cleanup.sessionIds.push(session.id);
  ctx.sessionId = session.id;

  // AC-10: Start session
  const { error: startErr } = await admin
    .from("teaching_session")
    .update({ status: "in_progress", updated_by: APP_A_ADMIN })
    .eq("id", session.id);
  record(10, "start session (in_progress)", !startErr);

  // AC-11: Record Attendance
  const { data: attendance, error: attErr } = await admin
    .from("attendance")
    .insert({
      organization_id: ORG_A,
      enrollment_id: enrollmentA.id,
      teaching_session_id: session.id,
      status: "present",
      recorded_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, status")
    .single();
  record(11, "record attendance", !attErr && attendance?.status === "present");
  if (!attendance?.id) {
    throw new Error(`Attendance insert failed: ${attErr?.message ?? "unknown"}`);
  }
  ctx.attendanceId = attendance.id;

  // AC-12: Record Observation
  const { data: observation, error: obsErr } = await admin
    .from("teacher_observation")
    .insert({
      organization_id: ORG_A,
      enrollment_id: enrollmentA.id,
      class_id: classA.id,
      teacher_id: teacherId,
      teaching_session_id: session.id,
      observed_at: session.scheduled_start_at,
      comment: "Acceptance observation",
      status: "recorded",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  record(12, "record observation", !obsErr && Boolean(observation?.id));
  ctx.observationId = observation.id;

  // AC-13: Complete Session
  const { error: completeErr } = await admin
    .from("teaching_session")
    .update({ status: "completed", updated_by: APP_A_ADMIN })
    .eq("id", session.id);
  record(13, "complete session", !completeErr);

  // AC-14: Create Assessment
  const { data: assessment, error: asmtErr } = await admin
    .from("assessment")
    .insert({
      organization_id: ORG_A,
      class_id: classA.id,
      title: `Acceptance Test ${ts}`,
      assessed_on: "2028-09-04",
      max_score: 20,
      status: "open",
      assessment_type_code: "progress_test",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  record(14, "create assessment", !asmtErr && Boolean(assessment?.id));
  cleanup.assessmentIds.push(assessment.id);
  ctx.assessmentId = assessment.id;

  // AC-15: Record score
  const { data: result, error: scoreErr } = await admin
    .from("assessment_result")
    .insert({
      organization_id: ORG_A,
      assessment_id: assessment.id,
      enrollment_id: enrollmentA.id,
      raw_score: 18,
      max_score: 20,
      status: "finalized",
      recorded_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, raw_score")
    .single();
  record(15, "record assessment score", !scoreErr && Number(result?.raw_score) === 18);
  if (!result?.id) {
    throw new Error(`Assessment result insert failed: ${scoreErr?.message ?? "unknown"}`);
  }
  ctx.resultId = result.id;

  // AC-16: Student progress data exists
  const { data: progressResults } = await admin
    .from("assessment_result")
    .select("id, enrollment_id")
    .eq("enrollment_id", enrollmentA.id);
  const { data: progressAttendance } = await admin
    .from("attendance")
    .select("id")
    .eq("enrollment_id", enrollmentA.id);
  record(
    16,
    "student academic progress source data",
    (progressResults?.length ?? 0) >= 1 && (progressAttendance?.length ?? 0) >= 1,
  );

  // AC-17: Class report source data
  const { count: sessionCount } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_id", classA.id)
    .eq("status", "completed");
  record(17, "class report source data", (sessionCount ?? 0) >= 1);

  // AC-18: Transfer to Class B
  const { data: classB, error: classBErr } = await admin
    .from("class")
    .insert({
      organization_id: ORG_A,
      course_id: course.id,
      name: `Acceptance Class B ${ts}`,
      status: "active",
      term_start_date: "2028-06-01",
      term_end_date: "2028-12-31",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  cleanup.classIds.push(classB.id);
  const { data: newEnrollmentId, error: xferErr } = await adminUser.rpc("transfer_enrollment", {
    p_source_enrollment_id: enrollmentA.id,
    p_destination_class_id: classB.id,
    p_destination_start_date: "2028-10-01",
    p_destination_status: "active",
  });
  record(
    18,
    "transfer student to another class",
    !classBErr && !xferErr && Boolean(newEnrollmentId),
  );
  ctx.enrollmentBId = newEnrollmentId;

  // AC-19: Old academic history preserved
  const { data: sourceEnrollment } = await admin
    .from("enrollment")
    .select("status, class_id, end_date")
    .eq("id", enrollmentA.id)
    .single();
  const { data: oldAttendance } = await admin
    .from("attendance")
    .select("id")
    .eq("id", ctx.attendanceId)
    .maybeSingle();
  const { data: oldResult } = await admin
    .from("assessment_result")
    .select("id, enrollment_id")
    .eq("id", ctx.resultId)
    .maybeSingle();
  const { data: oldObservation } = await admin
    .from("teacher_observation")
    .select("id")
    .eq("id", ctx.observationId)
    .maybeSingle();
  record(
    19,
    "old academic history preserved after transfer",
    sourceEnrollment?.status === "transferred" &&
      sourceEnrollment?.class_id === classA.id &&
      Boolean(sourceEnrollment?.end_date) &&
      Boolean(oldAttendance?.id) &&
      oldResult?.enrollment_id === enrollmentA.id &&
      Boolean(oldObservation?.id),
  );

  } finally {
    await cleanupFixtures(admin);
  }

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM1 acceptance scenario: ${results.length - failed.length}/${results.length} PASS`);
  console.log(`Test count: ${results.length}`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  AC-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
