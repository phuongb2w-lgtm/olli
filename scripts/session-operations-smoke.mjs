#!/usr/bin/env node
/**
 * M4-T06 session operations smoke tests.
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
const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} SO-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const ts = Date.now();

  const { data: course } = await admin
    .from("course")
    .insert({
      organization_id: ORG_A,
      code: `SO-${ts}`,
      name: `Session Ops ${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: classRow } = await admin
    .from("class")
    .insert({
      organization_id: ORG_A,
      course_id: course.id,
      name: `SO Class ${ts}`,
      status: "active",
      term_start_date: "2038-01-01",
      term_end_date: "2038-06-30",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: teacherA } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "SO",
      family_name: `A${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: teacherB } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "SO",
      family_name: `B${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: roomA } = await admin
    .from("room")
    .insert({
      organization_id: ORG_A,
      code: `SOA-${ts}`,
      name: `SO Room A ${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: roomB } = await admin
    .from("room")
    .insert({
      organization_id: ORG_A,
      code: `SOB-${ts}`,
      name: `SO Room B ${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  // Monday 2038-01-04
  const { data: schedule } = await admin
    .from("class_schedule")
    .insert({
      organization_id: ORG_A,
      class_id: classRow.id,
      weekday_code: "mon",
      start_time: "09:00:00",
      end_time: "10:00:00",
      effective_from: "2038-01-01",
      room_id: roomA.id,
      teacher_id: teacherA.id,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: session } = await admin
    .from("teaching_session")
    .insert({
      organization_id: ORG_A,
      class_id: classRow.id,
      class_schedule_id: schedule.id,
      teacher_id: teacherA.id,
      room_id: roomA.id,
      occurrence_date: "2038-01-04",
      scheduled_start_at: "2038-01-04T02:00:00Z",
      scheduled_end_at: "2038-01-04T03:00:00Z",
      status: "scheduled",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id, occurrence_date")
    .single();

  const { error: rescheduleErr } = await admin.rpc("reschedule_teaching_session", {
    p_session_id: session.id,
    p_scheduled_start_at: "2038-01-05T02:00:00Z",
    p_scheduled_end_at: "2038-01-05T03:00:00Z",
    p_reason: "Smoke reschedule",
  });
  const { data: afterReschedule } = await admin
    .from("teaching_session")
    .select("occurrence_date, scheduled_start_at, teacher_id, room_id, status")
    .eq("id", session.id)
    .single();
  record(
    1,
    "reschedule success",
    !rescheduleErr &&
      afterReschedule?.occurrence_date === "2038-01-04" &&
      afterReschedule?.scheduled_start_at?.startsWith("2038-01-05"),
  );

  // Conflict session for teacher overlap
  const { data: blocker } = await admin
    .from("teaching_session")
    .insert({
      organization_id: ORG_A,
      class_id: classRow.id,
      teacher_id: teacherA.id,
      room_id: roomB.id,
      scheduled_start_at: "2038-01-06T02:00:00Z",
      scheduled_end_at: "2038-01-06T03:00:00Z",
      status: "scheduled",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { error: conflictErr } = await admin.rpc("reschedule_teaching_session", {
    p_session_id: session.id,
    p_scheduled_start_at: "2038-01-06T02:00:00Z",
    p_scheduled_end_at: "2038-01-06T03:00:00Z",
    p_reason: "Should conflict",
  });
  record(2, "reschedule conflict failure", Boolean(conflictErr));

  const { error: subErr } = await admin.rpc("substitute_session_teacher", {
    p_session_id: session.id,
    p_new_teacher_id: teacherB.id,
    p_reason: "Smoke substitute",
  });
  const { data: afterSub } = await admin
    .from("teaching_session")
    .select("teacher_id")
    .eq("id", session.id)
    .single();
  const { data: scheduleTeacher } = await admin
    .from("class_schedule")
    .select("teacher_id")
    .eq("id", schedule.id)
    .single();
  record(
    3,
    "substitute success without timetable change",
    !subErr && afterSub?.teacher_id === teacherB.id && scheduleTeacher?.teacher_id === teacherA.id,
  );

  const { error: roomErr } = await admin.rpc("change_session_room", {
    p_session_id: session.id,
    p_new_room_id: roomB.id,
    p_reason: "Smoke room",
  });
  const { data: afterRoom } = await admin
    .from("teaching_session")
    .select("room_id")
    .eq("id", session.id)
    .single();
  const { data: scheduleRoom } = await admin
    .from("class_schedule")
    .select("room_id")
    .eq("id", schedule.id)
    .single();
  record(
    4,
    "room change success without timetable change",
    !roomErr && afterRoom?.room_id === roomB.id && scheduleRoom?.room_id === roomA.id,
  );

  const { data: history } = await admin.rpc("list_teaching_session_changes", {
    p_session_id: session.id,
  });
  record(5, "history read", Array.isArray(history) && history.length >= 3);

  const { data: calTue } = await admin.rpc("list_operational_calendar", {
    p_date_from: "2038-01-05",
    p_date_to: "2038-01-05",
    p_class_id: classRow.id,
    p_teacher_id: null,
    p_room_id: null,
  });
  const { data: calMon } = await admin.rpc("list_operational_calendar", {
    p_date_from: "2038-01-04",
    p_date_to: "2038-01-04",
    p_class_id: classRow.id,
    p_teacher_id: null,
    p_room_id: null,
  });
  const onTue = (calTue ?? []).some((e) => e.teaching_session_id === session.id);
  const projectedMon = (calMon ?? []).some(
    (e) => e.entry_type === "projected" && e.class_schedule_id === schedule.id,
  );
  record(6, "calendar refresh after reschedule", onTue && !projectedMon);

  const { error: cancelErr } = await admin.rpc("cancel_teaching_session", {
    p_session_id: session.id,
    p_reason: "Smoke cancel",
  });
  const { data: afterCancel } = await admin
    .from("teaching_session")
    .select("status")
    .eq("id", session.id)
    .single();
  const { data: calAfterCancel } = await admin.rpc("list_operational_calendar", {
    p_date_from: "2038-01-05",
    p_date_to: "2038-01-05",
    p_class_id: classRow.id,
    p_teacher_id: null,
    p_room_id: null,
  });
  const cancelVisible = (calAfterCancel ?? []).some(
    (e) => e.teaching_session_id === session.id && e.session_status === "cancelled",
  );
  record(
    7,
    "cancel success and calendar visible",
    !cancelErr && afterCancel?.status === "cancelled" && cancelVisible,
  );

  const { error: readerErr } = await reader.rpc("reschedule_teaching_session", {
    p_session_id: blocker.id,
    p_scheduled_start_at: "2038-01-07T02:00:00Z",
    p_scheduled_end_at: "2038-01-07T03:00:00Z",
    p_reason: "Denied",
  });
  record(8, "permission denial", Boolean(readerErr));

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM4-T06 session operations smoke: ${results.length - failed.length}/${results.length} ${failed.length ? "FAIL" : "PASS"}`);
  if (failed.length) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
