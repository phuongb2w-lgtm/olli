/**
 * Operational local date for materialized teaching sessions.
 * Authoritative placement uses scheduled_start_at in organization timezone.
 * occurrence_date is identity/provenance only after reschedule (M4/M5 contract).
 */

export function resolveSessionOperationalDate(input: {
  scheduledStartAt: string;
  timezone: string;
}): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: input.timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(input.scheduledStartAt));
}

/** @deprecated Use resolveSessionOperationalDate. Kept for provenance display only. */
export function resolveSessionProvenanceDate(input: {
  occurrenceDate: string | null;
  scheduledStartAt: string;
  timezone: string;
}): string {
  if (input.occurrenceDate) return input.occurrenceDate;
  return resolveSessionOperationalDate({
    scheduledStartAt: input.scheduledStartAt,
    timezone: input.timezone,
  });
}
