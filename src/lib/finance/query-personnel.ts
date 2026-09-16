import type { SupabaseClient } from "@supabase/supabase-js";
import { normalizePeriodMonth } from "@/lib/finance/format-finance-value";

export type CompensationRuleItem = {
  id: string;
  appUserId: string;
  displayName: string | null;
  costDomainCode: string;
  compensationBasisCode: string;
  amount: number;
  effectiveFrom: string;
  effectiveTo: string | null;
  notes: string | null;
};

export type PersonnelCostEntryItem = {
  id: string;
  costDomainCode: string;
  compensationBasisCode: string;
  amount: number;
  accountingPeriod: string;
  classId: string | null;
  className: string | null;
  status: string;
};

export type WelfareBaselineItem = {
  id: string;
  monthlyAmount: number;
  effectiveFrom: string;
  effectiveTo: string | null;
  notes: string | null;
};

export async function queryCompensationRules(
  supabase: SupabaseClient,
): Promise<{ items: CompensationRuleItem[]; error: string | null }> {
  const { data, error } = await supabase
    .from("staff_compensation_rule")
    .select(
      "id, app_user_id, cost_domain_code, compensation_basis_code, amount, effective_from, effective_to, notes, app_user:app_user_id(display_name)",
    )
    .order("effective_from", { ascending: false });

  if (error) return { items: [], error: "load_error" };

  return {
    items: (data ?? []).map((row) => {
      const user = row.app_user as { display_name?: string } | null;
      return {
        id: row.id,
        appUserId: row.app_user_id,
        displayName: user?.display_name ?? null,
        costDomainCode: row.cost_domain_code,
        compensationBasisCode: row.compensation_basis_code,
        amount: Number(row.amount),
        effectiveFrom: row.effective_from,
        effectiveTo: row.effective_to,
        notes: row.notes,
      };
    }),
    error: null,
  };
}

export async function queryPersonnelCostEntries(
  supabase: SupabaseClient,
  periodMonthInput?: string,
): Promise<{ items: PersonnelCostEntryItem[]; error: string | null }> {
  const periodMonth = normalizePeriodMonth(periodMonthInput);
  const { data, error } = await supabase
    .from("personnel_cost_entry_detail")
    .select("id, cost_domain_code, compensation_basis_code, amount, accounting_period, class_id, status, class_name")
    .eq("accounting_period", periodMonth)
    .order("amount", { ascending: false });

  if (error) return { items: [], error: "load_error" };

  return {
    items: (data ?? []).map((row) => ({
      id: row.id,
      costDomainCode: row.cost_domain_code,
      compensationBasisCode: row.compensation_basis_code,
      amount: Number(row.amount),
      accountingPeriod: row.accounting_period,
      classId: row.class_id,
      className: row.class_name,
      status: row.status,
    })),
    error: null,
  };
}

export async function queryWelfareBaselines(
  supabase: SupabaseClient,
): Promise<{ items: WelfareBaselineItem[]; error: string | null }> {
  const { data, error } = await supabase
    .from("welfare_fund_baseline_config")
    .select("id, monthly_amount, effective_from, effective_to, notes")
    .order("effective_from", { ascending: false });

  if (error) return { items: [], error: "load_error" };

  return {
    items: (data ?? []).map((row) => ({
      id: row.id,
      monthlyAmount: Number(row.monthly_amount),
      effectiveFrom: row.effective_from,
      effectiveTo: row.effective_to,
      notes: row.notes,
    })),
    error: null,
  };
}
