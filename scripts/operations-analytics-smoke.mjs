#!/usr/bin/env node
/**
 * M4-T07 workload and room usage analytics smoke tests.
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
  console.log(`${passed ? "PASS" : "FAIL"} OA-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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
      code: `OA-${ts}`,
      name: `Analytics ${ts}`,
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
      name: `OA Class ${ts}`,
      status: "active",
      term_start_date: "2039-01-01",
      term_end_date: "2039-03-31",
      created_by: APP_A_ADMIN,
      updated_by: APP_A_ADMIN,
    })
    .select("id")
    .single();

  const { data: teacherA } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "OA",
      family_name: `A${ts}`,
      status: "active",
    })
    .select("id")
    .single();

  const { data: teacherB } = await admin
    .from("teacher")
    .insert({
      organization_id: ORG_A,
      given_name: "OA",
      family_name: `B${ts}`,
      status: "active",
    })
    .select("id")
    .single();

  const { data: roomA } = await admin
    .from("room")
    .insert({
      organization_id: ORG_A,
      code: `OAR-${ts}`,
      name: `OA Room A ${ts}`,
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
      code: `OBR-${ts}`,
      name: `OA Room B ${ts}`,
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
      effective_from: "2039-01-01",
      teacher_id: teacherA.id,
      room_id: roomA.id,
      status: "active",
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
      occurrence_date: "2039-01-03",
      scheduled_start_at: "2039-01-03T02:00:00.000Z",
      scheduled_end_at: "2039-01-03T03:00:00.000Z",
      status: "scheduled",
    })
    .select("id")
    .single();

  // 1: teacher summary returns materialized workload
  {
    const { data, error } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-03",
      p_date_to: "2039-01-03",
      p_class_id: classRow.id,
      p_teacher_id: teacherA.id,
    });
    const row = (data ?? [])[0];
    record(
      1,
      "teacher summary materialized workload",
      !error && row?.materialized_session_count === 1,
      error?.message,
    );
  }

  // 2: room summary returns booked usage
  {
    const { data, error } = await admin.rpc("list_room_usage", {
      p_date_from: "2039-01-03",
      p_date_to: "2039-01-03",
      p_class_id: classRow.id,
      p_room_id: roomA.id,
    });
    const row = (data ?? [])[0];
    record(
      2,
      "room summary booked usage",
      !error && row?.materialized_session_count === 1 && row?.materialized_booked_minutes === 60,
      error?.message,
    );
  }

  // 3: projected workload for future Monday
  {
    const { data, error } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-10",
      p_date_to: "2039-01-10",
      p_class_id: classRow.id,
      p_teacher_id: teacherA.id,
    });
    const row = (data ?? [])[0];
    record(
      3,
      "projected teacher workload",
      !error && row?.projected_session_count === 1,
      error?.message,
    );
  }

  // 4: materialized suppresses projected duplicate
  {
    const { data, error } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-03",
      p_date_to: "2039-01-03",
      p_class_id: classRow.id,
      p_teacher_id: teacherA.id,
    });
    const row = (data ?? [])[0];
    record(
      4,
      "materialized suppresses projected duplicate",
      !error && row?.materialized_session_count === 1 && row?.projected_session_count === 0,
    );
  }

  // 5: reschedule moves workload to new date
  {
    await admin.rpc("reschedule_teaching_session", {
      p_session_id: session.id,
      p_scheduled_start_at: "2039-01-04T02:00:00.000Z",
      p_scheduled_end_at: "2039-01-04T03:00:00.000Z",
      p_reason: "OA smoke reschedule",
    });
    const { data: oldDay } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-03",
      p_date_to: "2039-01-03",
      p_teacher_id: teacherA.id,
    });
    const { data: newDay } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-04",
      p_date_to: "2039-01-04",
      p_teacher_id: teacherA.id,
    });
    const oldRow = (oldDay ?? []).find((r) => r.teacher_id === teacherA.id);
    const newRow = (newDay ?? []).find((r) => r.teacher_id === teacherA.id);
    record(
      5,
      "reschedule effect on workload",
      (oldRow?.materialized_session_count ?? 0) === 0 &&
        (newRow?.materialized_session_count ?? 0) === 1,
    );
  }

  // 6: substitution moves teacher workload
  {
    await admin.rpc("substitute_session_teacher", {
      p_session_id: session.id,
      p_new_teacher_id: teacherB.id,
      p_reason: "OA smoke substitute",
    });
    const { data } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-04",
      p_date_to: "2039-01-04",
      p_teacher_id: teacherB.id,
    });
    const row = (data ?? [])[0];
    record(6, "substitution effect on workload", row?.materialized_session_count === 1);
  }

  // 7: room change moves room usage
  {
    await admin.rpc("change_session_room", {
      p_session_id: session.id,
      p_new_room_id: roomB.id,
      p_reason: "OA smoke room change",
    });
    const { data: roomBData } = await admin.rpc("list_room_usage", {
      p_date_from: "2039-01-04",
      p_date_to: "2039-01-04",
      p_room_id: roomB.id,
    });
    const row = (roomBData ?? [])[0];
    record(7, "room change effect on usage", row?.materialized_session_count === 1);
  }

  // 8: cancel removes booked workload
  {
    await admin.rpc("cancel_teaching_session", {
      p_session_id: session.id,
      p_reason: "OA smoke cancel",
    });
    const { data } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-04",
      p_date_to: "2039-01-04",
      p_teacher_id: teacherB.id,
    });
    const row = (data ?? [])[0];
    record(
      8,
      "cancel effect on workload",
      row?.materialized_scheduled_minutes === 0 && row?.cancelled_session_count === 1,
    );
  }

  // 9: permission denial
  {
    const { error } = await reader.rpc("list_teacher_workload", {
      p_date_from: "2039-01-01",
      p_date_to: "2039-01-31",
    });
    record(9, "permission denial", error?.message?.includes("permission_denied"));
  }

  // 10: cross-org isolation via invalid teacher filter
  {
    const { data: orgBTeacher } = await signIn("org-b-admin@olli.local")
      .then((c) =>
        c
          .from("teacher")
          .insert({
            organization_id: "b0000000-0000-4000-8000-000000000001",
            given_name: "OrgB",
            family_name: `T${ts}`,
            status: "active",
          })
          .select("id")
          .single(),
      )
      .catch(() => ({ data: null }));
    const { error } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-01",
      p_date_to: "2039-01-31",
      p_teacher_id: orgBTeacher?.id,
    });
    record(10, "cross-org isolation", error?.message?.includes("invalid_teacher"));
  }

  // 11: date range validation
  {
    const { error } = await admin.rpc("list_teacher_workload", {
      p_date_from: "2039-01-01",
      p_date_to: "2040-01-02",
    });
    record(11, "date range validation", error?.message?.includes("analytics_range_too_large"));
  }

  const failed = results.filter((r) => !r.passed);
  console.log(`\nOperations analytics smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
