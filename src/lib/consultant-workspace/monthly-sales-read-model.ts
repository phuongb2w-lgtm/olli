export type ConsultantMonthlySalesComparisonKind =
  | "increase"
  | "decrease"
  | "neutral"
  | "new";

export type ConsultantMonthlySalesSnapshot = {
  periodMonth: string;
  monthEnd: string;
  timezone: string;
  salesAmount: number;
  paymentCount: number;
  currencyCode: string;
  isCurrentMonth: boolean;
  canGoNext: boolean;
  canGoPrevious: boolean;
  previousSalesAmount: number;
  previousPaymentCount: number;
  comparisonDelta: number;
  comparisonPercent: number | null;
  comparisonKind: ConsultantMonthlySalesComparisonKind;
};

function num(value: unknown): number {
  return Number(value ?? 0);
}

export function parseConsultantMonthlySalesRow(raw: Record<string, unknown>): ConsultantMonthlySalesSnapshot {
  const period = (raw.period as Record<string, unknown>) ?? {};
  const previous = (raw.previous_period as Record<string, unknown>) ?? {};
  const comparison = (raw.comparison as Record<string, unknown>) ?? {};
  const navigation = (raw.navigation as Record<string, unknown>) ?? {};
  const monthStart = String(period.month_start ?? period.start_date ?? "");
  const periodMonth =
    monthStart.length >= 7 ? `${monthStart.slice(0, 7)}-01` : monthStart;

  return {
    periodMonth,
    monthEnd: String(period.month_end ?? period.end_date ?? ""),
    timezone: String(period.timezone ?? "UTC"),
    salesAmount: num(raw.sales_amount),
    paymentCount: num(raw.payment_count),
    currencyCode: String(raw.currency_code ?? "VND"),
    isCurrentMonth: Boolean(navigation.is_current_month),
    canGoNext: Boolean(navigation.can_go_next),
    canGoPrevious: navigation.can_go_previous !== false,
    previousSalesAmount: num(previous.sales_amount),
    previousPaymentCount: num(previous.payment_count),
    comparisonDelta: num(comparison.delta_amount),
    comparisonPercent:
      comparison.percent == null || comparison.percent === ""
        ? null
        : Number(comparison.percent),
    comparisonKind: (comparison.kind as ConsultantMonthlySalesComparisonKind) ?? "neutral",
  };
}

/** Normalize period month from RPC (always YYYY-MM-01). */
export function normalizeMonthlySalesPeriodMonth(monthStart: string): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(monthStart)) {
    return `${monthStart.slice(0, 7)}-01`;
  }
  return monthStart;
}
