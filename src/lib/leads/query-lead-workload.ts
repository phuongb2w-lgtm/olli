import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchAppUserIdentityLabels } from "@/lib/identity/fetch-app-user-identity-labels";
import { LEAD_INACTIVE_STATUSES } from "@/lib/leads/constants";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type LeadWorkloadSummary = {
  unassignedActiveCount: number;
  byAssignee: { userId: string; displayName: string; activeCount: number }[];
};

export async function queryLeadWorkloadSummary(
  supabase: DbClient,
): Promise<{ summary: LeadWorkloadSummary | null; error: boolean }> {
  try {
    const { data: leads, error: leadsError } = await supabase
      .from("lead")
      .select("assigned_user_id, status");

    if (leadsError || !leads) {
      return { summary: null, error: true };
    }

    const activeLeads = leads.filter(
      (l) => !(LEAD_INACTIVE_STATUSES as readonly string[]).includes(l.status),
    );

    const counts = new Map<string | null, number>();
    for (const lead of activeLeads) {
      const key = lead.assigned_user_id;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }

    const unassignedActiveCount = counts.get(null) ?? 0;
    counts.delete(null);

    const userIds = [...counts.keys()].filter(Boolean) as string[];
    const userLabels = userIds.length
      ? await fetchAppUserIdentityLabels(supabase, userIds)
      : new Map<string, { userId: string; displayName: string; membershipStatus: string }>();

    const nameMap = new Map([...userLabels.entries()].map(([id, u]) => [id, u.displayName]));

    const byAssignee = userIds
      .map((userId) => ({
        userId,
        displayName: nameMap.get(userId) ?? userId,
        activeCount: counts.get(userId) ?? 0,
      }))
      .sort((a, b) => a.displayName.localeCompare(b.displayName));

    return {
      summary: { unassignedActiveCount, byAssignee },
      error: false,
    };
  } catch {
    return { summary: null, error: true };
  }
}
