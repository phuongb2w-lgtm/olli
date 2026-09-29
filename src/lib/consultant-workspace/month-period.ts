import { normalizePeriodMonth, periodMonthEnd } from "@/lib/finance/format-finance-value";

const MONTH_QUERY = /^(\d{4})-(0[1-9]|1[0-2])$/;

/** Parse `?month=YYYY-MM` for consultant workspace; invalid values fall back to current local month. */
export function parseConsultantWorkspaceMonthParam(raw?: string | null): {
  periodMonth: string;
  queryMonth: string;
  usedFallback: boolean;
} {
  if (raw && MONTH_QUERY.test(raw)) {
    const periodMonth = `${raw}-01`;
    return { periodMonth, queryMonth: raw, usedFallback: false };
  }
  const periodMonth = normalizePeriodMonth();
  return { periodMonth, queryMonth: periodMonth.slice(0, 7), usedFallback: Boolean(raw) };
}

export function consultantWorkspaceMonthEnd(periodMonth: string): string {
  return periodMonthEnd(periodMonth);
}

export function shiftConsultantWorkspaceMonth(periodMonth: string, deltaMonths: number): string {
  const [y, m] = periodMonth.slice(0, 7).split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1 + deltaMonths, 1));
  const ny = dt.getUTCFullYear();
  const nm = String(dt.getUTCMonth() + 1).padStart(2, "0");
  return `${ny}-${nm}-01`;
}

export function formatConsultantMonthLabel(periodMonth: string, locale: string): string {
  const [y, m] = periodMonth.slice(0, 7).split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, 1));
  return new Intl.DateTimeFormat(locale, { month: "2-digit", year: "numeric" }).format(dt);
}
