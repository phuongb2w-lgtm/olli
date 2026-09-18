#!/usr/bin/env node
/**
 * M4-T08 daily operations smoke tests.
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
  console.log(`${passed ? "PASS" : "FAIL"} OD-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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
      code: `OD-${ts}`,
      name: `Daily Ops ${ts}`,
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
      name: `OD Class ${ts}`,
      status: "active",
      term_start_date: "2037-01-01",
      term_end_date: "2037-03-31",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: teacherA } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "Daily",
      family_name: `A${ts}`,
      status: "active",
    })
    .select("id")
    .single();

  const { data: teacherB } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "Daily",
      family_name: `B${ts}`,
      status: "active",
    })
    .select("id")
    .single();

  const { data: roomA } = await admin
    .from("room")
    .insert({
      organization_id: ORG_A,
      code: `ODA-${ts}`,
      name: `OD Room A ${ts}`,
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
      code: `ODB-${ts}`,
      name: `OD Room B ${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: schedule } = await admin
    .from("class_schedule")
    .insert({
      organization_id: ORG_A,
      class_id: classRow.id,
      weekday_code: "mon",
      start_time: "09:00:00",
      end_time: "10:00:00",
      effective_from: "2037-01-01",
      room_id: roomA.id,
      teacher_id: teacherA.id,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  await admin.from("class_schedule").insert({
    organization_id: ORG_A,
    class_id: classRow.id,
    weekday_code: "tue",
    start_time: "14:00:00",
    end_time: "15:00:00",
    effective_from: "2037-01-01",
    status: "active",
    created_by: APP_A_ADMIN,
    updated_by: APP_A_ADMIN,
  });

  const { data: session } = await admin
    .from("teaching_session")
    .insert({
      organization_id: ORG_A,
      class_id: classRow.id,
      class_schedule_id: schedule.id,
      teacher_id: teacherA.id,
      room_id: roomA.id,
      occurrence_date: "2037-01-04",
      scheduled_start_at: "2037-01-04T02:00:00Z",
      scheduled_end_at: "2037-01-04T03:00:00Z",
      status: "scheduled",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const day = "2037-01-04";
  const projectedDay = "2037-01-06";

  const { data: dailyRows, error: dailyErr } = await admin.rpc("list_daily_operations", {
    p_date: day,
    p_class_id: classRow.id,
    p_teacher_id: null,
    p_room_id: null,
  });

  const hasSession = (dailyRows ?? []).some(
    (r) => r.entry_type === "session" && r.teaching_session_id === session.id,
  );
  record(1, "list_daily_operations returns materialized session", !dailyErr && hasSession);

  const { data: projRows } = await admin.rpc("list_daily_operations", {
    p_date: projectedDay,
    p_class_id: classRow.id,
    p_teacher_id: null,
    p_room_id: null,
  });
  const hasProjected = (projRows ?? []).some((r) => r.entry_type === "projected");
  record(2, "projected occurrence on timetable day", hasProjected);

  const dedupCount = (dailyRows ?? []).filter(
    (r) => r.class_schedule_id === schedule.id && r.occurrence_date === day,
  ).length;
  record(3, "session supersedes projection dedup", dedupCount === 1);

  const { data: gaps } = await admin.rpc("get_operational_planning_gaps", {
    p_date_from: projectedDay,
    p_date_to: projectedDay,
    p_class_id: classRow.id,
  });
  const gapRow = Array.isArray(gaps) ? gaps[0] : gaps;
  record(
    4,
    "planning gaps report unresolved teacher and roomless separately",
    Number(gapRow?.unresolved_projected_session_count ?? 0) >= 1 &&
      Number(gapRow?.roomless_projected_session_count ?? 0) >= 1,
  );

  const { error: subErr } = await admin.rpc("substitute_session_teacher", {
    p_session_id: session.id,
    p_new_teacher_id: teacherB.id,
    p_reason: "smoke sub",
  });
  const { data: afterSub } = await admin.rpc("list_daily_operations", {
    p_date: day,
    p_class_id: classRow.id,
  });
  record(
    5,
    "substitution reflects current teacher",
    !subErr &&
      (afterSub ?? []).some(
        (r) => r.teaching_session_id === session.id && r.teacher_id === teacherB.id,
      ),
  );

  const { error: roomErr } = await admin.rpc("change_session_room", {
    p_session_id: session.id,
    p_new_room_id: roomB.id,
    p_reason: "smoke room",
  });
  const { data: afterRoom } = await admin.rpc("list_daily_operations", {
    p_date: day,
    p_class_id: classRow.id,
  });
  record(
    6,
    "room change reflects current room",
    !roomErr &&
      (afterRoom ?? []).some((r) => r.teaching_session_id === session.id && r.room_id === roomB.id),
  );

  const newDay = "2037-01-11";
  const { error: resErr } = await admin.rpc("reschedule_teaching_session", {
    p_session_id: session.id,
    p_scheduled_start_at: "2037-01-11T02:00:00Z",
    p_scheduled_end_at: "2037-01-11T03:00:00Z",
    p_reason: "smoke move",
  });
  const { data: oldDayRows } = await admin.rpc("list_daily_operations", {
    p_date: day,
    p_class_id: classRow.id,
  });
  const { data: newDayRows } = await admin.rpc("list_daily_operations", {
    p_date: newDay,
    p_class_id: classRow.id,
  });
  record(
    7,
    "reschedule moves session off original day",
    !resErr &&
      !(oldDayRows ?? []).some((r) => r.teaching_session_id === session.id) &&
      (newDayRows ?? []).some((r) => r.teaching_session_id === session.id),
  );

  const { error: cancelErr } = await admin.rpc("cancel_teaching_session", {
    p_session_id: session.id,
    p_reason: "smoke cancel",
  });
  const { data: cancelRows } = await admin.rpc("list_daily_operations", {
    p_date: newDay,
    p_class_id: classRow.id,
  });
  const cancelledOnly = (cancelRows ?? []).filter((r) => r.teaching_session_id === session.id);
  record(
    8,
    "cancelled session stays materialized without projection",
    !cancelErr &&
      cancelledOnly.length === 1 &&
      cancelledOnly[0].entry_type === "session" &&
      cancelledOnly[0].session_status === "cancelled",
  );

  const { data: teacherFiltered } = await admin.rpc("list_daily_operations", {
    p_date: projectedDay,
    p_class_id: classRow.id,
    p_teacher_id: teacherA.id,
  });
  record(
    9,
    "teacher filter applies",
    (teacherFiltered ?? []).every((r) => r.teacher_id === teacherA.id || r.teacher_id === null),
  );

  const { error: readerErr } = await reader.rpc("list_daily_operations", {
    p_date: day,
  });
  record(
    10,
    "reader without enrollment.read denied",
    Boolean(readerErr) && (readerErr.message ?? "").includes("permission_denied"),
  );

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM4-T08 daily operations smoke: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  OD-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
