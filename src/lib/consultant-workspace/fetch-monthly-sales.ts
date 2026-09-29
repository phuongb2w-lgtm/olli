import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import {
  parseConsultantMonthlySalesRow,
  type ConsultantMonthlySalesSnapshot,
} from "@/lib/consultant-workspace/monthly-sales-read-model";

export async function fetchConsultantMonthlySales(
  supabase: SupabaseClient<Database>,
  periodMonth: string,
): Promise<{ data: ConsultantMonthlySalesSnapshot | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_consultant_monthly_sales", {
    p_period_month: periodMonth,
  });

  if (error) {
    return { data: null, error: error.message };
  }

  if (!data || typeof data !== "object") {
    return { data: null, error: "unavailable" };
  }

  return {
    data: parseConsultantMonthlySalesRow(data as Record<string, unknown>),
    error: null,
  };
}
