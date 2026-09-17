import type { SupabaseClient } from "@supabase/supabase-js";
import { formatPersonName } from "@/lib/leads/format-person-name";
import type {
  LeadActivityType,
  LeadFollowUpStatus,
  LeadStatus,
  LeadTrialEventType,
  LeadTrialStatus,
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

export type LeadAssignmentHistoryDetail = {
  id: string;
  changedAt: string;
  changedByName: string | null;
  previousAssigneeName: string | null;
  newAssigneeName: string | null;
  note: string | null;
};

export type LeadTrialDetail = {
  id: string;
  candidateId: string;
  classId: string;
  className: string;
  teachingSessionId: string | null;
  status: LeadTrialStatus;
  scheduledStartAt: string;
  scheduledEndAt: string;
  operationalNote: string | null;
  outcomeNote: string | null;
  createdAt: string;
};

export type LeadTrialEventDetail = {
  id: string;
  trialId: string;
  eventType: LeadTrialEventType;
  occurredAt: string;
  changedByName: string | null;
  note: string | null;
};

export type LeadTimelineEntry =
  | { kind: "activity"; occurredAt: string; activity: LeadActivityDetail }
  | { kind: "status"; occurredAt: string; status: LeadStatusHistoryDetail }
  | { kind: "assignment"; occurredAt: string; assignment: LeadAssignmentHistoryDetail }
  | { kind: "trial"; occurredAt: string; trialEvent: LeadTrialEventDetail };

export type LeadDetail = {
  id: string;
  status: LeadStatus;
  convertedAt: string | null;
  notesSummary: string | null;
  createdAt: string;
  sourceLabel: string | null;
  leadSourceId: string | null;
  campaignName: string | null;
  leadCampaignId: string | null;
  assignedUserName: string | null;
  assignedUserId: string | null;
  assignmentHistory: LeadAssignmentHistoryDetail[];
  lostReasonLabel: string | null;
  lostNotes: string | null;
  lostAt: string | null;
  candidates: LeadCandidateDetail[];
  contacts: LeadContactDetail[];
  activities: LeadActivityDetail[];
  statusHistory: LeadStatusHistoryDetail[];
  followUps: LeadFollowUpDetail[];
  trials: LeadTrialDetail[];
  trialEvents: LeadTrialEventDetail[];
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
      "id, status, converted_at, notes_summary, created_at, lead_source_id, lead_campaign_id, assigned_user_id, lost_reason_id, lost_notes, lost_at",
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
    assignmentHistory,
    trials,
    eligibleClasses,
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
    supabase
      .from("lead_assignment")
      .select(
        "id, changed_at, changed_by, previous_assigned_user_id, new_assigned_user_id, note",
      )
      .eq("lead_id", leadId)
      .order("changed_at", { ascending: false }),
    supabase
      .from("lead_trial")
      .select(
        "id, lead_candidate_id, class_id, teaching_session_id, status, scheduled_start_at, scheduled_end_at, operational_note, outcome_note, created_at",
      )
      .eq("lead_id", leadId)
      .order("created_at", { ascending: false }),
    supabase.rpc("list_eligible_trial_classes"),
  ]);

  const trialIds = (trials.data ?? []).map((t) => t.id);
  const { data: trialEvents } = trialIds.length
    ? await supabase
        .from("lead_trial_event")
        .select("id, lead_trial_id, event_type, occurred_at, changed_by, note")
        .in("lead_trial_id", trialIds)
        .order("occurred_at", { ascending: false })
    : { data: [] as { id: string; lead_trial_id: string; event_type: string; occurred_at: string; changed_by: string; note: string | null }[] };

  const actorIds = new Set<string>();
  for (const row of activities.data ?? []) {
    if (row.created_by) actorIds.add(row.created_by);
  }
  for (const row of statusHistory.data ?? []) {
    actorIds.add(row.changed_by);
  }
  for (const row of assignmentHistory.data ?? []) {
    actorIds.add(row.changed_by);
    if (row.previous_assigned_user_id) actorIds.add(row.previous_assigned_user_id);
    if (row.new_assigned_user_id) actorIds.add(row.new_assigned_user_id);
  }
  for (const row of trialEvents ?? []) {
    if (row.changed_by) actorIds.add(row.changed_by);
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

  const assignmentHistoryDetails: LeadAssignmentHistoryDetail[] = (
    assignmentHistory.data ?? []
  ).map((a) => ({
    id: a.id,
    changedAt: a.changed_at,
    changedByName: actorMap.get(a.changed_by) ?? null,
    previousAssigneeName: a.previous_assigned_user_id
      ? actorMap.get(a.previous_assigned_user_id) ?? null
      : null,
    newAssigneeName: a.new_assigned_user_id
      ? actorMap.get(a.new_assigned_user_id) ?? null
      : null,
    note: a.note,
  }));

  const classNameMap = new Map(
    (eligibleClasses.data ?? []).map((c) => [c.class_id, c.class_name]),
  );

  const trialDetails: LeadTrialDetail[] = (trials.data ?? []).map((trial) => ({
    id: trial.id,
    candidateId: trial.lead_candidate_id,
    classId: trial.class_id,
    className: classNameMap.get(trial.class_id) ?? trial.class_id,
    teachingSessionId: trial.teaching_session_id,
    status: trial.status as LeadTrialStatus,
    scheduledStartAt: trial.scheduled_start_at,
    scheduledEndAt: trial.scheduled_end_at,
    operationalNote: trial.operational_note,
    outcomeNote: trial.outcome_note,
    createdAt: trial.created_at,
  }));

  const trialEventDetails: LeadTrialEventDetail[] = (trialEvents ?? []).map((event) => ({
    id: event.id,
    trialId: event.lead_trial_id,
    eventType: event.event_type as LeadTrialEventType,
    occurredAt: event.occurred_at,
    changedByName: event.changed_by ? actorMap.get(event.changed_by) ?? null : null,
    note: event.note,
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
    ...assignmentHistoryDetails.map((assignment) => ({
      kind: "assignment" as const,
      occurredAt: assignment.changedAt,
      assignment,
    })),
    ...trialEventDetails.map((trialEvent) => ({
      kind: "trial" as const,
      occurredAt: trialEvent.occurredAt,
      trialEvent,
    })),
  ].sort((a, b) => {
    const timeCompare = b.occurredAt.localeCompare(a.occurredAt);
    if (timeCompare !== 0) return timeCompare;
    const kindOrder = { trial: 0, assignment: 1, status: 2, activity: 3 };
    return kindOrder[a.kind] - kindOrder[b.kind];
  });

  return {
    detail: {
      id: lead.id,
      status: lead.status as LeadStatus,
      convertedAt: lead.converted_at,
      notesSummary: lead.notes_summary,
      createdAt: lead.created_at,
      sourceLabel: source.data?.display_name ?? null,
      leadSourceId: lead.lead_source_id,
      campaignName: campaign.data?.name ?? null,
      leadCampaignId: lead.lead_campaign_id,
      assignedUserName: assignedUser.data?.display_name ?? null,
      assignedUserId: lead.assigned_user_id,
      assignmentHistory: assignmentHistoryDetails,
      lostReasonLabel: lostReason.data?.display_name ?? null,
      lostNotes: lead.lost_notes,
      lostAt: lead.lost_at,
      candidates: candidateDetails,
      contacts: contactDetails,
      activities: activityDetails,
      statusHistory: statusHistoryDetails,
      followUps: followUpDetails,
      trials: trialDetails,
      trialEvents: trialEventDetails,
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
