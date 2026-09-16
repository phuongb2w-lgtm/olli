import type { Locale } from "@/i18n/config";
import { formatMoneyVnd, formatPercentage } from "@/lib/formatting";

export function formatFinanceMoney(value: number | null | undefined, locale: Locale): string {
  if (value == null) return "—";
  return formatMoneyVnd(value, locale);
}

export function formatFinanceMargin(value: number | null | undefined, locale: Locale): string {
  if (value == null) return "—";
  return formatPercentage(Number(value) / 100, locale, 1);
}

export function normalizePeriodMonth(value?: string): string {
  if (value && /^\d{4}-\d{2}(-\d{2})?$/.test(value)) {
    return `${value.slice(0, 7)}-01`;
  }
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  return `${y}-${m}-01`;
}

export function periodMonthEnd(periodMonth: string): string {
  const [y, m] = periodMonth.slice(0, 7).split("-").map(Number);
  const lastDay = new Date(y, m, 0).getDate();
  return `${y}-${String(m).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`;
}
