import type { SupabaseClient } from "@supabase/supabase-js";
import { normalizePeriodMonth, periodMonthEnd } from "@/lib/finance/format-finance-value";

export type FinanceOverviewMetrics = {
  periodMonth: string;
  recognizedRevenue: number;
  cashReceived: number;
  cashAllocated: number;
  outstandingReceivables: number;
  serviceObligation: number;
  operatingCosts: number;
  personnelCosts: number;
  marketingSalesCosts: number;
  depreciation: number;
  unallocatedSharedCosts: number;
};

export async function queryFinanceOverview(
  supabase: SupabaseClient,
  periodMonthInput?: string,
): Promise<{ metrics: FinanceOverviewMetrics | null; error: string | null }> {
  const periodMonth = normalizePeriodMonth(periodMonthInput);
  const periodEnd = periodMonthEnd(periodMonth);

  let recognizedRevenue = 0;
  const revenueRes = await supabase
    .from("revenue_recognition_event")
    .select("amount")
    .eq("status", "posted")
    .gte("recognized_at", `${periodMonth}T00:00:00`)
    .lte("recognized_at", `${periodEnd}T23:59:59`);
  if (!revenueRes.error) {
    recognizedRevenue = (revenueRes.data ?? []).reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
  }

  let cashReceived = 0;
  const paymentsRes = await supabase
    .from("payment")
    .select("amount, id")
    .eq("status", "posted")
    .gte("paid_at", `${periodMonth}T00:00:00`)
    .lte("paid_at", `${periodEnd}T23:59:59`);
  if (!paymentsRes.error) {
    cashReceived = (paymentsRes.data ?? []).reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
  }

  let cashAllocated = 0;
  const paymentIds = (paymentsRes.data ?? []).map((p) => p.id);
  if (paymentIds.length > 0) {
    const allocRes = await supabase
      .from("payment_allocation")
      .select("amount")
      .eq("status", "posted")
      .in("payment_id", paymentIds);
    if (!allocRes.error) {
      cashAllocated = (allocRes.data ?? []).reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
    }
  }

  let outstandingReceivables = 0;
  const receivablesRes = await supabase.from("charge_balance").select("outstanding_balance");
  if (!receivablesRes.error) {
    outstandingReceivables = (receivablesRes.data ?? []).reduce(
      (sum, row) => sum + Number(row.outstanding_balance ?? 0),
      0,
    );
  }

  let serviceObligation = 0;
  const { data: enrollments } = await supabase.from("enrollment").select("id");
  for (const enr of enrollments ?? []) {
    const { data: summary, error } = await supabase.rpc("get_enrollment_financial_summary", {
      p_enrollment_id: enr.id,
    });
    if (!error && summary && typeof summary === "object") {
      const s = summary as Record<string, unknown>;
      serviceObligation += Number(s.unrecognized_service_obligation ?? 0);
    }
  }

  let operatingCosts = 0;
  let marketingSalesCosts = 0;
  const expenseRes = await supabase
    .from("expense")
    .select("amount, cost_group_id")
    .eq("status", "posted")
    .gte("incurred_date", periodMonth)
    .lte("incurred_date", periodEnd);
  if (!expenseRes.error) {
    const costGroupIds = [...new Set((expenseRes.data ?? []).map((r) => r.cost_group_id))];
    const domainByGroup = new Map<string, string>();
    if (costGroupIds.length > 0) {
      const { data: groups } = await supabase
        .from("cost_group")
        .select("id, cost_domain_code")
        .in("id", costGroupIds);
      for (const g of groups ?? []) {
        domainByGroup.set(g.id, g.cost_domain_code);
      }
    }
    for (const row of expenseRes.data ?? []) {
      const domain = domainByGroup.get(row.cost_group_id);
      if (domain === "operating_overhead") operatingCosts += Number(row.amount);
      if (domain === "marketing_sales") marketingSalesCosts += Number(row.amount);
    }
  }

  let personnelCosts = 0;
  const personnelRes = await supabase
    .from("personnel_cost_entry")
    .select("amount")
    .eq("status", "posted")
    .eq("accounting_period", periodMonth);
  if (!personnelRes.error) {
    personnelCosts = (personnelRes.data ?? []).reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
  }

  let depreciation = 0;
  const depreciationRes = await supabase
    .from("depreciation_entry")
    .select("amount")
    .eq("status", "posted")
    .eq("period_month", periodMonth);
  if (!depreciationRes.error) {
    depreciation = (depreciationRes.data ?? []).reduce((sum, row) => sum + Number(row.amount ?? 0), 0);
  }

  let unallocatedSharedCosts = 0;
  const reconciliationRes = await supabase.rpc("get_organization_cost_reconciliation", {
    p_period_month: periodMonth,
  });
  if (!reconciliationRes.error && reconciliationRes.data) {
    unallocatedSharedCosts = Number(
      (reconciliationRes.data as Record<string, unknown>).unallocated_total ?? 0,
    );
  }

  return {
    metrics: {
      periodMonth,
      recognizedRevenue,
      cashReceived,
      cashAllocated,
      outstandingReceivables,
      serviceObligation,
      operatingCosts,
      personnelCosts,
      marketingSalesCosts,
      depreciation,
      unallocatedSharedCosts,
    },
    error: null,
  };
}
