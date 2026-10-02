import type { SupabaseClient } from "@supabase/supabase-js";
import {
  normalizePeriodMonth,
  periodMonthEnd,
} from "@/lib/finance/format-finance-value";
import type { LocalDateRange, ReportingPeriodBounds } from "@/lib/reporting/period-contract";

export type FinanceComparisonMetric = {
  current: number;
  previous: number | null;
  change: number | null;
};

export type FinanceIntelligenceOverview = {
  period: ReportingPeriodBounds;
  comparisonPeriod: LocalDateRange | null;
  cashCollected: FinanceComparisonMetric & {
    paymentCount: number;
    paymentCountPrevious: number | null;
    cashAllocated: number;
  };
  recognizedRevenue: FinanceComparisonMetric & {
    eventCount: number;
    eventCountPrevious: number | null;
  };
  receivables: {
    totalOutstanding: number;
    obligationCount: number;
    overdueAmount: number;
    overdueCount: number;
  };
  serviceObligation: number;
  costs: {
    operatingOverhead: number;
    marketingSales: number;
    personnel: number;
    depreciation: number;
    totalOperating: number;
    unallocatedShared: number;
    previous: {
      operatingOverhead: number;
      marketingSales: number;
      personnel: number;
      depreciation: number;
      totalOperating: number;
    } | null;
    change: {
      operatingOverhead: number;
      marketingSales: number;
      personnel: number;
      depreciation: number;
      totalOperating: number;
    } | null;
  };
  operatingResult: FinanceComparisonMetric;
  consultantDeclarations: {
    pendingAmount: number;
    pendingCount: number;
    returnedAmount: number;
    returnedCount: number;
    approvedAmount: number;
    approvedCount: number;
    approvedLinkedCount: number;
    approvedUnlinkedCount: number;
  } | null;
};

export type FinanceException = {
  exceptionCode: string;
  reason: string;
  metricValue: number;
  entityType: string;
  entityId: string;
  drillDownPath: string;
  context: Record<string, unknown>;
};

export type CashPaymentRow = {
  paymentId: string;
  paidAt: string;
  amount: number;
  methodCode: string;
  payerName: string | null;
  studentId: string | null;
  allocatedAmount: number;
  status: string;
};

export type RecognitionEventRow = {
  eventId: string;
  recognizedAt: string;
  amount: number;
  enrollmentId: string;
  classId: string | null;
  className: string | null;
  teachingSessionId: string | null;
  status: string;
};

export type ReceivableRow = {
  chargeId: string;
  enrollmentId: string | null;
  studentId: string | null;
  studentName: string | null;
  dueDate: string | null;
  outstandingBalance: number;
  collectionStatus: string;
};

export type ConsultantDeclarationRow = {
  declarationId: string;
  declarationDate: string;
  declaredAmount: number;
  status: string;
  consultantUserId: string;
  consultantName: string;
  approvedPaymentId: string | null;
  hasCanonicalPayment: boolean;
  description: string | null;
  declarationKind: string | null;
  workflowKind: string | null;
  enrollmentId: string | null;
  studentId: string | null;
};

export type ClassEconomicsSummaryRow = {
  classId: string;
  className: string;
  classStatus: string;
  recognizedRevenue: number;
  totalCost: number;
  contribution: number;
  marginPercentage: number | null;
  deliveredSessionCount: number;
  enrolledStudentCount: number;
};

export function resolveReportingPeriodFromInput(input?: {
  startDate?: string;
  endDate?: string;
  periodMonth?: string;
}): LocalDateRange {
  if (input?.startDate && input?.endDate) {
    return { startDate: input.startDate, endDate: input.endDate };
  }
  const periodMonth = normalizePeriodMonth(input?.periodMonth);
  return { startDate: periodMonth, endDate: periodMonthEnd(periodMonth) };
}

function num(value: unknown): number {
  return Number(value ?? 0);
}

export function parseFinanceIntelligenceOverviewRow(
  raw: Record<string, unknown>,
): FinanceIntelligenceOverview {
  const period = raw.period as Record<string, unknown>;
  const cash = raw.cash_collected as Record<string, unknown>;
  const revenue = raw.recognized_revenue as Record<string, unknown>;
  const receivables = raw.receivables as Record<string, unknown>;
  const costsWrap = raw.costs as Record<string, unknown>;
  const costsCurrent = costsWrap.current as Record<string, unknown>;
  const costsPrevious = costsWrap.previous as Record<string, unknown> | null;
  const costsChange = costsWrap.change as Record<string, unknown> | null;
  const operating = raw.operating_result as Record<string, unknown>;
  const comparison = raw.comparison_period as Record<string, unknown> | null;
  const decl = raw.consultant_declarations as Record<string, unknown> | null;

  return {
    period: {
      organizationId: String(period.organization_id),
      timezone: String(period.timezone),
      startDate: String(period.start_date),
      endDate: String(period.end_date),
      startAtUtc: String(period.start_at_utc),
      endAtExclusive: String(period.end_at_exclusive),
    },
    comparisonPeriod: comparison
      ? {
          startDate: String(comparison.start_date),
          endDate: String(comparison.end_date),
        }
      : null,
    cashCollected: {
      current: num(cash.current),
      previous: cash.previous != null ? num(cash.previous) : null,
      change: cash.change != null ? num(cash.change) : null,
      paymentCount: num(cash.payment_count),
      paymentCountPrevious:
        cash.payment_count_previous != null ? num(cash.payment_count_previous) : null,
      cashAllocated: num(cash.cash_allocated),
    },
    recognizedRevenue: {
      current: num(revenue.current),
      previous: revenue.previous != null ? num(revenue.previous) : null,
      change: revenue.change != null ? num(revenue.change) : null,
      eventCount: num(revenue.event_count),
      eventCountPrevious:
        revenue.event_count_previous != null ? num(revenue.event_count_previous) : null,
    },
    receivables: {
      totalOutstanding: num(receivables.total_outstanding),
      obligationCount: num(receivables.obligation_count),
      overdueAmount: num(receivables.overdue_amount),
      overdueCount: num(receivables.overdue_count),
    },
    serviceObligation: num(raw.service_obligation),
    costs: {
      operatingOverhead: num(costsCurrent.operating_overhead),
      marketingSales: num(costsCurrent.marketing_sales),
      personnel: num(costsCurrent.personnel),
      depreciation: num(costsCurrent.depreciation),
      totalOperating: num(costsCurrent.total_operating),
      unallocatedShared: num(costsWrap.unallocated_shared),
      previous: costsPrevious
        ? {
            operatingOverhead: num(costsPrevious.operating_overhead),
            marketingSales: num(costsPrevious.marketing_sales),
            personnel: num(costsPrevious.personnel),
            depreciation: num(costsPrevious.depreciation),
            totalOperating: num(costsPrevious.total_operating),
          }
        : null,
      change: costsChange
        ? {
            operatingOverhead: num(costsChange.operating_overhead),
            marketingSales: num(costsChange.marketing_sales),
            personnel: num(costsChange.personnel),
            depreciation: num(costsChange.depreciation),
            totalOperating: num(costsChange.total_operating),
          }
        : null,
    },
    operatingResult: {
      current: num(operating.current),
      previous: operating.previous != null ? num(operating.previous) : null,
      change: operating.change != null ? num(operating.change) : null,
    },
    consultantDeclarations: decl
      ? {
          pendingAmount: num(decl.pending_amount),
          pendingCount: num(decl.pending_count),
          returnedAmount: num(decl.returned_amount),
          returnedCount: num(decl.returned_count),
          approvedAmount: num(decl.approved_amount),
          approvedCount: num(decl.approved_count),
          approvedLinkedCount: num(decl.approved_linked_count),
          approvedUnlinkedCount: num(decl.approved_unlinked_count),
        }
      : null,
  };
}

export async function fetchFinanceIntelligenceOverview(
  supabase: SupabaseClient,
  period: LocalDateRange,
  comparePrevious = true,
): Promise<{ overview: FinanceIntelligenceOverview | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_finance_intelligence_overview", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_compare_previous: comparePrevious,
  });

  if (error) {
    return { overview: null, error: error.message };
  }

  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row) {
    return { overview: null, error: "empty_overview" };
  }

  return { overview: parseFinanceIntelligenceOverviewRow(row), error: null };
}

export async function fetchFinanceExceptions(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ exceptions: FinanceException[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_finance_exceptions", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });

  if (error) {
    return { exceptions: [], error: error.message };
  }

  const exceptions = (data ?? []).map((row: Record<string, unknown>) => ({
    exceptionCode: String(row.exception_code),
    reason: String(row.reason),
    metricValue: num(row.metric_value),
    entityType: String(row.entity_type),
    entityId: String(row.entity_id),
    drillDownPath: String(row.drill_down_path),
    context: (row.context as Record<string, unknown>) ?? {},
  }));

  return { exceptions, error: null };
}

function parseJsonRow<T>(row: unknown, map: (r: Record<string, unknown>) => T): T {
  return map(row as Record<string, unknown>);
}

export async function fetchCashPayments(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ rows: CashPaymentRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_finance_cash_payments", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_limit: 200,
    p_offset: 0,
  });
  if (error) return { rows: [], error: error.message };
  const rows = (data ?? []).map((row: unknown) =>
    parseJsonRow(row, (r) => ({
      paymentId: String(r.payment_id),
      paidAt: String(r.paid_at),
      amount: num(r.amount),
      methodCode: String(r.method_code),
      payerName: r.payer_name != null ? String(r.payer_name) : null,
      studentId: r.student_id != null ? String(r.student_id) : null,
      allocatedAmount: num(r.allocated_amount),
      status: String(r.status),
    })),
  );
  return { rows, error: null };
}

export async function fetchRecognitionEvents(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ rows: RecognitionEventRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_finance_recognition_events", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_limit: 200,
    p_offset: 0,
  });
  if (error) return { rows: [], error: error.message };
  const rows = (data ?? []).map((row: unknown) =>
    parseJsonRow(row, (r) => ({
      eventId: String(r.event_id),
      recognizedAt: String(r.recognized_at),
      amount: num(r.amount),
      enrollmentId: String(r.enrollment_id),
      classId: r.class_id != null ? String(r.class_id) : null,
      className: r.class_name != null ? String(r.class_name) : null,
      teachingSessionId:
        r.teaching_session_id != null ? String(r.teaching_session_id) : null,
      status: String(r.status),
    })),
  );
  return { rows, error: null };
}

export async function fetchReceivables(
  supabase: SupabaseClient,
): Promise<{ rows: ReceivableRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_finance_receivables", {
    p_limit: 200,
    p_offset: 0,
  });
  if (error) return { rows: [], error: error.message };
  const rows = (data ?? []).map((row: unknown) =>
    parseJsonRow(row, (r) => ({
      chargeId: String(r.charge_id),
      enrollmentId: r.enrollment_id != null ? String(r.enrollment_id) : null,
      studentId: r.student_id != null ? String(r.student_id) : null,
      studentName: r.student_name != null ? String(r.student_name) : null,
      dueDate: r.due_date != null ? String(r.due_date) : null,
      outstandingBalance: num(r.outstanding_balance),
      collectionStatus: String(r.collection_status),
    })),
  );
  return { rows, error: null };
}

export type FinanceStudentAccountRow = {
  id: string;
  familyName: string;
  givenName: string;
  studentCode: string | null;
  studentStatus: string;
  totalCharged: number;
  totalPaid: number;
  outstandingBalance: number;
};

export async function fetchFinanceStudentAccounts(
  supabase: SupabaseClient,
): Promise<{ rows: FinanceStudentAccountRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_finance_student_accounts", {
    p_limit: 500,
    p_offset: 0,
  });
  if (error) return { rows: [], error: error.message };
  const rows = (data ?? []).map((row: unknown) =>
    parseJsonRow(row, (r) => ({
      id: String(r.student_id),
      familyName: String(r.family_name ?? ""),
      givenName: String(r.given_name ?? ""),
      studentCode: r.student_code != null ? String(r.student_code) : null,
      studentStatus: String(r.student_status ?? ""),
      totalCharged: num(r.total_charged),
      totalPaid: num(r.total_paid),
      outstandingBalance: num(r.outstanding_balance),
    })),
  );
  return { rows, error: null };
}

export async function fetchConsultantDeclarations(
  supabase: SupabaseClient,
  period: LocalDateRange,
  status?: string,
): Promise<{ rows: ConsultantDeclarationRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_finance_consultant_declarations", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
    p_status: status ?? null,
    p_limit: 200,
    p_offset: 0,
  });
  if (error) return { rows: [], error: error.message };
  const rows = (data ?? []).map((row: unknown) =>
    parseJsonRow(row, (r) => ({
      declarationId: String(r.declaration_id),
      declarationDate: String(r.declaration_date),
      declaredAmount: num(r.declared_amount),
      status: String(r.status),
      consultantUserId: String(r.consultant_user_id),
      consultantName: String(r.consultant_name),
      approvedPaymentId:
        r.approved_payment_id != null ? String(r.approved_payment_id) : null,
      hasCanonicalPayment: Boolean(r.has_canonical_payment),
      description: r.description != null ? String(r.description) : null,
      declarationKind: r.declaration_kind != null ? String(r.declaration_kind) : null,
      workflowKind: r.workflow_kind != null ? String(r.workflow_kind) : null,
      enrollmentId: r.enrollment_id != null ? String(r.enrollment_id) : null,
      studentId: r.student_id != null ? String(r.student_id) : null,
    })),
  );
  return { rows, error: null };
}

export async function fetchClassEconomicsSummary(
  supabase: SupabaseClient,
  period: LocalDateRange,
): Promise<{ rows: ClassEconomicsSummaryRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc("list_finance_class_economics_summary", {
    p_start_date: period.startDate,
    p_end_date: period.endDate,
  });
  if (error) return { rows: [], error: error.message };
  const rows = (data ?? []).map((row: unknown) =>
    parseJsonRow(row, (r) => ({
      classId: String(r.class_id),
      className: String(r.class_name),
      classStatus: String(r.class_status),
      recognizedRevenue: num(r.recognized_revenue),
      totalCost: num(r.total_cost),
      contribution: num(r.contribution),
      marginPercentage: r.margin_percentage != null ? num(r.margin_percentage) : null,
      deliveredSessionCount: num(r.delivered_session_count),
      enrolledStudentCount: num(r.enrolled_student_count),
    })),
  );
  return { rows, error: null };
}
