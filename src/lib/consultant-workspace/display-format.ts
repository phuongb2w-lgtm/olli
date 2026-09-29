import type { Locale } from "@/i18n/config";

/** Presentation-only; does not mutate stored canonical names. */
export function formatPortfolioNamePart(value: string | null, locale: Locale): string {
  if (!value) return "—";
  const trimmed = value.trim();
  if (!trimmed) return "—";
  if (locale === "vi") {
    return trimmed.toLocaleUpperCase("vi-VN");
  }
  return trimmed;
}

export function detailsHref(row: { portfolio_entry_id: string }, returnQuery?: string): string {
  const base = `/consultant/portfolio/${row.portfolio_entry_id}`;
  if (returnQuery) {
    return `${base}?return=${encodeURIComponent(returnQuery)}`;
  }
  return base;
}
