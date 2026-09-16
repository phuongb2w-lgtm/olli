import type { SupabaseClient } from "@supabase/supabase-js";
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
    if (matchingIds !== null && matchingIds.size === 0) {
      return {
        result: { items: [], totalCount: 0, params: { ...params, page: 1 } },
        error: false,
      };
    }

    let countQuery = supabase.from("lead").select("*", { count: "exact", head: true });
    if (params.status !== "all") {
      countQuery = countQuery.eq("status", params.status);
    }
    countQuery = applyOwnershipFilter(countQuery, params, currentUserId);
    if (matchingIds !== null) {
      countQuery = countQuery.in("id", [...matchingIds]);
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
    pageQuery = applyOwnershipFilter(pageQuery, params, currentUserId);
    if (matchingIds !== null) {
      pageQuery = pageQuery.in("id", [...matchingIds]);
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

async function resolveMatchingLeadIds(
  supabase: DbClient,
  q: string,
): Promise<Set<string> | null> {
  if (!isLeadSearchActive(q)) return null;

  const pattern = `%${q.replace(/[%_\\]/g, "\\$&")}%`;
  const leadIds = new Set<string>();

  const [candidates, contacts] = await Promise.all([
    supabase
      .from("lead_candidate")
      .select("lead_id")
      .or(`given_name.ilike.${pattern},family_name.ilike.${pattern}`)
      .eq("status", "active"),
    supabase
      .from("lead_contact")
      .select("lead_id")
      .or(`given_name.ilike.${pattern},family_name.ilike.${pattern},phone.ilike.${pattern},email.ilike.${pattern}`)
      .eq("status", "active"),
  ]);

  for (const row of candidates.data ?? []) {
    leadIds.add(row.lead_id);
  }
  for (const row of contacts.data ?? []) {
    leadIds.add(row.lead_id);
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

  const [sources, users, candidates, contacts, followUps, activities] = await Promise.all([
    sourceIds.length
      ? supabase.from("lead_source").select("id, code, display_name").in("id", sourceIds)
      : Promise.resolve({ data: [] }),
    userIds.length
      ? supabase.from("app_user").select("id, display_name").in("id", userIds)
      : Promise.resolve({ data: [] }),
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
  ]);

  const sourceMap = new Map((sources.data ?? []).map((s) => [s.id, s.display_name]));
  const userMap = new Map((users.data ?? []).map((u) => [u.id, u.display_name]));

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

  return leads.map((lead) => {
    const activity = lastActivity.get(lead.id);
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
    };
  });
}
