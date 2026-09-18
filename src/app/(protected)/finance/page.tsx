import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { FinanceComparisonMetricCard } from "@/components/finance/finance-comparison-metric-card";
import { FinanceExceptionsPanel } from "@/components/finance/finance-exceptions-panel";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { queryFinanceOverview } from "@/lib/finance/query-finance-overview";
import { fetchFinanceExceptions } from "@/lib/reporting/finance-read-model";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function FinanceOverviewPage({ searchParams }: Props) {
  const t = await getTranslations("finance.intelligence");
  const tOverview = await getTranslations("finance.overview");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const rawParams = await searchParams;
  const { period, comparePrevious } = parseReportingSearchParams(rawParams);

  const hasRead =
    (await can("charge.read")) ||
    (await can("payment.read")) ||
    (await can("revenue.read")) ||
    (await can("expense.read")) ||
    (await can("class_economics.read")) ||
    (await can("consultant_revenue.review")) ||
    (await can("report.executive.read"));

  if (!hasRead) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{tOverview("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { metrics, error } = await queryFinanceOverview(supabase, {
    startDate: period.startDate,
    endDate: period.endDate,
    comparePrevious,
  });

  if (error || !metrics) {
    return (
      <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
        <p>{tOverview("loadError")}</p>
      </section>
    );
  }

  const overview = metrics.overview;
  const { exceptions } = await fetchFinanceExceptions(supabase, period);

  return (
    <div className="space-y-6">
      <ReportingPeriodFilterForm
        startDate={period.startDate}
        endDate={period.endDate}
        comparePrevious={comparePrevious}
      />

      {overview.comparisonPeriod ? (
        <p className="text-xs text-slate-600">
          {t("comparisonHint", {
            start: overview.comparisonPeriod.startDate,
            end: overview.comparisonPeriod.endDate,
          })}
        </p>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <FinanceComparisonMetricCard
          label={t("cashCollected")}
          value={overview.cashCollected.current}
          change={comparePrevious ? overview.cashCollected.change : null}
          locale={locale}
          variant="cash"
          sublabel={t("paymentCount", { count: overview.cashCollected.paymentCount })}
        />
        <FinanceComparisonMetricCard
          label={t("recognizedRevenue")}
          value={overview.recognizedRevenue.current}
          change={comparePrevious ? overview.recognizedRevenue.change : null}
          locale={locale}
          variant="revenue"
          sublabel={t("eventCount", { count: overview.recognizedRevenue.eventCount })}
        />
        <FinanceComparisonMetricCard
          label={t("outstandingTuition")}
          value={overview.receivables.totalOutstanding}
          change={null}
          locale={locale}
          variant="receivable"
          sublabel={t("obligationCount", { count: overview.receivables.obligationCount })}
          hint={
            overview.receivables.overdueCount > 0
              ? t("overdueHint", {
                  amount: formatFinanceMoney(overview.receivables.overdueAmount, locale),
                  count: overview.receivables.overdueCount,
                })
              : undefined
          }
        />
        <FinanceComparisonMetricCard
          label={tOverview("serviceObligation")}
          value={overview.serviceObligation}
          change={null}
          locale={locale}
          variant="obligation"
        />
        <FinanceComparisonMetricCard
          label={t("operatingCosts")}
          value={overview.costs.totalOperating}
          change={comparePrevious ? overview.costs.change?.totalOperating ?? null : null}
          locale={locale}
          variant="cost"
        />
        <FinanceComparisonMetricCard
          label={t("operatingResult")}
          value={overview.operatingResult.current}
          change={comparePrevious ? overview.operatingResult.change : null}
          locale={locale}
          variant="neutral"
        />
        <FinanceComparisonMetricCard
          label={tOverview("personnelCosts")}
          value={overview.costs.personnel}
          change={comparePrevious ? overview.costs.change?.personnel ?? null : null}
          locale={locale}
          variant="cost"
        />
        <FinanceComparisonMetricCard
          label={tOverview("marketingSalesCosts")}
          value={overview.costs.marketingSales}
          change={comparePrevious ? overview.costs.change?.marketingSales ?? null : null}
          locale={locale}
          variant="cost"
        />
        <FinanceComparisonMetricCard
          label={tOverview("depreciation")}
          value={overview.costs.depreciation}
          change={comparePrevious ? overview.costs.change?.depreciation ?? null : null}
          locale={locale}
          variant="cost"
        />
        {overview.consultantDeclarations ? (
          <FinanceComparisonMetricCard
            label={t("pendingConsultantDeclarations")}
            value={overview.consultantDeclarations.pendingAmount}
            change={null}
            locale={locale}
            variant="neutral"
            sublabel={t("declarationCount", {
              count: overview.consultantDeclarations.pendingCount,
            })}
            hint={t("approvedUnlinkedHint", {
              count: overview.consultantDeclarations.approvedUnlinkedCount,
            })}
          />
        ) : null}
        <FinanceComparisonMetricCard
          label={tOverview("unallocatedSharedCosts")}
          value={overview.costs.unallocatedShared}
          change={null}
          locale={locale}
          variant="cost"
          hint={tOverview("unallocatedHint")}
        />
      </div>

      <div className="flex flex-wrap gap-3 text-sm">
        <Link href={`/finance/cash-revenue?start=${period.startDate}&end=${period.endDate}`} className="underline">
          {t("drillDownCashRevenue")}
        </Link>
        <Link href="/finance/receivables" className="underline">
          {t("drillDownReceivables")}
        </Link>
        <Link href={`/finance/class-economics?start=${period.startDate}&end=${period.endDate}`} className="underline">
          {t("drillDownClassEconomics")}
        </Link>
        {(await can("consultant_revenue.review")) ? (
          <Link
            href={`/finance/consultant-revenue?start=${period.startDate}&end=${period.endDate}`}
            className="underline"
          >
            {t("drillDownConsultantRevenue")}
          </Link>
        ) : null}
      </div>

      <FinanceExceptionsPanel
        exceptions={exceptions}
        locale={locale}
        title={t("exceptionsTitle")}
        emptyLabel={t("exceptionsEmpty")}
        viewLabel={t("viewDetail")}
      />
    </div>
  );
}
