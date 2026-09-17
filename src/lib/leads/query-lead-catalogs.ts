import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type LeadCatalogSource = {
  id: string;
  code: string;
  displayName: string;
  status: string;
};

export type LeadCatalogCampaign = {
  id: string;
  code: string;
  name: string;
  status: string;
  leadSourceId: string | null;
};

export type LeadCatalogLostReason = {
  id: string;
  code: string;
  displayName: string;
  status: string;
};

export async function queryLeadCatalogs(supabase: DbClient): Promise<{
  sources: LeadCatalogSource[];
  campaigns: LeadCatalogCampaign[];
  lostReasons: LeadCatalogLostReason[];
  error: boolean;
}> {
  const [sourcesRes, campaignsRes, lostReasonsRes] = await Promise.all([
    supabase.from("lead_source").select("id, code, display_name, status").order("display_name"),
    supabase.from("lead_campaign").select("id, code, name, status, lead_source_id").order("name"),
    supabase.from("lead_lost_reason").select("id, code, display_name, status").order("display_name"),
  ]);

  if (sourcesRes.error || campaignsRes.error || lostReasonsRes.error) {
    return { sources: [], campaigns: [], lostReasons: [], error: true };
  }

  return {
    sources: (sourcesRes.data ?? []).map((s) => ({
      id: s.id,
      code: s.code,
      displayName: s.display_name,
      status: s.status,
    })),
    campaigns: (campaignsRes.data ?? []).map((c) => ({
      id: c.id,
      code: c.code,
      name: c.name,
      status: c.status,
      leadSourceId: c.lead_source_id,
    })),
    lostReasons: (lostReasonsRes.data ?? []).map((r) => ({
      id: r.id,
      code: r.code,
      displayName: r.display_name,
      status: r.status,
    })),
    error: false,
  };
}

export function activeCatalogItems<T extends { status: string }>(items: T[]): T[] {
  return items.filter((item) => item.status === "active");
}
