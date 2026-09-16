import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { PeriodFilterForm } from "@/components/finance/period-filter-form";
import { AllocationRulesPanel } from "@/components/finance/allocation-rules-panel";
import { formatFinanceMoney, normalizePeriodMonth } from "@/lib/finance/format-finance-value";
import {
  queryCompensationRules,
  queryPersonnelCostEntries,
  queryWelfareBaselines,
} from "@/lib/finance/query-personnel";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { formatDate } from "@/lib/formatting";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

export default async function PersonnelCostsPage({ searchParams }: Props) {
  const t = await getTranslations("finance.personnel");
  const tDomain = await getTranslations("costDomain");
  const tBasis = await getTranslations("compensationBasis");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const rawParams = await searchParams;
  const periodParam = typeof rawParams.period === "string" ? rawParams.period : undefined;

  if (!(await can("personnel_cost.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const [rulesRes, entriesRes, welfareRes] = await Promise.all([
    queryCompensationRules(supabase),
    queryPersonnelCostEntries(supabase, periodParam),
    queryWelfareBaselines(supabase),
  ]);

  return (
    <div className="space-y-8">
      <div>
        <Link href="/finance/costs" className="text-sm text-slate-600 underline">
          ← {t("backToCosts")}
        </Link>
        <h2 className="mt-2 text-lg font-semibold">{t("title")}</h2>
      </div>

      <AllocationRulesPanel />

      <section className="space-y-3">
        <h3 className="font-medium">{t("compensationRules")}</h3>
        {rulesRes.items.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noRules")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-2 text-left">{t("staff")}</th>
                  <th className="px-4 py-2 text-left">{t("domain")}</th>
                  <th className="px-4 py-2 text-left">{t("basis")}</th>
                  <th className="px-4 py-2 text-right">{t("amount")}</th>
                  <th className="px-4 py-2 text-left">{t("effectiveFrom")}</th>
                </tr>
              </thead>
              <tbody>
                {rulesRes.items.map((rule) => (
                  <tr key={rule.id} className="border-t border-slate-100">
                    <td className="px-4 py-2">{rule.displayName ?? "—"}</td>
                    <td className="px-4 py-2">{tDomain(rule.costDomainCode as "personnel")}</td>
                    <td className="px-4 py-2">{tBasis(rule.compensationBasisCode as "monthly_fixed")}</td>
                    <td className="px-4 py-2 text-right">{formatFinanceMoney(rule.amount, locale)}</td>
                    <td className="px-4 py-2">{formatDate(rule.effectiveFrom, locale)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="space-y-3">
        <h3 className="font-medium">{t("welfareBaseline")}</h3>
        {welfareRes.items.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noWelfare")}</p>
        ) : (
          <ul className="space-y-2 text-sm">
            {welfareRes.items.map((w) => (
              <li key={w.id} className="rounded border border-slate-200 bg-white p-3">
                {formatFinanceMoney(w.monthlyAmount, locale)} / {t("month")} — {formatDate(w.effectiveFrom, locale)}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="space-y-3">
        <h3 className="font-medium">{t("costEntries")}</h3>
        <PeriodFilterForm
          periodMonth={periodParam ? `${periodParam}-01` : normalizePeriodMonth()}
          action="/finance/costs/personnel"
        />
        {entriesRes.items.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noEntries")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-2 text-left">{t("domain")}</th>
                  <th className="px-4 py-2 text-left">{t("class")}</th>
                  <th className="px-4 py-2 text-right">{t("amount")}</th>
                </tr>
              </thead>
              <tbody>
                {entriesRes.items.map((entry) => (
                  <tr key={entry.id} className="border-t border-slate-100">
                    <td className="px-4 py-2">{tDomain(entry.costDomainCode as "personnel")}</td>
                    <td className="px-4 py-2">{entry.className ?? t("sharedCost")}</td>
                    <td className="px-4 py-2 text-right">{formatFinanceMoney(entry.amount, locale)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
