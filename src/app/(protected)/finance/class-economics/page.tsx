import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { formatFinanceMargin, formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { fetchClassEconomicsSummary } from "@/lib/reporting/finance-read-model";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ClassEconomicsIndexPage({ searchParams }: Props) {
  const t = await getTranslations("finance.classEconomics");
  const tIntel = await getTranslations("finance.intelligence");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const { period } = parseReportingSearchParams(await searchParams);

  if (!(await can("class_economics.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { rows: summaryRows } = await fetchClassEconomicsSummary(supabase, period);
  const { data: classes } = await supabase
    .from("class")
    .select("id, name, course:course_id(code)")
    .order("name");

  return (
    <div className="space-y-6">
      <ReportingPeriodFilterForm
        startDate={period.startDate}
        endDate={period.endDate}
        action="/finance/class-economics"
        showComparisonToggle={false}
      />

      {summaryRows.length > 0 ? (
        <section className="space-y-3">
          <h2 className="text-lg font-semibold">{tIntel("drillDownClassEconomics")}</h2>
          <div className="overflow-x-auto rounded border border-slate-200">
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50 text-left">
                <tr>
                  <th className="px-3 py-2">{tIntel("class")}</th>
                  <th className="px-3 py-2">{tIntel("recognizedRevenue")}</th>
                  <th className="px-3 py-2">{t("totalCost")}</th>
                  <th className="px-3 py-2">{t("contribution")}</th>
                  <th className="px-3 py-2">{t("margin")}</th>
                  <th className="px-3 py-2">{t("deliveredSessions")}</th>
                </tr>
              </thead>
              <tbody>
                {summaryRows.map((row) => (
                  <tr key={row.classId} className="border-t border-slate-100">
                    <td className="px-3 py-2">
                      <Link href={`/finance/class-economics/${row.classId}`} className="underline">
                        {row.className}
                      </Link>
                    </td>
                    <td className="px-3 py-2">
                      {formatFinanceMoney(row.recognizedRevenue, locale)}
                    </td>
                    <td className="px-3 py-2">{formatFinanceMoney(row.totalCost, locale)}</td>
                    <td className="px-3 py-2">{formatFinanceMoney(row.contribution, locale)}</td>
                    <td className="px-3 py-2">{formatFinanceMargin(row.marginPercentage, locale)}</td>
                    <td className="px-3 py-2">{row.deliveredSessionCount}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      <div className="space-y-4">
        <h2 className="text-lg font-semibold">{t("selectClass")}</h2>
        {(classes ?? []).length === 0 ? (
          <p className="text-sm text-slate-600">{t("noClasses")}</p>
        ) : (
          <ul className="space-y-2">
            {(classes ?? []).map((cls) => {
              const course = cls.course as { code?: string } | null;
              return (
                <li key={cls.id}>
                  <Link href={`/finance/class-economics/${cls.id}`} className="text-sm underline">
                    {cls.name} {course?.code ? `(${course.code})` : ""}
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}
