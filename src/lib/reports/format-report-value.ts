import type { Locale } from "@/i18n/config";
import { formatDate, formatPercentage } from "@/lib/formatting";

export function formatReportPercentage(value: number | null, locale: Locale): string {
  if (value === null) return "—";
  return formatPercentage(value / 100, locale, value % 1 === 0 ? 0 : 1);
}

export function formatReportDate(value: string, locale: Locale): string {
  return formatDate(value, locale);
}

export function formatReportScore(
  rawScore: number | null,
  maxScore: number | null,
  locale: Locale,
): string {
  if (rawScore === null || maxScore === null) return "—";
  return `${rawScore} / ${maxScore}`;
}
