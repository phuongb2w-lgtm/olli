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

  const comparePrevious = compareParam !== "0";

  return { period, comparePrevious };
}
