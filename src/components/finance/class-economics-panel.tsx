import { getTranslations } from "next-intl/server";
import { getClassEconomics } from "@/app/actions/class-economics";
import { FinanceMetricCard } from "@/components/finance/finance-metric-card";
import { formatFinanceMargin, formatFinanceMoney, normalizePeriodMonth, periodMonthEnd } from "@/lib/finance/format-finance-value";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";

type Props = {
  classId: string;
  periodMode: string;
  period?: string;
  from?: string;
  to?: string;
};

export async function ClassEconomicsPanel({ classId, periodMode, period, from, to }: Props) {
  const t = await getTranslations("finance.classEconomics");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  let periodFrom: string;
  let periodTo: string;
  if (periodMode === "lifetime") {
    periodFrom = "2000-01-01";
    periodTo = "2099-12-31";
  } else if (periodMode === "custom" && from && to) {
    periodFrom = from;
    periodTo = to;
  } else {
    const month = normalizePeriodMonth(period);
    periodFrom = month;
    periodTo = periodMonthEnd(month);
  }

  const { result, error } = await getClassEconomics(classId, periodFrom, periodTo);
  if (error || !result) {
    return <p className="text-sm text-red-700">{t("loadError")}</p>;
  }
  const r = result as Record<string, unknown>;

  return (
    <div className="space-y-6">
      <form method="get" className="flex flex-wrap items-end gap-3 text-sm">
        <label>
          <span className="mb-1 block">{t("periodMode")}</span>
          <select name="mode" defaultValue={periodMode} className="rounded border border-slate-300 px-3 py-2">
            <option value="month">{t("modeMonth")}</option>
            <option value="custom">{t("modeCustom")}</option>
            <option value="lifetime">{t("modeLifetime")}</option>
          </select>
        </label>
        {periodMode !== "lifetime" && periodMode !== "custom" ? (
          <label>
            <span className="mb-1 block">{t("month")}</span>
            <input type="month" name="period" defaultValue={period?.slice(0, 7)} className="rounded border border-slate-300 px-3 py-2" />
          </label>
        ) : null}
        {periodMode === "custom" ? (
          <>
            <label>
              <span className="mb-1 block">{t("from")}</span>
              <input type="date" name="from" defaultValue={from} className="rounded border border-slate-300 px-3 py-2" />
            </label>
            <label>
              <span className="mb-1 block">{t("to")}</span>
              <input type="date" name="to" defaultValue={to} className="rounded border border-slate-300 px-3 py-2" />
            </label>
          </>
        ) : null}
        <button type="submit" className="rounded bg-slate-900 px-4 py-2 text-sm text-white">
          {t("apply")}
        </button>
      </form>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <FinanceMetricCard label={t("recognizedRevenue")} value={formatFinanceMoney(Number(r.recognized_revenue), locale)} variant="revenue" />
        <FinanceMetricCard label={t("directPersonnel")} value={formatFinanceMoney(Number(r.direct_personnel_cost), locale)} variant="cost" />
        <FinanceMetricCard label={t("allocatedPersonnel")} value={formatFinanceMoney(Number(r.allocated_personnel_cost), locale)} variant="cost" />
        <FinanceMetricCard label={t("allocatedOverhead")} value={formatFinanceMoney(Number(r.allocated_operating_overhead), locale)} variant="cost" />
        <FinanceMetricCard label={t("allocatedMarketing")} value={formatFinanceMoney(Number(r.allocated_marketing_sales), locale)} variant="cost" />
        <FinanceMetricCard label={t("allocatedDepreciation")} value={formatFinanceMoney(Number(r.allocated_depreciation), locale)} variant="cost" />
        <FinanceMetricCard label={t("totalCost")} value={formatFinanceMoney(Number(r.total_cost), locale)} variant="cost" />
        <FinanceMetricCard label={t("contribution")} value={formatFinanceMoney(Number(r.contribution), locale)} variant="revenue" />
        <FinanceMetricCard label={t("margin")} value={formatFinanceMargin(r.margin_percentage as number | null, locale)} />
      </div>
    </div>
  );
}
