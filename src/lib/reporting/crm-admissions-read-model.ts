import type { SupabaseClient } from "@supabase/supabase-js";
import type { LocalDateRange, ReportingPeriodBounds } from "@/lib/reporting/period-contract";

export type CrmLeadIntakeMetrics = {
  kpi: string;
  metric_type: string;
  leads_created: number;
  unassigned_count: number;
  denominator_rule: string;
  event_timestamp: string;
};

export type CrmActivityMetrics = {
  kpi: string;
  activities_recorded: number;
  pending_follow_ups: number;
  overdue_follow_ups: number;
  activity_event_timestamp: string;
  overdue_rule: string;
};

export type CrmTrialMetrics = {
  kpi: string;
  trials_scheduled: number;
  trials_completed: number;
  scheduled_event_timestamp: string;
  completed_event_timestamp: string;
  denominator_rule: string;
};

export type CrmConversionMetrics = {
  kpi: string;
  conversions_in_period: number;
  period_event_timestamp: string;
  period_event_denominator_rule: string;
  cohort_leads_created: number;
  cohort_conversions: number;
  cohort_conversion_rate: number | null;
  cohort_denominator_rule: string;
  enrollments_linked: number;
  conversions_without_enrollment: number;
};

export type CrmConsultantProductivityRow = {
  consultant_user_id: string;
  display_name: string;
  current_leads_owned: number;
  cohort_leads: number;
  activities_recorded: number;
  trials_scheduled: number;
  conversions_in_period: number;
  cohort_converted_leads: number;
  cohort_conversion_rate: number | null;
  approved_declarations_amount: number;
  pending_declarations_amount: number;
};

export type CrmConsultantProductivityPayload = {
  cohort_attribution_rule: string;
  cohort_conversion_time_rule: string;
  rows: CrmConsultantProductivityRow[];
};

export type CrmSourceMetricRow = {
  source_name: string;
  source_id: string | null;
  leads_created: number;
  conversions_in_period: number;
  cohort_converted_leads: number;
  cohort_conversion_rate: number | null;
};

export type CrmAdmissionsOverview = {
  period: ReportingPeriodBounds;
  comparisonPeriod: LocalDateRange | null;
  leadIntake: CrmLeadIntakeMetrics;
  activity: CrmActivityMetrics;
  trials: CrmTrialMetrics;
  conversions: CrmConversionMetrics;
  consultantProductivity: CrmConsultantProductivityPayload;
  sources: CrmSourceMetricRow[];
  pipelineSnapshot: { metric_type: string; as_of: string; by_status: Record<string, number> };
  declarations: Record<string, unknown>;
};

export type ConsultantPersonalDeclarations = {
  pending_amount: number;
  pending_count: number;
  returned_amount: number;
  returned_count: number;
  approved_amount: number;
  approved_count: number;
  approved_linked_count: number;
  semantic_note: string;
};

export type ConsultantCrmOverview = {
  period: { start_date: string; end_date: string; timezone: string };
  consultant_user_id: string;
  cohort_attribution_rule: string;
  cohort_conversion_time_rule: string;
  current_leads_owned: number;
  cohort_leads: number;
  leads_created_by_me: number;
  activities_in_period: number;
  trials_scheduled_in_period: number;
  conversions_in_period: number;
  cohort_converted_leads: number;
  cohort_conversion_rate: number | null;
  declarations: ConsultantPersonalDeclarations;
};

export function parseConsultantProductivityRows(
  payload: CrmConsultantProductivityPayload | CrmConsultantProductivityRow[] | null | undefined,
): CrmConsultantProductivityRow[] {
  if (!payload) return [];
  if (Array.isArray(payload)) return payload;
  return payload.rows ?? [];
}

export type CrmAdmissionsException = {
  exception_code: string;
  reason: string;
  entity_type: string;
  entity_id: string;
  metric_value: number;
  drill_down_path: string;
  context: Record<string, unknown>;
};

export type ConsultantWorkQueueItem = {
  queue_type: string;
  lead_id?: string;
  due_at?: string;
  note?: string;
  status?: string;
  drill_down_path: string;
};

export async function fetchCrmAdmissionsOverview(
  supabase: SupabaseClient,
  period: LocalDateRange,
  comparePrevious = true,
): Promise<{ data: CrmAdmissionsOverview | null; error: Error | null }> {
  const { data, error } = await supabase.rpc("get_crm_admissions_overview", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_compare_previous: comparePrevious,
  });

  if (error) {
    return { data: null, error: new Error(error.message) };
  }

  return { data: data as CrmAdmissionsOverview, error: null };
}

export async function fetchCrmAdmissionsExceptions(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ exceptions: CrmAdmissionsException[]; error: Error | null }> {
  const { data, error } = await supabase.rpc("list_crm_admissions_exceptions", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });

  if (error) {
    return { exceptions: [], error: new Error(error.message) };
  }

  return { exceptions: (data ?? []) as CrmAdmissionsException[], error: null };
}

export async function fetchConsultantCrmOverview(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ data: ConsultantCrmOverview | null; error: Error | null }> {
  const { data, error } = await supabase.rpc("get_consultant_crm_overview", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });

  if (error) {
    return { data: null, error: new Error(error.message) };
  }

  return { data: data as ConsultantCrmOverview, error: null };
}

export async function fetchConsultantWorkQueue(
  supabase: SupabaseClient,
  limit = 20,
): Promise<{ items: ConsultantWorkQueueItem[]; error: Error | null }> {
  const { data, error } = await supabase.rpc("list_consultant_work_queue", {
    p_limit: limit,
  });

  if (error) {
    return { items: [], error: new Error(error.message) };
  }

  return { items: (data ?? []) as ConsultantWorkQueueItem[], error: null };
}
