#!/usr/bin/env node
/**
 * M3-T10 vertical-slice acceptance scenario (AC-1 through AC-20).
 * Chains one Lead through intake → assignment → lifecycle → activities →
 * trial → identity resolution → conversion → finance boundary → reporting.
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
const ASSIGN_TARGET = APP_A_ADMIN;

const results = [];
const cleanup = { leadIds: [], studentIds: [], guardianIds: [], enrollmentIds: [] };

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
  for (const leadId of cleanup.leadIds) {
    const { data: convRows } = await admin
      .from("lead_conversion")
      .select("id")
      .eq("lead_id", leadId);
    const convIds = convRows?.map((r) => r.id) ?? [];
    for (const convId of convIds) {
      await admin.from("lead_conversion_enrollment").delete().eq("lead_conversion_id", convId);
      await admin.from("lead_conversion_student_guardian").delete().eq("lead_conversion_id", convId);
      await admin.from("lead_conversion_contact").delete().eq("lead_conversion_id", convId);
      await admin.from("lead_conversion_candidate").delete().eq("lead_conversion_id", convId);
      await admin.from("lead_conversion").delete().eq("id", convId);
    }
    await admin.from("lead_trial_event").delete().in(
      "lead_trial_id",
      (await admin.from("lead_trial").select("id").eq("lead_id", leadId)).data?.map((r) => r.id) ?? [],
    );
    await admin.from("lead_trial").delete().eq("lead_id", leadId);
    await admin.from("lead_activity").delete().eq("lead_id", leadId);
    await admin.from("lead_follow_up").delete().eq("lead_id", leadId);
    await admin.from("lead_assignment").delete().eq("lead_id", leadId);
    await admin.from("lead_status_history").delete().eq("lead_id", leadId);
    await admin.from("lead_candidate_identity_resolution").delete().in(
      "lead_candidate_id",
      (await admin.from("lead_candidate").select("id").eq("lead_id", leadId)).data?.map((r) => r.id) ?? [],
    );
    await admin.from("lead_contact_identity_resolution").delete().in(
      "lead_contact_id",
      (await admin.from("lead_contact").select("id").eq("lead_id", leadId)).data?.map((r) => r.id) ?? [],
    );
    await admin.from("lead_candidate").delete().eq("lead_id", leadId);
    await admin.from("lead_contact").delete().eq("lead_id", leadId);
    await admin.from("lead").delete().eq("id", leadId);
  }
  if (cleanup.enrollmentIds.length) {
    await admin.from("enrollment").delete().in("id", cleanup.enrollmentIds);
  }
  if (cleanup.studentIds.length) {
    await admin.from("student_guardian").delete().in("student_id", cleanup.studentIds);
    await admin.from("student").delete().in("id", cleanup.studentIds);
  }
  if (cleanup.guardianIds.length) {
    await admin.from("guardian").delete().in("id", cleanup.guardianIds);
  }
}

async function main() {
  const admin = createServiceAdmin();
  const user = await signIn("org-a-admin@olli.local");
  const ts = Date.now();
  const ctx = {};

  try {
    const { data: sourceRow } = await admin
      .from("lead_source")
      .select("id")
      .eq("organization_id", ORG_A)
      .eq("code", "walk_in")
      .single();
    const { data: campaignRow } = await admin
      .from("lead_campaign")
      .select("id")
      .eq("organization_id", ORG_A)
      .eq("status", "active")
      .limit(1)
      .maybeSingle();

    const beforeStudents = await admin.from("student").select("id", { count: "exact", head: true });
    const beforeGuardians = await admin.from("guardian").select("id", { count: "exact", head: true });
    const beforeEnrollments = await admin.from("enrollment").select("id", { count: "exact", head: true });

    // AC-1: Canonical intake with attribution
    const { data: intake, error: intakeErr } = await user.rpc("create_lead_with_people", {
      p_lead: {
        notes_summary: `M3 acceptance ${ts}`,
        lead_source_id: sourceRow?.id ?? null,
        lead_campaign_id: campaignRow?.id ?? null,
      },
      p_candidates: [{ given_name: "Accept", family_name: `Cand${ts}`, is_primary_candidate: true }],
      p_contacts: [
        {
          given_name: "Accept",
          family_name: `Contact${ts}`,
          phone: `09${String(ts).slice(-8)}`,
          is_primary_contact: true,
          is_billing_contact: true,
        },
      ],
    });
    record(1, "canonical intake with attribution", !intakeErr && Boolean(intake?.lead_id));
    ctx.leadId = intake?.lead_id;
    ctx.candidateId = intake?.candidate_ids?.[0];
    ctx.contactId = intake?.contact_ids?.[0];
    cleanup.leadIds.push(ctx.leadId);

    const afterIntakeStudents = await admin.from("student").select("id", { count: "exact", head: true });
    const afterIntakeGuardians = await admin.from("guardian").select("id", { count: "exact", head: true });
    const afterIntakeEnrollments = await admin.from("enrollment").select("id", { count: "exact", head: true });
    record(
      2,
      "intake creates no Student/Guardian/Enrollment",
      beforeStudents.count === afterIntakeStudents.count &&
        beforeGuardians.count === afterIntakeGuardians.count &&
        beforeEnrollments.count === afterIntakeEnrollments.count,
    );

    // AC-3: Assignment
    const { error: assignErr } = await user.rpc("assign_lead", {
      p_lead_id: ctx.leadId,
      p_assigned_user_id: ASSIGN_TARGET,
      p_note: "Acceptance assign",
    });
    const { count: assignHist } = await admin
      .from("lead_assignment")
      .select("*", { count: "exact", head: true })
      .eq("lead_id", ctx.leadId);
    record(3, "assign lead with history", !assignErr && (assignHist ?? 0) === 1);

    const { error: assignBypassErr } = await user
      .from("lead")
      .update({ assigned_user_id: null })
      .eq("id", ctx.leadId);
    record(4, "lead.update cannot bypass assignment", Boolean(assignBypassErr));

    // AC-5: Lifecycle progression
    await user.rpc("transition_lead_status", {
      p_lead_id: ctx.leadId,
      p_to_status: "contacted",
      p_lost_reason_id: null,
      p_notes: "AC contacted",
    });
    await user.rpc("transition_lead_status", {
      p_lead_id: ctx.leadId,
      p_to_status: "qualified",
      p_lost_reason_id: null,
      p_notes: "AC qualified",
    });
    const { data: lostReasons } = await admin
      .from("lead_lost_reason")
      .select("id")
      .eq("code", "other")
      .limit(1);
    await user.rpc("transition_lead_status", {
      p_lead_id: ctx.leadId,
      p_to_status: "lost",
      p_lost_reason_id: lostReasons?.[0]?.id,
      p_notes: "AC lost",
    });
    await user.rpc("transition_lead_status", {
      p_lead_id: ctx.leadId,
      p_to_status: "contacted",
      p_lost_reason_id: null,
      p_notes: "AC reactivated",
    });
    await user.rpc("transition_lead_status", {
      p_lead_id: ctx.leadId,
      p_to_status: "qualified",
      p_lost_reason_id: null,
      p_notes: "AC re-qualified",
    });
    const { count: statusHist } = await admin
      .from("lead_status_history")
      .select("*", { count: "exact", head: true })
      .eq("lead_id", ctx.leadId);
    const { data: leadAfterLifecycle } = await admin
      .from("lead")
      .select("status, lost_reason_id")
      .eq("id", ctx.leadId)
      .single();
    record(
      5,
      "lifecycle with lost/reactivation preserves history",
      (statusHist ?? 0) >= 5 &&
        leadAfterLifecycle?.status === "qualified" &&
        leadAfterLifecycle?.lost_reason_id === lostReasons?.[0]?.id,
    );

    // AC-7: Activities and follow-up
    await user.rpc("add_lead_activity", {
      p_lead_id: ctx.leadId,
      p_activity_type_code: "call",
      p_content: "Acceptance call",
    });
    const { data: followUpId } = await user.rpc("create_lead_follow_up", {
      p_lead_id: ctx.leadId,
      p_due_at: new Date(Date.now() + 86400000).toISOString(),
      p_note: "Acceptance follow-up",
    });
    await user.rpc("complete_lead_follow_up", { p_follow_up_id: followUpId, p_note: "Done" });
    const { count: actCount } = await admin
      .from("lead_activity")
      .select("*", { count: "exact", head: true })
      .eq("lead_id", ctx.leadId);
    const { data: fuRow } = await admin
      .from("lead_follow_up")
      .select("status, completed_by")
      .eq("id", followUpId)
      .single();
    record(
      7,
      "activities and follow-up with audit semantics",
      (actCount ?? 0) >= 1 && fuRow?.status === "completed" && fuRow?.completed_by === APP_A_ADMIN,
    );

    // AC-8: Trial
    const { data: eligibleClasses } = await user.rpc("list_eligible_trial_classes");
    const classId = eligibleClasses?.[0]?.class_id;
    const { data: trialResult, error: trialErr } = await user.rpc("schedule_lead_trial", {
      p_lead_id: ctx.leadId,
      p_lead_candidate_id: ctx.candidateId,
      p_class_id: classId,
      p_teaching_session_id: null,
      p_scheduled_start_at: new Date(Date.now() + 86400000 * 5).toISOString(),
      p_scheduled_end_at: new Date(Date.now() + 86400000 * 5 + 5400000).toISOString(),
      p_note: "Acceptance trial",
    });
    record(8, "schedule candidate-specific trial", !trialErr && Boolean(trialResult?.trial_id));
    ctx.trialId = trialResult?.trial_id;

    const enrollBeforeTrial = await admin.from("enrollment").select("id", { count: "exact", head: true });
    const attendBeforeTrial = await admin.from("attendance").select("id", { count: "exact", head: true });
    await user.rpc("complete_lead_trial", { p_trial_id: ctx.trialId, p_outcome_note: "AC complete" });
    const enrollAfterTrial = await admin.from("enrollment").select("id", { count: "exact", head: true });
    const attendAfterTrial = await admin.from("attendance").select("id", { count: "exact", head: true });
    record(
      9,
      "trial completion creates no Enrollment/Attendance",
      enrollBeforeTrial.count === enrollAfterTrial.count &&
        attendBeforeTrial.count === attendAfterTrial.count,
    );

    // AC-10: Identity resolution
    await user.rpc("resolve_lead_candidate_identity", {
      p_lead_candidate_id: ctx.candidateId,
      p_resolution_mode: "create_new",
    });
    await user.rpc("resolve_lead_contact_identity", {
      p_lead_contact_id: ctx.contactId,
      p_resolution_mode: "create_new",
    });
    const { data: readiness } = await user.rpc("get_lead_identity_resolution_status", {
      p_lead_id: ctx.leadId,
    });
    record(10, "identity resolution ready", readiness?.ready === true);

    const { error: candidateEditErr } = await user
      .from("lead_candidate")
      .update({ given_name: "AcceptEdited" })
      .eq("id", ctx.candidateId);
    if (candidateEditErr) throw new Error(`candidate edit failed: ${candidateEditErr.message}`);
    const { data: staleStatus } = await user.rpc("get_lead_identity_resolution_status", {
      p_lead_id: ctx.leadId,
    });
    record(11, "material identity edit causes stale resolution", staleStatus?.ready === false);

    await user.rpc("resolve_lead_candidate_identity", {
      p_lead_candidate_id: ctx.candidateId,
      p_resolution_mode: "create_new",
    });
    const { data: reconfirmed } = await user.rpc("get_lead_identity_resolution_status", {
      p_lead_id: ctx.leadId,
    });
    record(12, "reconfirm resolution after stale", reconfirmed?.ready === true);

    // AC-14: Conversion
    const convBeforeCharges = await admin.from("charge").select("id", { count: "exact", head: true });
    const convBeforePayments = await admin.from("payment").select("id", { count: "exact", head: true });
    const convBeforeRev = await admin
      .from("revenue_recognition_event")
      .select("id", { count: "exact", head: true });
    const convBeforeStudents = await admin.from("student").select("id", { count: "exact", head: true });

    const { data: convResult, error: convErr } = await user.rpc("convert_lead", {
      p_lead_id: ctx.leadId,
      p_relationships: [
        {
          lead_candidate_id: ctx.candidateId,
          lead_contact_id: ctx.contactId,
          relationship_type: "mother",
          is_primary_contact: true,
          is_billing_contact: true,
        },
      ],
      p_enrollments: [],
    });
    record(14, "atomic conversion", !convErr && Boolean(convResult?.lead_conversion_id));

    const { data: convertedLead } = await admin
      .from("lead")
      .select("status, converted_at, lead_source_id")
      .eq("id", ctx.leadId)
      .single();
    const { count: convHist } = await admin
      .from("lead_status_history")
      .select("*", { count: "exact", head: true })
      .eq("lead_id", ctx.leadId)
      .eq("to_status", "converted");
    const { data: convMapping } = await admin
      .from("lead_conversion")
      .select("id")
      .eq("lead_id", ctx.leadId)
      .maybeSingle();
    const { count: sgCount } = await admin
      .from("lead_conversion_student_guardian")
      .select("*", { count: "exact", head: true })
      .eq("lead_conversion_id", convMapping?.id ?? "");
    const convAfterStudents = await admin.from("student").select("id", { count: "exact", head: true });
    record(
      15,
      "conversion outputs Student/Guardian linkage",
      convertedLead?.status === "converted" &&
        Boolean(convertedLead?.converted_at) &&
        (convHist ?? 0) >= 1 &&
        (sgCount ?? 0) >= 1 &&
        (convAfterStudents.count ?? 0) > (convBeforeStudents.count ?? 0),
    );

    const convAfterCharges = await admin.from("charge").select("id", { count: "exact", head: true });
    const convAfterPayments = await admin.from("payment").select("id", { count: "exact", head: true });
    const convAfterRev = await admin
      .from("revenue_recognition_event")
      .select("id", { count: "exact", head: true });
    record(
      17,
      "conversion creates no finance side effects",
      convBeforeCharges.count === convAfterCharges.count &&
        convBeforePayments.count === convAfterPayments.count &&
        convBeforeRev.count === convAfterRev.count,
    );

    const { data: reportBefore } = await user.rpc("get_crm_attribution_report", {
      p_start_date: new Date(Date.now() - 86400000).toISOString().slice(0, 10),
      p_end_date: new Date(Date.now() + 86400000).toISOString().slice(0, 10),
    });
    record(
      18,
      "converted lead appears in CRM reporting",
      Boolean(reportBefore?.funnel) &&
        (reportBefore?.funnel?.converted_leads ?? 0) >= 1,
    );

    const { error: postConvErr } = await user.rpc("update_lead_operational", {
      p_lead_id: ctx.leadId,
      p_notes_summary: "Should fail",
    });
    record(19, "converted lead blocks operational rewrite", Boolean(postConvErr));

    const { data: convRow } = await admin
      .from("lead_conversion")
      .select("lead_source_id")
      .eq("lead_id", ctx.leadId)
      .single();
    record(
      20,
      "conversion snapshot preserves source attribution",
      convRow?.lead_source_id === convertedLead?.lead_source_id,
    );

    // Track created entities for cleanup
    const convId = convMapping?.id ?? convRow?.id;
    const { data: convCandidates } = await admin
      .from("lead_conversion_candidate")
      .select("student_id")
      .eq("lead_conversion_id", convId ?? "");
    const { data: convContacts } = await admin
      .from("lead_conversion_contact")
      .select("guardian_id")
      .eq("lead_conversion_id", convId ?? "");
    for (const row of convCandidates ?? []) {
      if (row.student_id) cleanup.studentIds.push(row.student_id);
    }
    for (const row of convContacts ?? []) {
      if (row.guardian_id) cleanup.guardianIds.push(row.guardian_id);
    }
  } finally {
    await cleanupFixtures(admin);
  }

  const failed = results.filter((r) => !r.passed);
  console.log(`\nM3 acceptance scenario: ${results.length - failed.length}/${results.length} PASS`);
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
