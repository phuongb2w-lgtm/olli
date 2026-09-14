/** Trim surrounding whitespace; empty result becomes null for storage. */
export function normalizeStudentCode(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const trimmed = raw.trim();
  return trimmed.length === 0 ? null : trimmed;
}

/** Case-insensitive, whitespace-normalized key used for duplicate comparison. */
export function normalizedStudentCodeKey(code: string): string {
  return code.trim().toLowerCase();
}
