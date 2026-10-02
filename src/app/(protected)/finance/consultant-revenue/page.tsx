import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ConsultantRevenueDeclarationsPanel } from "@/components/finance/consultant-revenue-declarations-panel";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";

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

  const canConfirm =
    (await can("consultant_revenue.review")) && (await can("payment.record"));

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

      <ConsultantRevenueDeclarationsPanel
        startDate={period.startDate}
        endDate={period.endDate}
        locale={locale}
        canConfirm={canConfirm}
      />
    </div>
  );
}
