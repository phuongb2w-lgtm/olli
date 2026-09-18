/**
 * Canonical M5 reporting period contract (application layer).
 * Database authority: resolve_reporting_period(start_date, end_date) RPC.
 */

export type LocalDateRange = {
  startDate: string;
  endDate: string;
};

export type ReportingPeriodBounds = LocalDateRange & {
  organizationId: string;
  timezone: string;
  startAtUtc: string;
  endAtExclusive: string;
};

export type PeriodValidationResult =
  | { ok: true; period: LocalDateRange }
  | { ok: false; error: "invalid_date" | "invalid_range" };

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export function isIsoLocalDate(value: string): boolean {
  if (!ISO_DATE.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return (
    date.getUTCFullYear() === y &&
    date.getUTCMonth() === m - 1 &&
    date.getUTCDate() === d
  );
}

/** Validates inclusive local date range before RPC resolution. */
export function validateLocalDateRange(
  startDate: string,
  endDate: string,
): PeriodValidationResult {
  if (!isIsoLocalDate(startDate) || !isIsoLocalDate(endDate)) {
    return { ok: false, error: "invalid_date" };
  }
  if (startDate > endDate) {
    return { ok: false, error: "invalid_range" };
  }
  return { ok: true, period: { startDate, endDate } };
}

/**
 * Pure helper mirroring resolve_reporting_period UTC conversion.
 * Uses same semantics: inclusive local dates, endAtExclusive = start of day after endDate.
 */
export function localDateRangeToUtcBounds(
  period: LocalDateRange,
  timezone: string,
): { startAtUtc: Date; endAtExclusive: Date } {
  const startAtUtc = zonedLocalDateToUtc(period.startDate, "00:00:00", timezone);
  const dayAfterEnd = addDaysIso(period.endDate, 1);
  const endAtExclusive = zonedLocalDateToUtc(dayAfterEnd, "00:00:00", timezone);
  return { startAtUtc, endAtExclusive };
}

function addDaysIso(isoDate: string, days: number): string {
  const [y, m, d] = isoDate.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return dt.toISOString().slice(0, 10);
}

function zonedLocalDateToUtc(
  isoDate: string,
  time: string,
  timezone: string,
): Date {
  const [y, mo, d] = isoDate.split("-").map(Number);
  const [hh, mm, ss] = time.split(":").map(Number);
  const utcGuess = Date.UTC(y, mo - 1, d, hh, mm, ss);
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  const parts = formatter.formatToParts(new Date(utcGuess));
  const read = (type: Intl.DateTimeFormatPartTypes) =>
    Number(parts.find((p) => p.type === type)?.value ?? "0");
  const asUtc = Date.UTC(
    read("year"),
    read("month") - 1,
    read("day"),
    read("hour"),
    read("minute"),
    read("second"),
  );
  const offsetMs = asUtc - utcGuess;
  return new Date(utcGuess - offsetMs);
}

/** Returns true when a timestamptz falls within inclusive local period bounds. */
export function timestampInReportingPeriod(
  instantIso: string,
  period: LocalDateRange,
  timezone: string,
): boolean {
  const { startAtUtc, endAtExclusive } = localDateRangeToUtcBounds(period, timezone);
  const instant = new Date(instantIso);
  return instant >= startAtUtc && instant < endAtExclusive;
}
