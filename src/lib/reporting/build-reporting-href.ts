import type { LocalDateRange } from "@/lib/reporting/period-contract";

type ReportingHrefOptions = {
  comparePrevious?: boolean;
  extra?: Record<string, string | undefined>;
};

/** Preserve canonical reporting period (and compare flag) across M5 drill-down navigation. */
export function buildReportingHref(
  pathname: string,
  period: LocalDateRange,
  options: ReportingHrefOptions = {},
): string {
  const params = new URLSearchParams();
  params.set("start", period.startDate);
  params.set("end", period.endDate);
  if (options.comparePrevious === false) {
    params.set("compare", "0");
  } else if (options.comparePrevious === true) {
    params.set("compare", "1");
  }
  if (options.extra) {
    for (const [key, value] of Object.entries(options.extra)) {
      if (value != null && value !== "") {
        params.set(key, value);
      }
    }
  }
  const query = params.toString();
  return query ? `${pathname}?${query}` : pathname;
}
