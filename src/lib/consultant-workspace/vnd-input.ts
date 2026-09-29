/** Parse locale-formatted VND input to integer dong amount. */
export function parseVndInput(raw: string): number | null {
  const digits = raw.replace(/[^\d]/g, "");
  if (!digits) return null;
  const value = Number.parseInt(digits, 10);
  if (!Number.isFinite(value) || value <= 0) return null;
  return value;
}

export function formatVndInputValue(value: number, locale: string): string {
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(value);
}
