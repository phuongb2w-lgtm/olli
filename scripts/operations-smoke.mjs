#!/usr/bin/env node
/**
 * M4-T05 operational calendar smoke tests.
 * Requires local Supabase with seed and M4-T05 migration applied.
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
  console.log(`${passed ? "PASS" : "FAIL"} OC-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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

async function rpcWithStaffRetry(email, rpcCall, attempts = 5) {
  let client = await signIn(email);
  let lastError = null;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const { error } = await rpcCall(client);
    if (!error) return { error: null };
    lastError = error;
    await new Promise((resolve) => setTimeout(resolve, 400 * (attempt + 1)));
    client = await signIn(email);
  }
  return { error: lastError };
}

async function main() {
  const admin = await signIn("org-a-admin@olli.local");
  const staff = await signIn("org-a-staff@olli.local");
  const reader = await signIn("org-a-reader@olli.local");
  const orgB = await signIn("org-b-admin@olli.local");

  const ts = Date.now();
  const { data: course } = await admin
    .from("course")
    .insert({
      organization_id: ORG_A,
      code: `OC-${ts}`,
      name: `Ops Cal ${ts}`,
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
      name: `Ops Class ${ts}`,
      status: "active",
      term_start_date: "2036-01-01",
      term_end_date: "2036-03-31",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: teacher } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "Ops",
      family_name: `T${ts}`,
      status: "active",
    })
    .select("id")
    .single();

  const { data: room } = await admin
    .from("room")
    .insert({
      organization_id: ORG_A,
      code: `OCR-${ts}`,
      name: `Ops Room ${ts}`,
      status: "active",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  // 2036-01-07 is Monday
  const { data: schedule } = await admin
    .from("class_schedule")
    .insert({
      organization_id: ORG_A,
      class_id: classRow.id,
      weekday_code: "mon",
      start_time: "09:00:00",
      end_time: "10:00:00",
      effective_from: "2036-01-01",
      room_id: room.id,
      teacher_id: teacher.id,
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
      teacher_id: teacher.id,
      room_id: room.id,
      occurrence_date: "2036-01-07",
      scheduled_start_at: "2036-01-07T02:00:00Z",
      scheduled_end_at: "2036-01-07T03:00:00Z",
      status: "scheduled",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: cancelled } = await admin
    .from("teaching_session")
    .insert({
      organization_id: ORG_A,
      class_id: classRow.id,
      class_schedule_id: schedule.id,
      teacher_id: teacher.id,
      room_id: room.id,
      occurrence_date: "2036-01-14",
      scheduled_start_at: "2036-01-14T02:00:00Z",
      scheduled_end_at: "2036-01-14T03:00:00Z",
      status: "cancelled",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  // Range query — session + projected Monday 2036-01-21
  const { data: rangeRows, error: rangeErr } = await admin.rpc("list_operational_calendar", {
    p_date_from: "2036-01-07",
    p_date_to: "2036-01-21",
    p_class_id: classRow.id,
    p_teacher_id: null,
    p_room_id: null,
  });
  const hasSession = (rangeRows ?? []).some(
    (r) => r.entry_type === "session" && r.teaching_session_id === session.id,
  );
  const hasProjected = (rangeRows ?? []).some(
    (r) => r.entry_type === "projected" && r.occurrence_date === "2036-01-21",
  );
  const hasCancelled = (rangeRows ?? []).some(
    (r) => r.entry_type === "session" && r.teaching_session_id === cancelled.id && r.session_status === "cancelled",
  );
  const cancelledNoProj = !(rangeRows ?? []).some(
    (r) => r.entry_type === "projected" && r.occurrence_date === "2036-01-14",
  );

  record(1, "today/range query returns rows", !rangeErr && (rangeRows ?? []).length >= 1);
  record(2, "materialized entry present", hasSession);
  record(3, "projected entry present", hasProjected);
  record(4, "cancelled entry present and suppresses projection", hasCancelled && cancelledNoProj);

  const { data: teacherFiltered } = await admin.rpc("list_operational_calendar", {
    p_date_from: "2036-01-07",
    p_date_to: "2036-01-21",
    p_class_id: classRow.id,
    p_teacher_id: teacher.id,
    p_room_id: null,
  });
  record(
    5,
    "teacher filter works",
    (teacherFiltered ?? []).length >= 1 &&
      (teacherFiltered ?? []).every((r) => r.teacher_id === teacher.id),
  );

  const { data: roomFiltered } = await admin.rpc("list_operational_calendar", {
    p_date_from: "2036-01-07",
    p_date_to: "2036-01-21",
    p_class_id: classRow.id,
    p_teacher_id: null,
    p_room_id: room.id,
  });
  record(
    6,
    "room filter works",
    (roomFiltered ?? []).length >= 1 &&
      (roomFiltered ?? []).every((r) => r.room_id === room.id),
  );

  record(7, "staff with enrollment.read can read calendar", await hasPermission(staff, "enrollment.read"));
  const { error: staffErr } = await rpcWithStaffRetry("org-a-staff@olli.local", (client) =>
    client.rpc("list_operational_calendar", {
      p_date_from: "2036-01-07",
      p_date_to: "2036-01-07",
      p_class_id: classRow.id,
      p_teacher_id: null,
      p_room_id: null,
    }),
  );
  record(
    8,
    "staff can call calendar RPC",
    !staffErr,
    staffErr?.message ?? "",
  );

  const readerHasRead = await hasPermission(reader, "enrollment.read");
  const { error: readerErr } = await reader.rpc("list_operational_calendar", {
    p_date_from: "2036-01-07",
    p_date_to: "2036-01-07",
    p_class_id: null,
    p_teacher_id: null,
    p_room_id: null,
  });
  record(
    9,
    "reader without enrollment.read denied",
    !readerHasRead && Boolean(readerErr) && (readerErr.message ?? "").includes("permission_denied"),
  );

  const { data: orgBRows, error: orgBErr } = await orgB.rpc("list_operational_calendar", {
    p_date_from: "2036-01-07",
    p_date_to: "2036-01-21",
    p_class_id: null,
    p_teacher_id: null,
    p_room_id: null,
  });
  const leaked = (orgBRows ?? []).some((r) => r.class_id === classRow.id);
  record(10, "cross-org isolation", !orgBErr && !leaked);

  const { error: crossFilterErr } = await admin.rpc("list_operational_calendar", {
    p_date_from: "2036-01-07",
    p_date_to: "2036-01-07",
    p_class_id: "b0000000-0000-4000-8000-000000000099",
    p_teacher_id: null,
    p_room_id: null,
  });
  // Use a real org B class if available
  const { data: bClass } = await orgB.from("class").select("id").limit(1).maybeSingle();
  let crossOk = false;
  if (bClass?.id) {
    const { error: e } = await admin.rpc("list_operational_calendar", {
      p_date_from: "2036-01-07",
      p_date_to: "2036-01-07",
      p_class_id: bClass.id,
      p_teacher_id: null,
      p_room_id: null,
    });
    crossOk = Boolean(e) && (e.message ?? "").includes("invalid_class");
  } else {
    crossOk = Boolean(crossFilterErr);
  }
  record(11, "cross-org filter rejected", crossOk);

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM4-T05 operations smoke: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    failed.forEach((f) => console.error(`  OC-${f.id}: ${f.name}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
