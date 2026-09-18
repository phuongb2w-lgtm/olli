import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { fetchConsultantDeclarations } from "@/lib/reporting/finance-read-model";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function FinanceConsultantRevenuePage({ searchParams }: Props) {
  const t = await getTranslations("finance.intelligence");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const { period } = parseReportingSearchParams(await searchParams);

  if (!(await can("consultant_revenue.review"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("consultantDenied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { rows } = await fetchConsultantDeclarations(supabase, period);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">{t("consultantRevenueTitle")}</h2>
        <Link href="/finance" className="text-sm underline">
          {t("backToOverview")}
        </Link>
      </div>

      <p className="text-sm text-slate-600">{t("consultantRevenueHint")}</p>

      <ReportingPeriodFilterForm
        startDate={period.startDate}
        endDate={period.endDate}
        action="/finance/consultant-revenue"
        showComparisonToggle={false}
      />

      {rows.length === 0 ? (
        <p className="text-sm text-slate-600">{t("noDeclarations")}</p>
      ) : (
        <div className="overflow-x-auto rounded border border-slate-200">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 text-left">
              <tr>
                <th className="px-3 py-2">{t("declarationDate")}</th>
                <th className="px-3 py-2">{t("consultant")}</th>
                <th className="px-3 py-2">{t("amount")}</th>
                <th className="px-3 py-2">{t("status")}</th>
                <th className="px-3 py-2">{t("paymentLink")}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.declarationId} className="border-t border-slate-100">
                  <td className="px-3 py-2">{row.declarationDate}</td>
                  <td className="px-3 py-2">{row.consultantName}</td>
                  <td className="px-3 py-2">
                    {formatFinanceMoney(row.declaredAmount, locale)}
                  </td>
                  <td className="px-3 py-2">{row.status}</td>
                  <td className="px-3 py-2">
                    {row.hasCanonicalPayment
                      ? t("linkedPayment")
                      : row.status === "approved"
                        ? t("unlinkedApproved")
                        : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
