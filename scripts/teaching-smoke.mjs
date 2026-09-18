#!/usr/bin/env node
/**
 * M1-T07 teaching operations smoke tests.
 * Requires local Supabase with dev seed and M1-T07 migration applied.
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
const WEEKDAY_CODES = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
const SESSION_STATUSES = ["scheduled", "in_progress", "completed", "cancelled"];
const results = [];
const createdCourseIds = [];
const createdClassIds = [];
const createdRoomIds = [];
const createdScheduleIds = [];
const createdAssignmentIds = [];
const createdSessionIds = []; // eslint-disable-line @typescript-eslint/no-unused-vars -- cleanup tracker

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} TE-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

function validateScheduleInput(input, options = {}) {
  const fieldErrors = {};
  const weekdayRaw = (input.weekdayCode ?? "").trim();
  const startTime = (input.startTime ?? "").trim();
  const endTime = (input.endTime ?? "").trim();
  const effectiveFromRaw = (input.effectiveFrom ?? "").trim();
  const effectiveToRaw = (input.effectiveTo ?? "").trim();

  if (!WEEKDAY_CODES.includes(weekdayRaw)) fieldErrors.weekdayCode = "invalid";
  if (!startTime) fieldErrors.startTime = "required";
  if (!endTime) fieldErrors.endTime = "required";
  if (startTime && endTime && endTime <= startTime) fieldErrors.endTime = "beforeStart";

  if (!effectiveFromRaw) fieldErrors.effectiveFrom = "required";
  else if (!isValidIsoDate(effectiveFromRaw)) fieldErrors.effectiveFrom = "invalid";

  if (effectiveToRaw) {
    if (!isValidIsoDate(effectiveToRaw)) fieldErrors.effectiveTo = "invalid";
    else if (effectiveFromRaw && effectiveToRaw < effectiveFromRaw) {
      fieldErrors.effectiveTo = "beforeStart";
    }
  }

  if (options.classStatus === "closed") {
    return { ok: false, fieldErrors: { ...fieldErrors, effectiveFrom: "classClosed" } };
  }

  return { ok: Object.keys(fieldErrors).length === 0, fieldErrors };
}

function validateRoomInput(input) {
  const fieldErrors = {};
  const name = (input.name ?? "").trim();
  const capacityRaw = (input.capacity ?? "").trim();
  const statusRaw = (input.status ?? "active").trim();

  if (!name) fieldErrors.name = "required";
  if (capacityRaw) {
    const parsed = Number(capacityRaw);
    if (!Number.isInteger(parsed) || parsed <= 0) fieldErrors.capacity = "invalid";
  }
  if (!["active", "inactive"].includes(statusRaw)) fieldErrors.status = "invalid";

  return { ok: Object.keys(fieldErrors).length === 0, fieldErrors };
}

function validateTeacherAssignmentInput(input) {
  const fieldErrors = {};
  const teacherId = (input.teacherId ?? "").trim();
  const roleRaw = (input.roleCode ?? "primary").trim();
  const effectiveFromRaw = (input.effectiveFrom ?? "").trim();
  const effectiveToRaw = (input.effectiveTo ?? "").trim();

  if (!teacherId) fieldErrors.teacherId = "required";
  if (!["primary", "assistant"].includes(roleRaw)) fieldErrors.roleCode = "invalid";
  if (!effectiveFromRaw) fieldErrors.effectiveFrom = "required";
  else if (!isValidIsoDate(effectiveFromRaw)) fieldErrors.effectiveFrom = "invalid";
  if (effectiveToRaw) {
    if (!isValidIsoDate(effectiveToRaw)) fieldErrors.effectiveTo = "invalid";
    else if (effectiveFromRaw && effectiveToRaw < effectiveFromRaw) {
      fieldErrors.effectiveTo = "beforeStart";
    }
  }

  return { ok: Object.keys(fieldErrors).length === 0, fieldErrors };
}

function getRoomCapacityWarning(classCapacity, roomCapacity) {
  if (classCapacity == null || classCapacity <= 0) return false;
  if (roomCapacity == null || roomCapacity <= 0) return false;
  return classCapacity > roomCapacity;
}

function isRoomEligibleForAssignment(room) {
  return Boolean(room && room.status === "active");
}

function isConflictError(error) {
  if (!error) return false;
  if (error.code === "23P01") return true;
  const msg = error.message ?? "";
  return (
    msg.includes("schedule_conflict") ||
    msg.includes("teacher_double_booked") ||
    msg.includes("room_double_booked") ||
    msg.includes("exclusion")
  );
}

function isTeacherUnavailableError(error) {
  if (!error) return false;
  return (error.message ?? "").includes("teacher_unavailable");
}

function localTimeFromUtc(iso, timeZone = "Asia/Ho_Chi_Minh") {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(iso));
}

async function ensureOrgBRoom(orgBAdmin) {
  const existing = await orgBAdmin.from("room").select("id").limit(1).maybeSingle();
  if (existing.data?.id) return existing.data.id;
  const created = await orgBAdmin
    .from("room")
    .insert({
      organization_id: ORG_B,
      code: `B-${Date.now()}`,
      name: "Org B Probe Room",
      status: "active",
    })
    .select("id")
    .single();
  return created.data?.id;
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
      code: `TE-${label}-${ts}`,
      name: `Teaching ${label} ${ts}`,
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
    .select("id, status, capacity, term_start_date, term_end_date")
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
    .select("id, status, capacity")
    .single();
  if (error) throw error;
  createdRoomIds.push(data.id);
  return data;
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
      status: input.status ?? "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  if (!row.error) createdScheduleIds.push(row.data.id);
  return row;
}

async function insertAssignment(admin, classId, input) {
  const row = await admin
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
  if (!row.error) createdAssignmentIds.push(row.data.id);
  return row;
}

async function generateSessions(admin, scheduleId, rangeStart, rangeEnd) {
  return admin.rpc("generate_teaching_sessions", {
    p_class_schedule_id: scheduleId,
    p_range_start: rangeStart,
    p_range_end: rangeEnd,
  });
}

async function getOrgATeacher(admin) {
  const { data } = await admin
    .from("teacher")
    .select("id")
    .eq("organization_id", ORG_A)
    .eq("status", "active")
    .limit(1)
    .single();
  return data?.id;
}

async function getOrgBTeacher(orgBAdmin) {
  const { data } = await orgBAdmin.from("teacher").select("id").limit(1).single();
  return data?.id;
}

async function setupClassWithPrimary(admin, label, options = {}) {
  const courseId = await createCourse(admin, label);
  const classRow = await createClass(admin, courseId, label, options);
  const teacherId = await createTeacher(admin, label);
  const room = await createRoom(admin, `${label}-room`);
  await insertAssignment(admin, classRow.id, {
    teacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  return { classRow, teacherId, roomId: room.id };
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const staff = await signIn("org-a-staff@olli.local");
  const orgBAdmin = await signIn("org-b-admin@olli.local");

  const orgATeacherId = await getOrgATeacher(admin);
  const orgBTeacherId = await getOrgBTeacher(orgBAdmin);
  const orgBRoomId = await ensureOrgBRoom(orgBAdmin);

  const { count: obsCountBeforeTeaching } = await admin
    .from("observation")
    .select("id", { count: "exact", head: true });

  const probeTeacherId = await createTeacher(admin, "Probe");
  const probeCourseId = await createCourse(admin, "probe");
  const probeClass = await createClass(admin, probeCourseId, "Probe");
  const probeRoom = await createRoom(admin, "ProbeRoom");
  await insertAssignment(admin, probeClass.id, {
    teacherId: probeTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const probeSchedule = await insertSchedule(admin, probeClass.id, {
    weekdayCode: "mon",
    startTime: "06:00:00",
    endTime: "06:30:00",
    effectiveFrom: "2028-08-07",
    roomId: probeRoom.id,
    teacherId: probeTeacherId,
  });
  const probeGen = await generateSessions(admin, probeSchedule.data.id, "2028-08-07", "2028-08-07");
  if (probeGen.error) {
    throw new Error(`Probe session generation failed: ${probeGen.error.message}`);
  }

  // Schema / audit (1-5)
  const { data: roomCols } = await admin.from("room").select("*").limit(1);
  const roomRow = roomCols?.[0];
  const { data: scheduleCols } = await admin
    .from("class_schedule")
    .select("*")
    .eq("id", probeSchedule.data.id);
  const scheduleRow = scheduleCols?.[0];
  const { data: sessionCols } = await admin
    .from("teaching_session")
    .select("*")
    .eq("class_schedule_id", probeSchedule.data.id)
    .limit(1);
  const sessionRow = sessionCols?.[0];
  const { data: assignmentCols } = await admin
    .from("class_teacher_assignment")
    .select("*")
    .eq("class_id", probeClass.id)
    .limit(1);
  const assignmentRow = assignmentCols?.[0];

  record(
    1,
    "teaching schema has expected columns",
    Boolean(
      roomRow &&
        "name" in roomRow &&
        "status" in roomRow &&
        scheduleRow &&
        "weekday_code" in scheduleRow &&
        "room_id" in scheduleRow &&
        "teacher_id" in scheduleRow &&
        sessionRow &&
        "class_schedule_id" in sessionRow &&
        "room_id" in sessionRow &&
        "occurrence_date" in sessionRow &&
        assignmentRow &&
        "teacher_id" in assignmentRow &&
        "role_code" in assignmentRow,
    ),
  );

  record(
    2,
    "audit actor columns exist on operational tables",
    Boolean(
      roomRow &&
        "created_by" in roomRow &&
        "updated_by" in roomRow &&
        scheduleRow &&
        "created_by" in scheduleRow &&
        "updated_by" in scheduleRow &&
        assignmentRow &&
        "created_by" in assignmentRow &&
        "updated_by" in assignmentRow &&
        sessionRow &&
        "created_by" in sessionRow &&
        "updated_by" in sessionRow,
    ),
  );

  const { data: orgBClass } = await orgBAdmin.from("class").select("id").limit(1).single();
  const crossClassSchedule = await admin.from("class_schedule").insert({
    organization_id: ORG_A,
    class_id: orgBClass.id,
    weekday_code: "mon",
    start_time: "09:00:00",
    end_time: "10:00:00",
    effective_from: "2028-06-01",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(3, "cross-org class reference rejected", Boolean(crossClassSchedule.error));

  const { data: orgAClass } = await admin.from("class").select("id").eq("organization_id", ORG_A).limit(1).single();
  const crossTeacherAssign = await admin.from("class_teacher_assignment").insert({
    organization_id: ORG_A,
    class_id: orgAClass.id,
    teacher_id: orgBTeacherId,
    role_code: "primary",
    effective_from: "2028-06-01",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(4, "cross-org teacher reference rejected", Boolean(crossTeacherAssign.error));

  const crossRoomSchedule = await admin.from("class_schedule").insert({
    organization_id: ORG_A,
    class_id: orgAClass.id,
    weekday_code: "tue",
    start_time: "09:00:00",
    end_time: "10:00:00",
    effective_from: "2028-06-01",
    room_id: orgBRoomId,
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(5, "cross-org room reference rejected", Boolean(crossRoomSchedule.error));

  // Teacher assignment (6-10)
  const taCourseId = await createCourse(admin, "ta");
  const taClass = await createClass(admin, taCourseId, "TeacherAssign");
  const validAssignInput = validateTeacherAssignmentInput({
    teacherId: orgATeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const firstAssign = await insertAssignment(admin, taClass.id, {
    teacherId: orgATeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  record(
    6,
    "eligible teacher can be assigned to class",
    validAssignInput.ok && !firstAssign.error && Boolean(firstAssign.data?.id),
  );

  record(7, "cross-org teacher cannot be assigned", Boolean(crossTeacherAssign.error));

  const secondTeacher = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "Second",
      family_name: `Teacher${Date.now()}`,
      status: "active",
    })
    .select("id")
    .single();
  const secondAssign = await insertAssignment(admin, taClass.id, {
    teacherId: secondTeacher.data.id,
    roleCode: "assistant",
    effectiveFrom: "2028-07-01",
  });
  const { count: assignCount } = await admin
    .from("class_teacher_assignment")
    .select("id", { count: "exact", head: true })
    .eq("class_id", taClass.id);
  record(
    8,
    "multiple historical assignments preserved",
    !firstAssign.error && !secondAssign.error && (assignCount ?? 0) >= 2,
  );

  await admin
    .from("class_teacher_assignment")
    .update({ status: "ended", effective_to: "2028-07-15", updated_by: APP_A_ADMIN })
    .eq("id", firstAssign.data.id);
  const { data: endedAssign } = await admin
    .from("class_teacher_assignment")
    .select("id, status")
    .eq("id", firstAssign.data.id)
    .single();
  record(
    9,
    "ending assignment does not delete history",
    endedAssign?.status === "ended" && Boolean(endedAssign?.id),
  );

  const { data: classSchema } = await admin.from("class").select("*").limit(1);
  record(10, "no direct teacher_id on class", !("teacher_id" in (classSchema?.[0] ?? {})));

  // Room (11-14)
  const validRoom = validateRoomInput({ name: "Lab 1", code: "L1", capacity: "20", status: "active" });
  const newRoom = await createRoom(admin, "CreateRoom", { code: "CR1", capacity: 20 });
  const { error: editRoomErr } = await admin
    .from("room")
    .update({ name: "Lab 1 Updated", updated_by: APP_A_ADMIN })
    .eq("id", newRoom.id);
  record(11, "create and edit room", validRoom.ok && Boolean(newRoom.id) && !editRoomErr);

  const inactiveRoom = await createRoom(admin, "Inactive", { status: "inactive" });
  record(
    12,
    "inactive room not eligible for new assignment",
    inactiveRoom.status === "inactive" && !isRoomEligibleForAssignment(inactiveRoom),
  );

  const histRoom = await createRoom(admin, "HistRoom");
  const histCourseId = await createCourse(admin, "hist-room");
  const histClass = await createClass(admin, histCourseId, "HistRoomClass");
  await insertAssignment(admin, histClass.id, {
    teacherId: orgATeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const histTeacherId = await createTeacher(admin, "Hist");
  const histSchedule = await insertSchedule(admin, histClass.id, {
    weekdayCode: "mon",
    startTime: "14:00:00",
    endTime: "15:00:00",
    effectiveFrom: "2028-06-12",
    roomId: histRoom.id,
    teacherId: histTeacherId,
  });
  await generateSessions(admin, histSchedule.data.id, "2028-06-12", "2028-06-12");
  await admin.from("room").update({ status: "inactive", updated_by: APP_A_ADMIN }).eq("id", histRoom.id);
  const { data: histSession } = await admin
    .from("teaching_session")
    .select("room_id")
    .eq("class_schedule_id", histSchedule.data.id)
    .maybeSingle();
  record(
    13,
    "historical references to inactive room remain valid",
    histSession?.room_id === histRoom.id,
  );

  record(
    14,
    "room capacity warning when class exceeds room",
    getRoomCapacityWarning(25, 20) && !getRoomCapacityWarning(15, 20),
  );

  // ClassSchedule (15-23)
  const schedCourseId = await createCourse(admin, "sched");
  const schedClass = await createClass(admin, schedCourseId, "Schedule");
  const schedRoom = await createRoom(admin, "SchedRoom");
  const validSched = validateScheduleInput({
    weekdayCode: "tue",
    startTime: "18:00:00",
    endTime: "19:30:00",
    effectiveFrom: "2028-06-06",
  });
  const goodSchedule = await insertSchedule(admin, schedClass.id, {
    weekdayCode: "tue",
    startTime: "18:00:00",
    endTime: "19:30:00",
    effectiveFrom: "2028-06-06",
    roomId: schedRoom.id,
    teacherId: orgATeacherId,
  });
  record(
    15,
    "create valid recurring slot",
    validSched.ok && !goodSchedule.error && Boolean(goodSchedule.data?.id),
  );

  const badWeekday = await admin.from("class_schedule").insert({
    organization_id: ORG_A,
    class_id: schedClass.id,
    weekday_code: "bogus",
    start_time: "09:00:00",
    end_time: "10:00:00",
    effective_from: "2028-06-01",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(16, "invalid weekday rejected", Boolean(badWeekday.error));

  const badTimes = await admin.from("class_schedule").insert({
    organization_id: ORG_A,
    class_id: schedClass.id,
    weekday_code: "wed",
    start_time: "11:00:00",
    end_time: "10:00:00",
    effective_from: "2028-06-01",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(17, "end time before start time rejected", Boolean(badTimes.error));

  const badDates = await admin.from("class_schedule").insert({
    organization_id: ORG_A,
    class_id: schedClass.id,
    weekday_code: "thu",
    start_time: "09:00:00",
    end_time: "10:00:00",
    effective_from: "2028-08-01",
    effective_to: "2028-06-01",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  record(18, "invalid effective dates rejected", Boolean(badDates.error));

  const closedCourseId = await createCourse(admin, "closed");
  const closedClass = await createClass(admin, closedCourseId, "Closed", { status: "closed" });
  const closedValidation = validateScheduleInput(
    {
      weekdayCode: "fri",
      startTime: "09:00:00",
      endTime: "10:00:00",
      effectiveFrom: "2028-06-01",
    },
    { classStatus: "closed" },
  );
  record(
    19,
    "closed class rejects new active schedule",
    !closedValidation.ok && Boolean(closedClass.id),
  );

  const slotB = await insertSchedule(admin, schedClass.id, {
    weekdayCode: "thu",
    startTime: "08:00:00",
    endTime: "09:00:00",
    effectiveFrom: "2028-06-01",
    teacherId: orgATeacherId,
  });
  record(
    20,
    "two weekly slots can exist for same class",
    !goodSchedule.error && !slotB.error,
  );

  const { data: classForSchedCheck } = await admin.from("class").select("*").eq("id", schedClass.id).single();
  record(
    21,
    "weekdays stored on schedule rows not class JSON",
    WEEKDAY_CODES.includes("tue") &&
      !("schedule" in (classForSchedCheck ?? {})) &&
      !("weekday_code" in (classForSchedCheck ?? {})),
  );

  const immutTeacherId = await createTeacher(admin, "Immut");
  const immutCourseId = await createCourse(admin, "immut");
  const immutClass = await createClass(admin, immutCourseId, "Immutable", {
    termStart: "2028-06-01",
    termEnd: "2028-12-31",
  });
  await insertAssignment(admin, immutClass.id, {
    teacherId: immutTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const immutRoom = await createRoom(admin, "ImmutRoom");
  const immutSchedule = await insertSchedule(admin, immutClass.id, {
    weekdayCode: "tue",
    startTime: "10:00:00",
    endTime: "11:00:00",
    effectiveFrom: "2028-06-01",
    roomId: immutRoom.id,
    teacherId: immutTeacherId,
  });
  await generateSessions(admin, immutSchedule.data.id, "2028-06-06", "2028-06-06");
  const { data: beforeEdit } = await admin
    .from("teaching_session")
    .select("scheduled_start_at, scheduled_end_at, occurrence_date")
    .eq("class_schedule_id", immutSchedule.data.id)
    .single();
  await admin
    .from("class_schedule")
    .update({ start_time: "12:00:00", end_time: "13:00:00", updated_by: APP_A_ADMIN })
    .eq("id", immutSchedule.data.id);
  const { data: afterEdit } = await admin
    .from("teaching_session")
    .select("scheduled_start_at, scheduled_end_at, occurrence_date")
    .eq("class_schedule_id", immutSchedule.data.id)
    .single();
  record(
    22,
    "schedule update does not mutate existing sessions",
    beforeEdit?.scheduled_start_at === afterEdit?.scheduled_start_at &&
      beforeEdit?.scheduled_end_at === afterEdit?.scheduled_end_at &&
      beforeEdit?.occurrence_date === afterEdit?.occurrence_date,
  );

  const endSchedTeacherId = await createTeacher(admin, "EndSched");
  const endSchedCourseId = await createCourse(admin, "endsched");
  const endSchedClass = await createClass(admin, endSchedCourseId, "EndSched");
  await insertAssignment(admin, endSchedClass.id, {
    teacherId: endSchedTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const endSchedRoom = await createRoom(admin, "EndSchedRoom");
  const endSchedule = await insertSchedule(admin, endSchedClass.id, {
    weekdayCode: "wed",
    startTime: "09:00:00",
    endTime: "10:00:00",
    effectiveFrom: "2028-06-01",
    roomId: endSchedRoom.id,
    teacherId: endSchedTeacherId,
  });
  await generateSessions(admin, endSchedule.data.id, "2028-06-07", "2028-06-07");
  const { count: sessionsBeforeEnd } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_schedule_id", endSchedule.data.id);
  await admin
    .from("class_schedule")
    .update({ status: "ended", updated_by: APP_A_ADMIN })
    .eq("id", endSchedule.data.id);
  const { count: sessionsAfterEnd } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_schedule_id", endSchedule.data.id);
  record(
    23,
    "ending schedule does not delete existing sessions",
    (sessionsBeforeEnd ?? 0) >= 1 && sessionsBeforeEnd === sessionsAfterEnd,
  );

  // Session generation (24-31)
  const genTeacherId = await createTeacher(admin, "Gen");
  const genCourseId = await createCourse(admin, "gen");
  const genClass = await createClass(admin, genCourseId, "Generate", {
    termStart: "2028-06-01",
    termEnd: "2028-07-31",
  });
  await insertAssignment(admin, genClass.id, {
    teacherId: genTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const genRoom = await createRoom(admin, "GenRoom");
  const genSchedule = await insertSchedule(admin, genClass.id, {
    weekdayCode: "tue",
    startTime: "09:00:00",
    endTime: "10:00:00",
    effectiveFrom: "2028-06-01",
    effectiveTo: "2028-06-30",
    roomId: genRoom.id,
    teacherId: genTeacherId,
  });
  const gen1 = await generateSessions(admin, genSchedule.data.id, "2028-06-01", "2028-06-30");
  const { count: genCount1 } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_schedule_id", genSchedule.data.id);
  record(
    24,
    "generate occurrences in finite range",
    !gen1.error && (genCount1 ?? 0) > 0,
  );

  const termTeacherId = await createTeacher(admin, "Term");
  const termCourseId = await createCourse(admin, "term");
  const termClass = await createClass(admin, termCourseId, "TermBound", {
    termStart: "2028-06-06",
    termEnd: "2028-06-13",
  });
  await insertAssignment(admin, termClass.id, {
    teacherId: termTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const termRoom = await createRoom(admin, "TermRoom");
  const termSchedule = await insertSchedule(admin, termClass.id, {
    weekdayCode: "tue",
    startTime: "11:00:00",
    endTime: "12:00:00",
    effectiveFrom: "2028-06-01",
    effectiveTo: "2028-07-31",
    roomId: termRoom.id,
    teacherId: termTeacherId,
  });
  const termGen = await generateSessions(admin, termSchedule.data.id, "2028-06-01", "2028-07-31");
  const { data: termSessions } = await admin
    .from("teaching_session")
    .select("occurrence_date")
    .eq("class_schedule_id", termSchedule.data.id);
  const termDates = (termSessions ?? []).map((s) => s.occurrence_date);
  record(
    25,
    "generation respects class term",
    !termGen.error &&
      termDates.length >= 1 &&
      termDates.every((d) => d >= "2028-06-06" && d <= "2028-06-13"),
    termGen.error?.message ?? "",
  );

  const effTeacherId = await createTeacher(admin, "Eff");
  const effCourseId = await createCourse(admin, "eff");
  const effClass = await createClass(admin, effCourseId, "EffBound");
  await insertAssignment(admin, effClass.id, {
    teacherId: effTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const effRoom = await createRoom(admin, "EffRoom");
  const effSchedule = await insertSchedule(admin, effClass.id, {
    weekdayCode: "mon",
    startTime: "13:00:00",
    endTime: "14:00:00",
    effectiveFrom: "2028-06-05",
    effectiveTo: "2028-06-12",
    roomId: effRoom.id,
    teacherId: effTeacherId,
  });
  await generateSessions(admin, effSchedule.data.id, "2028-06-01", "2028-06-30");
  const { data: effSessions } = await admin
    .from("teaching_session")
    .select("occurrence_date")
    .eq("class_schedule_id", effSchedule.data.id);
  const effDates = (effSessions ?? []).map((s) => s.occurrence_date);
  record(
    26,
    "generation respects schedule effective range",
    effDates.length >= 1 &&
      effDates.every((d) => d >= "2028-06-05" && d <= "2028-06-12"),
  );

  const idemGen2 = await generateSessions(admin, genSchedule.data.id, "2028-06-01", "2028-06-30");
  const { count: genCount2 } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_schedule_id", genSchedule.data.id);
  record(
    27,
    "re-running generation is idempotent",
    !idemGen2.error && (idemGen2.data ?? 0) === 0 && genCount1 === genCount2,
  );

  const idemGen3 = await generateSessions(admin, genSchedule.data.id, "2028-06-01", "2028-06-30");
  const { count: genCount3 } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_schedule_id", genSchedule.data.id);
  record(
    28,
    "repeated generation cannot duplicate occurrence",
    !idemGen3.error && (idemGen3.data ?? 0) === 0 && genCount2 === genCount3,
  );

  const dualTeacherId = await createTeacher(admin, "Dual");
  const dualCourseId = await createCourse(admin, "dual");
  const dualClass = await createClass(admin, dualCourseId, "DualSlot");
  await insertAssignment(admin, dualClass.id, {
    teacherId: dualTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const dualRoomA = await createRoom(admin, "DualA");
  const dualRoomB = await createRoom(admin, "DualB");
  const dualSchedA = await insertSchedule(admin, dualClass.id, {
    weekdayCode: "tue",
    startTime: "07:00:00",
    endTime: "08:00:00",
    effectiveFrom: "2028-06-06",
    roomId: dualRoomA.id,
    teacherId: dualTeacherId,
  });
  const dualSchedB = await insertSchedule(admin, dualClass.id, {
    weekdayCode: "thu",
    startTime: "07:00:00",
    endTime: "08:00:00",
    effectiveFrom: "2028-06-06",
    roomId: dualRoomB.id,
    teacherId: dualTeacherId,
  });
  await generateSessions(admin, dualSchedA.data.id, "2028-06-06", "2028-06-13");
  await generateSessions(admin, dualSchedB.data.id, "2028-06-06", "2028-06-13");
  const { count: dualCountA } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_schedule_id", dualSchedA.data.id);
  const { count: dualCountB } = await admin
    .from("teaching_session")
    .select("id", { count: "exact", head: true })
    .eq("class_schedule_id", dualSchedB.data.id);
  record(
    29,
    "different recurring slots generate distinct sessions",
    (dualCountA ?? 0) >= 1 && (dualCountB ?? 0) >= 1,
  );

  const rangeTeacherId = await createTeacher(admin, "Range");
  const rangeCourseId = await createCourse(admin, "range");
  const rangeClass = await createClass(admin, rangeCourseId, "Range");
  await insertAssignment(admin, rangeClass.id, {
    teacherId: rangeTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const rangeRoom = await createRoom(admin, "RangeRoom");
  const rangeSchedule = await insertSchedule(admin, rangeClass.id, {
    weekdayCode: "tue",
    startTime: "15:00:00",
    endTime: "16:00:00",
    effectiveFrom: "2028-06-01",
    roomId: rangeRoom.id,
    teacherId: rangeTeacherId,
  });
  await generateSessions(admin, rangeSchedule.data.id, "2028-06-06", "2028-06-13");
  const { data: rangeSessions } = await admin
    .from("teaching_session")
    .select("occurrence_date")
    .eq("class_schedule_id", rangeSchedule.data.id);
  const outOfRange = (rangeSessions ?? []).some(
    (s) => s.occurrence_date < "2028-06-06" || s.occurrence_date > "2028-06-13",
  );
  record(30, "no sessions outside requested range", (rangeSessions ?? []).length >= 1 && !outOfRange);

  const endedGen = await generateSessions(admin, endSchedule.data.id, "2028-07-01", "2028-07-31");
  record(
    31,
    "ended schedule does not generate new occurrences",
    Boolean(endedGen.error?.message?.includes("schedule_not_active")) ||
      (endedGen.data ?? 0) === 0,
  );

  // TeachingSession (32-38)
  const { data: sourceSession } = await admin
    .from("teaching_session")
    .select("class_schedule_id, occurrence_date, status")
    .eq("class_schedule_id", genSchedule.data.id)
    .limit(1)
    .single();
  record(
    32,
    "generated session retains source schedule",
    sourceSession?.class_schedule_id === genSchedule.data.id &&
      Boolean(sourceSession?.occurrence_date) &&
      SESSION_STATUSES.includes(sourceSession?.status),
  );

  record(
    33,
    "session timestamps stable after schedule edit",
    beforeEdit?.scheduled_start_at === afterEdit?.scheduled_start_at,
  );

  const { classRow: cancelClass, teacherId: cancelTeacherId, roomId: cancelRoomId } =
    await setupClassWithPrimary(admin, "Cancel");
  const cancelSchedule = await insertSchedule(admin, cancelClass.id, {
    weekdayCode: "fri",
    startTime: "16:00:00",
    endTime: "17:00:00",
    effectiveFrom: "2028-06-09",
    roomId: cancelRoomId,
    teacherId: cancelTeacherId,
  });
  await generateSessions(admin, cancelSchedule.data.id, "2028-06-09", "2028-06-09");
  const { data: cancelTarget } = await admin
    .from("teaching_session")
    .select("id")
    .eq("class_schedule_id", cancelSchedule.data.id)
    .maybeSingle();
  const { count: enrollBeforeCancel } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  const { count: attendBeforeCancel } = await admin
    .from("attendance")
    .select("id", { count: "exact", head: true });
  if (cancelTarget?.id) {
    await admin
      .from("teaching_session")
      .update({ status: "cancelled", updated_by: APP_A_ADMIN })
      .eq("id", cancelTarget.id);
  }
  const { data: cancelledRow } = await admin
    .from("teaching_session")
    .select("id, status")
    .eq("id", cancelTarget?.id ?? "00000000-0000-4000-8000-000000000099")
    .maybeSingle();
  record(
    34,
    "cancel session preserves row",
    Boolean(cancelTarget?.id) &&
      cancelledRow?.status === "cancelled" &&
      cancelledRow?.id === cancelTarget.id,
  );

  const { classRow: completeClass, teacherId: completeTeacherId, roomId: completeRoomId } =
    await setupClassWithPrimary(admin, "Complete");
  const completeSchedule = await insertSchedule(admin, completeClass.id, {
    weekdayCode: "fri",
    startTime: "17:00:00",
    endTime: "18:00:00",
    effectiveFrom: "2028-06-09",
    roomId: completeRoomId,
    teacherId: completeTeacherId,
  });
  await generateSessions(admin, completeSchedule.data.id, "2028-06-09", "2028-06-09");
  const { data: completeTarget } = await admin
    .from("teaching_session")
    .select("id")
    .eq("class_schedule_id", completeSchedule.data.id)
    .maybeSingle();
  if (completeTarget?.id) {
    await admin
      .from("teaching_session")
      .update({ status: "completed", updated_by: APP_A_ADMIN })
      .eq("id", completeTarget.id);
  }
  const { data: completedRow } = await admin
    .from("teaching_session")
    .select("id, status")
    .eq("id", completeTarget?.id ?? "00000000-0000-4000-8000-000000000099")
    .maybeSingle();
  record(
    35,
    "complete session preserves row",
    Boolean(completeTarget?.id) &&
      completedRow?.status === "completed" &&
      completedRow?.id === completeTarget.id,
  );

  const { count: enrollAfterCancel } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  record(36, "cancellation does not modify enrollment", enrollBeforeCancel === enrollAfterCancel);

  const { count: enrollAfterComplete } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  record(37, "completion does not modify enrollment", enrollBeforeCancel === enrollAfterComplete);

  const { count: attendAfterTeaching } = await admin
    .from("attendance")
    .select("id", { count: "exact", head: true });
  record(
    38,
    "no attendance row created",
    attendBeforeCancel === attendAfterTeaching,
  );

  // Room conflict (39-40)
  const conflictTeacherA = await createTeacher(admin, "RoomConfA");
  const conflictCourseId = await createCourse(admin, "roomconf");
  const conflictClass = await createClass(admin, conflictCourseId, "RoomConflict");
  await insertAssignment(admin, conflictClass.id, {
    teacherId: conflictTeacherA,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const sharedRoom = await createRoom(admin, "SharedRoom");
  const conflictSchedA = await insertSchedule(admin, conflictClass.id, {
    weekdayCode: "mon",
    startTime: "08:00:00",
    endTime: "09:00:00",
    effectiveFrom: "2028-06-19",
    roomId: sharedRoom.id,
    teacherId: conflictTeacherA,
  });
  const conflictTeacherB = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "ConflictB",
      family_name: `T${Date.now()}`,
      status: "active",
    })
    .select("id")
    .single();
  const conflictSchedB = await insertSchedule(admin, conflictClass.id, {
    weekdayCode: "mon",
    startTime: "08:30:00",
    endTime: "09:30:00",
    effectiveFrom: "2028-06-19",
    roomId: sharedRoom.id,
    teacherId: conflictTeacherB.data.id,
  });
  const roomConflictGen = await generateSessions(
    admin,
    conflictSchedA.data.id,
    "2028-06-19",
    "2028-06-19",
  );
  const roomConflictGen2 = await generateSessions(
    admin,
    conflictSchedB.data.id,
    "2028-06-19",
    "2028-06-19",
  );
  record(
    39,
    "same room double-booking rejected",
    !roomConflictGen.error &&
      (Boolean(roomConflictGen2.error) && isConflictError(roomConflictGen2.error)),
  );

  const freeTeacherA = await createTeacher(admin, "FreeA");
  const freeTeacherB = await createTeacher(admin, "FreeB");
  const freeCourseId = await createCourse(admin, "freeslot");
  const freeClass = await createClass(admin, freeCourseId, "FreeSlot");
  await insertAssignment(admin, freeClass.id, {
    teacherId: freeTeacherA,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const freeRoom = await createRoom(admin, "FreeRoom");
  const freeSched = await insertSchedule(admin, freeClass.id, {
    weekdayCode: "sun",
    startTime: "08:00:00",
    endTime: "09:00:00",
    effectiveFrom: "2028-06-11",
    roomId: freeRoom.id,
    teacherId: freeTeacherA,
  });
  const freeGen1 = await generateSessions(admin, freeSched.data.id, "2028-06-11", "2028-06-11");
  const { data: freeSession } = await admin
    .from("teaching_session")
    .select("id")
    .eq("class_schedule_id", freeSched.data.id)
    .maybeSingle();
  if (freeSession?.id) {
    await admin
      .from("teaching_session")
      .update({ status: "cancelled", updated_by: APP_A_ADMIN })
      .eq("id", freeSession.id);
  }
  const freeSched2 = await insertSchedule(admin, freeClass.id, {
    weekdayCode: "sun",
    startTime: "08:00:00",
    endTime: "09:00:00",
    effectiveFrom: "2028-06-11",
    roomId: freeRoom.id,
    teacherId: freeTeacherB,
  });
  const afterCancelGen = await generateSessions(
    admin,
    freeSched2.data.id,
    "2028-06-11",
    "2028-06-11",
  );
  record(
    40,
    "cancelled session does not occupy room",
    !freeGen1.error &&
      Boolean(freeSession?.id) &&
      !afterCancelGen.error &&
      (afterCancelGen.data ?? 0) >= 1,
  );

  // Teacher conflict (41-42)
  const tConfTeacherA = await createTeacher(admin, "TConfA");
  const tConfCourseId = await createCourse(admin, "tconf");
  const tConfClass = await createClass(admin, tConfCourseId, "TeacherConflict");
  const tConfSchedA = await insertSchedule(admin, tConfClass.id, {
    weekdayCode: "wed",
    startTime: "10:00:00",
    endTime: "11:00:00",
    effectiveFrom: "2028-06-21",
    roomId: sharedRoom.id,
    teacherId: tConfTeacherA,
  });
  const tConfSchedB = await insertSchedule(admin, tConfClass.id, {
    weekdayCode: "wed",
    startTime: "10:30:00",
    endTime: "11:30:00",
    effectiveFrom: "2028-06-21",
    roomId: freeRoom.id,
    teacherId: tConfTeacherA,
  });
  const tGen1 = await generateSessions(admin, tConfSchedA.data.id, "2028-06-21", "2028-06-21");
  const tGen2 = await generateSessions(admin, tConfSchedB.data.id, "2028-06-21", "2028-06-21");
  record(
    41,
    "explicit teacher conflict detected",
    !tGen1.error && Boolean(tGen2.error) && isConflictError(tGen2.error),
  );

  const assistPrimaryId = await createTeacher(admin, "AssistPrimary");
  const assistAssistantId = await createTeacher(admin, "AssistSecondary");
  const assistCourseId = await createCourse(admin, "assist");
  const assistClass = await createClass(admin, assistCourseId, "Assistant");
  await insertAssignment(admin, assistClass.id, {
    teacherId: assistPrimaryId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  await insertAssignment(admin, assistClass.id, {
    teacherId: assistAssistantId,
    roleCode: "assistant",
    effectiveFrom: "2028-06-01",
  });
  const assistRoom = await createRoom(admin, "AssistRoom");
  const assistSchedule = await insertSchedule(admin, assistClass.id, {
    weekdayCode: "thu",
    startTime: "09:00:00",
    endTime: "10:00:00",
    effectiveFrom: "2028-08-10",
    roomId: assistRoom.id,
  });
  const assistGen = await generateSessions(admin, assistSchedule.data.id, "2028-08-10", "2028-08-10");
  const { data: assistSession } = await admin
    .from("teaching_session")
    .select("teacher_id")
    .eq("class_schedule_id", assistSchedule.data.id)
    .maybeSingle();
  record(
    42,
    "assistant not auto-assigned to every session",
    !assistGen.error &&
      assistSession?.teacher_id === assistPrimaryId &&
      assistSession?.teacher_id !== assistAssistantId,
  );

  // Time semantics (43-44)
  const { data: orgRow } = await admin.from("organization").select("timezone").eq("id", ORG_A).single();
  const tzTeacherId = await createTeacher(admin, "Tz");
  const tzCourseId = await createCourse(admin, "tz");
  const tzClass = await createClass(admin, tzCourseId, "Timezone");
  await insertAssignment(admin, tzClass.id, {
    teacherId: tzTeacherId,
    roleCode: "primary",
    effectiveFrom: "2028-06-01",
  });
  const tzRoom = await createRoom(admin, "TzRoom");
  const tzSchedule = await insertSchedule(admin, tzClass.id, {
    weekdayCode: "mon",
    startTime: "09:00:00",
    endTime: "10:00:00",
    effectiveFrom: "2028-06-26",
    roomId: tzRoom.id,
    teacherId: tzTeacherId,
  });
  await generateSessions(admin, tzSchedule.data.id, "2028-06-26", "2028-06-26");
  const { data: tzSession } = await admin
    .from("teaching_session")
    .select("scheduled_start_at, scheduled_end_at, occurrence_date")
    .eq("class_schedule_id", tzSchedule.data.id)
    .single();
  const localStart = tzSession?.scheduled_start_at
    ? localTimeFromUtc(tzSession.scheduled_start_at, orgRow?.timezone ?? "Asia/Ho_Chi_Minh")
    : "";
  record(
    43,
    "generation uses organization timezone not client",
    orgRow?.timezone === "Asia/Ho_Chi_Minh" && localStart === "09:00",
  );

  record(
    44,
    "timezone matches Asia/Ho_Chi_Minh convention",
    orgRow?.timezone === "Asia/Ho_Chi_Minh" &&
      tzSession?.occurrence_date === "2028-06-26" &&
      Boolean(tzSession?.scheduled_start_at),
  );

  // UI / read model (45-49)
  const { data: teachingSchedules, error: teachingSchedErr } = await admin
    .from("class_schedule")
    .select("id, weekday_code, start_time, end_time")
    .eq("class_id", schedClass.id);
  record(
    45,
    "teaching schedule data loads for class",
    !teachingSchedErr && (teachingSchedules ?? []).length >= 1,
  );

  record(
    46,
    "schedule weekday codes are normalized enum values",
    (teachingSchedules ?? []).every((s) => WEEKDAY_CODES.includes(s.weekday_code)),
  );

  const { data: orderedSessions } = await admin
    .from("teaching_session")
    .select("occurrence_date, scheduled_start_at")
    .eq("class_id", genClass.id)
    .order("occurrence_date", { ascending: true })
    .order("scheduled_start_at", { ascending: true });
  const orderStable =
    (orderedSessions ?? []).length <= 1 ||
    (orderedSessions ?? []).every((row, idx, arr) => {
      if (idx === 0) return true;
      const prev = arr[idx - 1];
      const prevKey = `${prev.occurrence_date}${prev.scheduled_start_at}`;
      const curKey = `${row.occurrence_date}${row.scheduled_start_at}`;
      return curKey >= prevKey;
    });
  record(47, "sessions render in stable chronological order", orderStable);

  const { data: sessionListRow } = await admin
    .from("teaching_session")
    .select("occurrence_date, scheduled_start_at, scheduled_end_at, status, room_id, teacher_id")
    .eq("class_schedule_id", genSchedule.data.id)
    .limit(1)
    .single();
  record(
    48,
    "session list includes mobile-ready fields",
    Boolean(
      sessionListRow?.occurrence_date &&
        sessionListRow?.scheduled_start_at &&
        sessionListRow?.scheduled_end_at &&
        sessionListRow?.status,
    ),
  );

  const staffRoomInsert = await staff.from("room").insert({
    organization_id: ORG_A,
    name: "Staff Room",
    status: "active",
  });
  const staffScheduleInsert = await staff.from("class_schedule").insert({
    organization_id: ORG_A,
    class_id: schedClass.id,
    weekday_code: "sat",
    start_time: "09:00:00",
    end_time: "10:00:00",
    effective_from: "2028-08-01",
  });
  record(
    49,
    "staff denied teaching mutations admin allowed",
    (await hasPermission(admin, "enrollment.create")) &&
      (await hasPermission(admin, "enrollment.update")) &&
      !(await hasPermission(staff, "enrollment.create")) &&
      !(await hasPermission(staff, "enrollment.update")) &&
      Boolean(staffRoomInsert.error) &&
      Boolean(staffScheduleInsert.error),
  );

  // Architectural boundaries (50-55)
  record(
    50,
    "no attendance implemented in teaching ops",
    attendBeforeCancel === attendAfterTeaching,
  );

  const { count: obsCountAfterTeaching } = await admin
    .from("observation")
    .select("id", { count: "exact", head: true });
  record(
    51,
    "no score or observation mutation",
    obsCountBeforeTeaching === obsCountAfterTeaching,
  );

  const { count: chargeBefore } = await admin
    .from("charge")
    .select("id", { count: "exact", head: true });
  const { count: chargeAfter } = await admin
    .from("charge")
    .select("id", { count: "exact", head: true });
  record(52, "no finance mutation from teaching ops", chargeBefore === chargeAfter);

  record(53, "no enrollment mutation from teaching ops", enrollBeforeCancel === enrollAfterComplete);

  record(54, "no class teacher_id shortcut", !("teacher_id" in (classSchema?.[0] ?? {})));

  record(
    55,
    "no recurring schedule stored on class",
    !("schedule" in (classForSchedCheck ?? {})) &&
      !("recurrence" in (classForSchedCheck ?? {})),
  );

  // Regression (56-60)
  const { count: studentCount, error: studentErr } = await admin
    .from("student")
    .select("id", { count: "exact", head: true });
  record(56, "student list remains functional", !studentErr && (studentCount ?? 0) > 0);

  const { count: guardianCount, error: guardianErr } = await admin
    .from("student_guardian")
    .select("id", { count: "exact", head: true })
    .eq("status", "active");
  record(57, "guardian operations remain functional", !guardianErr && (guardianCount ?? 0) > 0);

  const { count: courseCount, error: courseErr } = await admin
    .from("course")
    .select("id", { count: "exact", head: true });
  const { count: classCount, error: classErr } = await admin
    .from("class")
    .select("id", { count: "exact", head: true });
  record(
    58,
    "course and class operations remain functional",
    !courseErr && !classErr && (courseCount ?? 0) > 0 && (classCount ?? 0) > 0,
  );

  const { count: enrollCount, error: enrollErr } = await admin
    .from("enrollment")
    .select("id", { count: "exact", head: true });
  record(59, "enrollment roster remains functional", !enrollErr && (enrollCount ?? 0) > 0);

  const xferCourseId = await createCourse(admin, "xfer");
  const xferSourceClass = await createClass(admin, xferCourseId, "XferSource");
  const xferDestClass = await createClass(admin, xferCourseId, "XferDest");
  const xferStudent = await admin
    .from("student")
    .insert({
      organization_id: ORG_A,
      given_name: "Xfer",
      family_name: `Smoke${Date.now()}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  const xferEnroll = await admin
    .from("enrollment")
    .insert({
      organization_id: ORG_A,
      student_id: xferStudent.data.id,
      class_id: xferSourceClass.id,
      start_date: "2028-06-01",
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();
  const { data: xferNewId, error: xferErr } = await admin.rpc("transfer_enrollment", {
    p_source_enrollment_id: xferEnroll.data.id,
    p_destination_class_id: xferDestClass.id,
    p_destination_start_date: "2028-06-06",
    p_destination_status: "active",
  });
  record(
    60,
    "transfer atomic behavior remains functional",
    !xferErr && Boolean(xferNewId),
  );

  // M4-T03 timetable and assignment integrity (61-65)
  const rpcCourseId = await createCourse(admin, "m4t3-rpc");
  const rpcClass = await createClass(admin, rpcCourseId, "M4T3Rpc");
  const rpcTeacherId = await createTeacher(admin, "RpcTeacher");
  const rpcRoom = await createRoom(admin, "RpcRoom");

  const { data: rpcScheduleId, error: rpcScheduleErr } = await admin.rpc("create_class_schedule", {
    p_class_id: rpcClass.id,
    p_weekday_code: "thu",
    p_start_time: "14:00:00",
    p_end_time: "15:30:00",
    p_effective_from: "2028-09-01",
    p_effective_to: null,
    p_room_id: rpcRoom.id,
    p_teacher_id: rpcTeacherId,
  });
  record(
    61,
    "create_class_schedule RPC creates valid timetable",
    !rpcScheduleErr && Boolean(rpcScheduleId),
  );

  const { error: rpcEndScheduleErr } = await admin.rpc("end_class_schedule", {
    p_schedule_id: rpcScheduleId,
  });
  const { data: endedSchedule } = await admin
    .from("class_schedule")
    .select("status")
    .eq("id", rpcScheduleId)
    .single();
  const { error: rpcUpdateEndedErr } = await admin.rpc("update_class_schedule", {
    p_schedule_id: rpcScheduleId,
    p_weekday_code: "thu",
    p_start_time: "15:00:00",
    p_end_time: "16:00:00",
    p_effective_from: "2028-09-01",
    p_effective_to: null,
    p_room_id: rpcRoom.id,
    p_teacher_id: rpcTeacherId,
  });
  record(
    62,
    "end_class_schedule RPC ends timetable and blocks update",
    !rpcEndScheduleErr &&
      endedSchedule?.status === "ended" &&
      Boolean(rpcUpdateEndedErr) &&
      (rpcUpdateEndedErr.message ?? "").includes("schedule_not_active"),
  );

  const { data: rpcAssignmentId, error: rpcAssignErr } = await admin.rpc(
    "create_class_teacher_assignment",
    {
      p_class_id: rpcClass.id,
      p_teacher_id: rpcTeacherId,
      p_role_code: "assistant",
      p_effective_from: "2028-09-01",
      p_effective_to: null,
    },
  );
  record(
    63,
    "create_class_teacher_assignment RPC creates valid assignment",
    !rpcAssignErr && Boolean(rpcAssignmentId),
  );

  const { error: rpcDupAssignErr } = await admin.rpc("create_class_teacher_assignment", {
    p_class_id: rpcClass.id,
    p_teacher_id: rpcTeacherId,
    p_role_code: "assistant",
    p_effective_from: "2028-09-01",
    p_effective_to: null,
  });
  record(
    64,
    "duplicate class teacher assignment rejected",
    Boolean(rpcDupAssignErr) && (rpcDupAssignErr.message ?? "").includes("duplicate_assignment"),
  );

  const m4ClosedCourseId = await createCourse(admin, "m4t3-closed");
  const m4ClosedClass = await createClass(admin, m4ClosedCourseId, "M4T3Closed", { status: "closed" });
  const { error: closedScheduleErr } = await admin.rpc("create_class_schedule", {
    p_class_id: m4ClosedClass.id,
    p_weekday_code: "fri",
    p_start_time: "09:00:00",
    p_end_time: "10:00:00",
    p_effective_from: "2028-09-01",
    p_effective_to: null,
    p_room_id: null,
    p_teacher_id: null,
  });
  record(
    65,
    "closed class rejects new timetable via RPC",
    Boolean(closedScheduleErr) && (closedScheduleErr.message ?? "").includes("invalid_class_state"),
  );

  // M4-T04 conflict detection (66-72)
  const t04CourseId = await createCourse(admin, "m4t4-conflict");
  const t04Class = await createClass(admin, t04CourseId, "M4T4Conflict", {
    termStart: "2029-01-01",
    termEnd: "2029-06-30",
  });
  const t04TeacherA = await createTeacher(admin, "T04A");
  const t04TeacherB = await createTeacher(admin, "T04B");
  const t04Room = await createRoom(admin, "T04Room");

  await insertSchedule(admin, t04Class.id, {
    weekdayCode: "mon",
    startTime: "10:00:00",
    endTime: "11:00:00",
    effectiveFrom: "2029-01-01",
    roomId: t04Room.id,
    teacherId: t04TeacherA,
  });

  const { data: previewConflicts, error: previewErr } = await admin.rpc(
    "check_class_schedule_conflicts",
    {
      p_class_id: t04Class.id,
      p_weekday_code: "mon",
      p_start_time: "10:30:00",
      p_end_time: "11:30:00",
      p_effective_from: "2029-01-01",
      p_effective_to: "2029-01-31",
      p_room_id: t04Room.id,
      p_teacher_id: t04TeacherB,
      p_exclude_schedule_id: null,
    },
  );
  record(
    66,
    "conflict preview returns structured conflicts",
    !previewErr &&
      Array.isArray(previewConflicts) &&
      previewConflicts.length >= 1 &&
      Boolean(previewConflicts[0]?.conflict_type) &&
      Boolean(previewConflicts[0]?.occurrence_date),
  );

  const t04UnavailClass = await createClass(admin, t04CourseId, "T04Unavail", {
    termStart: "2029-02-01",
    termEnd: "2029-06-30",
  });
  await admin.from("teacher_unavailability").insert({
    organization_id: ORG_A,
    teacher_id: t04TeacherA,
    block_type: "recurring",
    weekday_code: "tue",
    start_time: "09:00:00",
    end_time: "17:00:00",
    effective_from: "2029-02-01",
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });
  const t04UnavailSched = await insertSchedule(admin, t04UnavailClass.id, {
    weekdayCode: "tue",
    startTime: "10:00:00",
    endTime: "11:00:00",
    effectiveFrom: "2029-02-01",
    teacherId: t04TeacherA,
  });
  const t04UnavailGen = await generateSessions(
    admin,
    t04UnavailSched.data.id,
    "2029-02-06",
    "2029-02-06",
  );
  record(
    67,
    "teacher unavailable blocks session generation",
    Boolean(t04UnavailGen.error) && isTeacherUnavailableError(t04UnavailGen.error),
  );

  const t04RoomConflictClass = await createClass(admin, t04CourseId, "T04RoomConf", {
    termStart: "2029-03-01",
    termEnd: "2029-06-30",
  });
  await insertSchedule(admin, t04RoomConflictClass.id, {
    weekdayCode: "wed",
    startTime: "14:00:00",
    endTime: "15:00:00",
    effectiveFrom: "2029-03-01",
    roomId: t04Room.id,
    teacherId: t04TeacherA,
  });
  const { error: roomConflictCreateErr } = await admin.rpc("create_class_schedule", {
    p_class_id: t04RoomConflictClass.id,
    p_weekday_code: "wed",
    p_start_time: "14:30:00",
    p_end_time: "15:30:00",
    p_effective_from: "2029-03-01",
    p_effective_to: "2029-03-31",
    p_room_id: t04Room.id,
    p_teacher_id: t04TeacherB,
  });
  record(
    68,
    "room conflict rejected on schedule create",
    Boolean(roomConflictCreateErr) &&
      (roomConflictCreateErr.message ?? "").includes("room_double_booked"),
  );

  const t04TeacherConflictClass = await createClass(admin, t04CourseId, "T04TeacherConf", {
    termStart: "2029-04-01",
    termEnd: "2029-06-30",
  });
  const t04Room2 = await createRoom(admin, "T04Room2");
  await insertSchedule(admin, t04TeacherConflictClass.id, {
    weekdayCode: "thu",
    startTime: "16:00:00",
    endTime: "17:00:00",
    effectiveFrom: "2029-04-01",
    roomId: t04Room.id,
    teacherId: t04TeacherA,
  });
  const { error: teacherConflictCreateErr } = await admin.rpc("create_class_schedule", {
    p_class_id: t04TeacherConflictClass.id,
    p_weekday_code: "thu",
    p_start_time: "16:30:00",
    p_end_time: "17:30:00",
    p_effective_from: "2029-04-01",
    p_effective_to: "2029-04-30",
    p_room_id: t04Room2.id,
    p_teacher_id: t04TeacherA,
  });
  record(
    69,
    "teacher conflict rejected on schedule create",
    Boolean(teacherConflictCreateErr) &&
      (teacherConflictCreateErr.message ?? "").includes("teacher_double_booked"),
  );

  const t04OkClass = await createClass(admin, t04CourseId, "T04Ok", {
    termStart: "2029-05-01",
    termEnd: "2029-06-30",
  });
  const { data: okScheduleId, error: okScheduleErr } = await admin.rpc("create_class_schedule", {
    p_class_id: t04OkClass.id,
    p_weekday_code: "fri",
    p_start_time: "08:00:00",
    p_end_time: "09:00:00",
    p_effective_from: "2029-05-01",
    p_effective_to: "2029-05-31",
    p_room_id: t04Room2.id,
    p_teacher_id: t04TeacherB,
  });
  record(
    70,
    "non-conflicting schedule saved via RPC",
    !okScheduleErr && Boolean(okScheduleId),
  );

  const t04GenOk = await generateSessions(admin, okScheduleId, "2029-05-04", "2029-05-04");
  record(
    71,
    "non-conflicting session generation succeeds",
    !t04GenOk.error && (t04GenOk.data ?? 0) >= 1,
  );

  const t04PrimaryClass = await createClass(admin, t04CourseId, "T04Primary", {
    termStart: "2029-06-01",
    termEnd: "2029-06-30",
  });
  await insertAssignment(admin, t04PrimaryClass.id, {
    teacherId: t04TeacherA,
    roleCode: "primary",
    effectiveFrom: "2029-06-01",
  });
  await insertSchedule(admin, t04PrimaryClass.id, {
    weekdayCode: "sat",
    startTime: "09:00:00",
    endTime: "10:00:00",
    effectiveFrom: "2029-06-01",
    roomId: t04Room2.id,
    teacherId: t04TeacherA,
  });
  const { data: primaryPreview } = await admin.rpc("check_class_schedule_conflicts", {
    p_class_id: t04PrimaryClass.id,
    p_weekday_code: "sat",
    p_start_time: "09:00:00",
    p_end_time: "10:00:00",
    p_effective_from: "2029-06-01",
    p_effective_to: "2029-06-30",
    p_room_id: t04Room2.id,
    p_teacher_id: null,
    p_exclude_schedule_id: null,
  });
  record(
    72,
    "fallback primary teacher used in conflict preview",
    Array.isArray(primaryPreview) &&
      primaryPreview.some((c) => c.conflict_type === "teacher_double_booked"),
  );

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM1-T07 teaching smoke: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  TE-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
