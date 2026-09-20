import { resolveReportingPeriodFromInput } from "@/lib/reporting/finance-read-model";
import type { LocalDateRange } from "@/lib/reporting/period-contract";

export function parseReportingSearchParams(
  raw: Record<string, string | string[] | undefined>,
): { period: LocalDateRange; comparePrevious: boolean } {
  const startParam = typeof raw.start === "string" ? raw.start : undefined;
  const endParam = typeof raw.end === "string" ? raw.end : undefined;
  const periodParam = typeof raw.period === "string" ? raw.period : undefined;
  const compareParam = typeof raw.compare === "string" ? raw.compare : undefined;

  const period = resolveReportingPeriodFromInput({
    startDate: startParam,
    endDate: endParam,
    periodMonth: periodParam,
  });

  const comparePrevious = parseReportingCompareParam(compareParam);

  return { period, comparePrevious };
}

/** Supports hidden compare=0 + checkbox compare=1 form submissions and explicit URL params. */
export function parseReportingCompareParam(
  compareParam: string | string[] | undefined,
  defaultWhenAbsent = true,
): boolean {
  const values = Array.isArray(compareParam)
    ? compareParam
    : compareParam != null
      ? [compareParam]
      : [];
  if (values.includes("1")) return true;
  if (values.includes("0")) return false;
  return defaultWhenAbsent;
}
