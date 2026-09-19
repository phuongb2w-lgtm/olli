import type { SupabaseClient } from "@supabase/supabase-js";
import {
  normalizePeriodMonth,
  periodMonthEnd,
} from "@/lib/finance/format-finance-value";
import type { LocalDateRange, ReportingPeriodBounds } from "@/lib/reporting/period-contract";

export type AcademicComparisonMetric = {
  current: number | null;
  previous: number | null;
  change: number | null;
};

export type AcademicTeachingDelivery = {
  materializedSessions: number;
  deliveredSessions: number;
  cancelledSessions: number;
  inProgressSessions: number;
  scheduledSessions: number;
  deliveryCompletionRatio: number | null;
  denominatorRule: string;
};

export type AcademicAttendanceMetrics = {
  confirmedPresent: number;
  confirmedAbsent: number;
  confirmedLate: number;
  confirmedExcused: number;
  unconfirmedCount: number;
  attendanceRate: number | null;
  denominatorRule: string;
};

export type AcademicAssessmentScale = {
  assessmentTypeCode: string;
  maxScore: number;
  resultCount: number;
  finalizedCount: number;
  averageRawScore: number | null;
  averagePercent: number | null;
};

export type AcademicAssessmentMetrics = {
  totalResults: number;
  finalizedResults: number;
  submittedResults: number;
  coverageRatio: number | null;
  scoreByScale: AcademicAssessmentScale[];
  denominatorRule: string;
};

export type AcademicObservationMetrics = {
  observationCount: number;
  confirmedObservations: number;
  coverageRatio: number | null;
  awaitingTranslation: number;
};

export type AcademicReviewBacklog = {
  attendancePending: number;
  scoresPending: number;
  commentsPending: number;
  translationPending: number;
  returnedAttendance: number;
  returnedScores: number;
  returnedComments: number;
};

export type AcademicQualityOverview = {
  period: ReportingPeriodBounds;
  comparisonPeriod: LocalDateRange | null;
  teachingDelivery: AcademicTeachingDelivery;
  attendance: {
    current: AcademicAttendanceMetrics;
    previous: AcademicAttendanceMetrics | null;
    rateChange: number | null;
  };
  assessment: AcademicAssessmentMetrics;
  observation: AcademicObservationMetrics;
  reviewBacklog: AcademicReviewBacklog;
};

export type AcademicException = {
  exceptionCode: string;
  reason: string;
  metricValue: number;
  entityType: string;
  entityId: string;
  drillDownPath: string;
  context: Record<string, unknown>;
};

export type AcademicReviewQueueItem = {
  queueType: string;
  recordId: string;
  entityType: string;
  drillDownPath: string;
  [key: string]: unknown;
};

function num(value: unknown): number {
  if (value === null || value === undefined) return 0;
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function numOrNull(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function parsePeriod(raw: Record<string, unknown>): ReportingPeriodBounds {
  return {
    startDate: String(raw.start_date),
    endDate: String(raw.end_date),
    timezone: String(raw.timezone),
    startAtUtc: String(raw.start_at_utc),
    endAtExclusive: String(raw.end_at_exclusive),
    organizationId: String(raw.organization_id ?? ""),
  };
}

function parseTeachingDelivery(raw: Record<string, unknown>): AcademicTeachingDelivery {
  return {
    materializedSessions: num(raw.materialized_sessions),
    deliveredSessions: num(raw.delivered_sessions),
    cancelledSessions: num(raw.cancelled_sessions),
    inProgressSessions: num(raw.in_progress_sessions),
    scheduledSessions: num(raw.scheduled_sessions),
    deliveryCompletionRatio: numOrNull(raw.delivery_completion_ratio),
    denominatorRule: String(raw.denominator_rule ?? ""),
  };
}

function parseAttendanceMetrics(raw: Record<string, unknown>): AcademicAttendanceMetrics {
  return {
    confirmedPresent: num(raw.confirmed_present),
    confirmedAbsent: num(raw.confirmed_absent),
    confirmedLate: num(raw.confirmed_late),
    confirmedExcused: num(raw.confirmed_excused),
    unconfirmedCount: num(raw.unconfirmed_count),
    attendanceRate: numOrNull(raw.attendance_rate),
    denominatorRule: String(raw.denominator_rule ?? ""),
  };
}

function parseAssessmentMetrics(raw: Record<string, unknown>): AcademicAssessmentMetrics {
  const scales = Array.isArray(raw.score_by_scale) ? raw.score_by_scale : [];
  return {
    totalResults: num(raw.total_results),
    finalizedResults: num(raw.finalized_results),
    submittedResults: num(raw.submitted_results),
    coverageRatio: numOrNull(raw.coverage_ratio),
    scoreByScale: scales.map((s) => {
      const row = s as Record<string, unknown>;
      return {
        assessmentTypeCode: String(row.assessment_type_code ?? ""),
        maxScore: num(row.max_score),
        resultCount: num(row.result_count),
        finalizedCount: num(row.finalized_count),
        averageRawScore: numOrNull(row.average_raw_score),
        averagePercent: numOrNull(row.average_percent),
      };
    }),
    denominatorRule: String(raw.denominator_rule ?? ""),
  };
}

function parseObservationMetrics(raw: Record<string, unknown>): AcademicObservationMetrics {
  return {
    observationCount: num(raw.observation_count),
    confirmedObservations: num(raw.confirmed_observations),
    coverageRatio: numOrNull(raw.coverage_ratio),
    awaitingTranslation: num(raw.awaiting_translation),
  };
}

function parseReviewBacklog(raw: Record<string, unknown>): AcademicReviewBacklog {
  return {
    attendancePending: num(raw.attendance_pending),
    scoresPending: num(raw.scores_pending),
    commentsPending: num(raw.comments_pending),
    translationPending: num(raw.translation_pending),
    returnedAttendance: num(raw.returned_attendance),
    returnedScores: num(raw.returned_scores),
    returnedComments: num(raw.returned_comments),
  };
}

function parseOverview(raw: Record<string, unknown>): AcademicQualityOverview {
  const attendanceBlock = raw.attendance as Record<string, unknown>;
  const comparisonRaw = raw.comparison_period as Record<string, unknown> | null;

  return {
    period: parsePeriod(raw.period as Record<string, unknown>),
    comparisonPeriod: comparisonRaw
      ? {
          startDate: String(comparisonRaw.start_date),
          endDate: String(comparisonRaw.end_date),
        }
      : null,
    teachingDelivery: parseTeachingDelivery(raw.teaching_delivery as Record<string, unknown>),
    attendance: {
      current: parseAttendanceMetrics(attendanceBlock.current as Record<string, unknown>),
      previous: attendanceBlock.previous
        ? parseAttendanceMetrics(attendanceBlock.previous as Record<string, unknown>)
        : null,
      rateChange: numOrNull(attendanceBlock.rate_change),
    },
    assessment: parseAssessmentMetrics(raw.assessment as Record<string, unknown>),
    observation: parseObservationMetrics(raw.observation as Record<string, unknown>),
    reviewBacklog: parseReviewBacklog(raw.review_backlog as Record<string, unknown>),
  };
}

export function resolveReportingPeriodFromInput(input: {
  startDate?: string;
  endDate?: string;
  periodMonth?: string;
}): LocalDateRange {
  if (input.startDate && input.endDate) {
    return { startDate: input.startDate, endDate: input.endDate };
  }
  const month = normalizePeriodMonth(input.periodMonth ?? new Date().toISOString().slice(0, 7));
  return { startDate: `${month}-01`, endDate: periodMonthEnd(month) };
}

export async function fetchAcademicQualityOverview(
  supabase: SupabaseClient,
  period: LocalDateRange,
  comparePrevious = true,
): Promise<{ data: AcademicQualityOverview | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_academic_quality_overview", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_compare_previous: comparePrevious,
  });

  if (error) return { data: null, error: error.message };
  if (!data || typeof data !== "object") return { data: null, error: "invalid_response" };

  return { data: parseOverview(data as Record<string, unknown>), error: null };
}

export async function fetchAcademicExceptions(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ exceptions: AcademicException[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_academic_exceptions", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });

  if (error) return { exceptions: [], error: error.message };

  const exceptions = (data ?? []).map((row: Record<string, unknown>) => ({
    exceptionCode: String(row.exception_code ?? ""),
    reason: String(row.reason ?? ""),
    metricValue: num(row.metric_value),
    entityType: String(row.entity_type ?? ""),
    entityId: String(row.entity_id ?? ""),
    drillDownPath: String(row.drill_down_path ?? ""),
    context: (row.context as Record<string, unknown>) ?? {},
  }));

  return { exceptions, error: null };
}

export async function fetchAcademicReviewQueue(
  supabase: SupabaseClient,
  queueType: string,
  limit = 50,
  offset = 0,
): Promise<{ items: AcademicReviewQueueItem[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_academic_review_queue", {
    p_queue_type: queueType,
    p_limit: limit,
    p_offset: offset,
  });

  if (error) return { items: [], error: error.message };

  const items = (data ?? []).map((row: Record<string, unknown>) => ({
    queueType: String(row.queue_type ?? queueType),
    recordId: String(row.record_id ?? ""),
    entityType: String(row.entity_type ?? ""),
    drillDownPath: String(row.drill_down_path ?? ""),
    ...Object.fromEntries(
      Object.entries(row).filter(
        ([k]) => !["queue_type", "record_id", "entity_type", "drill_down_path"].includes(k),
      ),
    ),
  }));

  return { items, error: null };
}

export async function fetchAcademicReviewBacklog(
  supabase: SupabaseClient,
): Promise<{ backlog: AcademicReviewBacklog | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_academic_review_backlog");

  if (error) return { backlog: null, error: error.message };
  if (!data || typeof data !== "object") return { backlog: null, error: "invalid_response" };

  return { backlog: parseReviewBacklog(data as Record<string, unknown>), error: null };
}
