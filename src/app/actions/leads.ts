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
  if (message.includes("lead_lifecycle_protected")) return "invalid_transition";
  if (message.includes("Lead assignment must")) return "permission_denied";
  return "mutation_error";
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
