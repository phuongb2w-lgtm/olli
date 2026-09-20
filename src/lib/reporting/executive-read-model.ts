import type { SupabaseClient } from "@supabase/supabase-js";
import type { AcademicQualityOverview } from "@/lib/reporting/academic-read-model";
import { parseAcademicQualityOverviewRow } from "@/lib/reporting/academic-read-model";
import type { CrmAdmissionsOverview } from "@/lib/reporting/crm-admissions-read-model";
import type { FinanceIntelligenceOverview } from "@/lib/reporting/finance-read-model";
import { parseFinanceIntelligenceOverviewRow } from "@/lib/reporting/finance-read-model";
import type { LocalDateRange, ReportingPeriodBounds } from "@/lib/reporting/period-contract";
import type { TeachingOpsIntelligenceOverview } from "@/lib/reporting/teaching-ops-read-model";
import { mapTeachingOpsIntelligenceOverviewRow } from "@/lib/reporting/teaching-ops-read-model";

export type ExecutiveAttentionItem = {
  domain: "finance" | "admissions" | "quality" | "operations";
  domainDrillDownPath: string;
  exceptionCode: string;
  reason: string;
  entityType: string;
  entityId: string;
  metricValue: number;
  drillDownPath: string;
  context: Record<string, unknown>;
};

export type ExecutiveOverview = {
  period: ReportingPeriodBounds;
  comparisonPeriod: LocalDateRange | null;
  finance: FinanceIntelligenceOverview;
  admissions: CrmAdmissionsOverview;
  quality: AcademicQualityOverview;
  operations: TeachingOpsIntelligenceOverview;
  attention: ExecutiveAttentionItem[];
  compositionRule: string;
};

function parsePeriod(raw: Record<string, unknown>): ReportingPeriodBounds {
  return {
    organizationId: String(raw.organization_id ?? ""),
    timezone: String(raw.timezone ?? ""),
    startDate: String(raw.start_date ?? ""),
    endDate: String(raw.end_date ?? ""),
    startAtUtc: String(raw.start_at_utc ?? ""),
    endAtExclusive: String(raw.end_at_exclusive ?? ""),
  };
}

function parseAttentionItem(raw: Record<string, unknown>): ExecutiveAttentionItem {
  return {
    domain: String(raw.domain ?? "") as ExecutiveAttentionItem["domain"],
    domainDrillDownPath: String(raw.domain_drill_down_path ?? ""),
    exceptionCode: String(raw.exception_code ?? ""),
    reason: String(raw.reason ?? ""),
    entityType: String(raw.entity_type ?? ""),
    entityId: String(raw.entity_id ?? ""),
    metricValue: Number(raw.metric_value ?? 0),
    drillDownPath: String(raw.drill_down_path ?? ""),
    context: (raw.context as Record<string, unknown>) ?? {},
  };
}

export function parseExecutiveOverviewRow(raw: Record<string, unknown>): ExecutiveOverview {
  const comparisonRaw = raw.comparison_period as Record<string, unknown> | null;
  const attentionRaw = Array.isArray(raw.attention) ? raw.attention : [];

  return {
    period: parsePeriod((raw.period as Record<string, unknown>) ?? {}),
    comparisonPeriod: comparisonRaw
      ? {
          startDate: String(comparisonRaw.start_date),
          endDate: String(comparisonRaw.end_date),
        }
      : null,
    finance: parseFinanceIntelligenceOverviewRow(
      (raw.finance as Record<string, unknown>) ?? {},
    ),
    admissions: (raw.admissions ?? {}) as CrmAdmissionsOverview,
    quality: parseAcademicQualityOverviewRow((raw.quality as Record<string, unknown>) ?? {}),
    operations: mapTeachingOpsIntelligenceOverviewRow(
      (raw.operations as Record<string, unknown>) ?? {},
    ),
    attention: attentionRaw.map((item) =>
      parseAttentionItem(item as Record<string, unknown>),
    ),
    compositionRule: String(raw.composition_rule ?? ""),
  };
}

export async function fetchExecutiveOverview(
  supabase: SupabaseClient,
  period: LocalDateRange,
  comparePrevious = true,
): Promise<{ data: ExecutiveOverview | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_executive_overview", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_compare_previous: comparePrevious,
  });

  if (error) {
    return { data: null, error: error.message };
  }

  if (!data || typeof data !== "object") {
    return { data: null, error: "invalid_response" };
  }

  return { data: parseExecutiveOverviewRow(data as Record<string, unknown>), error: null };
}

export async function fetchExecutiveAttentionItems(
  supabase: SupabaseClient,
  period: LocalDateRange,
  limitPerDomain = 5,
): Promise<{ items: ExecutiveAttentionItem[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_executive_attention_items", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_limit_per_domain: limitPerDomain,
  });

  if (error) {
    return { items: [], error: error.message };
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return { items: rows.map(parseAttentionItem), error: null };
}
