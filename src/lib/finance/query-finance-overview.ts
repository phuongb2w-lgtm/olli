import type { SupabaseClient } from "@supabase/supabase-js";
import {
  fetchFinanceIntelligenceOverview,
  resolveReportingPeriodFromInput,
  type FinanceIntelligenceOverview,
} from "@/lib/reporting/finance-read-model";

/** @deprecated Use FinanceIntelligenceOverview from finance-read-model. */
export type FinanceOverviewMetrics = {
  periodMonth: string;
  startDate: string;
  endDate: string;
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
  operatingResult: number;
  overview: FinanceIntelligenceOverview;
};

export async function queryFinanceOverview(
  supabase: SupabaseClient,
  periodInput?: {
    periodMonth?: string;
    startDate?: string;
    endDate?: string;
    comparePrevious?: boolean;
  },
): Promise<{ metrics: FinanceOverviewMetrics | null; error: string | null }> {
  const period = resolveReportingPeriodFromInput(periodInput);
  const { overview, error } = await fetchFinanceIntelligenceOverview(
    supabase,
    period,
    periodInput?.comparePrevious ?? true,
  );

  if (error || !overview) {
    return { metrics: null, error: error ?? "load_failed" };
  }

  return {
    metrics: {
      periodMonth: period.startDate.slice(0, 7) + "-01",
      startDate: period.startDate,
      endDate: period.endDate,
      recognizedRevenue: overview.recognizedRevenue.current,
      cashReceived: overview.cashCollected.current,
      cashAllocated: overview.cashCollected.cashAllocated,
      outstandingReceivables: overview.receivables.totalOutstanding,
      serviceObligation: overview.serviceObligation,
      operatingCosts: overview.costs.operatingOverhead,
      personnelCosts: overview.costs.personnel,
      marketingSalesCosts: overview.costs.marketingSales,
      depreciation: overview.costs.depreciation,
      unallocatedSharedCosts: overview.costs.unallocatedShared,
      operatingResult: overview.operatingResult.current,
      overview,
    },
    error: null,
  };
}
