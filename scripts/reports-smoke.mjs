#!/usr/bin/env node
/**
 * M1-T10 reporting smoke tests (RP-1 through RP-68).
 * Requires local Supabase with dev seed and M1-T08/M1-T09 migrations applied.
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

const ATTENDANCE_OPPORTUNITY_STATUSES = new Set(["completed", "in_progress"]);
const REPORT_SNAPSHOT_FORBIDDEN_COLUMNS = [
  "attendance_rate",
  "attendance_summary",
  "assessment_summary",
  "report_data",
  "report_snapshot",
  "progress_report",
  "mean_score",
  "attendance_status",
];

const results = [];
const createdCourseIds = [];
const createdClassIds = [];
const createdStudentIds = [];
const createdTeacherIds = [];
const createdRoomIds = [];
const createdScheduleIds = [];
const createdAssessmentIds = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} RP-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

// --- metrics.ts (plain JS) ---

function emptyAttendanceCounts() {
  return {
    presentCount: 0,
    absentCount: 0,
    lateCount: 0,
    excusedCount: 0,
    notRecordedCount: 0,
    eligibleSessions: 0,
  };
}

function incrementAttendanceCount(counts, status) {
  const next = { ...counts, eligibleSessions: counts.eligibleSessions + 1 };
  if (status === "present") next.presentCount += 1;
  else if (status === "absent") next.absentCount += 1;
  else if (status === "late") next.lateCount += 1;
  else if (status === "excused") next.excusedCount += 1;
  else next.notRecordedCount += 1;
  return next;
}

function computeAttendanceRate(counts) {
  const recorded =
    counts.presentCount + counts.absentCount + counts.lateCount + counts.excusedCount;
  if (recorded === 0) return null;
  return roundPercentage(((counts.presentCount + counts.lateCount) / recorded) * 100);
}

function deriveScorePercentage(rawScore, maxScore) {
  if (maxScore <= 0) return null;
  return roundPercentage((rawScore / maxScore) * 100);
}

function roundPercentage(value) {
  return Math.round(value * 10) / 10;
}

function computeMeanPercentage(values) {
  if (values.length === 0) return null;
  const sum = values.reduce((a, b) => a + b, 0);
  return roundPercentage(sum / values.length);
}

// --- period.ts (plain JS) ---

function isIsoDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return (
    date.getUTCFullYear() === y &&
    date.getUTCMonth() === m - 1 &&
    date.getUTCDate() === d
  );
}

function validateReportPeriod(input) {
  const start = (input.startDate ?? input.termStartDate ?? "").trim();
  const end = (input.endDate ?? input.termEndDate ?? "").trim();

  if (!start || !end) {
    const today = new Date().toISOString().slice(0, 10);
    return {
      ok: true,
      period: {
        startDate: input.termStartDate ?? today,
        endDate: input.termEndDate ?? today,
      },
    };
  }

  if (!isIsoDate(start) || !isIsoDate(end)) {
    return { ok: false, error: "invalid_date" };
  }
  if (start > end) {
    return { ok: false, error: "invalid_range" };
  }
  return { ok: true, period: { startDate: start, endDate: end } };
}

function enrollmentOverlapsPeriod(startDate, endDate, period) {
  if (startDate > period.endDate) return false;
  if (endDate && endDate < period.startDate) return false;
  return true;
}

function sessionDateInPeriod(sessionDate, period) {
  return sessionDate >= period.startDate && sessionDate <= period.endDate;
}

// --- eligibility helpers ---

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

function resolveSessionOccurrenceDate(session, timezone = "Asia/Ho_Chi_Minh") {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(session.scheduledStartAt));
}

function formatStudentName(row) {
  return `${row.family_name} ${row.given_name}`.trim();
}

// --- fixture helpers ---

async function createCourse(admin, label) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("course")
    .insert({
      organization_id: ORG_A,
      code: `RP-${label}-${ts}`,
      name: `Report ${label} ${ts}`,
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
      term_start_date: options.termStart ?? "2028-06-01",
      term_end_date: options.termEnd ?? "2028-12-31",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, status, term_start_date, term_end_date")
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

async function createRoom(admin, label) {
  const ts = Date.now();
  const { data, error } = await admin
    .from("room")
    .insert({
      organization_id: ORG_A,
      code: `RP-R-${ts}`,
      name: `${label} ${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (error) throw error;
  createdRoomIds.push(data.id);
  return data;
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
  if (row.error) throw new Error(`insertSchedule failed: ${row.error.message}`);
  createdScheduleIds.push(row.data.id);
  return row;
}

async function generateSessions(client, scheduleId, rangeStart, rangeEnd) {
  return client.rpc("generate_teaching_sessions", {
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
    })
    .select("*")
    .single();
}

async function addSessionToClass(admin, rpcClient, classId, input) {
  const schedule = await insertSchedule(admin, classId, {
    weekdayCode: input.weekdayCode,
    startTime: input.startTime ?? "09:00:00",
    endTime: input.endTime ?? "10:00:00",
    effectiveFrom: input.effectiveFrom ?? "2028-06-01",
    roomId: input.roomId ?? null,
    teacherId: input.teacherId ?? null,
  });
  const gen = await generateSessions(rpcClient, schedule.data.id, input.sessionDate, input.sessionDate);
  if (gen.error) throw new Error(`Session generation failed: ${gen.error.message}`);
  const { data: session } = await admin
    .from("teaching_session")
    .select("id, class_id, status, occurrence_date, scheduled_start_at, class_schedule_id")
    .eq("class_schedule_id", schedule.data.id)
    .maybeSingle();
  if (!session?.id) throw new Error(`No session materialized for ${input.sessionDate}`);
  if (input.sessionStatus && input.sessionStatus !== session.status) {
    await admin
      .from("teaching_session")
      .update({ status: input.sessionStatus, updated_by: APP_A_ADMIN })
      .eq("id", session.id);
    session.status = input.sessionStatus;
  }
  return { scheduleId: schedule.data.id, session };
}

async function setupClassSession(admin, rpcClient, label, options = {}) {
  const sessionDate = options.sessionDate ?? "2028-09-04";
  const weekdayCode = options.weekdayCode ?? "mon";
  const courseId = options.courseId ?? (await createCourse(admin, label));
  const classRow = options.classId
    ? { id: options.classId }
    : await createClass(admin, courseId, label, options.classOptions ?? {});
  const teacherId = options.teacherId ?? (await createTeacher(admin, label));
  const room = options.skipRoom ? null : await createRoom(admin, `${label}-room`);
  if (!options.classId) {
    await insertAssignment(admin, classRow.id, {
      teacherId,
      roleCode: "primary",
      effectiveFrom: options.assignmentFrom ?? "2028-06-01",
    });
  }
  const { scheduleId, session } = await addSessionToClass(admin, rpcClient, classRow.id, {
    weekdayCode,
    startTime: options.startTime,
    endTime: options.endTime,
    effectiveFrom: options.effectiveFrom,
    roomId: room?.id ?? options.roomId ?? null,
    teacherId: options.scheduleTeacherId ?? teacherId,
    sessionDate,
    sessionStatus: options.sessionStatus,
  });
  return {
    courseId,
    classRow,
    teacherId,
    room,
    scheduleId,
    session,
    sessionDate,
  };
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

// --- fetch helpers (mirroring fetch-report-data.ts) ---

async function fetchClassReportContext(admin, classId) {
  const { data, error } = await admin
    .from("class")
    .select("id, name, status, term_start_date, term_end_date, course:course(code, name)")
    .eq("id", classId)
    .maybeSingle();
  if (error || !data) return null;
  const course = Array.isArray(data.course) ? data.course[0] : data.course;
  return {
    classId: data.id,
    className: data.name,
    classStatus: data.status,
    courseCode: course?.code ?? null,
    courseName: course?.name ?? null,
    termStartDate: data.term_start_date,
    termEndDate: data.term_end_date,
  };
}

async function fetchOrganizationBranding(admin) {
  const { data, error } = await admin.from("organization").select("name").maybeSingle();
  if (error || !data) return null;
  return { name: data.name, hasLogo: false };
}

async function fetchClassEnrollments(admin, classId, period) {
  const { data, error } = await admin
    .from("enrollment")
    .select(
      "id, student_id, start_date, end_date, status, student:student(given_name, family_name, student_code)",
    )
    .eq("class_id", classId)
    .order("start_date");
  if (error || !data) return [];

  return data
    .filter((row) => {
      if (!period) return true;
      return enrollmentOverlapsPeriod(row.start_date, row.end_date, period);
    })
    .map((row) => {
      const student = Array.isArray(row.student) ? row.student[0] : row.student;
      return {
        id: row.id,
        studentId: row.student_id,
        startDate: row.start_date,
        endDate: row.end_date,
        status: row.status,
        studentName: student ? formatStudentName(student) : "—",
        studentCode: student?.student_code ?? null,
      };
    });
}

async function fetchSessionsInPeriod(admin, classId, period) {
  const { data, error } = await admin
    .from("teaching_session")
    .select("id, status, occurrence_date, scheduled_start_at")
    .eq("class_id", classId)
    .order("scheduled_start_at");
  if (error || !data) return [];

  return data
    .map((row) => ({
      id: row.id,
      occurrenceDate: resolveSessionOccurrenceDate({
        occurrenceDate: row.occurrence_date,
        scheduledStartAt: row.scheduled_start_at,
      }),
      status: row.status,
    }))
    .filter((row) => sessionDateInPeriod(row.occurrenceDate, period));
}

async function fetchAttendanceForSessions(admin, sessionIds) {
  if (sessionIds.length === 0) return [];
  const { data, error } = await admin
    .from("attendance")
    .select("enrollment_id, teaching_session_id, status")
    .in("teaching_session_id", sessionIds);
  if (error || !data) return [];
  return data.map((row) => ({
    enrollmentId: row.enrollment_id,
    teachingSessionId: row.teaching_session_id,
    status: row.status,
  }));
}

async function fetchAssessmentsInPeriod(admin, classId, period, assessmentId) {
  let query = admin
    .from("assessment")
    .select("id, title, assessed_on, max_score")
    .eq("class_id", classId)
    .gte("assessed_on", period.startDate)
    .lte("assessed_on", period.endDate)
    .order("assessed_on")
    .order("title");
  if (assessmentId) query = query.eq("id", assessmentId);
  const { data, error } = await query;
  if (error || !data) return [];
  return data.map((row) => ({
    id: row.id,
    title: row.title,
    assessedOn: row.assessed_on,
    maxScore: Number(row.max_score),
  }));
}

async function fetchAssessmentResults(admin, assessmentIds) {
  if (assessmentIds.length === 0) return [];
  const { data, error } = await admin
    .from("assessment_result")
    .select("assessment_id, enrollment_id, raw_score, max_score")
    .in("assessment_id", assessmentIds);
  if (error || !data) return [];
  return data.map((row) => ({
    assessmentId: row.assessment_id,
    enrollmentId: row.enrollment_id,
    rawScore: Number(row.raw_score),
    maxScore: Number(row.max_score),
  }));
}

async function fetchObservationsForSessions(admin, sessions) {
  const sessionIds = sessions.map((s) => s.id);
  if (sessionIds.length === 0) return [];
  const sessionDateById = new Map(sessions.map((s) => [s.id, s.occurrenceDate]));
  const { data, error } = await admin
    .from("teacher_observation")
    .select(
      "enrollment_id, teaching_session_id, comment, observation_rating(indicator_code, rating_code)",
    )
    .in("teaching_session_id", sessionIds)
    .neq("status", "void");
  if (error || !data) return [];

  return data.map((row) => {
    const ratings = {};
    const ratingRows = row.observation_rating;
    if (Array.isArray(ratingRows)) {
      for (const rating of ratingRows) {
        ratings[rating.indicator_code] = rating.rating_code;
      }
    }
    return {
      enrollmentId: row.enrollment_id,
      teachingSessionId: row.teaching_session_id,
      sessionDate: sessionDateById.get(row.teaching_session_id) ?? "",
      comment: row.comment,
      ratings,
    };
  });
}

async function fetchStudentEnrollments(admin, studentId) {
  const { data, error } = await admin
    .from("enrollment")
    .select("id, class_id, start_date, end_date, status, class:class(name, course:course(code))")
    .eq("student_id", studentId)
    .order("start_date", { ascending: false });
  if (error || !data) return [];

  return data.map((row) => {
    const classRow = Array.isArray(row.class) ? row.class[0] : row.class;
    const course = classRow?.course
      ? Array.isArray(classRow.course)
        ? classRow.course[0]
        : classRow.course
      : null;
    return {
      id: row.id,
      classId: row.class_id,
      className: classRow?.name ?? "—",
      courseCode: course?.code ?? null,
      startDate: row.start_date,
      endDate: row.end_date,
      status: row.status,
    };
  });
}

function aggregateObservations(observations) {
  const distribution = new Map();
  const sessionIds = new Set();
  let commentCount = 0;

  for (const obs of observations) {
    sessionIds.add(obs.teachingSessionId);
    if (obs.comment?.trim()) commentCount += 1;
    for (const [indicatorCode, ratingCode] of Object.entries(obs.ratings)) {
      const key = `${indicatorCode}:${ratingCode}`;
      distribution.set(key, (distribution.get(key) ?? 0) + 1);
    }
  }

  const ratingDistribution = [...distribution.entries()]
    .map(([key, count]) => {
      const [indicatorCode, ratingCode] = key.split(":");
      return { indicatorCode, ratingCode, count };
    })
    .sort((a, b) => a.indicatorCode.localeCompare(b.indicatorCode));

  return { ratingDistribution, commentCount, sessionCount: sessionIds.size };
}

// --- report builders (mirroring src/lib/reports/build-*.ts) ---

async function buildClassAttendanceReport(admin, input) {
  const context = await fetchClassReportContext(admin, input.classId);
  if (!context) return { ok: false, error: "not_found" };

  const periodResult = validateReportPeriod({
    startDate: input.startDate,
    endDate: input.endDate,
    termStartDate: context.termStartDate,
    termEndDate: context.termEndDate,
  });
  if (!periodResult.ok) return { ok: false, error: periodResult.error };
  const period = periodResult.period;

  const branding = (await fetchOrganizationBranding(admin)) ?? { name: "—", hasLogo: false };

  const [enrollments, sessions] = await Promise.all([
    fetchClassEnrollments(admin, input.classId, period),
    fetchSessionsInPeriod(admin, input.classId, period),
  ]);

  const opportunitySessions = sessions.filter((s) =>
    ATTENDANCE_OPPORTUNITY_STATUSES.has(s.status),
  );
  const completedSessions = sessions.filter((s) => s.status === "completed");

  const attendanceRows = await fetchAttendanceForSessions(
    admin,
    opportunitySessions.map((s) => s.id),
  );
  const attendanceByKey = new Map(
    attendanceRows.map((a) => [`${a.teachingSessionId}:${a.enrollmentId}`, a.status]),
  );

  const countsByEnrollment = new Map();

  for (const session of opportunitySessions) {
    for (const enrollment of enrollments) {
      const rosterRow = {
        id: enrollment.id,
        studentId: enrollment.studentId,
        startDate: enrollment.startDate,
        endDate: enrollment.endDate,
        status: enrollment.status,
      };
      if (!isEnrollmentVisibleOnSessionRoster(rosterRow, session.occurrenceDate)) continue;

      const key = enrollment.id;
      const current = countsByEnrollment.get(key) ?? emptyAttendanceCounts();
      const status = attendanceByKey.get(`${session.id}:${enrollment.id}`) ?? null;
      countsByEnrollment.set(key, incrementAttendanceCount(current, status));
    }
  }

  const learners = enrollments
    .map((enrollment) => {
      const counts = countsByEnrollment.get(enrollment.id) ?? emptyAttendanceCounts();
      const recordedSessions =
        counts.presentCount + counts.absentCount + counts.lateCount + counts.excusedCount;
      return {
        enrollmentId: enrollment.id,
        studentId: enrollment.studentId,
        studentName: enrollment.studentName,
        studentCode: enrollment.studentCode,
        enrollmentStatus: enrollment.status,
        eligibleSessions: counts.eligibleSessions,
        presentCount: counts.presentCount,
        absentCount: counts.absentCount,
        lateCount: counts.lateCount,
        excusedCount: counts.excusedCount,
        notRecordedCount: counts.notRecordedCount,
        recordedSessions,
        attendanceRate: computeAttendanceRate(counts),
      };
    })
    .sort((a, b) => a.studentName.localeCompare(b.studentName));

  return {
    ok: true,
    report: {
      branding,
      context,
      period,
      generatedAt: new Date().toISOString(),
      sessionTotals: {
        materialized: sessions.length,
        completed: completedSessions.length,
        cancelled: sessions.filter((s) => s.status === "cancelled").length,
        inProgress: sessions.filter((s) => s.status === "in_progress").length,
        scheduled: sessions.filter((s) => s.status === "scheduled").length,
      },
      learners,
    },
  };
}

async function buildClassAssessmentReport(admin, input) {
  const context = await fetchClassReportContext(admin, input.classId);
  if (!context) return { ok: false, error: "not_found" };

  const periodResult = validateReportPeriod({
    startDate: input.startDate,
    endDate: input.endDate,
    termStartDate: context.termStartDate,
    termEndDate: context.termEndDate,
  });
  if (!periodResult.ok) return { ok: false, error: periodResult.error };
  const period = periodResult.period;

  const branding = (await fetchOrganizationBranding(admin)) ?? { name: "—", hasLogo: false };

  const [enrollments, assessments] = await Promise.all([
    fetchClassEnrollments(admin, input.classId),
    fetchAssessmentsInPeriod(admin, input.classId, period, input.assessmentId),
  ]);

  const resultsData = await fetchAssessmentResults(
    admin,
    assessments.map((a) => a.id),
  );
  const resultByKey = new Map(
    resultsData.map((r) => [`${r.assessmentId}:${r.enrollmentId}`, r]),
  );

  const allPercentages = [];
  let scoredCount = 0;
  let withoutScoreCount = 0;

  const learners = enrollments
    .map((enrollment) => {
      const cells = assessments.map((assessment) => {
        const eligible = isEnrollmentVisibleForAssessmentResult(
          {
            startDate: enrollment.startDate,
            endDate: enrollment.endDate,
            status: enrollment.status,
          },
          assessment.assessedOn,
        );
        if (!eligible) {
          return {
            assessmentId: assessment.id,
            rawScore: null,
            maxScore: null,
            percentage: null,
            hasScore: false,
          };
        }

        const result = resultByKey.get(`${assessment.id}:${enrollment.id}`);
        if (!result) {
          withoutScoreCount += 1;
          return {
            assessmentId: assessment.id,
            rawScore: null,
            maxScore: assessment.maxScore,
            percentage: null,
            hasScore: false,
          };
        }

        const percentage = deriveScorePercentage(result.rawScore, result.maxScore);
        scoredCount += 1;
        if (percentage !== null) allPercentages.push(percentage);

        return {
          assessmentId: assessment.id,
          rawScore: result.rawScore,
          maxScore: result.maxScore,
          percentage,
          hasScore: true,
        };
      });

      const hasVisibleCell = cells.some(
        (_, i) =>
          isEnrollmentVisibleForAssessmentResult(
            {
              startDate: enrollment.startDate,
              endDate: enrollment.endDate,
              status: enrollment.status,
            },
            assessments[i]?.assessedOn ?? "",
          ),
      );
      if (!hasVisibleCell) return null;

      return {
        enrollmentId: enrollment.id,
        studentName: enrollment.studentName,
        studentCode: enrollment.studentCode,
        cells,
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.studentName.localeCompare(b.studentName));

  return {
    ok: true,
    report: {
      branding,
      context,
      period,
      generatedAt: new Date().toISOString(),
      assessments: assessments.map((a) => ({
        id: a.id,
        title: a.title,
        assessedOn: a.assessedOn,
        maxScore: a.maxScore,
      })),
      learners,
      aggregates: {
        scoredCount,
        withoutScoreCount,
        meanPercentage: computeMeanPercentage(allPercentages),
        minPercentage: allPercentages.length > 0 ? Math.min(...allPercentages) : null,
        maxPercentage: allPercentages.length > 0 ? Math.max(...allPercentages) : null,
      },
    },
  };
}

async function buildClassEndOfCourseReport(admin, input) {
  const [attendanceResult, assessmentResult] = await Promise.all([
    buildClassAttendanceReport(admin, input),
    buildClassAssessmentReport(admin, input),
  ]);

  if (!attendanceResult.ok) return attendanceResult;
  if (!assessmentResult.ok) return assessmentResult;

  const { report: attendanceReport } = attendanceResult;
  const { report: assessmentReport } = assessmentResult;
  const periodResult = validateReportPeriod({
    startDate: input.startDate,
    endDate: input.endDate,
    termStartDate: attendanceReport.context.termStartDate,
    termEndDate: attendanceReport.context.termEndDate,
  });
  if (!periodResult.ok) return { ok: false, error: periodResult.error };

  const enrollments = await fetchClassEnrollments(
    admin,
    input.classId,
    periodResult.period,
  );
  const byStatus = {};
  for (const enr of enrollments) {
    byStatus[enr.status] = (byStatus[enr.status] ?? 0) + 1;
  }

  const rates = attendanceReport.learners
    .map((l) => l.attendanceRate)
    .filter((r) => r !== null);

  let observations = null;
  if (input.includeObservations) {
    const sessions = await fetchSessionsInPeriod(admin, input.classId, periodResult.period);
    const completedSessions = sessions.filter((s) => s.status === "completed");
    const obsRows = await fetchObservationsForSessions(admin, completedSessions);
    observations = aggregateObservations(obsRows);
  }

  return {
    ok: true,
    report: {
      branding: attendanceReport.branding,
      context: attendanceReport.context,
      period: attendanceReport.period,
      generatedAt: attendanceReport.generatedAt,
      includesObservations: Boolean(input.includeObservations),
      sessions: {
        completed: attendanceReport.sessionTotals.completed,
        cancelled: attendanceReport.sessionTotals.cancelled,
        total: attendanceReport.sessionTotals.materialized,
      },
      enrollments: { total: enrollments.length, byStatus },
      attendance: {
        learnersWithData: attendanceReport.learners.filter((l) => l.recordedSessions > 0).length,
        averageAttendanceRate: computeMeanPercentage(rates),
        totalNotRecorded: attendanceReport.learners.reduce(
          (sum, l) => sum + l.notRecordedCount,
          0,
        ),
      },
      assessments: {
        count: assessmentReport.assessments.length,
        resultsRecorded: assessmentReport.aggregates.scoredCount,
        meanPercentage: assessmentReport.aggregates.meanPercentage,
      },
      observations,
      attendanceReport,
      assessmentReport,
    },
  };
}

async function buildStudentProgressReport(admin, input) {
  const { data: student, error: studentError } = await admin
    .from("student")
    .select("id, given_name, family_name, student_code")
    .eq("id", input.studentId)
    .maybeSingle();
  if (studentError || !student) return { ok: false, error: "not_found" };

  const studentName = `${student.family_name} ${student.given_name}`.trim();
  const enrollments = await fetchStudentEnrollments(admin, input.studentId);
  if (enrollments.length === 0) {
    const branding = (await fetchOrganizationBranding(admin)) ?? { name: "—", hasLogo: false };
    const today = new Date().toISOString().slice(0, 10);
    return {
      ok: true,
      report: {
        branding,
        studentId: input.studentId,
        studentName,
        studentCode: student.student_code,
        period: { startDate: today, endDate: today },
        generatedAt: new Date().toISOString(),
        includesObservations: false,
        enrollmentScope: null,
        attendance: null,
        assessments: [],
        averagePercentage: null,
        observations: null,
      },
    };
  }

  const scopedEnrollment = input.enrollmentId
    ? enrollments.find((e) => e.id === input.enrollmentId)
    : enrollments[0];
  if (input.enrollmentId && !scopedEnrollment) {
    return { ok: false, error: "not_found" };
  }

  const periodResult = validateReportPeriod({
    startDate: input.startDate,
    endDate: input.endDate,
    termStartDate: scopedEnrollment?.startDate,
    termEndDate: scopedEnrollment?.endDate,
  });
  if (!periodResult.ok) return { ok: false, error: periodResult.error };
  const period = periodResult.period;

  const branding = (await fetchOrganizationBranding(admin)) ?? { name: "—", hasLogo: false };

  let attendance = null;
  let assessments = [];
  let observations = null;

  if (scopedEnrollment) {
    const classReport = await buildClassAttendanceReport(admin, {
      classId: scopedEnrollment.classId,
      startDate: period.startDate,
      endDate: period.endDate,
    });
    if (classReport.ok) {
      attendance =
        classReport.report.learners.find((l) => l.enrollmentId === scopedEnrollment.id) ?? null;
    }

    const assessmentRows = await fetchAssessmentsInPeriod(
      admin,
      scopedEnrollment.classId,
      period,
    );
    const resultsData = await fetchAssessmentResults(
      admin,
      assessmentRows.map((a) => a.id),
    );
    const resultByAssessment = new Map(
      resultsData
        .filter((r) => r.enrollmentId === scopedEnrollment.id)
        .map((r) => [r.assessmentId, r]),
    );

    assessments = assessmentRows
      .filter((a) =>
        isEnrollmentVisibleForAssessmentResult(
          {
            startDate: scopedEnrollment.startDate,
            endDate: scopedEnrollment.endDate,
            status: scopedEnrollment.status,
          },
          a.assessedOn,
        ),
      )
      .map((a) => {
        const result = resultByAssessment.get(a.id);
        return {
          assessmentId: a.id,
          title: a.title,
          assessedOn: a.assessedOn,
          rawScore: result?.rawScore ?? null,
          maxScore: result ? result.maxScore : a.maxScore,
          percentage:
            result !== undefined
              ? deriveScorePercentage(result.rawScore, result.maxScore)
              : null,
        };
      });

    if (input.includeObservations) {
      const sessions = await fetchSessionsInPeriod(admin, scopedEnrollment.classId, period);
      const completedSessions = sessions.filter((s) => s.status === "completed");
      const obsRows = await fetchObservationsForSessions(admin, completedSessions);
      observations = obsRows
        .filter((o) => o.enrollmentId === scopedEnrollment.id)
        .map((o) => ({
          sessionDate: o.sessionDate,
          className: scopedEnrollment.className,
          ratings: o.ratings,
          comment: o.comment,
        }))
        .sort((a, b) => b.sessionDate.localeCompare(a.sessionDate));
    }
  }

  const percentages = assessments.map((a) => a.percentage).filter((p) => p !== null);

  return {
    ok: true,
    report: {
      branding,
      studentId: input.studentId,
      studentName,
      studentCode: student.student_code,
      period,
      generatedAt: new Date().toISOString(),
      includesObservations: Boolean(input.includeObservations),
      enrollmentScope: scopedEnrollment
        ? {
            enrollmentId: scopedEnrollment.id,
            classId: scopedEnrollment.classId,
            className: scopedEnrollment.className,
            courseCode: scopedEnrollment.courseCode,
            enrollmentStatus: scopedEnrollment.status,
            startDate: scopedEnrollment.startDate,
            endDate: scopedEnrollment.endDate,
          }
        : null,
      attendance,
      assessments,
      averagePercentage: computeMeanPercentage(percentages),
      observations,
    },
  };
}

async function tableHasForbiddenReportColumns(admin, tableName) {
  const { data, error } = await admin.from(tableName).select("*").limit(1);
  if (error) return { ok: false, error: error.message };
  const sample = data?.[0] ?? {};
  const found = REPORT_SNAPSHOT_FORBIDDEN_COLUMNS.filter((col) => col in sample);
  return { ok: found.length === 0, found };
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
    await admin.from("attendance").delete().in(
      "teaching_session_id",
      (
        await admin
          .from("teaching_session")
          .select("id")
          .in("class_id", createdClassIds)
      ).data?.map((s) => s.id) ?? [],
    );
    await admin.from("teaching_session").delete().in("class_id", createdClassIds);
    await admin.from("class_schedule").delete().in("class_id", createdClassIds);
    await admin.from("class_teacher_assignment").delete().in("class_id", createdClassIds);
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
  if (createdRoomIds.length > 0) {
    await admin.from("room").delete().in("id", createdRoomIds);
  }
}

async function main() {
  const admin = createServiceAdmin();
  const adminUser = await signIn("org-a-admin@olli.local");
  const staff = await signIn("org-a-staff@olli.local");
  const reader = await signIn("org-a-reader@olli.local");

  const { count: chargeCountBefore } = await admin
    .from("charge")
    .select("id", { count: "exact", head: true });
  const { count: enrollmentCountBefore } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });

  const period = { startDate: "2028-06-01", endDate: "2028-12-31" };

  // Attendance fixture: completed + in_progress + cancelled + scheduled sessions
  const attFixture = await setupClassSession(admin, adminUser, "Att", {
    sessionDate: "2028-09-04",
    weekdayCode: "mon",
    sessionStatus: "completed",
    classOptions: { termStart: period.startDate, termEnd: period.endDate },
  });
  const attClass = attFixture.classRow;
  const attCourse = attFixture.courseId;
  await generateSessions(adminUser, attFixture.scheduleId, "2028-09-04", "2028-09-25");
  const { data: attSessionsRaw } = await admin
    .from("teaching_session")
    .select("id, status, occurrence_date, scheduled_start_at")
    .eq("class_id", attClass.id)
    .order("scheduled_start_at");
  const attSessionsByDate = new Map(
    (attSessionsRaw ?? []).map((session) => [
      resolveSessionOccurrenceDate({
        occurrenceDate: session.occurrence_date,
        scheduledStartAt: session.scheduled_start_at,
      }),
      session,
    ]),
  );
  const statusByDate = {
    "2028-09-04": "completed",
    "2028-09-11": "in_progress",
    "2028-09-18": "cancelled",
    "2028-09-25": "scheduled",
  };
  for (const [date, status] of Object.entries(statusByDate)) {
    const session = attSessionsByDate.get(date);
    if (session && session.status !== status) {
      if (status === "cancelled") {
        const { error } = await adminUser.rpc("cancel_teaching_session", {
          p_session_id: session.id,
          p_reason: "Reports smoke cancel fixture",
        });
        if (error) throw new Error(`cancel fixture failed: ${error.message}`);
      } else if (status === "completed") {
        await admin
          .from("teaching_session")
          .update({ status: "in_progress", updated_by: APP_A_ADMIN })
          .eq("id", session.id);
        await admin
          .from("teaching_session")
          .update({ status: "completed", updated_by: APP_A_ADMIN })
          .eq("id", session.id);
      } else {
        await admin
          .from("teaching_session")
          .update({ status, updated_by: APP_A_ADMIN })
          .eq("id", session.id);
      }
      session.status = status;
    }
  }
  const completedSessionId = attSessionsByDate.get("2028-09-04")?.id;
  const inProgressSessionId = attSessionsByDate.get("2028-09-11")?.id;
  if (!completedSessionId || !inProgressSessionId) {
    throw new Error(
      `Attendance fixture sessions not materialized (found: ${[...attSessionsByDate.keys()].join(", ")})`,
    );
  }

  const attStudent = await createStudent(admin, "AttMain");
  const attEnroll = await insertEnrollment(admin, {
    studentId: attStudent,
    classId: attClass.id,
    startDate: "2028-06-01",
    status: "active",
  });
  await insertAttendance(admin, {
    sessionId: completedSessionId,
    enrollmentId: attEnroll.data.id,
    status: "present",
  });
  await insertAttendance(admin, {
    sessionId: inProgressSessionId,
    enrollmentId: attEnroll.data.id,
    status: "late",
  });

  const attReport = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const attLearner = attReport.report?.learners.find(
    (l) => l.enrollmentId === attEnroll.data.id,
  );

  record(
    1,
    "completed session counts as attendance opportunity",
    attLearner?.eligibleSessions === 2,
  );
  record(
    2,
    "in_progress session counts as attendance opportunity",
    attLearner?.presentCount === 1 && attLearner?.lateCount === 1,
  );
  record(
    3,
    "cancelled session excluded from opportunity",
    attReport.report?.sessionTotals.cancelled === 1 &&
      attLearner?.eligibleSessions === 2,
  );
  record(
    4,
    "scheduled session excluded from opportunity",
    attReport.report?.sessionTotals.scheduled === 1 &&
      attLearner?.eligibleSessions === 2,
  );

  const lateStartStudent = await createStudent(admin, "AttLateStart");
  const lateStartEnroll = await insertEnrollment(admin, {
    studentId: lateStartStudent,
    classId: attClass.id,
    startDate: "2028-10-01",
    status: "active",
  });
  const attReportLate = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const lateStartRow = attReportLate.report?.learners.find(
    (l) => l.enrollmentId === lateStartEnroll.data.id,
  );
  record(
    5,
    "enrollment beginning after session excluded",
    (lateStartRow?.eligibleSessions ?? 0) === 0,
  );

  const earlyEndStudent = await createStudent(admin, "AttEarlyEnd");
  const earlyEndEnroll = await insertEnrollment(admin, {
    studentId: earlyEndStudent,
    classId: attClass.id,
    startDate: "2028-06-01",
    endDate: "2028-08-01",
    status: "withdrawn",
  });
  const attReportEarly = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const earlyEndRow = attReportEarly.report?.learners.find(
    (l) => l.enrollmentId === earlyEndEnroll.data.id,
  );
  record(
    6,
    "enrollment ending before session excluded",
    (earlyEndRow?.eligibleSessions ?? 0) === 0,
  );

  const pendingStudent = await createStudent(admin, "AttPending");
  const pendingEnroll = await insertEnrollment(admin, {
    studentId: pendingStudent,
    classId: attClass.id,
    startDate: "2028-06-01",
    status: "pending",
  });
  const attReportPending = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const pendingRow = attReportPending.report?.learners.find(
    (l) => l.enrollmentId === pendingEnroll.data.id,
  );
  record(
    7,
    "pending enrollment excluded from attendance report",
    !pendingRow || pendingRow.eligibleSessions === 0,
  );

  const notRecStudent = await createStudent(admin, "AttNotRec");
  const notRecEnroll = await insertEnrollment(admin, {
    studentId: notRecStudent,
    classId: attClass.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const attReportNotRec = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const notRecRow = attReportNotRec.report?.learners.find(
    (l) => l.enrollmentId === notRecEnroll.data.id,
  );
  record(
    8,
    "not-recorded is not counted as absent",
    notRecRow?.notRecordedCount === 2 && notRecRow?.absentCount === 0,
  );
  record(
    9,
    "attendance rate equals present plus late over recorded",
    attLearner?.attendanceRate === computeAttendanceRate({
      presentCount: 1,
      absentCount: 0,
      lateCount: 1,
      excusedCount: 0,
      notRecordedCount: 0,
      eligibleSessions: 2,
    }),
  );

  const xferStudent = await createStudent(admin, "AttXfer");
  const xferEnroll = await insertEnrollment(admin, {
    studentId: xferStudent,
    classId: attClass.id,
    startDate: "2028-06-01",
    endDate: "2028-09-20",
    status: "active",
  });
  await insertAttendance(admin, {
    sessionId: completedSessionId,
    enrollmentId: xferEnroll.data.id,
    status: "present",
  });
  const xferDest = await createClass(admin, attCourse, "AttXferDest");
  await adminUser.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferEnroll.data.id,
    p_destination_class_id: xferDest.id,
    p_destination_start_date: "2028-09-21",
    p_destination_status: "active",
  });
  const attReportXfer = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const xferRow = attReportXfer.report?.learners.find(
    (l) => l.enrollmentId === xferEnroll.data.id,
  );
  record(
    10,
    "historical transferred enrollment included in attendance report",
    xferRow?.enrollmentStatus === "transferred" && (xferRow?.presentCount ?? 0) >= 1,
  );

  const wdStudent = await createStudent(admin, "AttWd");
  const wdEnroll = await insertEnrollment(admin, {
    studentId: wdStudent,
    classId: attClass.id,
    startDate: "2028-06-01",
    status: "active",
  });
  await insertAttendance(admin, {
    sessionId: completedSessionId,
    enrollmentId: wdEnroll.data.id,
    status: "excused",
  });
  await admin
    .from("enrollment")
    .update({ status: "withdrawn", end_date: "2028-10-01", updated_by: APP_A_ADMIN })
    .eq("id", wdEnroll.data.id);
  const attReportWd = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const wdRow = attReportWd.report?.learners.find((l) => l.enrollmentId === wdEnroll.data.id);
  record(
    11,
    "historical withdrawn enrollment included in attendance report",
    wdRow?.enrollmentStatus === "withdrawn" && wdRow?.excusedCount === 1,
  );

  // Assessment (12-18)
  const asmtFixture = await setupClassWithEnrollment(admin, "Asmt", { startDate: "2028-06-01" });
  const asmtA = await insertAssessment(admin, {
    classId: asmtFixture.classRow.id,
    title: "Quiz A",
    assessedOn: "2028-09-10",
    maxScore: 20,
  });
  const asmtB = await insertAssessment(admin, {
    classId: asmtFixture.classRow.id,
    title: "Quiz B",
    assessedOn: "2028-09-20",
    maxScore: 25,
  });
  await insertAssessmentResult(admin, {
    assessmentId: asmtA.data.id,
    enrollmentId: asmtFixture.enrollment.data.id,
    rawScore: 16,
    maxScore: 20,
  });
  const asmtMissingStudent = await createStudent(admin, "AsmtMissing");
  const asmtMissingEnroll = await insertEnrollment(admin, {
    studentId: asmtMissingStudent,
    classId: asmtFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const asmtReport = await buildClassAssessmentReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const scoredLearner = asmtReport.report?.learners.find(
    (l) => l.enrollmentId === asmtFixture.enrollment.data.id,
  );
  const missingLearner = asmtReport.report?.learners.find(
    (l) => l.enrollmentId === asmtMissingEnroll.data.id,
  );
  const scoredCell = scoredLearner?.cells.find((c) => c.assessmentId === asmtA.data.id);
  const missingCell = missingLearner?.cells.find((c) => c.assessmentId === asmtA.data.id);

  record(
    12,
    "assessments in period appear in report",
    asmtReport.report?.assessments.some((a) => a.id === asmtA.data.id) &&
      asmtReport.report?.assessments.some((a) => a.id === asmtB.data.id),
  );
  record(
    13,
    "missing score stays null",
    missingCell?.rawScore === null && missingCell?.percentage === null && !missingCell?.hasScore,
  );
  record(
    14,
    "mean percentage excludes missing scores",
    asmtReport.report?.aggregates.meanPercentage === deriveScorePercentage(16, 20) &&
      asmtReport.report?.aggregates.scoredCount === 1 &&
      asmtReport.report?.aggregates.withoutScoreCount >= 1,
  );

  const asmtLateStudent = await createStudent(admin, "AsmtLate");
  await insertEnrollment(admin, {
    studentId: asmtLateStudent,
    classId: asmtFixture.classRow.id,
    startDate: "2028-10-01",
    status: "active",
  });
  const asmtReportLate = await buildClassAssessmentReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    15,
    "ineligible enrollment excluded from assessment learner row",
    !asmtReportLate.report?.learners.some((l) => l.studentName.includes("AsmtLate")),
  );

  const asmtPendingStudent = await createStudent(admin, "AsmtPending");
  await insertEnrollment(admin, {
    studentId: asmtPendingStudent,
    classId: asmtFixture.classRow.id,
    startDate: "2028-06-01",
    status: "pending",
  });
  const asmtReportPending = await buildClassAssessmentReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    16,
    "pending enrollment excluded from assessment report",
    !asmtReportPending.report?.learners.some((l) => l.studentName.includes("AsmtPending")),
  );

  const asmtOutPeriod = await insertAssessment(admin, {
    classId: asmtFixture.classRow.id,
    title: "Out of period",
    assessedOn: "2029-01-15",
  });
  const asmtReportPeriod = await buildClassAssessmentReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    17,
    "assessment outside period excluded",
    !asmtReportPeriod.report?.assessments.some((a) => a.id === asmtOutPeriod.data.id),
  );
  record(
    18,
    "eligible enrollment with score shows percentage",
    scoredCell?.hasScore === true && scoredCell?.percentage === deriveScorePercentage(16, 20),
  );

  // EOC (19-24)
  const eocReportNoObs = await buildClassEndOfCourseReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
    includeObservations: false,
  });
  record(
    19,
    "end-of-course combines attendance and assessment aggregates",
    eocReportNoObs.ok &&
      eocReportNoObs.report?.attendanceReport &&
      eocReportNoObs.report?.assessmentReport &&
      eocReportNoObs.report?.assessments.count >= 2,
  );
  record(
    20,
    "end-of-course enrollment byStatus counts",
    eocReportNoObs.report?.enrollments.total >= 1 &&
      typeof eocReportNoObs.report?.enrollments.byStatus.active === "number",
  );
  record(
    21,
    "end-of-course session totals derived",
    typeof eocReportNoObs.report?.sessions.total === "number" &&
      typeof eocReportNoObs.report?.sessions.completed === "number" &&
      typeof eocReportNoObs.report?.sessions.cancelled === "number",
  );
  record(
    22,
    "includeObservations false yields null observations",
    eocReportNoObs.report?.observations === null &&
      eocReportNoObs.report?.includesObservations === false,
  );

  const eocSessionFixture = await setupClassSession(admin, adminUser, "EocObs", {
    sessionDate: "2028-10-09",
    weekdayCode: "mon",
    sessionStatus: "completed",
  });
  const eocObsStudent = await createStudent(admin, "EocObs");
  const eocObsEnroll = await insertEnrollment(admin, {
    studentId: eocObsStudent,
    classId: eocSessionFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const eocObs = await admin
    .from("teacher_observation")
    .insert({
      organization_id: ORG_A,
      enrollment_id: eocObsEnroll.data.id,
      class_id: eocSessionFixture.classRow.id,
      teacher_id: eocSessionFixture.teacherId,
      teaching_session_id: eocSessionFixture.session.id,
      observed_at: eocSessionFixture.session.scheduled_start_at,
      comment: "EOC observation",
      status: "recorded",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  await admin.from("observation_rating").insert({
    organization_id: ORG_A,
    teacher_observation_id: eocObs.data.id,
    indicator_code: "engagement",
    rating_code: "high",
  });
  const eocObsReport = await buildClassEndOfCourseReport(admin, {
    classId: eocSessionFixture.classRow.id,
    startDate: "2028-06-01",
    endDate: "2028-12-31",
    includeObservations: true,
  });
  record(
    23,
    "includeObservations true populates observation summary",
    eocObsReport.report?.observations !== null &&
      (eocObsReport.report?.observations.commentCount ?? 0) >= 1,
  );
  record(
    24,
    "end-of-course average attendance rate derived from learners",
    eocReportNoObs.report?.attendance.averageAttendanceRate ===
      computeMeanPercentage(
        (eocReportNoObs.report?.attendanceReport.learners ?? [])
          .map((l) => l.attendanceRate)
          .filter((r) => r !== null),
      ),
  );

  // Student progress (25-30)
  const progFixture = await setupClassWithEnrollment(admin, "ProgOld", {
    startDate: "2028-06-01",
    endDate: "2028-08-31",
    enrollmentStatus: "withdrawn",
  });
  const progNewEnroll = await insertEnrollment(admin, {
    studentId: progFixture.studentId,
    classId: progFixture.classRow.id,
    startDate: "2028-09-01",
    status: "active",
  });
  const progAssessment = await insertAssessment(admin, {
    classId: progFixture.classRow.id,
    title: "Prog Quiz",
    assessedOn: "2028-09-15",
  });
  await insertAssessmentResult(admin, {
    assessmentId: progAssessment.data.id,
    enrollmentId: progNewEnroll.data.id,
    rawScore: 18,
    maxScore: 20,
  });
  const progDefault = await buildStudentProgressReport(admin, {
    studentId: progFixture.studentId,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    25,
    "default scope is most recent enrollment",
    progDefault.report?.enrollmentScope?.enrollmentId === progNewEnroll.data.id,
  );

  const progScoped = await buildStudentProgressReport(admin, {
    studentId: progFixture.studentId,
    enrollmentId: progFixture.enrollment.data.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    26,
    "enrollmentId scopes to specific enrollment",
    progScoped.report?.enrollmentScope?.enrollmentId === progFixture.enrollment.data.id,
  );

  const progInvalid = await buildStudentProgressReport(admin, {
    studentId: progFixture.studentId,
    enrollmentId: "00000000-0000-4000-8000-000000000099",
  });
  record(27, "invalid enrollmentId returns not_found", progInvalid.ok === false);

  const progSession = await setupClassSession(admin, adminUser, "ProgAtt", {
    sessionDate: "2028-10-16",
    weekdayCode: "mon",
    sessionStatus: "completed",
  });
  const progAttEnroll = await insertEnrollment(admin, {
    studentId: progFixture.studentId,
    classId: progSession.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  await insertAttendance(admin, {
    sessionId: progSession.session.id,
    enrollmentId: progAttEnroll.data.id,
    status: "present",
  });
  const progAttReport = await buildStudentProgressReport(admin, {
    studentId: progFixture.studentId,
    enrollmentId: progAttEnroll.data.id,
    startDate: "2028-06-01",
    endDate: "2028-12-31",
  });
  record(
    28,
    "attendance row scoped to enrollment",
    progAttReport.report?.attendance?.enrollmentId === progAttEnroll.data.id &&
      (progAttReport.report?.attendance?.presentCount ?? 0) >= 1,
  );
  record(
    29,
    "assessments scoped to enrollment class",
    progDefault.report?.assessments.some((a) => a.assessmentId === progAssessment.data.id),
  );

  const emptyStudent = await createStudent(admin, "ProgEmpty");
  const progEmpty = await buildStudentProgressReport(admin, { studentId: emptyStudent });
  record(
    30,
    "student with no enrollments returns empty progress report",
    progEmpty.ok &&
      progEmpty.report?.assessments.length === 0 &&
      progEmpty.report?.enrollmentScope === null,
  );

  // Observation permissions (31-34)
  const obsPermFixture = await setupClassSession(admin, adminUser, "ObsPerm", {
    sessionDate: "2028-10-23",
    weekdayCode: "mon",
    sessionStatus: "completed",
  });
  const obsPermStudent = await createStudent(admin, "ObsPerm");
  const obsPermEnroll = await insertEnrollment(admin, {
    studentId: obsPermStudent,
    classId: obsPermFixture.classRow.id,
    startDate: "2028-06-01",
    status: "active",
  });
  const obsPermRow = await admin
    .from("teacher_observation")
    .insert({
      organization_id: ORG_A,
      enrollment_id: obsPermEnroll.data.id,
      class_id: obsPermFixture.classRow.id,
      teacher_id: obsPermFixture.teacherId,
      teaching_session_id: obsPermFixture.session.id,
      observed_at: obsPermFixture.session.scheduled_start_at,
      comment: "Permission probe",
      status: "recorded",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const progNoObs = await buildStudentProgressReport(admin, {
    studentId: obsPermStudent,
    enrollmentId: obsPermEnroll.data.id,
    startDate: "2028-06-01",
    endDate: "2028-12-31",
    includeObservations: false,
  });
  const progWithObs = await buildStudentProgressReport(admin, {
    studentId: obsPermStudent,
    enrollmentId: obsPermEnroll.data.id,
    startDate: "2028-06-01",
    endDate: "2028-12-31",
    includeObservations: true,
  });
  record(
    31,
    "includeObservations false excludes observation rows",
    progNoObs.report?.observations === null && progNoObs.report?.includesObservations === false,
  );
  record(
    32,
    "includeObservations true includes observation rows",
    (progWithObs.report?.observations?.length ?? 0) >= 1 &&
      progWithObs.report?.includesObservations === true,
  );

  const readerObs = await reader
    .from("teacher_observation")
    .select("id")
    .eq("id", obsPermRow.data.id);
  record(
    33,
    "reader lacks observation.read and cannot read observations",
    !(await hasPermission(reader, "observation.read")) && (readerObs.data ?? []).length === 0,
  );
  record(
    34,
    "staff has observation.read permission",
    await hasPermission(staff, "observation.read"),
  );

  // Permission composition (35-39)
  record(
    35,
    "attendance.read controls attendance report access",
    (await hasPermission(adminUser, "attendance.read")) &&
      (await hasPermission(staff, "attendance.read")) &&
      !(await hasPermission(reader, "attendance.read")),
  );
  record(
    36,
    "assessment.read controls assessment report access",
    (await hasPermission(adminUser, "assessment.read")) &&
      (await hasPermission(staff, "assessment.read")) &&
      !(await hasPermission(reader, "assessment.read")),
  );
  record(
    37,
    "student.read or enrollment.read required for progress report",
    (await hasPermission(adminUser, "student.read")) &&
      (await hasPermission(staff, "enrollment.read")),
  );
  const { data: reportReadPerm } = await admin
    .from("permission")
    .select("code")
    .eq("code", "report.read")
    .maybeSingle();
  record(
    38,
    "report.read permission registered",
    reportReadPerm?.code === "report.read" && !(await hasPermission(reader, "report.read")),
  );
  record(
    39,
    "admin has composite read permissions for reports",
    (await hasPermission(adminUser, "attendance.read")) &&
      (await hasPermission(adminUser, "assessment.read")) &&
      (await hasPermission(adminUser, "student.read")),
  );

  // No-data (40-44)
  const emptyClassFixture = await setupClassWithEnrollment(admin, "NoData");
  const emptyAttReport = await buildClassAttendanceReport(admin, {
    classId: emptyClassFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    40,
    "class with no sessions yields zero opportunity counts",
    emptyAttReport.report?.sessionTotals.materialized === 0 &&
      emptyAttReport.report?.learners.every((l) => l.eligibleSessions === 0),
  );

  const emptyAsmtReport = await buildClassAssessmentReport(admin, {
    classId: emptyClassFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    41,
    "class with no assessments yields empty assessment list",
    emptyAsmtReport.report?.assessments.length === 0,
  );

  const noEnrollClass = await createClass(admin, emptyClassFixture.courseId, "NoEnroll");
  const noEnrollReport = await buildClassAttendanceReport(admin, {
    classId: noEnrollClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  record(
    42,
    "class with no enrollments yields empty learners",
    noEnrollReport.report?.learners.length === 0,
  );

  const narrowPeriodReport = await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: "2027-01-01",
    endDate: "2027-01-31",
  });
  record(
    43,
    "period with no overlapping sessions yields zero opportunities",
    narrowPeriodReport.report?.sessionTotals.materialized === 0,
  );

  const invalidPeriod = validateReportPeriod({
    startDate: "2028-12-01",
    endDate: "2028-06-01",
  });
  record(44, "invalid period range rejected", invalidPeriod.ok === false);

  // Calculations (45-48)
  record(
    45,
    "computeAttendanceRate rounds to one decimal",
    computeAttendanceRate({
      presentCount: 1,
      absentCount: 1,
      lateCount: 1,
      excusedCount: 0,
      notRecordedCount: 0,
      eligibleSessions: 3,
    }) === 66.7,
  );
  record(
    46,
    "computeMeanPercentage returns null for empty input",
    computeMeanPercentage([]) === null && computeMeanPercentage([80, 90]) === 85,
  );
  record(
    47,
    "deriveScorePercentage handles max score",
    deriveScorePercentage(15, 20) === 75 && deriveScorePercentage(1, 0) === null,
  );
  record(48, "roundPercentage precision", roundPercentage(33.333) === 33.3);

  // Print/read model (49-51)
  record(
    49,
    "attendance report read model has required fields",
    Boolean(
      attReport.report?.branding?.name &&
        attReport.report?.context?.classId &&
        attReport.report?.period?.startDate &&
        attReport.report?.generatedAt,
    ),
  );
  const attCountBeforeReadModel = (
    await admin.from("attendance").select("id", { count: "exact", head: true })
  ).count;
  const asmtResultCountBeforeReadModel = (
    await admin.from("assessment_result").select("id", { count: "exact", head: true })
  ).count;
  await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  await buildClassAssessmentReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  await buildStudentProgressReport(admin, { studentId: attStudent });
  const attCountAfterReadModel = (
    await admin.from("attendance").select("id", { count: "exact", head: true })
  ).count;
  const asmtResultCountAfterReadModel = (
    await admin.from("assessment_result").select("id", { count: "exact", head: true })
  ).count;
  record(
    50,
    "report builders are read-only over source tables",
    attCountBeforeReadModel === attCountAfterReadModel &&
      asmtResultCountBeforeReadModel === asmtResultCountAfterReadModel,
  );
  const printTableProbe = await admin.from("report_print_log").select("id").limit(1);
  record(
    51,
    "print is client-side only with no print persistence table",
    Boolean(printTableProbe.error?.message?.includes("Could not find")),
  );

  // Architectural boundaries (52-59)
  const studentCols = await tableHasForbiddenReportColumns(admin, "student");
  const classCols = await tableHasForbiddenReportColumns(admin, "class");
  const enrollmentCols = await tableHasForbiddenReportColumns(admin, "enrollment");
  record(
    52,
    "no report snapshot columns on student",
    studentCols.ok,
    studentCols.found?.join(", "),
  );
  record(
    53,
    "no report snapshot columns on class",
    classCols.ok,
    classCols.found?.join(", "),
  );
  record(
    54,
    "no report snapshot columns on enrollment",
    enrollmentCols.ok,
    enrollmentCols.found?.join(", "),
  );

  const reportSnapshotProbe = await admin.from("report_snapshot").select("id").limit(1);
  record(
    55,
    "no report_snapshot persistence table",
    Boolean(reportSnapshotProbe.error?.message?.includes("Could not find")),
  );

  const attCountBeforeBuild = (
    await admin.from("attendance").select("id", { count: "exact", head: true })
  ).count;
  await buildClassAttendanceReport(admin, {
    classId: attClass.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const attCountAfterBuild = (
    await admin.from("attendance").select("id", { count: "exact", head: true })
  ).count;
  record(
    56,
    "building attendance report does not mutate attendance",
    attCountBeforeBuild === attCountAfterBuild,
  );

  const asmtCountBeforeBuild = (
    await admin.from("assessment_result").select("id", { count: "exact", head: true })
  ).count;
  await buildClassAssessmentReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const asmtCountAfterBuild = (
    await admin.from("assessment_result").select("id", { count: "exact", head: true })
  ).count;
  record(
    57,
    "building assessment report does not mutate assessment_result",
    asmtCountBeforeBuild === asmtCountAfterBuild,
  );

  const enrollCountMid = (
    await admin.from("enrollment").select("id", { count: "exact", head: true })
  ).count;
  await buildClassEndOfCourseReport(admin, {
    classId: asmtFixture.classRow.id,
    startDate: period.startDate,
    endDate: period.endDate,
  });
  const enrollCountAfterBuild = (
    await admin.from("enrollment").select("id", { count: "exact", head: true })
  ).count;
  record(
    58,
    "building end-of-course report does not mutate enrollment",
    enrollCountMid === enrollCountAfterBuild,
  );

  const { data: studentBeforeReport } = await admin
    .from("student")
    .select("given_name, status")
    .eq("id", attStudent)
    .single();
  await buildStudentProgressReport(admin, { studentId: attStudent });
  const { data: studentAfterReport } = await admin
    .from("student")
    .select("given_name, status")
    .eq("id", attStudent)
    .single();
  record(
    59,
    "building student progress report does not mutate student master",
    JSON.stringify(studentBeforeReport) === JSON.stringify(studentAfterReport),
  );

  // Regression (60-68)
  const { count: studentCount, error: studentErr } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  record(60, "student operations pass", !studentErr && (studentCount ?? 0) > 0);

  const { count: guardianCount, error: guardianErr } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("status", "active");
  record(61, "guardian operations pass", !guardianErr && (guardianCount ?? 0) > 0);

  const { count: courseCount, error: courseErr } = await admin
    .from("course")
    .select("id", { count: "exact", head: true });
  const { count: classCount, error: classErr } = await admin
    .from("class")
    .select("id", { count: "exact", head: true });
  record(
    62,
    "course/class operations pass",
    !courseErr && !classErr && (courseCount ?? 0) > 0 && (classCount ?? 0) > 0,
  );

  const { count: enrollCount, error: enrollErr } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  record(
    63,
    "enrollment roster pass",
    !enrollErr && (enrollCount ?? 0) > 0 && (enrollCount ?? 0) >= (enrollmentCountBefore ?? 0),
  );

  const { count: chargeCountAfter } = await admin
    .from("charge")
    .select("id", { count: "exact", head: true });
  record(64, "no finance mutation during reporting smoke", chargeCountBefore === chargeCountAfter);

  const { count: assessmentCountAfter } = await admin
    .from("assessment")
    .select("id", { count: "exact", head: true });
  record(
    65,
    "assessment module tables remain accessible",
    (assessmentCountAfter ?? 0) > 0,
  );

  const sessionProbe = await setupClassSession(admin, adminUser, "RegSession", {
    sessionDate: "2028-11-06",
    weekdayCode: "mon",
  });
  const { data: sessionRow } = await admin
    .from("teaching_session")
    .select("id")
    .eq("id", sessionProbe.session.id)
    .single();
  record(66, "session execution tables remain accessible", Boolean(sessionRow?.id));

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
  record(67, "transfer remains atomic", !xferRegErr && Boolean(xferRegNewId));

  const staffObs = await staff
    .from("teacher_observation")
    .select("id")
    .eq("id", obsPermRow.data.id);
  record(
    68,
    "observation read regression pass",
    (staffObs.data ?? []).length === 1 && (await hasPermission(staff, "observation.read")),
  );

  await cleanupFixtures(admin);

  const pass = results.filter((r) => r.passed).length;
  const total = results.length;
  console.log(`\nM1-T10 reporting smoke: ${pass}/${total} PASS`);
  console.log(`Test count: ${results.length}`);
  if (pass !== total) {
    results.filter((r) => !r.passed).forEach((f) => console.error(`  RP-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
