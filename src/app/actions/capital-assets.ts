"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  validateDetailedCapitalAssetInput,
  validateQuickCapitalAssetInput,
  type DetailedCapitalAssetInput,
  type QuickCapitalAssetInput,
} from "@/lib/capital-assets/validate-capital-asset-input";
import { createClient } from "@/lib/supabase/server";

export type CapitalAssetActionState = {
  error?:
    | "permission_denied"
    | "validation_error"
    | "save_error"
    | "not_found";
  fieldErrors?: Record<string, string>;
  assetId?: string;
  postedCount?: number;
};

export async function createDetailedCapitalAsset(
  input: DetailedCapitalAssetInput,
): Promise<CapitalAssetActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("asset.create"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateDetailedCapitalAssetInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_capital_asset", {
    p_name: parsed.data.name,
    p_original_cost: parsed.data.originalCost,
    p_useful_life_months: parsed.data.usefulLifeMonths,
    p_placed_in_service_date: parsed.data.placedInServiceDate,
    p_category_code: parsed.data.categoryCode ?? undefined,
    p_notes: parsed.data.notes ?? undefined,
    p_is_quick_mode: false,
  });

  if (error || !data) return { error: "save_error" };
  return { assetId: data as string };
}

export async function createQuickCapitalAsset(
  input: QuickCapitalAssetInput,
): Promise<CapitalAssetActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("asset.create"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateQuickCapitalAssetInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_quick_capital_asset", {
    p_total_investment: parsed.data.totalInvestment,
    p_useful_life_months: parsed.data.usefulLifeMonths,
    p_placed_in_service_date: parsed.data.placedInServiceDate,
    p_name: parsed.data.name,
  });

  if (error || !data) return { error: "save_error" };
  return { assetId: data as string };
}

export async function postDepreciationThrough(
  assetId: string,
  throughMonth: string,
): Promise<CapitalAssetActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("asset.update"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("post_depreciation_through", {
    p_capital_asset_id: assetId,
    p_through_month: throughMonth,
  });

  if (error) return { error: "save_error" };
  return { postedCount: data as number };
}

export async function retireCapitalAsset(
  assetId: string,
  retiredAt: string,
): Promise<CapitalAssetActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("asset.update"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("retire_capital_asset", {
    p_capital_asset_id: assetId,
    p_retired_at: retiredAt,
  });

  if (error) {
    if (error.code === "P0002") return { error: "not_found" };
    return { error: "save_error" };
  }

  return {};
}
