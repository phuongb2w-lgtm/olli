"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import type { LeadUserActivityType } from "@/lib/leads/constants";
import { LEAD_USER_ACTIVITY_TYPES } from "@/lib/leads/constants";
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
    | "mutation_error";
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
