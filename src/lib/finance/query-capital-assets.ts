import type { SupabaseClient } from "@supabase/supabase-js";

export type CapitalAssetListItem = {
  id: string;
  name: string;
  originalCost: number;
  usefulLifeMonths: number;
  placedInServiceDate: string;
  status: string;
  isQuickMode: boolean;
  categoryCode: string | null;
  monthlyDepreciation: number;
  postedDepreciation: number;
};

export async function queryCapitalAssetsList(
  supabase: SupabaseClient,
): Promise<{ items: CapitalAssetListItem[]; error: string | null }> {
  const { data, error } = await supabase
    .from("capital_asset")
    .select("id, name, original_cost, useful_life_months, placed_in_service_date, status, is_quick_mode, category_code")
    .order("placed_in_service_date", { ascending: false });

  if (error) return { items: [], error: "load_error" };

  const items: CapitalAssetListItem[] = [];
  for (const row of data ?? []) {
    const monthlyDepreciation = Math.floor(Number(row.original_cost) / Number(row.useful_life_months));
    const { data: postedRows } = await supabase
      .from("depreciation_entry")
      .select("amount")
      .eq("capital_asset_id", row.id)
      .eq("status", "posted");
    const postedDepreciation = (postedRows ?? []).reduce((s, r) => s + Number(r.amount), 0);

    items.push({
      id: row.id,
      name: row.name,
      originalCost: Number(row.original_cost),
      usefulLifeMonths: Number(row.useful_life_months),
      placedInServiceDate: row.placed_in_service_date,
      status: row.status,
      isQuickMode: row.is_quick_mode,
      categoryCode: row.category_code,
      monthlyDepreciation,
      postedDepreciation,
    });
  }

  return { items, error: null };
}

export async function queryCapitalAssetDetail(
  supabase: SupabaseClient,
  assetId: string,
): Promise<{ asset: CapitalAssetListItem | null; schedule: Array<{ periodMonth: string; amount: number; status: string }>; error: string | null }> {
  const { data: row, error } = await supabase
    .from("capital_asset")
    .select("id, name, original_cost, useful_life_months, placed_in_service_date, status, is_quick_mode, category_code")
    .eq("id", assetId)
    .maybeSingle();

  if (error || !row) return { asset: null, schedule: [], error: "not_found" };

  const monthlyDepreciation = Math.floor(Number(row.original_cost) / Number(row.useful_life_months));
  const { data: depRows } = await supabase
    .from("depreciation_entry")
    .select("period_month, amount, status")
    .eq("capital_asset_id", assetId)
    .order("period_number", { ascending: true });

  const postedDepreciation = (depRows ?? [])
    .filter((r) => r.status === "posted")
    .reduce((s, r) => s + Number(r.amount), 0);

  return {
    asset: {
      id: row.id,
      name: row.name,
      originalCost: Number(row.original_cost),
      usefulLifeMonths: Number(row.useful_life_months),
      placedInServiceDate: row.placed_in_service_date,
      status: row.status,
      isQuickMode: row.is_quick_mode,
      categoryCode: row.category_code,
      monthlyDepreciation,
      postedDepreciation,
    },
    schedule: (depRows ?? []).map((r) => ({
      periodMonth: r.period_month,
      amount: Number(r.amount),
      status: r.status,
    })),
    error: null,
  };
}
