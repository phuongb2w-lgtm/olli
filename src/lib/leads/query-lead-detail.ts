import type { SupabaseClient } from "@supabase/supabase-js";
import { formatPersonName } from "@/lib/leads/format-person-name";
import type {
  LeadActivityType,
  LeadFollowUpStatus,
  LeadStatus,
} from "@/lib/leads/constants";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type LeadCandidateDetail = {
  id: string;
  givenName: string;
  familyName: string;
  displayName: string;
  dateOfBirth: string | null;
  isPrimaryCandidate: boolean;
};

export type LeadContactDetail = {
  id: string;
  givenName: string;
  familyName: string;
  displayName: string;
  phone: string | null;
  email: string | null;
  relationshipType: string;
  isPrimaryContact: boolean;
  isBillingContact: boolean;
};

export type LeadActivityDetail = {
  id: string;
  activityType: LeadActivityType;
  occurredAt: string;
  content: string | null;
  createdByName: string | null;
  metadata: Record<string, unknown>;
};

export type LeadStatusHistoryDetail = {
  id: string;
  fromStatus: LeadStatus | null;
  toStatus: LeadStatus;
  changedAt: string;
  changedByName: string | null;
  lostReasonLabel: string | null;
  notes: string | null;
};

export type LeadFollowUpDetail = {
  id: string;
  dueAt: string;
  note: string | null;
  status: LeadFollowUpStatus;
  assignedUserName: string | null;
  completedAt: string | null;
};

export type LeadTimelineEntry =
  | { kind: "activity"; occurredAt: string; activity: LeadActivityDetail }
  | { kind: "status"; occurredAt: string; status: LeadStatusHistoryDetail };

export type LeadDetail = {
  id: string;
  status: LeadStatus;
  notesSummary: string | null;
  createdAt: string;
  sourceLabel: string | null;
  campaignName: string | null;
  assignedUserName: string | null;
  lostReasonLabel: string | null;
  lostNotes: string | null;
  lostAt: string | null;
  candidates: LeadCandidateDetail[];
  contacts: LeadContactDetail[];
  activities: LeadActivityDetail[];
  statusHistory: LeadStatusHistoryDetail[];
  followUps: LeadFollowUpDetail[];
  timeline: LeadTimelineEntry[];
  lostReasons: { id: string; code: string; displayName: string }[];
};

export async function queryLeadDetail(
  supabase: DbClient,
  leadId: string,
): Promise<{ detail: LeadDetail | null; error: boolean; notFound: boolean }> {
  const { data: lead, error: leadError } = await supabase
    .from("lead")
    .select(
      "id, status, notes_summary, created_at, lead_source_id, lead_campaign_id, assigned_user_id, lost_reason_id, lost_notes, lost_at",
    )
    .eq("id", leadId)
    .maybeSingle();

  if (leadError) {
    return { detail: null, error: true, notFound: false };
  }
  if (!lead) {
    return { detail: null, error: false, notFound: true };
  }

  const [
    source,
    campaign,
    assignedUser,
    lostReason,
    lostReasons,
    candidates,
    contacts,
    activities,
    statusHistory,
    followUps,
  ] = await Promise.all([
    lead.lead_source_id
      ? supabase.from("lead_source").select("display_name").eq("id", lead.lead_source_id).maybeSingle()
      : Promise.resolve({ data: null }),
    lead.lead_campaign_id
      ? supabase.from("lead_campaign").select("name").eq("id", lead.lead_campaign_id).maybeSingle()
      : Promise.resolve({ data: null }),
    lead.assigned_user_id
      ? supabase.from("app_user").select("display_name").eq("id", lead.assigned_user_id).maybeSingle()
      : Promise.resolve({ data: null }),
    lead.lost_reason_id
      ? supabase.from("lead_lost_reason").select("display_name").eq("id", lead.lost_reason_id).maybeSingle()
      : Promise.resolve({ data: null }),
    supabase
      .from("lead_lost_reason")
      .select("id, code, display_name")
      .eq("status", "active")
      .order("display_name"),
    supabase
      .from("lead_candidate")
      .select("id, given_name, family_name, date_of_birth, is_primary_candidate")
      .eq("lead_id", leadId)
      .eq("status", "active")
      .order("is_primary_candidate", { ascending: false }),
    supabase
      .from("lead_contact")
      .select(
        "id, given_name, family_name, phone, email, relationship_type, is_primary_contact, is_billing_contact",
      )
      .eq("lead_id", leadId)
      .eq("status", "active")
      .order("is_primary_contact", { ascending: false }),
    supabase
      .from("lead_activity")
      .select("id, activity_type_code, occurred_at, content, metadata, created_by")
      .eq("lead_id", leadId)
      .order("occurred_at", { ascending: false }),
    supabase
      .from("lead_status_history")
      .select("id, from_status, to_status, changed_at, changed_by, lost_reason_id, notes")
      .eq("lead_id", leadId)
      .order("changed_at", { ascending: false }),
    supabase
      .from("lead_follow_up")
      .select("id, due_at, note, status, assigned_user_id, completed_at")
      .eq("lead_id", leadId)
      .order("due_at", { ascending: true }),
  ]);

  const actorIds = new Set<string>();
  for (const row of activities.data ?? []) {
    if (row.created_by) actorIds.add(row.created_by);
  }
  for (const row of statusHistory.data ?? []) {
    actorIds.add(row.changed_by);
  }
  const assigneeIds = (followUps.data ?? [])
    .map((f) => f.assigned_user_id)
    .filter(Boolean) as string[];
  for (const id of assigneeIds) actorIds.add(id);

  const { data: actors } = actorIds.size
    ? await supabase.from("app_user").select("id, display_name").in("id", [...actorIds])
    : { data: [] as { id: string; display_name: string }[] };

  const actorMap = new Map((actors ?? []).map((a) => [a.id, a.display_name]));

  const lostReasonIds = (statusHistory.data ?? [])
    .map((h) => h.lost_reason_id)
    .filter(Boolean) as string[];
  const { data: historyReasons } = lostReasonIds.length
    ? await supabase.from("lead_lost_reason").select("id, display_name").in("id", lostReasonIds)
    : { data: [] as { id: string; display_name: string }[] };
  const historyReasonMap = new Map((historyReasons ?? []).map((r) => [r.id, r.display_name]));

  const candidateDetails: LeadCandidateDetail[] = (candidates.data ?? []).map((c) => ({
    id: c.id,
    givenName: c.given_name,
    familyName: c.family_name,
    displayName: formatPersonName(c.given_name, c.family_name),
    dateOfBirth: c.date_of_birth,
    isPrimaryCandidate: c.is_primary_candidate,
  }));

  const contactDetails: LeadContactDetail[] = (contacts.data ?? []).map((c) => ({
    id: c.id,
    givenName: c.given_name,
    familyName: c.family_name,
    displayName: formatPersonName(c.given_name, c.family_name),
    phone: c.phone,
    email: c.email,
    relationshipType: c.relationship_type,
    isPrimaryContact: c.is_primary_contact,
    isBillingContact: c.is_billing_contact,
  }));

  const activityDetails: LeadActivityDetail[] = (activities.data ?? []).map((a) => ({
    id: a.id,
    activityType: a.activity_type_code as LeadActivityType,
    occurredAt: a.occurred_at,
    content: a.content,
    createdByName: a.created_by ? actorMap.get(a.created_by) ?? null : null,
    metadata: (a.metadata as Record<string, unknown>) ?? {},
  }));

  const statusHistoryDetails: LeadStatusHistoryDetail[] = (statusHistory.data ?? []).map((h) => ({
    id: h.id,
    fromStatus: h.from_status as LeadStatus | null,
    toStatus: h.to_status as LeadStatus,
    changedAt: h.changed_at,
    changedByName: actorMap.get(h.changed_by) ?? null,
    lostReasonLabel: h.lost_reason_id ? historyReasonMap.get(h.lost_reason_id) ?? null : null,
    notes: h.notes,
  }));

  const followUpDetails: LeadFollowUpDetail[] = (followUps.data ?? []).map((f) => ({
    id: f.id,
    dueAt: f.due_at,
    note: f.note,
    status: f.status as LeadFollowUpStatus,
    assignedUserName: f.assigned_user_id ? actorMap.get(f.assigned_user_id) ?? null : null,
    completedAt: f.completed_at,
  }));

  const timeline: LeadTimelineEntry[] = [
    ...activityDetails.map((activity) => ({
      kind: "activity" as const,
      occurredAt: activity.occurredAt,
      activity,
    })),
    ...statusHistoryDetails.map((status) => ({
      kind: "status" as const,
      occurredAt: status.changedAt,
      status,
    })),
  ].sort((a, b) => b.occurredAt.localeCompare(a.occurredAt));

  return {
    detail: {
      id: lead.id,
      status: lead.status as LeadStatus,
      notesSummary: lead.notes_summary,
      createdAt: lead.created_at,
      sourceLabel: source.data?.display_name ?? null,
      campaignName: campaign.data?.name ?? null,
      assignedUserName: assignedUser.data?.display_name ?? null,
      lostReasonLabel: lostReason.data?.display_name ?? null,
      lostNotes: lead.lost_notes,
      lostAt: lead.lost_at,
      candidates: candidateDetails,
      contacts: contactDetails,
      activities: activityDetails,
      statusHistory: statusHistoryDetails,
      followUps: followUpDetails,
      timeline,
      lostReasons: (lostReasons.data ?? []).map((r) => ({
        id: r.id,
        code: r.code,
        displayName: r.display_name,
      })),
    },
    error: false,
    notFound: false,
  };
}
