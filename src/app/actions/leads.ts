"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import type { LeadUserActivityType } from "@/lib/leads/constants";
import { LEAD_CONTACT_RELATIONSHIPS, LEAD_USER_ACTIVITY_TYPES } from "@/lib/leads/constants";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type LeadMutationState = {
  error?:
    | "permission_denied"
    | "not_found"
    | "invalid_transition"
    | "lost_reason_required"
    | "conversion_reserved"
    | "invalid_activity_type"
    | "due_at_required"
    | "follow_up_not_pending"
    | "invalid_assignee"
    | "lead_lost"
    | "lead_converted"
    | "invalid_candidate"
    | "invalid_class"
    | "class_not_eligible"
    | "invalid_teaching_session"
    | "session_class_mismatch"
    | "schedule_required"
    | "invalid_schedule"
    | "trial_not_scheduled"
    | "strong_match_ack_required"
    | "invalid_resolution"
    | "ineligible_target"
    | "identity_not_ready"
    | "duplicate_risk_changed"
    | "relationship_mapping_required"
    | "invalid_relationship_mapping"
    | "invalid_enrollment_mapping"
    | "capacity_reached"
    | "overlap_conflict"
    | "intake_people_required"
    | "invalid_contact"
    | "invalid_source"
    | "invalid_campaign"
    | "invalid_referral"
    | "primary_candidate_conflict"
    | "primary_contact_conflict"
    | "invalid_status"
    | "mutation_error";
};

export type LeadIntakeState = LeadMutationState & {
  leadId?: string;
  assignError?: LeadMutationState["error"];
};

export type LeadCatalogState = LeadMutationState & {
  success?: boolean;
};

function mapRpcError(message: string): LeadMutationState["error"] {
  if (message.includes("permission_denied")) return "permission_denied";
  if (message.includes("not_found")) return "not_found";
  if (message.includes("invalid_transition")) return "invalid_transition";
  if (message.includes("lost_reason_required")) return "lost_reason_required";
  if (message.includes("conversion_reserved")) return "conversion_reserved";
  if (message.includes("invalid_activity_type")) return "invalid_activity_type";
  if (message.includes("due_at_required")) return "due_at_required";
  if (message.includes("follow_up_not_pending")) return "follow_up_not_pending";
  if (message.includes("invalid_assignee")) return "invalid_assignee";
  if (message.includes("lead_lost")) return "lead_lost";
  if (message.includes("lead_converted")) return "lead_converted";
  if (message.includes("invalid_candidate")) return "invalid_candidate";
  if (message.includes("invalid_class")) return "invalid_class";
  if (message.includes("class_not_eligible")) return "class_not_eligible";
  if (message.includes("invalid_teaching_session")) return "invalid_teaching_session";
  if (message.includes("session_class_mismatch")) return "session_class_mismatch";
  if (message.includes("schedule_required")) return "schedule_required";
  if (message.includes("invalid_schedule")) return "invalid_schedule";
  if (message.includes("trial_not_scheduled")) return "trial_not_scheduled";
  if (message.includes("strong_match_ack_required")) return "strong_match_ack_required";
  if (message.includes("invalid_resolution")) return "invalid_resolution";
  if (message.includes("ineligible_target")) return "ineligible_target";
  if (message.includes("identity_not_ready")) return "identity_not_ready";
  if (message.includes("duplicate_risk_changed")) return "duplicate_risk_changed";
  if (message.includes("relationship_mapping_required")) return "relationship_mapping_required";
  if (message.includes("invalid_relationship_mapping")) return "invalid_relationship_mapping";
  if (message.includes("invalid_enrollment_mapping")) return "invalid_enrollment_mapping";
  if (message.includes("capacity_reached")) return "capacity_reached";
  if (message.includes("overlap_conflict")) return "overlap_conflict";
  if (message.includes("stale_candidate_resolution") || message.includes("stale_contact_resolution")) {
    return "identity_not_ready";
  }
  if (message.includes("lead_lifecycle_protected")) return "invalid_transition";
  if (message.includes("identity resolution must")) return "permission_denied";
  if (message.includes("Lead assignment must")) return "permission_denied";
  if (message.includes("Lead trial")) return "permission_denied";
  if (message.includes("intake_people_required")) return "intake_people_required";
  if (message.includes("invalid_contact")) return "invalid_contact";
  if (message.includes("invalid_source")) return "invalid_source";
  if (message.includes("invalid_campaign")) return "invalid_campaign";
  if (message.includes("invalid_referral")) return "invalid_referral";
  if (message.includes("primary_candidate_conflict")) return "primary_candidate_conflict";
  if (message.includes("primary_contact_conflict")) return "primary_contact_conflict";
  if (message.includes("invalid_status")) return "invalid_status";
  return "mutation_error";
}

function parseOptionalDateTime(raw: string): string | undefined {
  const trimmed = raw.trim();
  if (!trimmed) return undefined;
  return new Date(trimmed).toISOString();
}

export async function transitionLeadStatusAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const toStatus = String(formData.get("toStatus") ?? "");
  const lostReasonId = String(formData.get("lostReasonId") ?? "") || undefined;
  const notes = String(formData.get("notes") ?? "") || undefined;

  if (!leadId || !toStatus) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("transition_lead_status", {
    p_lead_id: leadId,
    p_to_status: toStatus,
    p_lost_reason_id: lostReasonId,
    p_notes: notes,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function addLeadActivityAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const activityType = String(formData.get("activityType") ?? "") as LeadUserActivityType;
  const content = String(formData.get("content") ?? "") || undefined;

  if (!leadId || !(LEAD_USER_ACTIVITY_TYPES as readonly string[]).includes(activityType)) {
    return { error: "invalid_activity_type" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("add_lead_activity", {
    p_lead_id: leadId,
    p_activity_type_code: activityType,
    p_content: content,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function createLeadFollowUpAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const dueAt = String(formData.get("dueAt") ?? "");
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId || !dueAt) {
    return { error: "due_at_required" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_lead_follow_up", {
    p_lead_id: leadId,
    p_due_at: new Date(dueAt).toISOString(),
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function completeLeadFollowUpAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const followUpId = String(formData.get("followUpId") ?? "");
  const leadId = String(formData.get("leadId") ?? "");
  const note = String(formData.get("note") ?? "") || undefined;

  if (!followUpId || !leadId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("complete_lead_follow_up", {
    p_follow_up_id: followUpId,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function assignLeadAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.assign"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const assigneeRaw = String(formData.get("assignedUserId") ?? "");
  const unassign = formData.get("unassign") === "true";
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId) {
    return { error: "mutation_error" };
  }

  const assignedUserId = unassign ? null : assigneeRaw || null;
  if (!unassign && !assignedUserId) {
    return { error: "invalid_assignee" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("assign_lead", {
    p_lead_id: leadId,
    p_assigned_user_id: assignedUserId ?? undefined,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function scheduleLeadTrialAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const candidateId = String(formData.get("candidateId") ?? "");
  const classId = String(formData.get("classId") ?? "");
  const teachingSessionId = String(formData.get("teachingSessionId") ?? "") || undefined;
  const scheduledStartAt = parseOptionalDateTime(String(formData.get("scheduledStartAt") ?? ""));
  const scheduledEndAt = parseOptionalDateTime(String(formData.get("scheduledEndAt") ?? ""));
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId || !candidateId || !classId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("schedule_lead_trial", {
    p_lead_id: leadId,
    p_lead_candidate_id: candidateId,
    p_class_id: classId,
    p_teaching_session_id: teachingSessionId,
    p_scheduled_start_at: scheduledStartAt,
    p_scheduled_end_at: scheduledEndAt,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function rescheduleLeadTrialAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const trialId = String(formData.get("trialId") ?? "");
  const classId = String(formData.get("classId") ?? "") || undefined;
  const teachingSessionId = String(formData.get("teachingSessionId") ?? "") || undefined;
  const scheduledStartAt = parseOptionalDateTime(String(formData.get("scheduledStartAt") ?? ""));
  const scheduledEndAt = parseOptionalDateTime(String(formData.get("scheduledEndAt") ?? ""));
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId || !trialId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("reschedule_lead_trial", {
    p_trial_id: trialId,
    p_class_id: classId,
    p_teaching_session_id: teachingSessionId,
    p_scheduled_start_at: scheduledStartAt,
    p_scheduled_end_at: scheduledEndAt,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function completeLeadTrialAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const trialId = String(formData.get("trialId") ?? "");
  const outcomeNote = String(formData.get("outcomeNote") ?? "") || undefined;

  if (!leadId || !trialId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("complete_lead_trial", {
    p_trial_id: trialId,
    p_outcome_note: outcomeNote,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function cancelLeadTrialAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const trialId = String(formData.get("trialId") ?? "");
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId || !trialId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_lead_trial", {
    p_trial_id: trialId,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function markLeadTrialNoShowAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const trialId = String(formData.get("trialId") ?? "");
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId || !trialId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_lead_trial_no_show", {
    p_trial_id: trialId,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function resolveLeadCandidateIdentityAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const candidateId = String(formData.get("candidateId") ?? "");
  const resolutionMode = String(formData.get("resolutionMode") ?? "");
  const studentId = String(formData.get("studentId") ?? "") || undefined;
  const acknowledgeStrongMatch = formData.get("acknowledgeStrongMatch") === "true";
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId || !candidateId || !resolutionMode) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_lead_candidate_identity", {
    p_lead_candidate_id: candidateId,
    p_resolution_mode: resolutionMode,
    p_student_id: studentId,
    p_acknowledge_strong_match: acknowledgeStrongMatch,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function resolveLeadContactIdentityAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const contactId = String(formData.get("contactId") ?? "");
  const resolutionMode = String(formData.get("resolutionMode") ?? "");
  const guardianId = String(formData.get("guardianId") ?? "") || undefined;
  const acknowledgeStrongMatch = formData.get("acknowledgeStrongMatch") === "true";
  const note = String(formData.get("note") ?? "") || undefined;

  if (!leadId || !contactId || !resolutionMode) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_lead_contact_identity", {
    p_lead_contact_id: contactId,
    p_resolution_mode: resolutionMode,
    p_guardian_id: guardianId,
    p_acknowledge_strong_match: acknowledgeStrongMatch,
    p_note: note,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function clearLeadCandidateIdentityAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const candidateId = String(formData.get("candidateId") ?? "");
  if (!leadId || !candidateId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_lead_candidate_identity", {
    p_lead_candidate_id: candidateId,
    p_resolution_mode: undefined,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function clearLeadContactIdentityAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const contactId = String(formData.get("contactId") ?? "");
  if (!leadId || !contactId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_lead_contact_identity", {
    p_lead_contact_id: contactId,
    p_resolution_mode: undefined,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function convertLeadAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.convert"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  if (!leadId) {
    return { error: "mutation_error" };
  }

  const relationships: { lead_candidate_id: string; lead_contact_id: string }[] = [];
  for (const value of formData.getAll("relationship")) {
    const [candidateId, contactId] = String(value).split(":");
    if (candidateId && contactId) {
      relationships.push({ lead_candidate_id: candidateId, lead_contact_id: contactId });
    }
  }

  const enrollments: {
    lead_candidate_id: string;
    class_id: string;
    start_date: string;
    status: string;
  }[] = [];
  for (const [key, value] of formData.entries()) {
    if (key.startsWith("enrollmentClass_") && value) {
      const candidateId = key.replace("enrollmentClass_", "");
      enrollments.push({
        lead_candidate_id: candidateId,
        class_id: String(value),
        start_date: new Date().toISOString().slice(0, 10),
        status: "pending",
      });
    }
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("convert_lead", {
    p_lead_id: leadId,
    p_relationships: relationships,
    p_enrollments: enrollments,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

type IntakeCandidate = {
  given_name: string;
  family_name: string;
  date_of_birth?: string;
  is_primary_candidate?: boolean;
};

type IntakeContact = {
  given_name: string;
  family_name: string;
  phone?: string;
  email?: string;
  relationship_type?: string;
  is_primary_contact?: boolean;
  is_billing_contact?: boolean;
};

function parseIntakePayload(formData: FormData): {
  lead: Record<string, string | null>;
  candidates: IntakeCandidate[];
  contacts: IntakeContact[];
} | null {
  const raw = String(formData.get("payload") ?? "");
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as {
      lead?: Record<string, string | null>;
      candidates?: IntakeCandidate[];
      contacts?: IntakeContact[];
    };
    return {
      lead: parsed.lead ?? {},
      candidates: parsed.candidates ?? [],
      contacts: parsed.contacts ?? [],
    };
  } catch {
    return null;
  }
}

export async function createLeadWithPeopleAction(
  _prev: LeadIntakeState,
  formData: FormData,
): Promise<LeadIntakeState> {
  if (!(await can("lead.create"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const payload = parseIntakePayload(formData);
  if (!payload) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_lead_with_people", {
    p_lead: payload.lead,
    p_candidates: payload.candidates,
    p_contacts: payload.contacts,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  const leadId = String((data as { lead_id?: string } | null)?.lead_id ?? "");
  if (!leadId) {
    return { error: "mutation_error" };
  }

  const assignAfter = formData.get("assignAfter") === "true";
  const assigneeId = String(formData.get("assignedUserId") ?? "");
  let assignError: LeadMutationState["error"] | undefined;

  if (assignAfter && assigneeId) {
    if (!(await can("lead.assign"))) {
      assignError = "permission_denied";
    } else {
      const { error: assignErr } = await supabase.rpc("assign_lead", {
        p_lead_id: leadId,
        p_assigned_user_id: assigneeId,
      });
      if (assignErr) {
        assignError = mapRpcError(assignErr.message);
      }
    }
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);

  if (assignError) {
    return { leadId, assignError };
  }

  redirect(`/crm/leads/${leadId}`);
}

export async function updateLeadOperationalAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const notesSummary = String(formData.get("notesSummary") ?? "");
  const sourceId = String(formData.get("leadSourceId") ?? "");
  const campaignId = String(formData.get("leadCampaignId") ?? "");
  const clearSource = formData.get("clearSource") === "true";
  const clearCampaign = formData.get("clearCampaign") === "true";

  if (!leadId) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_lead_operational", {
    p_lead_id: leadId,
    p_notes_summary: notesSummary || undefined,
    p_lead_source_id: sourceId || undefined,
    p_lead_campaign_id: campaignId || undefined,
    p_clear_source: clearSource,
    p_clear_campaign: clearCampaign,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function updateLeadCandidateAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  const actor = await getCurrentAppUser();
  if (!actor) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const candidateId = String(formData.get("candidateId") ?? "");
  const givenName = String(formData.get("givenName") ?? "").trim();
  const familyName = String(formData.get("familyName") ?? "").trim();
  const dateOfBirth = String(formData.get("dateOfBirth") ?? "") || null;
  const isPrimary = formData.get("isPrimaryCandidate") === "true";

  if (!leadId || !candidateId || !givenName || !familyName) {
    return { error: "invalid_candidate" };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("lead_candidate")
    .update({
      given_name: givenName,
      family_name: familyName,
      date_of_birth: dateOfBirth,
      is_primary_candidate: isPrimary,
      updated_by: actor.appUserId,
    })
    .eq("id", candidateId)
    .eq("lead_id", leadId);

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function updateLeadContactAction(
  _prev: LeadMutationState,
  formData: FormData,
): Promise<LeadMutationState> {
  if (!(await can("lead.update"))) {
    return { error: "permission_denied" };
  }
  const actor = await getCurrentAppUser();
  if (!actor) {
    return { error: "permission_denied" };
  }

  const leadId = String(formData.get("leadId") ?? "");
  const contactId = String(formData.get("contactId") ?? "");
  const givenName = String(formData.get("givenName") ?? "").trim();
  const familyName = String(formData.get("familyName") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const email = String(formData.get("email") ?? "").trim() || null;
  const relationshipRaw = String(formData.get("relationshipType") ?? "guardian");
  const relationshipType = (LEAD_CONTACT_RELATIONSHIPS as readonly string[]).includes(
    relationshipRaw,
  )
    ? relationshipRaw
    : "guardian";
  const isPrimary = formData.get("isPrimaryContact") === "true";
  const isBilling = formData.get("isBillingContact") === "true";

  if (!leadId || !contactId || !givenName || !familyName) {
    return { error: "invalid_contact" };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("lead_contact")
    .update({
      given_name: givenName,
      family_name: familyName,
      phone,
      email,
      relationship_type: relationshipType,
      is_primary_contact: isPrimary,
      is_billing_contact: isBilling,
      updated_by: actor.appUserId,
    })
    .eq("id", contactId)
    .eq("lead_id", leadId);

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/leads");
  revalidatePath(`/crm/leads/${leadId}`);
  return {};
}

export async function upsertLeadSourceCatalogAction(
  _prev: LeadCatalogState,
  formData: FormData,
): Promise<LeadCatalogState> {
  if (!(await can("lead.manage_sources"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const id = String(formData.get("id") ?? "") || undefined;
  const code = String(formData.get("code") ?? "");
  const displayName = String(formData.get("displayName") ?? "");
  const status = String(formData.get("status") ?? "active");

  if (!code.trim() || !displayName.trim()) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("upsert_lead_source_catalog", {
    p_id: (id ?? null) as unknown as string,
    p_code: code,
    p_display_name: displayName,
    p_status: status,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/settings");
  revalidatePath("/crm/leads");
  return { success: true };
}

export async function upsertLeadCampaignCatalogAction(
  _prev: LeadCatalogState,
  formData: FormData,
): Promise<LeadCatalogState> {
  if (!(await can("lead.manage_sources"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const id = String(formData.get("id") ?? "") || undefined;
  const code = String(formData.get("code") ?? "");
  const name = String(formData.get("name") ?? "");
  const leadSourceId = String(formData.get("leadSourceId") ?? "") || undefined;
  const status = String(formData.get("status") ?? "active");

  if (!code.trim() || !name.trim()) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("upsert_lead_campaign_catalog", {
    p_id: (id ?? null) as unknown as string,
    p_code: code,
    p_name: name,
    p_lead_source_id: (leadSourceId ?? null) as string | undefined,
    p_status: status,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/settings");
  revalidatePath("/crm/leads");
  return { success: true };
}

export async function upsertLeadLostReasonCatalogAction(
  _prev: LeadCatalogState,
  formData: FormData,
): Promise<LeadCatalogState> {
  if (!(await can("lead.manage_sources"))) {
    return { error: "permission_denied" };
  }
  if (!(await getCurrentAppUser())) {
    return { error: "permission_denied" };
  }

  const id = String(formData.get("id") ?? "") || undefined;
  const code = String(formData.get("code") ?? "");
  const displayName = String(formData.get("displayName") ?? "");
  const status = String(formData.get("status") ?? "active");

  if (!code.trim() || !displayName.trim()) {
    return { error: "mutation_error" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("upsert_lead_lost_reason_catalog", {
    p_id: (id ?? null) as unknown as string,
    p_code: code,
    p_display_name: displayName,
    p_status: status,
  });

  if (error) {
    return { error: mapRpcError(error.message) };
  }

  revalidatePath("/crm/settings");
  revalidatePath("/crm/leads");
  return { success: true };
}
