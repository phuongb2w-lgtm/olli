import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { queryCapitalAssetsList } from "@/lib/finance/query-capital-assets";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { formatDate } from "@/lib/formatting";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function CapitalAssetsPage() {
  const t = await getTranslations("finance.assets");
  const tStatus = await getTranslations("assetStatus");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("asset.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const canCreate = await can("asset.create");
  const supabase = await createClient();
  const { items, error } = await queryCapitalAssetsList(supabase);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <Link href="/finance/costs" className="text-sm text-slate-600 underline">
            ← {t("backToCosts")}
          </Link>
          <h2 className="mt-2 text-lg font-semibold">{t("title")}</h2>
        </div>
        {canCreate ? (
          <div className="flex gap-2">
            <Link href="/finance/costs/assets/new?mode=quick" className="rounded border border-slate-300 px-4 py-2 text-sm">
              {t("quickCreate")}
            </Link>
            <Link href="/finance/costs/assets/new?mode=detailed" className="rounded bg-slate-900 px-4 py-2 text-sm text-white">
              {t("detailedCreate")}
            </Link>
          </div>
        ) : null}
      </div>

      {error ? (
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      ) : null}

      {items.length === 0 ? (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("empty")}</p>
        </section>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-4 py-2 text-left">{t("name")}</th>
                <th className="px-4 py-2 text-right">{t("originalInvestment")}</th>
                <th className="px-4 py-2 text-right">{t("monthlyDepreciation")}</th>
                <th className="px-4 py-2 text-right">{t("postedDepreciation")}</th>
                <th className="px-4 py-2 text-left">{t("inService")}</th>
                <th className="px-4 py-2 text-left">{t("status")}</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item) => (
                <tr key={item.id} className="border-t border-slate-100">
                  <td className="px-4 py-2">
                    <Link href={`/finance/costs/assets/${item.id}`} className="underline">
                      {item.name}
                    </Link>
                    {item.isQuickMode ? (
                      <span className="ml-2 rounded bg-slate-100 px-2 py-0.5 text-xs">{t("quickMode")}</span>
                    ) : null}
                  </td>
                  <td className="px-4 py-2 text-right">{formatFinanceMoney(item.originalCost, locale)}</td>
                  <td className="px-4 py-2 text-right">{formatFinanceMoney(item.monthlyDepreciation, locale)}</td>
                  <td className="px-4 py-2 text-right">{formatFinanceMoney(item.postedDepreciation, locale)}</td>
                  <td className="px-4 py-2">{formatDate(item.placedInServiceDate, locale)}</td>
                  <td className="px-4 py-2">{tStatus(item.status as "active")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
