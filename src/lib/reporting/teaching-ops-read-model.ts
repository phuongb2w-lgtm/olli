import type { SupabaseClient } from "@supabase/supabase-js";
import type { LocalDateRange, ReportingPeriodBounds } from "@/lib/reporting/period-contract";

export type TeachingOpsSessionMetrics = {
  kpi: string;
  materialized_sessions: number;
  scheduled_sessions: number;
  in_progress_sessions: number;
  delivered_sessions: number;
  cancelled_sessions: number;
  delivery_ratio: number | null;
  delivery_ratio_denominator_rule: string;
  projected_occurrences: number;
  projected_minutes: number;
  projected_rule: string;
};

export type TeachingOpsChangeBucket = {
  event_count: number;
  affected_session_count: number;
  sessions_with_multiple_events?: number;
};

export type TeachingOpsChangeMetrics = {
  kpi: string;
  event_timestamp_rule: string;
  reschedule: TeachingOpsChangeBucket;
  cancellation: TeachingOpsChangeBucket;
  teacher_substitution: TeachingOpsChangeBucket;
  room_change: TeachingOpsChangeBucket;
};

export type TeachingOpsComparison<T> = {
  current: T;
  previous: T | null;
};

export type TeachingOpsIntelligenceOverview = {
  period: ReportingPeriodBounds;
  comparisonPeriod: LocalDateRange | null;
  sessionMetrics: TeachingOpsComparison<TeachingOpsSessionMetrics>;
  changeMetrics: TeachingOpsComparison<TeachingOpsChangeMetrics>;
  workloadReadModel: string;
  roomUsageReadModel: string;
  utilizationPercentageRule: string;
};

export type TeachingOpsException = {
  exception_code: string;
  reason: string;
  entity_type: string;
  entity_id: string;
  metric_value: number;
  drill_down_path: string;
  context: Record<string, unknown>;
};

export type TeachingOpsOperationalChange = {
  change_id: string;
  change_type: string;
  occurred_at: string;
  reason: string | null;
  teaching_session_id: string;
  class_id: string;
  class_name: string;
  operational_date: string;
  drill_down_path: string;
};

export type MyTeachingOpsOverview = {
  period: { start_date: string; end_date: string; timezone: string };
  teacher_id: string;
  scope_rule: string;
  scheduled_sessions: number;
  projected_sessions: number;
  completed_sessions: number;
  delivered_minutes: number;
  scheduled_minutes: number;
  upcoming_sessions: number;
  cancelled_sessions: number;
  attribution_rule: string;
};

function mapSessionMetrics(raw: Record<string, unknown>): TeachingOpsSessionMetrics {
  return {
    kpi: String(raw.kpi ?? ""),
    materialized_sessions: Number(raw.materialized_sessions ?? 0),
    scheduled_sessions: Number(raw.scheduled_sessions ?? 0),
    in_progress_sessions: Number(raw.in_progress_sessions ?? 0),
    delivered_sessions: Number(raw.delivered_sessions ?? 0),
    cancelled_sessions: Number(raw.cancelled_sessions ?? 0),
    delivery_ratio:
      raw.delivery_ratio === null || raw.delivery_ratio === undefined
        ? null
        : Number(raw.delivery_ratio),
    delivery_ratio_denominator_rule: String(raw.delivery_ratio_denominator_rule ?? ""),
    projected_occurrences: Number(raw.projected_occurrences ?? 0),
    projected_minutes: Number(raw.projected_minutes ?? 0),
    projected_rule: String(raw.projected_rule ?? ""),
  };
}

function mapChangeBucket(raw: Record<string, unknown>): TeachingOpsChangeBucket {
  return {
    event_count: Number(raw.event_count ?? 0),
    affected_session_count: Number(raw.affected_session_count ?? 0),
    sessions_with_multiple_events:
      raw.sessions_with_multiple_events === undefined
        ? undefined
        : Number(raw.sessions_with_multiple_events ?? 0),
  };
}

function mapChangeMetrics(raw: Record<string, unknown>): TeachingOpsChangeMetrics {
  return {
    kpi: String(raw.kpi ?? ""),
    event_timestamp_rule: String(raw.event_timestamp_rule ?? ""),
    reschedule: mapChangeBucket((raw.reschedule as Record<string, unknown>) ?? {}),
    cancellation: mapChangeBucket((raw.cancellation as Record<string, unknown>) ?? {}),
    teacher_substitution: mapChangeBucket(
      (raw.teacher_substitution as Record<string, unknown>) ?? {},
    ),
    room_change: mapChangeBucket((raw.room_change as Record<string, unknown>) ?? {}),
  };
}

export function mapTeachingOpsIntelligenceOverviewRow(
  row: Record<string, unknown>,
): TeachingOpsIntelligenceOverview {
  const sessionBlock = row.sessionMetrics as Record<string, unknown>;
  const changeBlock = row.changeMetrics as Record<string, unknown>;
  const comparisonRaw = row.comparison_period as Record<string, unknown> | null;

  return {
    period: row.period as ReportingPeriodBounds,
    comparisonPeriod: comparisonRaw
      ? {
          startDate: String(comparisonRaw.start_date),
          endDate: String(comparisonRaw.end_date),
        }
      : null,
    sessionMetrics: {
      current: mapSessionMetrics((sessionBlock.current as Record<string, unknown>) ?? {}),
      previous: sessionBlock.previous
        ? mapSessionMetrics(sessionBlock.previous as Record<string, unknown>)
        : null,
    },
    changeMetrics: {
      current: mapChangeMetrics((changeBlock.current as Record<string, unknown>) ?? {}),
      previous: changeBlock.previous
        ? mapChangeMetrics(changeBlock.previous as Record<string, unknown>)
        : null,
    },
    workloadReadModel: String(row.workload_read_model ?? ""),
    roomUsageReadModel: String(row.room_usage_read_model ?? ""),
    utilizationPercentageRule: String(row.utilization_percentage_rule ?? ""),
  };
}

export async function fetchTeachingOpsIntelligenceOverview(
  supabase: SupabaseClient,
  period: LocalDateRange,
  comparePrevious: boolean,
): Promise<{ data: TeachingOpsIntelligenceOverview | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_teaching_ops_intelligence_overview", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_compare_previous: comparePrevious,
  });

  if (error) {
    return { data: null, error: error.message };
  }

  return {
    data: mapTeachingOpsIntelligenceOverviewRow(data as Record<string, unknown>),
    error: null,
  };
}

export async function fetchTeachingOpsSessionMetrics(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ data: TeachingOpsSessionMetrics | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_teaching_ops_session_metrics", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });
  if (error) return { data: null, error: error.message };
  return { data: mapSessionMetrics((data as Record<string, unknown>) ?? {}), error: null };
}

export async function fetchTeachingOpsChangeMetrics(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ data: TeachingOpsChangeMetrics | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_teaching_ops_change_metrics", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });
  if (error) return { data: null, error: error.message };
  return { data: mapChangeMetrics((data as Record<string, unknown>) ?? {}), error: null };
}

export async function fetchTeachingOpsExceptions(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ exceptions: TeachingOpsException[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_teaching_ops_exceptions", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });
  if (error) return { exceptions: [], error: error.message };
  const rows = (data ?? []) as Record<string, unknown>[];
  return {
    exceptions: rows.map((ex) => ({
      exception_code: String(ex.exception_code ?? ""),
      reason: String(ex.reason ?? ""),
      entity_type: String(ex.entity_type ?? ""),
      entity_id: String(ex.entity_id ?? ""),
      metric_value: Number(ex.metric_value ?? 0),
      drill_down_path: String(ex.drill_down_path ?? ""),
      context: (ex.context as Record<string, unknown>) ?? {},
    })),
    error: null,
  };
}

export async function fetchTeachingOpsOperationalChanges(
  supabase: SupabaseClient,
  period: LocalDateRange,
  limit = 50,
): Promise<{ changes: TeachingOpsOperationalChange[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_teaching_session_operational_changes", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_limit: limit,
    p_offset: 0,
  });
  if (error) return { changes: [], error: error.message };
  const rows = (data ?? []) as Record<string, unknown>[];
  return {
    changes: rows.map((c) => ({
      change_id: String(c.change_id ?? ""),
      change_type: String(c.change_type ?? ""),
      occurred_at: String(c.occurred_at ?? ""),
      reason: (c.reason as string | null) ?? null,
      teaching_session_id: String(c.teaching_session_id ?? ""),
      class_id: String(c.class_id ?? ""),
      class_name: String(c.class_name ?? ""),
      operational_date: String(c.operational_date ?? ""),
      drill_down_path: String(c.drill_down_path ?? ""),
    })),
    error: null,
  };
}

export async function fetchMyTeachingOpsOverview(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ data: MyTeachingOpsOverview | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_my_teaching_ops_overview", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });
  if (error) return { data: null, error: error.message };
  const row = data as Record<string, unknown>;
  return {
    data: {
      period: row.period as MyTeachingOpsOverview["period"],
      teacher_id: String(row.teacher_id ?? ""),
      scope_rule: String(row.scope_rule ?? ""),
      scheduled_sessions: Number(row.scheduled_sessions ?? 0),
      projected_sessions: Number(row.projected_sessions ?? 0),
      completed_sessions: Number(row.completed_sessions ?? 0),
      delivered_minutes: Number(row.delivered_minutes ?? 0),
      scheduled_minutes: Number(row.scheduled_minutes ?? 0),
      upcoming_sessions: Number(row.upcoming_sessions ?? 0),
      cancelled_sessions: Number(row.cancelled_sessions ?? 0),
      attribution_rule: String(row.attribution_rule ?? ""),
    },
    error: null,
  };
}

export function teachingOpsMetricDelta(
  current: number,
  previous: number | null | undefined,
): number | null {
  if (previous === null || previous === undefined) return null;
  return current - previous;
}
