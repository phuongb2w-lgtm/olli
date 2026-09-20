import type { Locale } from "@/i18n/config";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { formatInteger, formatPercentage } from "@/lib/formatting";

/** Canonical 0–1 attendance/conversion rate display for M5 intelligence surfaces. */
export function formatReportingRate(rate: number | null, locale: Locale): string {
  if (rate === null) return "—";
  return formatPercentage(rate, locale, rate % 0.01 === 0 ? 0 : 1);
}

export function formatReportingCount(value: number | null, locale: Locale): string {
  if (value === null) return "—";
  return formatInteger(value, locale);
}

export function formatReportingMoney(value: number | null, locale: Locale): string {
  if (value === null) return "—";
  return formatFinanceMoney(value, locale);
}

export function formatReportingCountDelta(delta: number | null, locale: Locale): string | null {
  if (delta == null) return null;
  if (delta === 0) return "0";
  const formatted = formatInteger(Math.abs(delta), locale);
  return `${delta > 0 ? "+" : "−"}${formatted}`;
}

export function formatReportingRateDelta(delta: number | null, locale: Locale): string | null {
  if (delta == null) return null;
  if (delta === 0) return "0";
  const formatted = formatPercentage(Math.abs(delta), locale, 1);
  return `${delta > 0 ? "+" : "−"}${formatted}`;
}
