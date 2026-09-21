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

  const { data: identityLeadRow } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "qualified", notes_summary: "Identity smoke lead" })
    .select("id")
    .single();
  const identityLeadId = identityLeadRow?.id;
  const { data: identityCandidate } = await admin
    .from("lead_candidate")
    .insert({
      organization_id: ORG_A,
      lead_id: identityLeadId,
      given_name: "Student",
      family_name: "A",
      is_primary_candidate: true,
    })
    .select("id")
    .single();
  const { data: identityContact } = await admin
    .from("lead_contact")
    .insert({
      organization_id: ORG_A,
      lead_id: identityLeadId,
      given_name: "Lan",
      family_name: "Phạm",
      phone: "0912345678",
      is_primary_contact: true,
    })
    .select("id")
    .single();
  const { data: studentMatches } = await admin.rpc("find_student_matches_for_lead_candidate", {
    p_lead_candidate_id: identityCandidate?.id,
  });
  record(
    27,
    "candidate student match suggestions",
    (studentMatches?.length ?? 0) >= 1 &&
      studentMatches.some(
        (m) => m.match_confidence === "strong" || m.match_confidence === "possible",
      ),
  );
  const { data: guardianMatches } = await admin.rpc("find_guardian_matches_for_lead_contact", {
    p_lead_contact_id: identityContact?.id,
  });
  record(
    28,
    "contact guardian match suggestions",
    (guardianMatches?.length ?? 0) >= 1 &&
      guardianMatches.some((m) => m.match_confidence === "strong"),
  );

  const seedStudentId = "a5100000-0000-4000-8000-000000000001";
  const seedGuardianId = "a5200000-0000-4000-8000-000000000001";
  const { error: resolveCandidateErr } = await admin.rpc("resolve_lead_candidate_identity", {
    p_lead_candidate_id: identityCandidate?.id,
    p_resolution_mode: "use_existing",
    p_student_id: seedStudentId,
  });
  const { error: resolveContactErr } = await admin.rpc("resolve_lead_contact_identity", {
    p_lead_contact_id: identityContact?.id,
    p_resolution_mode: "use_existing",
    p_guardian_id: seedGuardianId,
  });
  record(
    29,
    "resolve candidate and contact identities",
    !resolveCandidateErr && !resolveContactErr,
  );

  const { data: readiness } = await admin.rpc("get_lead_identity_resolution_status", {
    p_lead_id: identityLeadId,
  });
  record(30, "identity readiness reports ready", readiness?.ready === true);

  const beforeIdentityStudents = await admin.from("student").select("id", { count: "exact", head: true });
  const beforeIdentityGuardians = await admin.from("guardian").select("id", { count: "exact", head: true });
  await admin.rpc("resolve_lead_candidate_identity", {
    p_lead_candidate_id: identityCandidate?.id,
    p_resolution_mode: "create_new",
    p_acknowledge_strong_match: true,
  });
  const afterIdentityStudents = await admin.from("student").select("id", { count: "exact", head: true });
  const afterIdentityGuardians = await admin.from("guardian").select("id", { count: "exact", head: true });
  record(
    31,
    "identity resolution creates no student or guardian rows",
    beforeIdentityStudents.count === afterIdentityStudents.count &&
      beforeIdentityGuardians.count === afterIdentityGuardians.count,
  );

  const { data: convLead } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "qualified" })
    .select("id")
    .single();
  const { data: convCandidate } = await admin
    .from("lead_candidate")
    .insert({
      organization_id: ORG_A,
      lead_id: convLead.id,
      given_name: "ConvSmoke",
      family_name: "Candidate",
      is_primary_candidate: true,
    })
    .select("id")
    .single();
  const { data: convContact } = await admin
    .from("lead_contact")
    .insert({
      organization_id: ORG_A,
      lead_id: convLead.id,
      given_name: "ConvSmoke",
      family_name: "Contact",
      phone: `09${Date.now().toString().slice(-8)}`,
      is_primary_contact: true,
      is_billing_contact: true,
    })
    .select("id")
    .single();
  await admin.rpc("resolve_lead_candidate_identity", {
    p_lead_candidate_id: convCandidate.id,
    p_resolution_mode: "create_new",
  });
  await admin.rpc("resolve_lead_contact_identity", {
    p_lead_contact_id: convContact.id,
    p_resolution_mode: "create_new",
  });
  const convBeforeStudents = await admin.from("student").select("id", { count: "exact", head: true });
  const convBeforeCharges = await admin.from("charge").select("id", { count: "exact", head: true });
  const { data: convResult, error: convErr } = await admin.rpc("convert_lead", {
    p_lead_id: convLead.id,
    p_relationships: [],
    p_enrollments: [],
  });
  record(32, "convert lead without enrollment", !convErr && Boolean(convResult?.lead_conversion_id));
  const { data: convAgain } = await admin.rpc("convert_lead", { p_lead_id: convLead.id });
  record(
    33,
    "repeated conversion is idempotent",
    convAgain?.already_converted === true && convAgain?.lead_conversion_id === convResult?.lead_conversion_id,
  );

  const { data: raceLead } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "qualified" })
    .select("id")
    .single();
  const { data: raceCandidate } = await admin
    .from("lead_candidate")
    .insert({
      organization_id: ORG_A,
      lead_id: raceLead.id,
      given_name: "RaceSmoke",
      family_name: "Candidate",
      is_primary_candidate: true,
    })
    .select("id")
    .single();
  const { data: raceContact } = await admin
    .from("lead_contact")
    .insert({
      organization_id: ORG_A,
      lead_id: raceLead.id,
      given_name: "RaceSmoke",
      family_name: "Contact",
      phone: `09${Date.now().toString().slice(-7)}1`,
      is_primary_contact: true,
      is_billing_contact: true,
    })
    .select("id")
    .single();
  await admin.rpc("resolve_lead_candidate_identity", {
    p_lead_candidate_id: raceCandidate.id,
    p_resolution_mode: "create_new",
  });
  await admin.rpc("resolve_lead_contact_identity", {
    p_lead_contact_id: raceContact.id,
    p_resolution_mode: "create_new",
  });
  const [raceA, raceB] = await Promise.all([
    admin.rpc("convert_lead", { p_lead_id: raceLead.id, p_relationships: [], p_enrollments: [] }),
    admin.rpc("convert_lead", { p_lead_id: raceLead.id, p_relationships: [], p_enrollments: [] }),
  ]);
  const { count: raceConvCount } = await admin
    .from("lead_conversion")
    .select("id", { count: "exact", head: true })
    .eq("lead_id", raceLead.id);
  const raceConvIdA = raceA.data?.lead_conversion_id ?? null;
  const raceConvIdB = raceB.data?.lead_conversion_id ?? null;
  record(
    37,
    "concurrent conversion requests produce one canonical handoff",
    raceConvCount === 1 &&
      raceConvIdA !== null &&
      raceConvIdA === raceConvIdB &&
      (!raceA.error || !raceB.error),
  );
  const convAfterStudents = await admin.from("student").select("id", { count: "exact", head: true });
  const convAfterCharges = await admin.from("charge").select("id", { count: "exact", head: true });
  record(
    34,
    "conversion creates student records",
    (convAfterStudents.count ?? 0) > (convBeforeStudents.count ?? 0),
  );
  record(
    35,
    "conversion creates no charge side effects",
    convBeforeCharges.count === convAfterCharges.count,
  );
  const { data: staffConvLead } = await admin
    .from("lead")
    .insert({ organization_id: ORG_A, status: "qualified" })
    .select("id")
    .single();
  const { error: staffConvErr } = await staff.rpc("convert_lead", { p_lead_id: staffConvLead.id });
  record(36, "staff without lead.convert cannot convert", Boolean(staffConvErr));

  const { data: convActorRow } = await admin
    .from("lead_conversion")
    .select("converted_by")
    .eq("lead_id", convLead.id)
    .maybeSingle();
  record(
    38,
    "conversion actor is authenticated app user not client-supplied",
    convActorRow?.converted_by === "a1000000-0000-4000-8000-000000000001",
  );

  const { data: reportData, error: reportErr } = await admin.rpc("get_crm_attribution_report", {
    p_start_date: new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10),
    p_end_date: new Date().toISOString().slice(0, 10),
  });
  record(
    39,
    "admin can load CRM attribution report",
    !reportErr && Boolean(reportData?.funnel) && Array.isArray(reportData?.sources),
  );

  const { data: readerReport, error: readerReportErr } = await reader.rpc("get_crm_attribution_report", {
    p_start_date: new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10),
    p_end_date: new Date().toISOString().slice(0, 10),
  });
  record(
    40,
    "reader without lead.read cannot load CRM attribution report",
    Boolean(readerReportErr) || readerReport === null,
  );

  const { data: intakeResult, error: intakeErr } = await admin.rpc("create_lead_with_people", {
    p_lead: { notes_summary: "Smoke intake" },
    p_candidates: [{ given_name: "Smoke", family_name: "Candidate" }],
    p_contacts: [{ given_name: "Smoke", family_name: "Contact", phone: "0900123456" }],
  });
  record(
    41,
    "admin can create lead with people via RPC",
    !intakeErr && Boolean(intakeResult?.lead_id),
  );

  const intakeLeadId = intakeResult?.lead_id;
  const { count: intakeAssignNull } = await admin
    .from("lead")
    .select("*", { count: "exact", head: true })
    .eq("id", intakeLeadId)
    .is("assigned_user_id", null);
  record(42, "intake leaves assignment null", intakeAssignNull === 1);

  const { data: multiResult, error: multiErr } = await admin.rpc("create_lead_with_people", {
    p_lead: {},
    p_candidates: [
      { given_name: "A", family_name: "Sibling" },
      { given_name: "B", family_name: "Sibling", is_primary_candidate: true },
    ],
    p_contacts: [
      { given_name: "Parent", family_name: "One", phone: "0900111111" },
      { given_name: "Parent", family_name: "Two", phone: "0900222222" },
    ],
  });
  record(
    43,
    "intake supports multiple candidates and contacts",
    !multiErr && Boolean(multiResult?.lead_id),
  );

  const { error: updateOpErr } = await admin.rpc("update_lead_operational", {
    p_lead_id: intakeLeadId,
    p_notes_summary: "Smoke updated notes",
  });
  record(44, "admin can update lead operational fields", !updateOpErr);

  const { data: staffIntake, error: staffIntakeErr } = await staff.rpc("create_lead_with_people", {
    p_lead: {},
    p_candidates: [{ given_name: "Denied", family_name: "Create" }],
    p_contacts: [{ given_name: "Denied", family_name: "Contact" }],
  });
  record(
    45,
    "staff without lead.create cannot intake",
    Boolean(staffIntakeErr) || !staffIntake?.lead_id,
  );

  const { data: newSourceId, error: catalogErr } = await admin.rpc("upsert_lead_source_catalog", {
    p_id: null,
    p_code: `smoke_src_${Date.now()}`,
    p_display_name: "Smoke Source",
    p_status: "active",
  });
  record(46, "admin can upsert lead source catalog", !catalogErr && Boolean(newSourceId));

  const { data: inactiveSource } = await admin
    .from("lead_source")
    .select("id")
    .eq("organization_id", ORG_A)
    .eq("status", "inactive")
    .limit(1)
    .maybeSingle();
  if (inactiveSource?.id) {
    const { error: inactiveSrcErr } = await admin.rpc("create_lead_with_people", {
      p_lead: { lead_source_id: inactiveSource.id },
      p_candidates: [{ given_name: "Bad", family_name: "Source" }],
      p_contacts: [{ given_name: "Bad", family_name: "Contact" }],
    });
    record(47, "inactive source rejected for intake", Boolean(inactiveSrcErr));
  } else {
    record(47, "inactive source rejected for intake", true, "skipped — no inactive source");
  }

  const { data: searchCandidates } = await admin
    .from("lead_candidate")
    .select("lead_id")
    .ilike("given_name", "%Linh%")
    .eq("status", "active");
  record(
    48,
    "candidate name search finds fixture lead",
    (searchCandidates ?? []).some((row) => row.lead_id === LEAD_A1),
  );

  const { data: searchContacts } = await admin
    .from("lead_contact")
    .select("lead_id")
    .eq("phone_normalized", "0900111222")
    .eq("status", "active");
  record(
    49,
    "contact normalized phone search finds fixture lead",
    (searchContacts ?? []).some((row) => row.lead_id === LEAD_A1),
  );

  const failed = results.filter((r) => !r.passed);
  console.log(`\nCRM leads smoke: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
