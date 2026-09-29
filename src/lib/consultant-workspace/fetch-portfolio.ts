import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import {
  parseConsultantWorkspacePortfolioResult,
  type ConsultantWorkspacePortfolioFilters,
  type ConsultantWorkspacePortfolioResult,
} from "@/lib/consultant-workspace/portfolio-read-model";

export type FetchPortfolioParams = {
  filters?: ConsultantWorkspacePortfolioFilters;
  sortField?: string;
  sortDirection?: "asc" | "desc";
  limit?: number;
  cursorWorkspaceSequence?: number | null;
  cursorPortfolioEntryId?: string | null;
  includeHidden?: boolean;
};

export async function fetchConsultantWorkspacePortfolio(
  supabase: SupabaseClient<Database>,
  params: FetchPortfolioParams = {},
): Promise<{ data: ConsultantWorkspacePortfolioResult | null; error: string | null }> {
  const filtersJson = params.filters ? { ...params.filters } : {};

  const { data, error } = await supabase.rpc("list_consultant_workspace_portfolio", {
    p_filters: filtersJson,
    p_sort_field: params.sortField ?? "workspace_sequence",
    p_sort_direction: params.sortDirection ?? "desc",
    p_limit: params.limit ?? 50,
    p_cursor_workspace_sequence: params.cursorWorkspaceSequence ?? undefined,
    p_cursor_portfolio_entry_id: params.cursorPortfolioEntryId ?? undefined,
    p_include_hidden: params.includeHidden ?? false,
  });

  if (error) {
    return { data: null, error: error.message };
  }

  return { data: parseConsultantWorkspacePortfolioResult(data), error: null };
}
