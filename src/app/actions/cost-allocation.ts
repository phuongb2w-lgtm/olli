"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type CostAllocationActionState = {
  error?: "permission_denied" | "validation_error" | "save_error";
  fieldErrors?: Record<string, string>;
  ruleId?: string;
  result?: Record<string, unknown>;
};

const SOURCE_SCOPES = ["operating_overhead", "marketing_sales", "depreciation", "personnel_shared"] as const;
const BASIS_CODES = ["equal", "active_enrollment_count", "delivered_session_count", "recognized_revenue"] as const;

export async function createCostAllocationRule(input: {
  sourceScopeCode: string;
  allocationBasisCode: string;
  effectiveFrom: string;
  notes?: string | null;
}): Promise<CostAllocationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("cost_allocation.manage"))) {
    return { error: "permission_denied" };
  }

  if (!SOURCE_SCOPES.includes(input.sourceScopeCode as (typeof SOURCE_SCOPES)[number])) {
    return { error: "validation_error", fieldErrors: { sourceScopeCode: "invalid" } };
  }
  if (!BASIS_CODES.includes(input.allocationBasisCode as (typeof BASIS_CODES)[number])) {
    return { error: "validation_error", fieldErrors: { allocationBasisCode: "invalid" } };
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.effectiveFrom)) {
    return { error: "validation_error", fieldErrors: { effectiveFrom: "invalid" } };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_cost_allocation_rule", {
    p_source_scope_code: input.sourceScopeCode,
    p_allocation_basis_code: input.allocationBasisCode,
    p_effective_from: input.effectiveFrom,
    p_notes: input.notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { ruleId: data as string };
}
