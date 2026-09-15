import type { ReportPeriod } from "./types";

export type PeriodInput = {
  startDate?: string;
  endDate?: string;
  termStartDate?: string | null;
  termEndDate?: string | null;
};

export function validateReportPeriod(input: PeriodInput): {
  ok: true;
  period: ReportPeriod;
} | {
  ok: false;
  error: "invalid_range" | "invalid_date";
} {
  const start = (input.startDate ?? input.termStartDate ?? "").trim();
  const end = (input.endDate ?? input.termEndDate ?? "").trim();

  if (!start || !end) {
    const today = new Date().toISOString().slice(0, 10);
    return {
      ok: true,
      period: {
        startDate: input.termStartDate ?? today,
        endDate: input.termEndDate ?? today,
      },
    };
  }

  if (!isIsoDate(start) || !isIsoDate(end)) {
    return { ok: false, error: "invalid_date" };
  }
  if (start > end) {
    return { ok: false, error: "invalid_range" };
  }
  return { ok: true, period: { startDate: start, endDate: end } };
}

function isIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return (
    date.getUTCFullYear() === y &&
    date.getUTCMonth() === m - 1 &&
    date.getUTCDate() === d
  );
}

export function enrollmentOverlapsPeriod(
  startDate: string,
  endDate: string | null,
  period: ReportPeriod,
): boolean {
  if (startDate > period.endDate) return false;
  if (endDate && endDate < period.startDate) return false;
  return true;
}

export function sessionDateInPeriod(sessionDate: string, period: ReportPeriod): boolean {
  return sessionDate >= period.startDate && sessionDate <= period.endDate;
}
