/** Strip non-digits for phone comparison/search. */
export function normalizePhoneDigits(value: string): string {
  return value.replace(/\D/g, "");
}
