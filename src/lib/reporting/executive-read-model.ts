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

export type ExecutiveExceptionFollowUp = {
  id: string;
  status: "open" | "acknowledged" | "resolved" | "dismissed";
  latestNote: string | null;
  updatedAt: string;
};

export type ExecutiveExceptionRow = {
  exceptionKey: string;
  domain: ExecutiveAttentionItem["domain"];
  domainDrillDownPath: string;
  exceptionCode: string;
  reason: string | null;
  entityType: string;
  entityId: string;
  metricValue: number | null;
  drillDownPath: string | null;
  context: Record<string, unknown>;
  sourceCurrentlyDetected: boolean;
  followUp: ExecutiveExceptionFollowUp | null;
  reportingPeriod: LocalDateRange;
};

export type ExecutiveExceptionWorklistSummary = {
  currentDetectedCount: number;
  openFollowUpCount: number;
  acknowledgedFollowUpCount: number;
  worklistPath: string;
};

export type ExecutiveExceptionFollowUpHistoryEvent = {
  eventType: "created" | "status_changed" | "note_added";
  previousStatus: ExecutiveExceptionFollowUp["status"] | null;
  newStatus: ExecutiveExceptionFollowUp["status"] | null;
  note: string | null;
  actorId: string;
  createdAt: string;
};

export type ExecutiveOverview = {
  period: ReportingPeriodBounds;
  comparisonPeriod: LocalDateRange | null;
  finance: FinanceIntelligenceOverview;
  admissions: CrmAdmissionsOverview;
  quality: AcademicQualityOverview;
  operations: TeachingOpsIntelligenceOverview;
  attention: ExecutiveAttentionItem[];
  exceptionWorklist: ExecutiveExceptionWorklistSummary;
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
    exceptionWorklist: parseExceptionWorklistSummary(
      (raw.exception_worklist as Record<string, unknown>) ?? {},
    ),
    compositionRule: String(raw.composition_rule ?? ""),
  };
}

function parseExceptionWorklistSummary(
  raw: Record<string, unknown>,
): ExecutiveExceptionWorklistSummary {
  return {
    currentDetectedCount: Number(raw.current_detected_count ?? 0),
    openFollowUpCount: Number(raw.open_follow_up_count ?? 0),
    acknowledgedFollowUpCount: Number(raw.acknowledged_follow_up_count ?? 0),
    worklistPath: String(raw.worklist_path ?? "/executive/exceptions"),
  };
}

function parseExecutiveExceptionRow(raw: Record<string, unknown>): ExecutiveExceptionRow {
  const followRaw = raw.follow_up as Record<string, unknown> | null;
  const periodRaw = (raw.reporting_period as Record<string, unknown>) ?? {};

  return {
    exceptionKey: String(raw.exception_key ?? ""),
    domain: String(raw.domain ?? "") as ExecutiveExceptionRow["domain"],
    domainDrillDownPath: String(raw.domain_drill_down_path ?? ""),
    exceptionCode: String(raw.exception_code ?? ""),
    reason: raw.reason != null ? String(raw.reason) : null,
    entityType: String(raw.entity_type ?? ""),
    entityId: String(raw.entity_id ?? ""),
    metricValue: raw.metric_value != null ? Number(raw.metric_value) : null,
    drillDownPath: raw.drill_down_path != null ? String(raw.drill_down_path) : null,
    context: (raw.context as Record<string, unknown>) ?? {},
    sourceCurrentlyDetected: Boolean(raw.source_currently_detected),
    followUp: followRaw
      ? {
          id: String(followRaw.id ?? ""),
          status: String(followRaw.status ?? "open") as ExecutiveExceptionFollowUp["status"],
          latestNote:
            followRaw.latest_note != null ? String(followRaw.latest_note) : null,
          updatedAt: String(followRaw.updated_at ?? ""),
        }
      : null,
    reportingPeriod: {
      startDate: String(periodRaw.start_date ?? ""),
      endDate: String(periodRaw.end_date ?? ""),
    },
  };
}

function parseFollowUpHistoryEvent(
  raw: Record<string, unknown>,
): ExecutiveExceptionFollowUpHistoryEvent {
  return {
    eventType: String(raw.event_type ?? "") as ExecutiveExceptionFollowUpHistoryEvent["eventType"],
    previousStatus: raw.previous_status
      ? (String(raw.previous_status) as ExecutiveExceptionFollowUp["status"])
      : null,
    newStatus: raw.new_status
      ? (String(raw.new_status) as ExecutiveExceptionFollowUp["status"])
      : null,
    note: raw.note != null ? String(raw.note) : null,
    actorId: String(raw.actor_id ?? ""),
    createdAt: String(raw.created_at ?? ""),
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

export type ExecutiveExceptionListFilters = {
  domain?: ExecutiveExceptionRow["domain"];
  exceptionCode?: string;
  followUpStatus?: ExecutiveExceptionFollowUp["status"];
  search?: string;
  includeHistorical?: boolean;
};

export async function fetchExecutiveExceptions(
  supabase: SupabaseClient,
  period: LocalDateRange,
  filters: ExecutiveExceptionListFilters = {},
): Promise<{ rows: ExecutiveExceptionRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_executive_exceptions", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_domain: filters.domain ?? undefined,
    p_exception_code: filters.exceptionCode ?? undefined,
    p_follow_up_status: filters.followUpStatus ?? undefined,
    p_search: filters.search ?? undefined,
    p_include_historical: filters.includeHistorical ?? true,
  });

  if (error) {
    return { rows: [], error: error.message };
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return { rows: rows.map(parseExecutiveExceptionRow), error: null };
}

export async function fetchExecutiveExceptionFollowUpHistory(
  supabase: SupabaseClient,
  exceptionKey: string,
): Promise<{ events: ExecutiveExceptionFollowUpHistoryEvent[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_executive_exception_follow_up_history", {
    p_exception_key: exceptionKey,
  });

  if (error) {
    return { events: [], error: error.message };
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  return { events: rows.map(parseFollowUpHistoryEvent), error: null };
}
