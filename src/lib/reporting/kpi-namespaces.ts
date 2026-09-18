/**
 * Stable KPI namespace contracts for M5 reporting read models.
 * Implementations arrive in M5-T02..T07; names must not drift.
 */

export const FINANCE_KPIS = {
  cashCollected: "finance.cash_collected",
  recognizedRevenue: "finance.recognized_revenue",
  receivables: "finance.receivables",
  operatingCosts: "finance.operating_costs",
  costADepreciation: "finance.cost_a_depreciation",
  personnelCosts: "finance.personnel_costs",
  marketingSalesCosts: "finance.marketing_sales_costs",
  classContribution: "finance.class_contribution",
  pendingConsultantDeclarations: "finance.pending_consultant_declarations",
  /** Accountant-validated declarations — NOT cash collected or recognized revenue. */
  approvedConsultantDeclarations: "finance.approved_consultant_declarations",
} as const;

export const CRM_KPIS = {
  leadIntake: "crm.lead_intake",
  followUpActivity: "crm.follow_up_activity",
  trials: "crm.trials",
  conversions: "crm.conversions",
  personalDeclaredRevenue: "crm.personal_declared_revenue",
  /** Approved declaration count/amount — not booked revenue. */
  personalApprovedDeclaration: "crm.personal_approved_declaration",
  pipelineWorkload: "crm.pipeline_workload",
  consultantProductivity: "crm.consultant_productivity",
} as const;

export const ACADEMIC_KPIS = {
  attendanceRate: "academic.attendance_rate",
  absenceCount: "academic.absence_count",
  assessmentScores: "academic.assessment_scores",
  testingOutcomes: "academic.testing_outcomes",
  observations: "academic.observations",
  learningProgress: "academic.learning_progress",
  serviceFulfillment: "academic.service_fulfillment",
} as const;

export const TEACHING_OPS_KPIS = {
  /** Projected schedule occurrence — not materialized. */
  projectedOccurrences: "teaching_ops.projected_occurrences",
  /** Concrete teaching_session row (non-cancelled). Includes scheduled/in_progress — not delivered. */
  materializedSessions: "teaching_ops.materialized_sessions",
  /**
   * Reserved: requires teaching_session.status = completed.
   * Do not implement until read model uses canonical delivered evidence.
   */
  deliveredSessions: "teaching_ops.delivered_sessions",
  cancelledSessions: "teaching_ops.cancelled_sessions",
  rescheduledSessions: "teaching_ops.rescheduled_sessions",
  teacherWorkload: "teaching_ops.teacher_workload",
  roomUsage: "teaching_ops.room_usage",
  operationalExceptions: "teaching_ops.operational_exceptions",
} as const;

export const MANAGEMENT_KPIS = {
  executiveOverview: "management.executive_overview",
  crossDomainExceptions: "management.cross_domain_exceptions",
  departmentalProductivity: "management.departmental_productivity",
} as const;

export type FinanceKpi = (typeof FINANCE_KPIS)[keyof typeof FINANCE_KPIS];
export type CrmKpi = (typeof CRM_KPIS)[keyof typeof CRM_KPIS];
export type AcademicKpi = (typeof ACADEMIC_KPIS)[keyof typeof ACADEMIC_KPIS];
export type TeachingOpsKpi = (typeof TEACHING_OPS_KPIS)[keyof typeof TEACHING_OPS_KPIS];
export type ManagementKpi = (typeof MANAGEMENT_KPIS)[keyof typeof MANAGEMENT_KPIS];

/** KPIs requiring report.executive.read for center-wide (non-personal) aggregation. */
export const EXECUTIVE_ONLY_KPIS: ReadonlySet<string> = new Set([
  MANAGEMENT_KPIS.executiveOverview,
  MANAGEMENT_KPIS.crossDomainExceptions,
  MANAGEMENT_KPIS.departmentalProductivity,
  FINANCE_KPIS.classContribution,
  CRM_KPIS.consultantProductivity,
  TEACHING_OPS_KPIS.teacherWorkload,
]);
