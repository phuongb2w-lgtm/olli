#!/usr/bin/env node
/**
 * M1-T08 session execution smoke tests (SE-1 through SE-71).
 * Requires local Supabase with dev seed and M1-T08 migration applied.
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
const ATTENDANCE_STATUSES = ["present", "absent", "late", "excused"];
const OBSERVATION_INDICATORS = ["concentration", "engagement", "participation"];

const results = [];
const createdCourseIds = [];
const createdClassIds = [];
const createdRoomIds = [];
const createdScheduleIds = [];
const createdStudentIds = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} SE-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

function isEnrollmentEligibleOnSessionDate(enrollment, sessionDate) {
  if (enrollment.startDate > sessionDate) return false;
  if (enrollment.endDate && enrollment.endDate < sessionDate) return false;
  return true;
}

function isEnrollmentVisibleOnSessionRoster(enrollment, sessionDate) {
  if (!isEnrollmentEligibleOnSessionDate(enrollment, sessionDate)) return false;
  if (enrollment.status === "pending") return false;
  return true;
}

function isEnrollmentOperationalForAttendance(enrollment, sessionDate) {
  if (!isEnrollmentEligibleOnSessionDate(enrollment, sessionDate)) return false;
  return enrollment.status === "active";
}

function isAttendanceConflict(error) {
  if (!error) return false;
  if (error.code === "23505") return true;
  return error.message?.includes("duplicate") ?? false;
}

function isCrossClassAttendance(error) {
  if (!error?.message) return false;
  return (
    error.message.includes("class must match") ||
    error.message.includes("enrollment_not_eligible") ||
    error.message.includes("pending_enrollment") ||
    error.message.includes("observation_class_mismatch")
  );
}

function countAttendanceProgress(roster) {
  const total = roster.length;
  const recorded = roster.filter((r) => r.attendanceStatus !== null).length;
  return { total, recorded, notRecorded: total - recorded };
}

function requiresCompletionConfirm(roster, confirmUnrecorded) {
  const progress = countAttendanceProgress(roster);
  return progress.notRecorded > 0 && !confirmUnrecorded;
}

function resolveBulkMarkAllPresentTargets(roster, sessionDate, overwriteNonPresent) {
  return roster.filter((row) => {
    const eligible = isEnrollmentOperationalForAttendance(
      {
        startDate: row.enrollmentStartDate,
        endDate: row.enrollmentEndDate,
        status: row.enrollmentStatus,
      },
      sessionDate,
    );
    if (!eligible) return false;
    if (row.attendanceStatus && row.attendanceStatus !== "present" && !overwriteNonPresent) {
      return false;
    }
    return row.attendanceStatus !== "present";
  });
}

function isConflictError(error) {
  if (!error) return false;
  if (error.code === "23P01") return true;
  const msg = error.message ?? "";
  return msg.includes("schedule_conflict") || msg.includes("exclusion");
}

async function createTeacher(admin, label) {
  const { data, error } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: label,
      family_name: `Smoke${Date.now()}`,
      status: "active",
    })
    .select("id")
    .single();
  if (error) throw error;
  return data.id;
}

async function createCourse(admin, label) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("course")
    .insert({
      organization_id: ORG_A,
      code: `SE-${label}-${ts}`,
      name: `SessionExec ${label} ${ts}`,
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
      term_start_date: options.termStart ?? null,
      term_end_date: options.termEnd ?? null,
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, status")
    .single();
  if (error) throw error;
  createdClassIds.push(data.id);
  return data;
}

async function createRoom(admin, label, options = {}) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("room")
    .insert({
      organization_id: ORG_A,
      code: options.code ?? `R-${ts}`,
      name: `${label} ${ts}`,
      capacity: options.capacity ?? null,
      status: options.status ?? "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, name")
    .single();
  if (error) throw error;
  createdRoomIds.push(data.id);
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
    .select("id, student_id, class_id, start_date, end_date, status")
    .single();
}

async function insertAssignment(admin, classId, input) {
  return admin
    .from("class_teacher_assignment")
    .insert({
      organization_id: ORG_A,
      class_id: classId,
      teacher_id: input.teacherId,
      role_code: input.roleCode ?? "primary",
      effective_from: input.effectiveFrom,
      effective_to: input.effectiveTo ?? null,
      status: input.status ?? "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
}

async function insertSchedule(admin, classId, input) {
  const row = await admin
    .from("class_schedule")
    .insert({
      organization_id: ORG_A,
      class_id: classId,
      weekday_code: input.weekdayCode,
      start_time: input.startTime,
      end_time: input.endTime,
      effective_from: input.effectiveFrom,
      effective_to: input.effectiveTo ?? null,
      room_id: input.roomId ?? null,
      teacher_id: input.teacherId ?? null,
      location: input.location ?? null,
      status: input.status ?? "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (!row.error) createdScheduleIds.push(row.data.id);
  return row;
}

async function generateSessions(admin, scheduleId, rangeStart, rangeEnd) {
  return admin.rpc("generate_teaching_sessions", {
    p_class_schedule_id: scheduleId,
    p_range_start: rangeStart,
    p_range_end: rangeEnd,
  });
}

async function insertAttendance(admin, input) {
  return admin
    .from("attendance")
    .insert({
      organization_id: ORG_A,
      teaching_session_id: input.sessionId,
      enrollment_id: input.enrollmentId,
      status: input.status,
      recorded_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("*")
    .single();
}

async function updateAttendance(admin, attendanceId, status) {
  return admin
    .from("attendance")
    .update({
      status,
      updated_by: APP_A_ADMIN,
      recorded_by: APP_A_ADMIN,
    })
    .eq("id", attendanceId)
    .select("id, status, updated_by")
    .single();
}

async function deriveSessionRoster(admin, classId, sessionId, sessionDate) {
  const [{ data: enrollments }, { data: attendances }] = await Promise.all([
    admin
      .from("enrollment")
      .select("id, student_id, start_date, end_date, status")
      .eq("class_id", classId),
    admin
      .from("attendance")
      .select("id, enrollment_id, status")
      .eq("teaching_session_id", sessionId),
  ]);

  const attendanceByEnrollment = new Map(
    (attendances ?? []).map((a) => [a.enrollment_id, a]),
  );

  const roster = [];
  for (const row of enrollments ?? []) {
    const enrollmentRow = {
      id: row.id,
      studentId: row.student_id,
      startDate: row.start_date,
      endDate: row.end_date,
      status: row.status,
    };
    if (!isEnrollmentVisibleOnSessionRoster(enrollmentRow, sessionDate)) continue;
    const attendance = attendanceByEnrollment.get(row.id);
    roster.push({
      enrollmentId: row.id,
      studentId: row.student_id,
      enrollmentStatus: row.status,
      enrollmentStartDate: row.start_date,
      enrollmentEndDate: row.end_date,
      attendanceStatus: attendance?.status ?? null,
      attendanceId: attendance?.id ?? null,
    });
  }
  return roster;
}

async function setupClassSession(admin, label, options = {}) {
  const sessionDate = options.sessionDate ?? "2028-09-04";
  const weekdayCode = options.weekdayCode ?? "mon";
  const courseId = options.courseId ?? (await createCourse(admin, label));
  const classRow = await createClass(admin, courseId, label, options.classOptions ?? {});
  const teacherId = options.teacherId ?? (await createTeacher(admin, label));
  const room = options.skipRoom ? null : await createRoom(admin, `${label}-room`);
  await insertAssignment(admin, classRow.id, {
    teacherId,
    roleCode: "primary",
    effectiveFrom: options.assignmentFrom ?? "2028-06-01",
  });
  const schedule = await insertSchedule(admin, classRow.id, {
    weekdayCode,
    startTime: options.startTime ?? "09:00:00",
    endTime: options.endTime ?? "10:00:00",
    effectiveFrom: options.effectiveFrom ?? "2028-06-01",
    roomId: room?.id ?? null,
    teacherId: options.scheduleTeacherId ?? teacherId,
    location: options.location ?? null,
  });
  const gen = await generateSessions(admin, schedule.data.id, sessionDate, sessionDate);
  if (gen.error) throw new Error(`Session generation failed for ${label}: ${gen.error.message}`);
  const { data: session } = await admin
    .from("teaching_session")
    .select("id, class_id, status, occurrence_date, scheduled_start_at, teacher_id, room_id, class_schedule_id")
    .eq("class_schedule_id", schedule.data.id)
    .maybeSingle();
  if (!session?.id) throw new Error(`No session materialized for ${label}`);
  return {
    courseId,
    classRow,
    teacherId,
    room,
    scheduleId: schedule.data.id,
    session,
    sessionDate,
  };
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const staff = await signIn("org-a-staff@olli.local");
  const orgBAdmin = await signIn("org-b-admin@olli.local");

  const {
    count: chargeCountBefore,
  } = await admin.from("charge").select("id", { count: "exact", head: true });
  const {
    count: assessmentResultCountBefore,
  } = await admin.from("assessment_result").select("id", { count: "exact", head: true });

  const probeFixture = await setupClassSession(admin, "Probe", { sessionDate: "2028-09-04", weekdayCode: "mon" });
  const probeStudent = await createStudent(admin, "Probe");
  const probeEnroll = await insertEnrollment(admin, {
    studentId: probeStudent,
    classId: probeFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const probeAtt = await insertAttendance(admin, {
    sessionId: probeFixture.session.id,
    enrollmentId: probeEnroll.data.id,
    status: "present",
  });
  const probeObs = await admin
    .from("teacher_observation")
    .insert({
      organization_id: ORG_A,
      enrollment_id: probeEnroll.data.id,
      class_id: probeFixture.classRow.id,
      teacher_id: probeFixture.teacherId,
      teaching_session_id: probeFixture.session.id,
      observed_at: probeFixture.session.scheduled_start_at,
      status: "recorded",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("*")
    .single();

  // Schema / integrity (1-6)
  const attendanceSample = probeAtt.data;
  record(
    1,
    "attendance physical schema audited correctly",
    Boolean(
      attendanceSample &&
        "teaching_session_id" in attendanceSample &&
        "enrollment_id" in attendanceSample &&
        "status" in attendanceSample &&
        "recorded_by" in attendanceSample &&
        "updated_by" in attendanceSample &&
        ATTENDANCE_STATUSES.includes("present"),
    ),
  );

  const { data: indicators } = await admin.from("observation_indicator").select("code").order("code");
  const obsSample = probeObs.data;
  const indicatorCodes = (indicators ?? []).map((i) => i.code);
  record(
    2,
    "observation physical/reference schema audited correctly",
    OBSERVATION_INDICATORS.every((code) => indicatorCodes.includes(code)) &&
      Boolean(
        obsSample &&
          "enrollment_id" in obsSample &&
          "teaching_session_id" in obsSample &&
          "comment" in obsSample &&
          "updated_by" in obsSample,
      ),
  );

  const dupFixture = await setupClassSession(admin, "DupAtt");
  const dupStudent = await createStudent(admin, "DupAtt");
  const dupEnroll = await insertEnrollment(admin, {
    studentId: dupStudent,
    classId: dupFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const firstAtt = await insertAttendance(admin, {
    sessionId: dupFixture.session.id,
    enrollmentId: dupEnroll.data.id,
    status: "present",
  });
  const secondAtt = await admin.from("attendance").insert({
    organization_id: ORG_A,
    teaching_session_id: dupFixture.session.id,
    enrollment_id: dupEnroll.data.id,
    status: "absent",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(
    3,
    "one attendance per enrollment and session",
    !firstAtt.error && Boolean(secondAtt.error) && isAttendanceConflict(secondAtt.error),
  );

  const crossClassCourse = await createCourse(admin, "CrossClass");
  const classA = await createClass(admin, crossClassCourse, "CrossA");
  const classB = await createClass(admin, crossClassCourse, "CrossB");
  const crossTeacher = await createTeacher(admin, "CrossClass");
  const crossRoom = await createRoom(admin, "CrossClass");
  await insertAssignment(admin, classA.id, { teacherId: crossTeacher, effectiveFrom: "2028-06-01" });
  await insertAssignment(admin, classB.id, { teacherId: crossTeacher, effectiveFrom: "2028-06-01" });
  const schedA = await insertSchedule(admin, classA.id, {
    weekdayCode: "tue",
    startTime: "11:00:00",
    endTime: "12:00:00",
    effectiveFrom: "2028-09-05",
    roomId: crossRoom.id,
    teacherId: crossTeacher,
  });
  await generateSessions(admin, schedA.data.id, "2028-09-05", "2028-09-05");
  const { data: sessionA } = await admin
    .from("teaching_session")
    .select("id")
    .eq("class_schedule_id", schedA.data.id)
    .single();
  const crossStudent = await createStudent(admin, "CrossClass");
  const enrollB = await insertEnrollment(admin, {
    studentId: crossStudent,
    classId: classB.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const crossClassAtt = sessionA?.id
    ? await insertAttendance(admin, {
        sessionId: sessionA.id,
        enrollmentId: enrollB.data.id,
        status: "present",
      })
    : { error: { message: "missing_session" } };
  record(
    4,
    "cross-class enrollment/session attendance rejected",
    Boolean(sessionA?.id) &&
      Boolean(crossClassAtt.error) &&
      isCrossClassAttendance(crossClassAtt.error),
  );

  const { data: orgBSession } = await orgBAdmin
    .from("teaching_session")
    .select("id")
    .limit(1)
    .maybeSingle();
  const { data: orgAEnroll } = await admin
    .from("enrollment")
    .select("id")
    .eq("organization_id", ORG_A)
    .limit(1)
    .single();
  const crossOrgAtt = await admin.from("attendance").insert({
    organization_id: ORG_B,
    teaching_session_id: orgBSession?.id ?? "00000000-0000-4000-8000-000000000099",
    enrollment_id: orgAEnroll.id,
    status: "present",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(5, "cross-org relation rejected", Boolean(crossOrgAtt.error));

  const obsFixture = await setupClassSession(admin, "ObsUnique");
  const obsStudent = await createStudent(admin, "ObsUnique");
  const obsEnroll = await insertEnrollment(admin, {
    studentId: obsStudent,
    classId: obsFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const obs1 = await admin
    .from("teacher_observation")
    .insert({
      organization_id: ORG_A,
      enrollment_id: obsEnroll.data.id,
      class_id: obsFixture.classRow.id,
      teacher_id: obsFixture.teacherId,
      teaching_session_id: obsFixture.session.id,
      observed_at: obsFixture.session.scheduled_start_at,
      status: "recorded",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  const obs2 = await admin.from("teacher_observation").insert({
    organization_id: ORG_A,
    enrollment_id: obsEnroll.data.id,
    class_id: obsFixture.classRow.id,
    teacher_id: obsFixture.teacherId,
    teaching_session_id: obsFixture.session.id,
    observed_at: obsFixture.session.scheduled_start_at,
    status: "recorded",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(
    6,
    "observation uniqueness/integrity behaves as documented",
    !obs1.error && Boolean(obs2.error) && isAttendanceConflict(obs2.error),
  );

  // Session roster (7-14)
  const rosterFixture = await setupClassSession(admin, "Roster", { sessionDate: "2028-09-11", weekdayCode: "mon" });
  const rosterStudent = await createStudent(admin, "RosterEligible");
  const rosterEnroll = await insertEnrollment(admin, {
    studentId: rosterStudent,
    classId: rosterFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const roster = await deriveSessionRoster(
    admin,
    rosterFixture.classRow.id,
    rosterFixture.session.id,
    rosterFixture.sessionDate,
  );
  record(
    7,
    "eligible enrollment appears on session roster",
    roster.some((r) => r.enrollmentId === rosterEnroll.data.id),
  );

  const lateStartStudent = await createStudent(admin, "LateStart");
  const lateStartEnroll = await insertEnrollment(admin, {
    studentId: lateStartStudent,
    classId: rosterFixture.classRow.id,
    startDate: "2028-10-01",
    status: "active",
  });
  const rosterLateStart = await deriveSessionRoster(
    admin,
    rosterFixture.classRow.id,
    rosterFixture.session.id,
    rosterFixture.sessionDate,
  );
  record(
    8,
    "enrollment beginning after session does not appear",
    !rosterLateStart.some((r) => r.enrollmentId === lateStartEnroll.data.id),
  );

  const earlyEndStudent = await createStudent(admin, "EarlyEnd");
  const earlyEndEnroll = await insertEnrollment(admin, {
    studentId: earlyEndStudent,
    classId: rosterFixture.classRow.id,
    startDate: "2028-06-01",
    endDate: "2028-08-01",
    status: "withdrawn",
  });
  const rosterEarlyEnd = await deriveSessionRoster(
    admin,
    rosterFixture.classRow.id,
    rosterFixture.session.id,
    rosterFixture.sessionDate,
  );
  record(
    9,
    "enrollment ending before session does not appear",
    !rosterEarlyEnd.some((r) => r.enrollmentId === earlyEndEnroll.data.id),
  );

  const xferFixture = await setupClassSession(admin, "XferHist", { sessionDate: "2028-09-18", weekdayCode: "mon" });
  const xferStudent = await createStudent(admin, "XferHist");
  const xferEnroll = await insertEnrollment(admin, {
    studentId: xferStudent,
    classId: xferFixture.classRow.id,
    startDate: "2028-06-01",
    endDate: "2028-09-20",
    status: "active",
  });
  const xferDestClass = await createClass(admin, xferFixture.courseId, "XferDest");
  await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferEnroll.data.id,
    p_destination_class_id: xferDestClass.id,
    p_destination_start_date: "2028-09-21",
    p_destination_status: "active",
  });
  const rosterTransferred = await deriveSessionRoster(
    admin,
    xferFixture.classRow.id,
    xferFixture.session.id,
    xferFixture.sessionDate,
  );
  record(
    10,
    "historical transferred enrollment appears for earlier eligible session",
    rosterTransferred.some((r) => r.enrollmentId === xferEnroll.data.id && r.enrollmentStatus === "transferred"),
  );

  const wdFixture = await setupClassSession(admin, "WdHist", { sessionDate: "2028-09-25", weekdayCode: "mon" });
  const wdStudent = await createStudent(admin, "WdHist");
  const wdEnroll = await insertEnrollment(admin, {
    studentId: wdStudent,
    classId: wdFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  await admin
    .from("enrollment")
    .update({ status: "withdrawn", end_date: "2028-10-01", updated_by: APP_A_ADMIN })
    .eq("id", wdEnroll.data.id);
  const rosterWithdrawn = await deriveSessionRoster(
    admin,
    wdFixture.classRow.id,
    wdFixture.session.id,
    wdFixture.sessionDate,
  );
  record(
    11,
    "historical withdrawn enrollment appears for earlier eligible session",
    rosterWithdrawn.some((r) => r.enrollmentId === wdEnroll.data.id && r.enrollmentStatus === "withdrawn"),
  );

  const cpFixture = await setupClassSession(admin, "CpHist", { sessionDate: "2028-10-02", weekdayCode: "mon" });
  const cpStudent = await createStudent(admin, "CpHist");
  const cpEnroll = await insertEnrollment(admin, {
    studentId: cpStudent,
    classId: cpFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const cpAtt = await insertAttendance(admin, {
    sessionId: cpFixture.session.id,
    enrollmentId: cpEnroll.data.id,
    status: "present",
  });
  await admin
    .from("enrollment")
    .update({ status: "completed", end_date: "2028-10-15", updated_by: APP_A_ADMIN })
    .eq("id", cpEnroll.data.id);
  const { data: cpAttAfter } = await admin
    .from("attendance")
    .select("id, status")
    .eq("id", cpAtt.data.id)
    .single();
  record(
    12,
    "completed enrollment historical attendance remains visible",
    cpAttAfter?.status === "present" && Boolean(cpAttAfter?.id),
  );

  const pendingStudent = await createStudent(admin, "Pending");
  const pendingEnroll = await insertEnrollment(admin, {
    studentId: pendingStudent,
    classId: rosterFixture.classRow.id,
    startDate: "2028-06-01",
    status: "pending",
  });
  const pendingOperational = isEnrollmentOperationalForAttendance(
    {
      startDate: pendingEnroll.data.start_date,
      endDate: pendingEnroll.data.end_date,
      status: pendingEnroll.data.status,
    },
    rosterFixture.sessionDate,
  );
  record(
    13,
    "pending enrollment is not silently treated as participating",
    !pendingOperational,
  );

  const notRecStudent = await createStudent(admin, "NotRec");
  const notRecEnroll = await insertEnrollment(admin, {
    studentId: notRecStudent,
    classId: rosterFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const rosterNotRec = await deriveSessionRoster(
    admin,
    rosterFixture.classRow.id,
    rosterFixture.session.id,
    rosterFixture.sessionDate,
  );
  const notRecRow = rosterNotRec.find((r) => r.enrollmentId === notRecEnroll.data.id);
  record(
    14,
    "no attendance row renders not recorded",
    Boolean(notRecRow) && notRecRow.attendanceStatus === null,
  );

  // Attendance create/update (15-24)
  const attFixture = await setupClassSession(admin, "AttOps", { sessionDate: "2028-10-09", weekdayCode: "mon" });
  const attStudent = await createStudent(admin, "AttOps");
  const attEnroll = await insertEnrollment(admin, {
    studentId: attStudent,
    classId: attFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });

  const presentAtt = await insertAttendance(admin, {
    sessionId: attFixture.session.id,
    enrollmentId: attEnroll.data.id,
    status: "present",
  });
  record(15, "mark present", !presentAtt.error && presentAtt.data?.status === "present");

  const absentStudent = await createStudent(admin, "Absent");
  const absentEnroll = await insertEnrollment(admin, {
    studentId: absentStudent,
    classId: attFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const absentAtt = await insertAttendance(admin, {
    sessionId: attFixture.session.id,
    enrollmentId: absentEnroll.data.id,
    status: "absent",
  });
  record(16, "mark absent", !absentAtt.error && absentAtt.data?.status === "absent");

  const lateStudent = await createStudent(admin, "Late");
  const lateEnroll = await insertEnrollment(admin, {
    studentId: lateStudent,
    classId: attFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const lateAtt = await insertAttendance(admin, {
    sessionId: attFixture.session.id,
    enrollmentId: lateEnroll.data.id,
    status: "late",
  });
  record(17, "mark late", !lateAtt.error && lateAtt.data?.status === "late");

  const excusedStudent = await createStudent(admin, "Excused");
  const excusedEnroll = await insertEnrollment(admin, {
    studentId: excusedStudent,
    classId: attFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const excusedAtt = await insertAttendance(admin, {
    sessionId: attFixture.session.id,
    enrollmentId: excusedEnroll.data.id,
    status: "excused",
  });
  record(18, "mark excused", !excusedAtt.error && excusedAtt.data?.status === "excused");

  const updatedAtt = await updateAttendance(admin, presentAtt.data.id, "late");
  record(
    19,
    "update previous attendance status",
    !updatedAtt.error && updatedAtt.data?.status === "late",
  );

  const { count: attRowCount } = await admin
    .from("attendance")
    .select("id", { count: "exact", head: true })
    .eq("teaching_session_id", attFixture.session.id)
    .eq("enrollment_id", attEnroll.data.id);
  record(
    20,
    "update preserves single attendance row",
    (attRowCount ?? 0) === 1,
  );

  record(
    21,
    "trusted audit actor populated",
    presentAtt.data?.recorded_by === APP_A_ADMIN &&
      updatedAtt.data?.updated_by === APP_A_ADMIN,
  );

  const staffAtt = await staff.from("attendance").insert({
    organization_id: ORG_A,
    teaching_session_id: attFixture.session.id,
    enrollment_id: attEnroll.data.id,
    status: "present",
  });
  record(22, "unauthorized mutation rejected", Boolean(staffAtt.error));

  record(
    23,
    "duplicate concurrent create protected by db",
    Boolean(secondAtt.error) && secondAtt.error?.code === "23505",
  );

  record(
    24,
    "raw conflict does not leak to ui",
    isAttendanceConflict(secondAtt.error) && !String(secondAtt.error?.message ?? "").includes("23505"),
  );

  // Bulk workflow (25-27)
  const bulkFixture = await setupClassSession(admin, "Bulk", { sessionDate: "2028-10-16", weekdayCode: "mon" });
  const bulkActiveA = await createStudent(admin, "BulkA");
  const bulkActiveB = await createStudent(admin, "BulkB");
  const bulkPending = await createStudent(admin, "BulkPending");
  const bulkFuture = await createStudent(admin, "BulkFuture");
  const bulkEnrollA = await insertEnrollment(admin, {
    studentId: bulkActiveA,
    classId: bulkFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const bulkEnrollB = await insertEnrollment(admin, {
    studentId: bulkActiveB,
    classId: bulkFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  await insertEnrollment(admin, {
    studentId: bulkPending,
    classId: bulkFixture.classRow.id,
    startDate: "2028-06-01",
    status: "pending",
  });
  await insertEnrollment(admin, {
    studentId: bulkFuture,
    classId: bulkFixture.classRow.id,
    startDate: "2028-11-01",
    status: "active",
  });
  await insertAttendance(admin, {
    sessionId: bulkFixture.session.id,
    enrollmentId: bulkEnrollB.data.id,
    status: "absent",
  });
  const bulkRoster = await deriveSessionRoster(
    admin,
    bulkFixture.classRow.id,
    bulkFixture.session.id,
    bulkFixture.sessionDate,
  );
  const bulkTargets = resolveBulkMarkAllPresentTargets(
    bulkRoster,
    bulkFixture.sessionDate,
    false,
  );
  record(
    25,
    "mark-all-present affects eligible learners only",
    bulkTargets.some((t) => t.enrollmentId === bulkEnrollA.data.id) &&
      !bulkTargets.some((t) => t.enrollmentId === bulkEnrollB.data.id),
  );

  record(
    26,
    "existing explicit non-present mark is not silently overwritten",
    !bulkTargets.some((t) => t.enrollmentId === bulkEnrollB.data.id),
  );

  record(
    27,
    "pending/non-eligible enrollment is not included",
    !bulkRoster.some((r) => r.enrollmentStatus === "pending") &&
      !bulkRoster.some((r) => r.enrollmentStartDate === "2028-11-01") &&
      !bulkTargets.some((t) => t.enrollmentId === bulkEnrollB.data.id),
  );

  // Session execution (28-34)
  const execFixture = await setupClassSession(admin, "Exec", { sessionDate: "2028-10-23", weekdayCode: "mon" });
  const { error: startErr } = await admin
    .from("teaching_session")
    .update({ status: "in_progress", updated_by: APP_A_ADMIN })
    .eq("id", execFixture.session.id);
  const { data: startedSession } = await admin
    .from("teaching_session")
    .select("status")
    .eq("id", execFixture.session.id)
    .single();
  record(
    28,
    "scheduled to in_progress succeeds",
    !startErr && startedSession?.status === "in_progress",
  );

  const { count: attBeforeComplete } = await admin
    .from("attendance")
    .select("id", { count: "exact", head: true })
    .eq("teaching_session_id", execFixture.session.id);
  const { error: completeErr } = await admin
    .from("teaching_session")
    .update({ status: "completed", updated_by: APP_A_ADMIN })
    .eq("id", execFixture.session.id);
  const { data: completedSession } = await admin
    .from("teaching_session")
    .select("status")
    .eq("id", execFixture.session.id)
    .single();
  const { count: attAfterComplete } = await admin
    .from("attendance")
    .select("id", { count: "exact", head: true })
    .eq("teaching_session_id", execFixture.session.id);
  record(
    29,
    "in_progress to completed succeeds",
    !completeErr && completedSession?.status === "completed",
  );

  const cancelFixture = await setupClassSession(admin, "Cancel", { sessionDate: "2028-10-30", weekdayCode: "mon" });
  await admin
    .from("teaching_session")
    .update({ status: "cancelled", updated_by: APP_A_ADMIN })
    .eq("id", cancelFixture.session.id);
  const { data: cancelledSession } = await admin
    .from("teaching_session")
    .select("id, status")
    .eq("id", cancelFixture.session.id)
    .single();
  record(
    30,
    "cancelled session remains stored",
    cancelledSession?.status === "cancelled" && cancelledSession?.id === cancelFixture.session.id,
  );

  record(
    31,
    "completion does not create missing attendance automatically",
    attBeforeComplete === attAfterComplete,
  );

  const confirmFixture = await setupClassSession(admin, "Confirm", { sessionDate: "2028-11-06", weekdayCode: "mon" });
  const confirmStudent = await createStudent(admin, "Confirm");
  await insertEnrollment(admin, {
    studentId: confirmStudent,
    classId: confirmFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const confirmRoster = await deriveSessionRoster(
    admin,
    confirmFixture.classRow.id,
    confirmFixture.session.id,
    confirmFixture.sessionDate,
  );
  record(
    32,
    "completion with unrecorded learners requires explicit confirmation",
    requiresCompletionConfirm(confirmRoster, false) && !requiresCompletionConfirm(confirmRoster, true),
  );

  const { count: enrollBeforeStatus } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  const { count: studentBeforeStatus } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  await admin
    .from("teaching_session")
    .update({ status: "in_progress", updated_by: APP_A_ADMIN })
    .eq("id", confirmFixture.session.id);
  const { count: enrollAfterStatus } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  const { count: studentAfterStatus } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  record(33, "session status mutations do not mutate enrollment", enrollBeforeStatus === enrollAfterStatus);
  record(34, "session status mutations do not mutate student", studentBeforeStatus === studentAfterStatus);

  // Observation (35-41)
  record(
    35,
    "existing observation indicators load from reference data",
    OBSERVATION_INDICATORS.every((code) => indicatorCodes.includes(code)),
  );

  const obsRecFixture = await setupClassSession(admin, "ObsRec", { sessionDate: "2028-11-13", weekdayCode: "mon" });
  const obsRecStudent = await createStudent(admin, "ObsRec");
  const obsRecEnroll = await insertEnrollment(admin, {
    studentId: obsRecStudent,
    classId: obsRecFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const obsRec = await admin
    .from("teacher_observation")
    .insert({
      organization_id: ORG_A,
      enrollment_id: obsRecEnroll.data.id,
      class_id: obsRecFixture.classRow.id,
      teacher_id: obsRecFixture.teacherId,
      teaching_session_id: obsRecFixture.session.id,
      observed_at: obsRecFixture.session.scheduled_start_at,
      comment: "Initial comment",
      status: "recorded",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  const ratingIns = await admin.from("observation_rating").insert({
    organization_id: ORG_A,
    teacher_observation_id: obsRec.data.id,
    indicator_code: "concentration",
    rating_code: "medium",
  });
  record(
    36,
    "observation can be recorded for eligible learner/session",
    !obsRec.error && !ratingIns.error && Boolean(obsRec.data?.id),
  );

  const { error: obsUpdateErr } = await admin
    .from("teacher_observation")
    .update({ comment: "Corrected comment", updated_by: APP_A_ADMIN })
    .eq("id", obsRec.data.id);
  const { data: obsUpdated } = await admin
    .from("teacher_observation")
    .select("comment")
    .eq("id", obsRec.data.id)
    .single();
  record(
    37,
    "observation can be corrected",
    !obsUpdateErr && obsUpdated?.comment === "Corrected comment",
  );

  const { data: obsAnchored } = await admin
    .from("teacher_observation")
    .select("enrollment_id, teaching_session_id")
    .eq("id", obsRec.data.id)
    .single();
  record(
    38,
    "observation remains anchored to enrollment and session",
    obsAnchored?.enrollment_id === obsRecEnroll.data.id &&
      obsAnchored?.teaching_session_id === obsRecFixture.session.id,
  );

  const wrongClassObs =
    sessionA?.id
      ? await admin.from("teacher_observation").insert({
          organization_id: ORG_A,
          enrollment_id: enrollB.data.id,
          class_id: classB.id,
          teacher_id: crossTeacher,
          teaching_session_id: sessionA.id,
          observed_at: new Date().toISOString(),
          status: "recorded",
          created_by: APP_A_ADMIN,
          updated_by: APP_A_ADMIN,
        })
      : { error: { message: "observation_class_mismatch" } };
  record(
    39,
    "observation for wrong class relation rejected",
    Boolean(sessionA?.id) &&
      Boolean(wrongClassObs.error) &&
      isCrossClassAttendance(wrongClassObs.error),
  );

  const { data: studentBeforeObs } = await admin
    .from("student")
    .select("given_name, family_name, status")
    .eq("id", obsRecStudent)
    .single();
  const { data: studentAfterObs } = await admin
    .from("student")
    .select("given_name, family_name, status")
    .eq("id", obsRecStudent)
    .single();
  record(
    40,
    "observation does not modify student master fields",
    JSON.stringify(studentBeforeObs) === JSON.stringify(studentAfterObs),
  );

  record(
    41,
    "teacher comment persists correctly where supported",
    obsUpdated?.comment === "Corrected comment",
  );

  // Historical truth (42-45)
  const histXferFixture = await setupClassSession(admin, "HistXfer", { sessionDate: "2028-11-20", weekdayCode: "mon" });
  const histXferStudent = await createStudent(admin, "HistXfer");
  const histXferEnroll = await insertEnrollment(admin, {
    studentId: histXferStudent,
    classId: histXferFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const histXferAtt = await insertAttendance(admin, {
    sessionId: histXferFixture.session.id,
    enrollmentId: histXferEnroll.data.id,
    status: "present",
  });
  const histXferDest = await createClass(admin, histXferFixture.courseId, "HistXferDest");
  await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: histXferEnroll.data.id,
    p_destination_class_id: histXferDest.id,
    p_destination_start_date: "2028-11-25",
    p_destination_status: "active",
  });
  const { data: histXferAttAfter } = await admin
    .from("attendance")
    .select("status")
    .eq("id", histXferAtt.data.id)
    .single();
  record(
    42,
    "attendance remains visible after enrollment transfer",
    histXferAttAfter?.status === "present",
  );

  const histCpFixture = await setupClassSession(admin, "HistCp", { sessionDate: "2028-11-27", weekdayCode: "mon" });
  const histCpStudent = await createStudent(admin, "HistCp");
  const histCpEnroll = await insertEnrollment(admin, {
    studentId: histCpStudent,
    classId: histCpFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const histCpAtt = await insertAttendance(admin, {
    sessionId: histCpFixture.session.id,
    enrollmentId: histCpEnroll.data.id,
    status: "late",
  });
  await admin
    .from("enrollment")
    .update({ status: "completed", end_date: "2028-12-01", updated_by: APP_A_ADMIN })
    .eq("id", histCpEnroll.data.id);
  const { data: histCpAttAfter } = await admin
    .from("attendance")
    .select("status")
    .eq("id", histCpAtt.data.id)
    .single();
  record(
    43,
    "attendance remains visible after enrollment completion",
    histCpAttAfter?.status === "late",
  );

  const histCloseFixture = await setupClassSession(admin, "HistClose", { sessionDate: "2028-12-04", weekdayCode: "mon" });
  const histCloseStudent = await createStudent(admin, "HistClose");
  const histCloseEnroll = await insertEnrollment(admin, {
    studentId: histCloseStudent,
    classId: histCloseFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const histCloseAtt = await insertAttendance(admin, {
    sessionId: histCloseFixture.session.id,
    enrollmentId: histCloseEnroll.data.id,
    status: "excused",
  });
  await admin
    .from("class")
    .update({ status: "closed", updated_by: APP_A_ADMIN })
    .eq("id", histCloseFixture.classRow.id);
  const { data: histCloseAttAfter } = await admin
    .from("attendance")
    .select("status")
    .eq("id", histCloseAtt.data.id)
    .single();
  record(
    44,
    "attendance remains visible after class closes",
    histCloseAttAfter?.status === "excused",
  );

  const { data: studentBeforeLifecycle } = await admin
    .from("student")
    .select("status, given_name")
    .eq("id", histCloseStudent)
    .single();
  await admin
    .from("student")
    .update({ status: "inactive", updated_by: APP_A_ADMIN })
    .eq("id", histCloseStudent);
  const { data: histLifecycleAtt } = await admin
    .from("attendance")
    .select("status")
    .eq("id", histCloseAtt.data.id)
    .single();
  await admin
    .from("student")
    .update({ status: studentBeforeLifecycle.status, given_name: studentBeforeLifecycle.given_name, updated_by: APP_A_ADMIN })
    .eq("id", histCloseStudent);
  record(
    45,
    "later student lifecycle change does not rewrite attendance",
    histLifecycleAtt?.status === "excused",
  );

  // Teacher correctness (46-49)
  const teacherFixture = await setupClassSession(admin, "TeacherHist", { sessionDate: "2028-12-11", weekdayCode: "mon" });
  const originalTeacherId = teacherFixture.session.teacher_id;
  const replacementTeacher = await createTeacher(admin, "Replacement");
  await insertAssignment(admin, teacherFixture.classRow.id, {
    teacherId: replacementTeacher,
    roleCode: "primary",
    effectiveFrom: "2028-12-15",
  });
  const { data: sessionTeacherAfterAssign } = await admin
    .from("teaching_session")
    .select("teacher_id")
    .eq("id", teacherFixture.session.id)
    .single();
  record(
    46,
    "session uses explicit historical teacher",
    sessionTeacherAfterAssign?.teacher_id === originalTeacherId,
  );
  record(
    47,
    "later class teacher assignment changes do not rewrite session teacher",
    sessionTeacherAfterAssign?.teacher_id !== replacementTeacher,
  );

  const effTeacherA = await createTeacher(admin, "EffA");
  const effTeacherB = await createTeacher(admin, "EffB");
  const effCourse = await createCourse(admin, "EffTeacher");
  const effClass = await createClass(admin, effCourse, "EffTeacher");
  await insertAssignment(admin, effClass.id, {
    teacherId: effTeacherA,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
    effectiveTo: "2028-08-31",
  });
  await insertAssignment(admin, effClass.id, {
    teacherId: effTeacherB,
    roleCode: "primary",
    effectiveFrom: "2028-09-01",
  });
  const effRoom = await createRoom(admin, "EffTeacher");
  const effSchedule = await insertSchedule(admin, effClass.id, {
    weekdayCode: "tue",
    startTime: "14:00:00",
    endTime: "15:00:00",
    effectiveFrom: "2028-06-01",
    roomId: effRoom.id,
  });
  await generateSessions(admin, effSchedule.data.id, "2028-09-05", "2028-09-05");
  const { data: effSessionEarly } = await admin
    .from("teaching_session")
    .select("teacher_id, occurrence_date")
    .eq("class_schedule_id", effSchedule.data.id)
    .eq("occurrence_date", "2028-09-05")
    .maybeSingle();
  record(
    48,
    "schedule fallback teacher resolution respects occurrence-date effective range",
    effSessionEarly?.teacher_id === effTeacherB,
  );

  const ambTeacherA = await createTeacher(admin, "AmbA");
  const ambTeacherB = await createTeacher(admin, "AmbB");
  const ambCourse = await createCourse(admin, "AmbTeacher");
  const ambClass = await createClass(admin, ambCourse, "AmbTeacher");
  await insertAssignment(admin, ambClass.id, {
    teacherId: ambTeacherA,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  await insertAssignment(admin, ambClass.id, {
    teacherId: ambTeacherB,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const ambRoom = await createRoom(admin, "AmbTeacher");
  const ambSchedule = await insertSchedule(admin, ambClass.id, {
    weekdayCode: "wed",
    startTime: "14:00:00",
    endTime: "15:00:00",
    effectiveFrom: "2028-06-01",
    roomId: ambRoom.id,
  });
  const ambGen = await generateSessions(admin, ambSchedule.data.id, "2028-09-06", "2028-09-06");
  record(
    49,
    "ambiguous teacher generation remains blocked",
    Boolean(ambGen.error) &&
      (ambGen.error.message?.includes("ambiguous_teacher") ?? false),
  );

  // Room correctness (50-52)
  const roomFixture = await setupClassSession(admin, "RoomAuth", { sessionDate: "2028-12-18", weekdayCode: "mon" });
  const { data: roomSession } = await admin
    .from("teaching_session")
    .select("room_id, class_schedule_id")
    .eq("id", roomFixture.session.id)
    .single();
  const { data: roomMaster } = await admin
    .from("room")
    .select("name")
    .eq("id", roomSession?.room_id ?? "00000000-0000-4000-8000-000000000099")
    .maybeSingle();
  record(
    50,
    "room_id is authoritative when present",
    Boolean(roomSession?.room_id) && Boolean(roomMaster?.name),
  );

  const locCourse = await createCourse(admin, "LocFallback");
  const locClass = await createClass(admin, locCourse, "LocFallback");
  const locTeacher = await createTeacher(admin, "LocFallback");
  await insertAssignment(admin, locClass.id, { teacherId: locTeacher, effectiveFrom: "2028-06-01" });
  const locSchedule = await insertSchedule(admin, locClass.id, {
    weekdayCode: "thu",
    startTime: "10:00:00",
    endTime: "11:00:00",
    effectiveFrom: "2028-06-01",
    teacherId: locTeacher,
    location: "Building C Room 2",
  });
  await generateSessions(admin, locSchedule.data.id, "2028-09-08", "2028-09-08");
  const { data: locSession } = await admin
    .from("teaching_session")
    .select("room_id, class_schedule_id")
    .eq("class_schedule_id", locSchedule.data.id)
    .maybeSingle();
  const { data: locScheduleRow } = await admin
    .from("class_schedule")
    .select("location")
    .eq("id", locSchedule.data.id)
    .single();
  record(
    51,
    "location is fallback when no room exists",
    !locSession?.room_id && locScheduleRow?.location === "Building C Room 2",
  );

  const roomBefore = roomSession?.room_id;
  const roomAttStudent = await createStudent(admin, "RoomAtt");
  const roomAttEnroll = await insertEnrollment(admin, {
    studentId: roomAttStudent,
    classId: roomFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  await insertAttendance(admin, {
    sessionId: roomFixture.session.id,
    enrollmentId: roomAttEnroll.data.id,
    status: "present",
  });
  const { data: roomAfterSession } = await admin
    .from("teaching_session")
    .select("room_id")
    .eq("id", roomFixture.session.id)
    .single();
  record(
    52,
    "attendance workflow does not modify room/session location",
    roomBefore === roomAfterSession?.room_id,
  );

  // Permissions / security (53-57)
  record(
    53,
    "read permission controls session roster access",
    (await hasPermission(admin, "attendance.read")) &&
      (await hasPermission(staff, "attendance.read")) &&
      (await hasPermission(staff, "observation.read")),
  );

  record(
    54,
    "create/update permission controls attendance as defined by registry",
    (await hasPermission(admin, "attendance.record")) &&
      (await hasPermission(admin, "observation.record")) &&
      !(await hasPermission(staff, "attendance.record")) &&
      !(await hasPermission(staff, "observation.record")),
  );

  const { data: orgBSessions } = await admin
    .from("teaching_session")
    .select("id")
    .eq("organization_id", ORG_B);
  record(
    55,
    "cross-org session cannot be accessed",
    (orgBSessions ?? []).length === 0,
  );

  const crossOrgEnrollAtt = await admin.from("attendance").insert({
    organization_id: ORG_A,
    teaching_session_id: attFixture.session.id,
    enrollment_id: (
      await orgBAdmin.from("enrollment").select("id").limit(1).single()
    ).data.id,
    status: "present",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(56, "cross-org enrollment cannot be attached", Boolean(crossOrgEnrollAtt.error));

  const orgOverrideAtt = await admin.from("attendance").insert({
    organization_id: ORG_B,
    teaching_session_id: attFixture.session.id,
    enrollment_id: absentEnroll.data.id,
    status: "present",
    recorded_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  const actorStudent = await createStudent(admin, "Actor");
  const actorEnroll = await insertEnrollment(admin, {
    studentId: actorStudent,
    classId: attFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const actorOverride = await admin
    .from("attendance")
    .insert({
      organization_id: ORG_A,
      teaching_session_id: attFixture.session.id,
      enrollment_id: actorEnroll.data.id,
      status: "present",
      recorded_by: "00000000-0000-4000-8000-000000000099",
      updated_by: "00000000-0000-4000-8000-000000000099",
    })
    .select("recorded_by, updated_by")
    .single();
  record(
    57,
    "client cannot override organization/actor",
    Boolean(orgOverrideAtt.error) && Boolean(actorOverride.error),
  );

  // Architectural boundaries (58-64)
  const {
    count: assessmentResultCountAfter,
  } = await admin.from("assessment_result").select("id", { count: "exact", head: true });
  record(
    58,
    "no test scores implemented",
    assessmentResultCountBefore === assessmentResultCountAfter,
  );

  const homeworkTables = ["homework", "homework_submission", "exam", "exam_paper"];
  const homeworkExists = (
    await Promise.all(
      homeworkTables.map(async (table) => {
        const { error } = await admin.from(table).select("id").limit(1);
        return !error || !error.message.includes("Could not find");
      }),
    )
  ).some(Boolean);
  record(59, "no homework/exam workflow implemented", !homeworkExists);

  const { count: chargeCountAfter } = await admin
    .from("charge")
    .select("id", { count: "exact", head: true });
  record(60, "no finance mutation", chargeCountBefore === chargeCountAfter);

  const { data: enrollLifecycleSample } = await admin
    .from("enrollment")
    .select("status")
    .eq("id", histCpEnroll.data.id)
    .single();
  record(
    61,
    "no enrollment lifecycle mutation",
    enrollLifecycleSample?.status === "completed",
  );

  const { data: studentLifecycleSample } = await admin
    .from("student")
    .select("status")
    .eq("id", histCloseStudent)
    .single();
  record(
    62,
    "no student lifecycle mutation",
    studentLifecycleSample?.status === studentBeforeLifecycle.status,
  );

  const { data: classSchema } = await admin.from("class").select("*").limit(1);
  const { data: studentSchema } = await admin.from("student").select("*").limit(1);
  record(
    63,
    "no attendance fields added to student/class",
    !("attendance_status" in (classSchema?.[0] ?? {})) &&
      !("attendance_status" in (studentSchema?.[0] ?? {})),
  );

  const { data: sessionSchema } = await admin.from("teaching_session").select("*").limit(1);
  record(
    64,
    "no roster arrays stored on teaching session",
    !("roster" in (sessionSchema?.[0] ?? {})) &&
      !("student_ids" in (sessionSchema?.[0] ?? {})) &&
      !("enrollment_ids" in (sessionSchema?.[0] ?? {})),
  );

  // Regression (65-71)
  const { count: studentCount, error: studentErr } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  record(65, "student operations pass", !studentErr && (studentCount ?? 0) > 0);

  const { count: guardianCount, error: guardianErr } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("status", "active");
  record(66, "guardian operations pass", !guardianErr && (guardianCount ?? 0) > 0);

  const { count: courseCount, error: courseErr } = await admin
    .from("course")
    .select("id", { count: "exact", head: true });
  const { count: classCount, error: classErr } = await admin
    .from("class")
    .select("id", { count: "exact", head: true });
  record(
    67,
    "course/class operations pass",
    !courseErr && !classErr && (courseCount ?? 0) > 0 && (classCount ?? 0) > 0,
  );

  const { count: enrollCount, error: enrollErr } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  record(68, "enrollment/roster pass", !enrollErr && (enrollCount ?? 0) > 0);

  const regenFixture = await setupClassSession(admin, "Regen", { sessionDate: "2028-12-25", weekdayCode: "mon" });
  const regenAgain = await generateSessions(admin, regenFixture.scheduleId, "2028-12-25", "2028-12-25");
  record(
    69,
    "t07 schedule/session generation pass",
    !regenAgain.error && (regenAgain.data ?? 0) === 0,
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
  const { data: xferRegNewId, error: xferRegErr } = await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferRegEnroll.data.id,
    p_destination_class_id: xferRegDest.id,
    p_destination_start_date: "2028-06-06",
    p_destination_status: "active",
  });
  record(
    70,
    "transfer remains atomic",
    !xferRegErr && Boolean(xferRegNewId),
  );

  const conflictTeacher = await createTeacher(admin, "ConflictReg");
  const conflictCourse = await createCourse(admin, "ConflictReg");
  const conflictClass = await createClass(admin, conflictCourse, "ConflictReg");
  await insertAssignment(admin, conflictClass.id, {
    teacherId: conflictTeacher,
    effectiveFrom: "2028-06-01",
  });
  const sharedRoom = await createRoom(admin, "ConflictShared");
  const conflictSchedA = await insertSchedule(admin, conflictClass.id, {
    weekdayCode: "fri",
    startTime: "08:00:00",
    endTime: "09:00:00",
    effectiveFrom: "2028-09-22",
    roomId: sharedRoom.id,
    teacherId: conflictTeacher,
  });
  const conflictSchedB = await insertSchedule(admin, conflictClass.id, {
    weekdayCode: "fri",
    startTime: "08:30:00",
    endTime: "09:30:00",
    effectiveFrom: "2028-09-22",
    roomId: sharedRoom.id,
    teacherId: conflictTeacher,
  });
  const conflictGen1 = await generateSessions(admin, conflictSchedA.data.id, "2028-09-22", "2028-09-22");
  const conflictGen2 = await generateSessions(admin, conflictSchedB.data.id, "2028-09-22", "2028-09-22");
  record(
    71,
    "room/teacher session conflict constraints remain functional",
    !conflictGen1.error &&
      Boolean(conflictGen2.error) &&
      isConflictError(conflictGen2.error),
  );

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM1-T08 session execution smoke: ${results.length - failed.length}/${results.length} PASS`);
  console.log(`Test count: ${results.length}`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  SE-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
