#!/usr/bin/env node
/**
 * M3-T03 CRM leads lifecycle smoke tests.
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

const LEAD_A1 = "a6100000-0000-4000-8000-000000000001";
const ORG_A = "a0000000-0000-4000-8000-000000000001";

const results = [];

function record(id, name, passed, detail = "") {
  results.push({ id, name, passed, detail });
  console.log(`${passed ? "PASS" : "FAIL"} CRM-${id}: ${name}${detail ? ` — ${detail}` : ""}`);
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
  const staff = await signIn("org-a-staff@olli.local");
  const reader = await signIn("org-a-reader@olli.local");

  const { data: adminLeads, error: readErr } = await admin.from("lead").select("id").limit(5);
  record(1, "admin can read leads", !readErr && (adminLeads?.length ?? 0) >= 1);

  const { data: staffLeads } = await staff.from("lead").select("id");
  record(2, "staff without lead.read cannot read leads", (staffLeads?.length ?? 0) === 0);

  const { data: readerLeads } = await reader.from("lead").select("id");
  record(3, "reader without lead.read cannot read leads", (readerLeads?.length ?? 0) === 0);

  const { data: newLead, error: createErr } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "new", notes_summary: "Smoke create" })
    .select("id")
    .single();
  record(4, "admin can create lead row", !createErr && Boolean(newLead?.id));

  const leadId = newLead?.id ?? LEAD_A1;

  const { error: transitionErr } = await admin.rpc("transition_lead_status", {
    p_lead_id: leadId,
    p_to_status: "contacted",
    p_lost_reason_id: null,
    p_notes: "Smoke transition",
  });
  record(5, "valid lifecycle transition via RPC", !transitionErr);

  const { error: invalidErr } = await admin.rpc("transition_lead_status", {
    p_lead_id: leadId,
    p_to_status: "converted",
    p_lost_reason_id: null,
    p_notes: null,
  });
  record(6, "converted transition blocked", Boolean(invalidErr));

  const { data: lostReasons } = await admin
    .from("lead_lost_reason")
    .select("id")
    .eq("code", "other")
    .limit(1);
  const lostReasonId = lostReasons?.[0]?.id;

  const { data: lostLead } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "qualified" })
    .select("id")
    .single();

  const { error: lostErr } = await admin.rpc("transition_lead_status", {
    p_lead_id: lostLead.id,
    p_to_status: "lost",
    p_lost_reason_id: lostReasonId,
    p_notes: "Smoke lost",
  });
  record(7, "lost transition with reason succeeds", !lostErr);

  const { error: lostMissingErr } = await admin.rpc("transition_lead_status", {
    p_lead_id: leadId,
    p_to_status: "lost",
    p_lost_reason_id: null,
    p_notes: null,
  });
  record(8, "lost without reason fails", Boolean(lostMissingErr));

  const { count: histCount } = await admin
    .from("lead_status_history")
    .select("*", { count: "exact", head: true })
    .eq("lead_id", leadId);
  record(9, "status history recorded", (histCount ?? 0) >= 1);

  const { error: actErr } = await admin.rpc("add_lead_activity", {
    p_lead_id: leadId,
    p_activity_type_code: "call",
    p_content: "Smoke call",
  });
  record(10, "add activity via RPC", !actErr);

  const { data: followUpId, error: fuErr } = await admin.rpc("create_lead_follow_up", {
    p_lead_id: leadId,
    p_due_at: new Date(Date.now() + 86400000).toISOString(),
    p_note: "Smoke follow-up",
  });
  record(11, "create follow-up via RPC", !fuErr && Boolean(followUpId));

  const { error: completeErr } = await admin.rpc("complete_lead_follow_up", {
    p_follow_up_id: followUpId,
    p_note: "Done",
  });
  record(12, "complete follow-up via RPC", !completeErr);

  const { error: bypassErr } = await admin
    .from("lead")
    .update({ status: "qualified" })
    .eq("id", leadId);
  record(13, "direct status update bypass blocked", Boolean(bypassErr));

  const beforeStudents = await admin.from("student").select("id", { count: "exact", head: true });
  await admin.rpc("add_lead_activity", {
    p_lead_id: leadId,
    p_activity_type_code: "note",
    p_content: "No side effects",
  });
  const afterStudents = await admin.from("student").select("id", { count: "exact", head: true });
  record(
    14,
    "CRM mutations have no student side effects",
    beforeStudents.count === afterStudents.count,
  );

  const { error: reactivateErr } = await admin.rpc("transition_lead_status", {
    p_lead_id: lostLead.id,
    p_to_status: "contacted",
    p_lost_reason_id: null,
    p_notes: "Reactivated",
  });
  const { data: reactivated } = await admin
    .from("lead")
    .select("status, lost_reason_id")
    .eq("id", lostLead.id)
    .single();
  record(
    15,
    "reactivation preserves lost reason snapshot",
    !reactivateErr &&
      reactivated?.status === "contacted" &&
      reactivated?.lost_reason_id === lostReasonId,
  );

  const { data: assignLead } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "new", notes_summary: "Assign smoke" })
    .select("id")
    .single();

  const assignTarget = "a1000000-0000-4000-8000-000000000001";
  const { error: assignErr, data: assignResult } = await admin.rpc("assign_lead", {
    p_lead_id: assignLead.id,
    p_assigned_user_id: assignTarget,
    p_note: "Smoke assign",
  });
  record(16, "assign lead via RPC", !assignErr && assignResult?.no_op === false);

  const { count: assignHistCount } = await admin
    .from("lead_assignment")
    .select("*", { count: "exact", head: true })
    .eq("lead_id", assignLead.id);
  record(17, "assignment history recorded", (assignHistCount ?? 0) === 1);

  const { error: unassignErr } = await admin.rpc("assign_lead", {
    p_lead_id: assignLead.id,
    p_assigned_user_id: null,
    p_note: "Smoke unassign",
  });
  record(18, "unassign lead via RPC", !unassignErr);

  const { error: assignBypassErr } = await admin
    .from("lead")
    .update({ assigned_user_id: assignTarget })
    .eq("id", assignLead.id);
  record(19, "direct assigned_user_id update blocked", Boolean(assignBypassErr));

  const { count: histAfterNoOp } = await admin
    .from("lead_assignment")
    .select("*", { count: "exact", head: true })
    .eq("lead_id", assignLead.id);
  await admin.rpc("assign_lead", {
    p_lead_id: assignLead.id,
    p_assigned_user_id: null,
    p_note: null,
  });
  const { count: histAfterDuplicate } = await admin
    .from("lead_assignment")
    .select("*", { count: "exact", head: true })
    .eq("lead_id", assignLead.id);
  record(
    20,
    "no-op assignment does not append history",
    histAfterNoOp === histAfterDuplicate,
  );

  const { data: assignedLead } = await admin
    .from("lead")
    .select("assigned_user_id, status")
    .eq("id", assignLead.id)
    .single();
  record(21, "assignment does not change status", assignedLead?.status === "new");

  const { data: trialLeadRow } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "qualified", notes_summary: "Trial smoke lead" })
    .select("id")
    .single();
  const trialLeadId = trialLeadRow?.id;
  const { data: trialCandidate } = await admin
    .from("lead_candidate")
    .insert({
      organization_id: ORG_A,
      lead_id: trialLeadId,
      given_name: "Smoke",
      family_name: "Trial",
      is_primary_candidate: true,
    })
    .select("id")
    .single();
  const { data: trialClass } = await admin.rpc("list_eligible_trial_classes");
  const classId = trialClass?.[0]?.class_id;
  const { error: scheduleTrialErr, data: scheduleTrialResult } = await admin.rpc(
    "schedule_lead_trial",
    {
      p_lead_id: trialLeadId,
      p_lead_candidate_id: trialCandidate?.id,
      p_class_id: classId,
      p_teaching_session_id: null,
      p_scheduled_start_at: new Date(Date.now() + 86400000 * 3).toISOString(),
      p_scheduled_end_at: new Date(Date.now() + 86400000 * 3 + 5400000).toISOString(),
      p_note: "Smoke trial",
    },
  );
  record(22, "schedule trial via RPC", !scheduleTrialErr && Boolean(scheduleTrialResult?.trial_id));

  const trialId = scheduleTrialResult?.trial_id;
  const { count: trialEventCount } = await admin
    .from("lead_trial_event")
    .select("*", { count: "exact", head: true })
    .eq("lead_trial_id", trialId);
  record(23, "trial scheduling appends event", (trialEventCount ?? 0) === 1);

  const { data: trialLeadStatus } = await admin
    .from("lead")
    .select("status")
    .eq("id", trialLeadId)
    .single();
  record(24, "trial scheduling advances lifecycle", trialLeadStatus?.status === "trial_scheduled");

  const beforeEnroll = await admin.from("enrollment").select("id", { count: "exact", head: true });
  const beforeAttend = await admin.from("attendance").select("id", { count: "exact", head: true });
  await admin.rpc("complete_lead_trial", { p_trial_id: trialId, p_outcome_note: "Smoke complete" });
  const afterEnroll = await admin.from("enrollment").select("id", { count: "exact", head: true });
  const afterAttend = await admin.from("attendance").select("id", { count: "exact", head: true });
  record(
    25,
    "trial completion has no enrollment side effect",
    beforeEnroll.count === afterEnroll.count && beforeAttend.count === afterAttend.count,
  );

  const { error: trialBypassErr, data: trialBypassRows } = await admin
    .from("lead_trial")
    .update({ status: "scheduled" })
    .eq("id", trialId)
    .select("id");
  const { data: trialAfterBypass } = await admin
    .from("lead_trial")
    .select("status")
    .eq("id", trialId)
    .single();
  record(
    26,
    "direct trial status update blocked",
    Boolean(trialBypassErr) ||
      (trialBypassRows?.length ?? 0) === 0 ||
      trialAfterBypass?.status === "completed",
  );

  const failed = results.filter((r) => !r.passed);
  console.log(`\nCRM leads smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
