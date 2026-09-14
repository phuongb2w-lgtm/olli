import type { Locale } from "@/i18n/config";

export function formatDate(value: Date | string, locale: Locale): string {
  const date = typeof value === "string" ? new Date(value) : value;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(date);
}

export function formatDateTime(value: Date | string, locale: Locale): string {
  const date = typeof value === "string" ? new Date(value) : value;
  return new Intl.DateTimeFormat(locale, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

export function formatInteger(value: number, locale: Locale): string {
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(value);
}

/** VND is stored as numeric in DB; presentation uses locale-aware grouping with zero decimal places. */
export function formatMoneyVnd(value: number, locale: Locale): string {
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: "VND",
    maximumFractionDigits: 0,
  }).format(value);
}

/** Reserved for future modules (e.g. completion rates). Use this helper — do not invent local formatters. */
export function formatPercentage(value: number, locale: Locale, fractionDigits = 1): string {
  return new Intl.NumberFormat(locale, {
    style: "percent",
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(value);
}
