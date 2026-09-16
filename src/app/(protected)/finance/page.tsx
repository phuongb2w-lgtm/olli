import { getTranslations } from "next-intl/server";
import { FinanceMetricCard } from "@/components/finance/finance-metric-card";
import { PeriodFilterForm } from "@/components/finance/period-filter-form";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { queryFinanceOverview } from "@/lib/finance/query-finance-overview";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function FinanceOverviewPage({ searchParams }: Props) {
  const t = await getTranslations("finance.overview");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const rawParams = await searchParams;
  const periodParam = typeof rawParams.period === "string" ? rawParams.period : undefined;

  const hasRead =
    (await can("charge.read")) ||
    (await can("payment.read")) ||
    (await can("class_economics.read"));

  if (!hasRead) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { metrics, error } = await queryFinanceOverview(supabase, periodParam);

  if (error || !metrics) {
    return (
      <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
        <p>{t("loadError")}</p>
      </section>
    );
  }

  return (
    <div className="space-y-6">
      <PeriodFilterForm periodMonth={metrics.periodMonth} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <FinanceMetricCard
          label={t("recognizedRevenue")}
          value={formatFinanceMoney(metrics.recognizedRevenue, locale)}
          variant="revenue"
        />
        <FinanceMetricCard
          label={t("cashReceived")}
          value={formatFinanceMoney(metrics.cashReceived, locale)}
          variant="cash"
        />
        <FinanceMetricCard
          label={t("cashAllocated")}
          value={formatFinanceMoney(metrics.cashAllocated, locale)}
          variant="cash"
        />
        <FinanceMetricCard
          label={t("outstandingReceivable")}
          value={formatFinanceMoney(metrics.outstandingReceivables, locale)}
          variant="receivable"
        />
        <FinanceMetricCard
          label={t("serviceObligation")}
          value={formatFinanceMoney(metrics.serviceObligation, locale)}
          variant="obligation"
        />
        <FinanceMetricCard
          label={t("operatingCosts")}
          value={formatFinanceMoney(metrics.operatingCosts, locale)}
          variant="cost"
        />
        <FinanceMetricCard
          label={t("personnelCosts")}
          value={formatFinanceMoney(metrics.personnelCosts, locale)}
          variant="cost"
        />
        <FinanceMetricCard
          label={t("marketingSalesCosts")}
          value={formatFinanceMoney(metrics.marketingSalesCosts, locale)}
          variant="cost"
        />
        <FinanceMetricCard
          label={t("depreciation")}
          value={formatFinanceMoney(metrics.depreciation, locale)}
          variant="cost"
        />
        <FinanceMetricCard
          label={t("unallocatedSharedCosts")}
          value={formatFinanceMoney(metrics.unallocatedSharedCosts, locale)}
          variant="cost"
          hint={t("unallocatedHint")}
        />
      </div>
    </div>
  );
}
