import { getTranslations } from "next-intl/server";
import { getOrganizationCostReconciliation } from "@/app/actions/class-economics";
import { FinanceMetricCard } from "@/components/finance/finance-metric-card";
import { formatFinanceMoney, normalizePeriodMonth } from "@/lib/finance/format-finance-value";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";

type Props = { periodParam?: string };

export async function ReconciliationPanel({ periodParam }: Props) {
  const t = await getTranslations("finance.reconciliation");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const periodMonth = normalizePeriodMonth(periodParam);
  const { result, error } = await getOrganizationCostReconciliation(periodMonth);

  if (error) return null;
  const r = result as Record<string, unknown> | undefined;
  if (!r) return null;

  return (
    <section className="space-y-3">
      <h2 className="text-lg font-semibold">{t("title")}</h2>
      <div className="grid gap-4 sm:grid-cols-3">
        <FinanceMetricCard
          label={t("sharedSourceTotal")}
          value={formatFinanceMoney(Number(r.shared_source_total), locale)}
        />
        <FinanceMetricCard
          label={t("allocatedTotal")}
          value={formatFinanceMoney(Number(r.allocated_total), locale)}
        />
        <FinanceMetricCard
          label={t("unallocatedTotal")}
          value={formatFinanceMoney(Number(r.unallocated_total), locale)}
          variant="cost"
          hint={t("unallocatedHint")}
        />
      </div>
    </section>
  );
}
