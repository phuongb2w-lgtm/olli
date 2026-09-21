import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchAppUserIdentityLabels } from "@/lib/identity/fetch-app-user-identity-labels";
import { formatPersonName } from "@/lib/leads/format-person-name";
import {
  clampPage,
  isLeadSearchActive,
  parseLeadListParams,
} from "@/lib/leads/parse-list-params";
import type { LeadStatus } from "@/lib/leads/constants";
import type { LeadListParams } from "@/lib/leads/parse-list-params";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type LeadListItem = {
  id: string;
  status: LeadStatus;
  createdAt: string;
  sourceLabel: string | null;
  assignedUserName: string | null;
  primaryCandidateName: string | null;
  primaryContactName: string | null;
  nextFollowUpAt: string | null;
  lastActivityAt: string | null;
  lastActivityType: string | null;
  nextTrialAt: string | null;
  hasScheduledTrial: boolean;
  identityReady: boolean;
  unresolvedIdentityCount: number;
};

export type LeadListResult = {
  items: LeadListItem[];
  totalCount: number;
  params: LeadListParams;
};

type LeadRow = {
  id: string;
  status: string;
  created_at: string;
  assigned_user_id: string | null;
  lead_source_id: string | null;
};

function applyOwnershipFilter<T extends { eq: (col: string, val: string) => T; is: (col: string, val: null) => T }>(
  query: T,
  params: LeadListParams,
  currentUserId: string | null,
): T {
  if (params.owner === "me" && currentUserId) {
    return query.eq("assigned_user_id", currentUserId);
  }
  if (params.owner === "unassigned") {
    return query.is("assigned_user_id", null);
  }
  if (params.owner === "user" && params.ownerUserId) {
    return query.eq("assigned_user_id", params.ownerUserId);
  }
  return query;
}

export async function queryLeadList(
  supabase: DbClient,
  rawParams: Record<string, string | string[] | undefined>,
  currentUserId: string | null = null,
): Promise<{ result: LeadListResult | null; error: boolean }> {
  const params = parseLeadListParams(rawParams);

  try {
    const matchingIds = await resolveMatchingLeadIds(supabase, params.q);
    const scheduledTrialLeadIds =
      params.trial === "scheduled" ? await resolveScheduledTrialLeadIds(supabase) : null;
    const followUpDueLeadIds =
      params.preset === "follow_up_due" ? await resolveFollowUpDueLeadIds(supabase) : null;
    const identityLeadIds =
      params.identity !== "all" ? await resolveIdentityLeadIds(supabase, params.identity) : null;

    const extraFilterIds = intersectLeadIdSets([
      matchingIds,
      scheduledTrialLeadIds,
      followUpDueLeadIds,
      identityLeadIds,
    ]);

    if (extraFilterIds !== null && extraFilterIds.size === 0) {
      return {
        result: { items: [], totalCount: 0, params: { ...params, page: 1 } },
        error: false,
      };
    }

    let countQuery = supabase.from("lead").select("*", { count: "exact", head: true });
    if (params.status !== "all") {
      countQuery = countQuery.eq("status", params.status);
    }
    if (params.sourceId === "unattributed") {
      countQuery = countQuery.is("lead_source_id", null);
    } else if (params.sourceId) {
      countQuery = countQuery.eq("lead_source_id", params.sourceId);
    }
    if (params.campaignId === "unattributed") {
      countQuery = countQuery.is("lead_campaign_id", null);
    } else if (params.campaignId) {
      countQuery = countQuery.eq("lead_campaign_id", params.campaignId);
    }
    countQuery = applyOwnershipFilter(countQuery, params, currentUserId);
    if (extraFilterIds !== null) {
      countQuery = countQuery.in("id", [...extraFilterIds]);
    }
    const { count, error: countError } = await countQuery;

    if (countError) {
      return { result: null, error: true };
    }

    const totalCount = count ?? 0;
    const safePage = clampPage(params.page, totalCount, params.pageSize);
    const from = (safePage - 1) * params.pageSize;
    const to = from + params.pageSize - 1;

    let pageQuery = supabase
      .from("lead")
      .select("id, status, created_at, assigned_user_id, lead_source_id")
      .order("created_at", { ascending: false })
      .range(from, to);
    if (params.status !== "all") {
      pageQuery = pageQuery.eq("status", params.status);
    }
    if (params.sourceId === "unattributed") {
      pageQuery = pageQuery.is("lead_source_id", null);
    } else if (params.sourceId) {
      pageQuery = pageQuery.eq("lead_source_id", params.sourceId);
    }
    if (params.campaignId === "unattributed") {
      pageQuery = pageQuery.is("lead_campaign_id", null);
    } else if (params.campaignId) {
      pageQuery = pageQuery.eq("lead_campaign_id", params.campaignId);
    }
    pageQuery = applyOwnershipFilter(pageQuery, params, currentUserId);
    if (extraFilterIds !== null) {
      pageQuery = pageQuery.in("id", [...extraFilterIds]);
    }
    const { data: leads, error: pageError } = await pageQuery;
    if (pageError || !leads) {
      return { result: null, error: true };
    }

    const items = await enrichLeadListItems(supabase, leads as LeadRow[]);

    return {
      result: {
        items,
        totalCount,
        params: { ...params, page: safePage },
      },
      error: false,
    };
  } catch {
    return { result: null, error: true };
  }
}

function intersectLeadIdSets(filters: Array<Set<string> | null>): Set<string> | null {
  const active = filters.filter((f): f is Set<string> => f !== null);
  if (active.length === 0) return null;
  let result = new Set(active[0]);
  for (let i = 1; i < active.length; i += 1) {
    result = new Set([...result].filter((id) => active[i].has(id)));
  }
  return result;
}

async function resolveFollowUpDueLeadIds(supabase: DbClient): Promise<Set<string>> {
  const endOfDay = new Date();
  endOfDay.setHours(23, 59, 59, 999);
  const { data } = await supabase
    .from("lead_follow_up")
    .select("lead_id")
    .eq("status", "pending")
    .lte("due_at", endOfDay.toISOString());
  return new Set((data ?? []).map((row) => row.lead_id));
}

async function resolveIdentityLeadIds(
  supabase: DbClient,
  filter: "ready" | "unresolved",
): Promise<Set<string>> {
  const unresolved = new Set<string>();

  const [
    { data: candidates },
    { data: candidateResolutions },
    { data: contacts },
    { data: contactResolutions },
  ] = await Promise.all([
    supabase.from("lead_candidate").select("id, lead_id").eq("status", "active"),
    supabase
      .from("lead_candidate_identity_resolution")
      .select("lead_candidate_id, is_stale, resolution_mode, student_id"),
    supabase.from("lead_contact").select("id, lead_id").eq("status", "active"),
    supabase
      .from("lead_contact_identity_resolution")
      .select("lead_contact_id, is_stale, resolution_mode, guardian_id"),
  ]);

  const candResMap = new Map(
    (candidateResolutions ?? []).map((r) => [r.lead_candidate_id, r]),
  );
  const contactResMap = new Map(
    (contactResolutions ?? []).map((r) => [r.lead_contact_id, r]),
  );

  const leadsWithCandidates = new Set<string>();
  const leadsWithContacts = new Set<string>();
  for (const c of candidates ?? []) {
    leadsWithCandidates.add(c.lead_id);
    const res = candResMap.get(c.id);
    if (!res || res.is_stale) {
      unresolved.add(c.lead_id);
    }
  }
  for (const c of contacts ?? []) {
    leadsWithContacts.add(c.lead_id);
    const res = contactResMap.get(c.id);
    if (!res || res.is_stale) {
      unresolved.add(c.lead_id);
    }
  }

  if (filter === "unresolved") {
    return unresolved;
  }

  const ready = new Set<string>();
  for (const leadId of leadsWithCandidates) {
    if (leadsWithContacts.has(leadId) && !unresolved.has(leadId)) {
      ready.add(leadId);
    }
  }
  return ready;
}

async function resolveScheduledTrialLeadIds(supabase: DbClient): Promise<Set<string>> {
  const { data } = await supabase
    .from("lead_trial")
    .select("lead_id")
    .eq("status", "scheduled");
  return new Set((data ?? []).map((row) => row.lead_id));
}

async function resolveMatchingLeadIds(
  supabase: DbClient,
  q: string,
): Promise<Set<string> | null> {
  if (!isLeadSearchActive(q)) return null;

  const pattern = `%${q.replace(/[%_\\]/g, "\\$&")}%`;
  const leadIds = new Set<string>();

  const digitsOnly = q.replace(/\D/g, "");
  const contactOrParts = [
    `given_name.ilike.${pattern}`,
    `family_name.ilike.${pattern}`,
    `phone.ilike.${pattern}`,
    `email.ilike.${pattern}`,
    `phone_normalized.ilike.${pattern}`,
    `email_normalized.ilike.${pattern}`,
  ];
  if (digitsOnly.length >= 4) {
    contactOrParts.push(`phone_normalized.ilike.%${digitsOnly}%`);
  }

  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const [candidates, contacts] = await Promise.all([
    supabase
      .from("lead_candidate")
      .select("lead_id")
      .or(`given_name.ilike.${pattern},family_name.ilike.${pattern}`)
      .eq("status", "active"),
    supabase
      .from("lead_contact")
      .select("lead_id")
      .or(contactOrParts.join(","))
      .eq("status", "active"),
  ]);

  for (const row of candidates.data ?? []) {
    leadIds.add(row.lead_id);
  }
  for (const row of contacts.data ?? []) {
    leadIds.add(row.lead_id);
  }
  if (uuidPattern.test(q.trim())) {
    leadIds.add(q.trim());
  }

  return leadIds;
}

async function enrichLeadListItems(
  supabase: DbClient,
  leads: LeadRow[],
): Promise<LeadListItem[]> {
  if (leads.length === 0) return [];

  const leadIds = leads.map((l) => l.id);
  const sourceIds = [...new Set(leads.map((l) => l.lead_source_id).filter(Boolean))] as string[];
  const userIds = [...new Set(leads.map((l) => l.assigned_user_id).filter(Boolean))] as string[];

  const [sources, userLabels, candidates, contacts, followUps, activities, trials] = await Promise.all([
    sourceIds.length
      ? supabase.from("lead_source").select("id, code, display_name").in("id", sourceIds)
      : Promise.resolve({ data: [] }),
    userIds.length ? fetchAppUserIdentityLabels(supabase, userIds) : Promise.resolve(new Map()),
    supabase
      .from("lead_candidate")
      .select("lead_id, given_name, family_name, is_primary_candidate")
      .in("lead_id", leadIds)
      .eq("status", "active"),
    supabase
      .from("lead_contact")
      .select("lead_id, given_name, family_name, is_primary_contact")
      .in("lead_id", leadIds)
      .eq("status", "active"),
    supabase
      .from("lead_follow_up")
      .select("lead_id, due_at, status")
      .in("lead_id", leadIds)
      .eq("status", "pending")
      .order("due_at", { ascending: true }),
    supabase
      .from("lead_activity")
      .select("lead_id, occurred_at, activity_type_code")
      .in("lead_id", leadIds)
      .order("occurred_at", { ascending: false }),
    supabase
      .from("lead_trial")
      .select("lead_id, scheduled_start_at, status")
      .in("lead_id", leadIds)
      .eq("status", "scheduled")
      .order("scheduled_start_at", { ascending: true }),
  ]);

  const sourceMap = new Map((sources.data ?? []).map((s) => [s.id, s.display_name]));
  const userMap = new Map(
    [...userLabels.entries()].map(([id, label]) => [id, label.displayName]),
  );

  const primaryCandidate = new Map<string, string>();
  const primaryContact = new Map<string, string>();
  for (const c of candidates.data ?? []) {
    const name = formatPersonName(c.given_name, c.family_name);
    if (c.is_primary_candidate || !primaryCandidate.has(c.lead_id)) {
      primaryCandidate.set(c.lead_id, name);
    }
  }
  for (const c of contacts.data ?? []) {
    const name = formatPersonName(c.given_name, c.family_name);
    if (c.is_primary_contact || !primaryContact.has(c.lead_id)) {
      primaryContact.set(c.lead_id, name);
    }
  }

  const nextFollowUp = new Map<string, string>();
  for (const f of followUps.data ?? []) {
    if (!nextFollowUp.has(f.lead_id)) {
      nextFollowUp.set(f.lead_id, f.due_at);
    }
  }

  const lastActivity = new Map<string, { at: string; type: string }>();
  for (const a of activities.data ?? []) {
    if (!lastActivity.has(a.lead_id)) {
      lastActivity.set(a.lead_id, { at: a.occurred_at, type: a.activity_type_code });
    }
  }

  const nextTrial = new Map<string, string>();
  for (const trial of trials.data ?? []) {
    if (!nextTrial.has(trial.lead_id)) {
      nextTrial.set(trial.lead_id, trial.scheduled_start_at);
    }
  }

  const identityStatuses = await Promise.all(
    leadIds.map(async (leadId) => {
      const { data } = await supabase.rpc("get_lead_identity_resolution_status", {
        p_lead_id: leadId,
      });
      return {
        leadId,
        ready: Boolean((data as { ready?: boolean } | null)?.ready),
        unresolved:
          ((data as { unresolved_candidates?: number } | null)?.unresolved_candidates ?? 0) +
          ((data as { unresolved_contacts?: number } | null)?.unresolved_contacts ?? 0),
      };
    }),
  );
  const identityMap = new Map(identityStatuses.map((s) => [s.leadId, s]));

  return leads.map((lead) => {
    const activity = lastActivity.get(lead.id);
    const trialAt = nextTrial.get(lead.id) ?? null;
    return {
      id: lead.id,
      status: lead.status as LeadStatus,
      createdAt: lead.created_at,
      sourceLabel: lead.lead_source_id ? sourceMap.get(lead.lead_source_id) ?? null : null,
      assignedUserName: lead.assigned_user_id ? userMap.get(lead.assigned_user_id) ?? null : null,
      primaryCandidateName: primaryCandidate.get(lead.id) ?? null,
      primaryContactName: primaryContact.get(lead.id) ?? null,
      nextFollowUpAt: nextFollowUp.get(lead.id) ?? null,
      lastActivityAt: activity?.at ?? null,
      lastActivityType: activity?.type ?? null,
      nextTrialAt: trialAt,
      hasScheduledTrial: trialAt !== null,
      identityReady: identityMap.get(lead.id)?.ready ?? false,
      unresolvedIdentityCount: identityMap.get(lead.id)?.unresolved ?? 0,
    };
  });
}
