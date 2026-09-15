/** Trim surrounding whitespace; empty optional fields become null. */
export function normalizeOptionalText(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const trimmed = raw.trim();
  return trimmed.length === 0 ? null : trimmed;
}

export function normalizeGuardianEmail(raw: string | null | undefined): string | null {
  const trimmed = normalizeOptionalText(raw);
  return trimmed ? trimmed.toLowerCase() : null;
}

export function normalizedEmailKey(email: string): string {
  return email.trim().toLowerCase();
}
