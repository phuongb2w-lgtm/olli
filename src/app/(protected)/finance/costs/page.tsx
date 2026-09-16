import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { PeriodFilterForm } from "@/components/finance/period-filter-form";
import { ReconciliationPanel } from "@/components/finance/reconciliation-panel";
import { formatFinanceMoney, normalizePeriodMonth } from "@/lib/finance/format-finance-value";
import { queryExpensesByDomain } from "@/lib/finance/query-expenses";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { formatDate } from "@/lib/formatting";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const DOMAIN_ORDER = ["operating_overhead", "personnel", "marketing_sales", "capital"] as const;

export default async function CostsPage({ searchParams }: Props) {
  const t = await getTranslations("finance.costs");
  const tDomain = await getTranslations("costDomain");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const rawParams = await searchParams;
  const periodParam = typeof rawParams.period === "string" ? rawParams.period : undefined;

  const hasExpenseRead = await can("expense.read");
  const hasAssetRead = await can("asset.read");
  const hasPersonnelRead = await can("personnel_cost.read");
  const hasEconomicsRead = await can("class_economics.read");

  if (!hasExpenseRead && !hasAssetRead && !hasPersonnelRead) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { items, error } = hasExpenseRead
    ? await queryExpensesByDomain(supabase, periodParam)
    : { items: [], error: null };

  const grouped = DOMAIN_ORDER.map((domain) => ({
    domain,
    items: items.filter((i) =>
      domain === "capital" ? false : i.domainCode === domain,
    ),
    total: items
      .filter((i) => domain !== "capital" && i.domainCode === domain)
      .reduce((s, i) => s + i.amount, 0),
  }));

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap gap-3">
        {hasAssetRead ? (
          <Link href="/finance/costs/assets" className="rounded border border-slate-300 px-4 py-2 text-sm hover:bg-slate-50">
            {t("capitalAssets")}
          </Link>
        ) : null}
        {hasPersonnelRead ? (
          <Link href="/finance/costs/personnel" className="rounded border border-slate-300 px-4 py-2 text-sm hover:bg-slate-50">
            {t("personnelCosts")}
          </Link>
        ) : null}
      </div>

      {hasExpenseRead ? (
        <PeriodFilterForm periodMonth={periodParam ? `${periodParam}-01` : normalizePeriodMonth()} />
      ) : null}

      {hasEconomicsRead ? <ReconciliationPanel periodParam={periodParam} /> : null}

      {error ? (
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      ) : null}

      {grouped.map(({ domain, items: domainItems, total }) => (
        <section key={domain} className="space-y-3">
          <div className="flex items-center justify-between gap-3">
            <h2 className="text-lg font-semibold">{tDomain(domain)}</h2>
            {domain !== "capital" ? (
              <p className="text-sm font-medium text-slate-700">
                {t("domainTotal")}: {formatFinanceMoney(total, locale)}
              </p>
            ) : null}
          </div>
          {domain === "capital" ? (
            <p className="text-sm text-slate-600">{t("capitalHint")}</p>
          ) : domainItems.length === 0 ? (
            <p className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">{t("emptyDomain")}</p>
          ) : (
            <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
              <table className="min-w-full text-sm">
                <thead className="bg-slate-50">
                  <tr>
                    <th className="px-4 py-2 text-left">{t("category")}</th>
                    <th className="px-4 py-2 text-left">{t("period")}</th>
                    <th className="px-4 py-2 text-left">{t("class")}</th>
                    <th className="px-4 py-2 text-right">{t("amount")}</th>
                  </tr>
                </thead>
                <tbody>
                  {domainItems.map((item) => (
                    <tr key={item.id} className="border-t border-slate-100">
                      <td className="px-4 py-2">{item.categoryName}</td>
                      <td className="px-4 py-2">{formatDate(item.incurredDate, locale)}</td>
                      <td className="px-4 py-2">{item.className ?? "—"}</td>
                      <td className="px-4 py-2 text-right">{formatFinanceMoney(item.amount, locale)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      ))}
    </div>
  );
}
