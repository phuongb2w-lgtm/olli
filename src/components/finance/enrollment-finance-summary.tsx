import { getTranslations } from "next-intl/server";
import { FinanceMetricCard } from "@/components/finance/finance-metric-card";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";

type Props = { summary: Record<string, unknown> | null };

export async function EnrollmentFinanceSummary({ summary }: Props) {
  const t = await getTranslations("finance.enrollment");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!summary) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("noTerms")}</p>
      </section>
    );
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <FinanceMetricCard label={t("netTuition")} value={formatFinanceMoney(Number(summary.net_tuition), locale)} />
      <FinanceMetricCard label={t("scheduledAmount")} value={formatFinanceMoney(Number(summary.scheduled_amount), locale)} />
      <FinanceMetricCard label={t("chargedAmount")} value={formatFinanceMoney(Number(summary.charged_amount), locale)} />
      <FinanceMetricCard label={t("adjustments")} value={formatFinanceMoney(Number(summary.adjustments_amount), locale)} />
      <FinanceMetricCard label={t("cashAllocated")} value={formatFinanceMoney(Number(summary.cash_allocated_to_enrollment), locale)} variant="cash" />
      <FinanceMetricCard label={t("outstandingReceivable")} value={formatFinanceMoney(Number(summary.outstanding_receivable), locale)} variant="receivable" />
      <FinanceMetricCard label={t("recognizedRevenue")} value={formatFinanceMoney(Number(summary.recognized_revenue), locale)} variant="revenue" />
      <FinanceMetricCard label={t("serviceObligation")} value={formatFinanceMoney(Number(summary.unrecognized_service_obligation), locale)} variant="obligation" />
      <FinanceMetricCard label={t("unappliedCash")} value={formatFinanceMoney(Number(summary.unapplied_payment_amount), locale)} variant="cash" />
    </div>
  );
}
