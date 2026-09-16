import type { SupabaseClient } from "@supabase/supabase-js";
import { normalizePeriodMonth, periodMonthEnd } from "@/lib/finance/format-finance-value";

export type ExpenseListItem = {
  id: string;
  amount: number;
  incurredDate: string;
  status: string;
  domainCode: string;
  categoryCode: string;
  categoryName: string;
  classId: string | null;
  className: string | null;
  notes: string | null;
};

export async function queryExpensesByDomain(
  supabase: SupabaseClient,
  periodMonthInput?: string,
): Promise<{ items: ExpenseListItem[]; error: string | null }> {
  const periodMonth = normalizePeriodMonth(periodMonthInput);
  const periodEnd = periodMonthEnd(periodMonth);

  const { data, error } = await supabase
    .from("expense")
    .select(
      "id, amount, incurred_date, status, description, class_id, cost_group:cost_group_id(cost_domain_code), category:expense_category_id(code, display_name), class:class_id(name)",
    )
    .eq("status", "posted")
    .gte("incurred_date", periodMonth)
    .lte("incurred_date", periodEnd)
    .order("incurred_date", { ascending: false });

  if (error) return { items: [], error: "load_error" };

  const items = (data ?? []).map((row) => {
    const cg = row.cost_group as { cost_domain_code?: string } | null;
    const cat = row.category as { code?: string; display_name?: string } | null;
    const cls = row.class as { name?: string } | null;
    return {
      id: row.id,
      amount: Number(row.amount),
      incurredDate: row.incurred_date,
      status: row.status,
      domainCode: cg?.cost_domain_code ?? "",
      categoryCode: cat?.code ?? "",
      categoryName: cat?.display_name ?? "",
      classId: row.class_id,
      className: cls?.name ?? null,
      notes: row.description,
    };
  });

  return { items, error: null };
}
