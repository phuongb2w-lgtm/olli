import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { RetireAssetForm } from "@/components/finance/retire-asset-form";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { queryCapitalAssetDetail } from "@/lib/finance/query-capital-assets";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { formatDate } from "@/lib/formatting";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ id: string }> };

export default async function CapitalAssetDetailPage({ params }: Props) {
  const t = await getTranslations("finance.assets");
  const tDep = await getTranslations("depreciation");
  const { id } = await params;
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("asset.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { asset, schedule, error } = await queryCapitalAssetDetail(supabase, id);
  if (error || !asset) notFound();

  const canUpdate = await can("asset.update");

  return (
    <div className="space-y-6">
      <Link href="/finance/costs/assets" className="text-sm text-slate-600 underline">
        ← {t("backToList")}
      </Link>
      <h2 className="text-lg font-semibold">{asset.name}</h2>

      <section className="grid gap-4 rounded-lg border border-slate-200 bg-white p-4 sm:grid-cols-3 text-sm">
        <div>
          <p className="text-slate-600">{t("originalInvestment")}</p>
          <p className="font-medium">{formatFinanceMoney(asset.originalCost, locale)}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("monthlyDepreciation")}</p>
          <p className="font-medium">{formatFinanceMoney(asset.monthlyDepreciation, locale)}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("postedDepreciation")}</p>
          <p className="font-medium">{formatFinanceMoney(asset.postedDepreciation, locale)}</p>
        </div>
        <div>
          <p className="text-slate-600">{t("inService")}</p>
          <p className="font-medium">{formatDate(asset.placedInServiceDate, locale)}</p>
        </div>
      </section>

      <section className="space-y-3">
        <h3 className="font-medium">{t("depreciationSchedule")}</h3>
        {schedule.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noSchedule")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
            <table className="min-w-full text-sm">
              <thead className="bg-slate-50">
                <tr>
                  <th className="px-4 py-2 text-left">{tDep("periodMonth")}</th>
                  <th className="px-4 py-2 text-right">{tDep("amount")}</th>
                  <th className="px-4 py-2 text-left">{t("status")}</th>
                </tr>
              </thead>
              <tbody>
                {schedule.map((row) => (
                  <tr key={row.periodMonth} className="border-t border-slate-100">
                    <td className="px-4 py-2">{formatDate(row.periodMonth, locale)}</td>
                    <td className="px-4 py-2 text-right">{formatFinanceMoney(row.amount, locale)}</td>
                    <td className="px-4 py-2">{tDep(row.status as "posted")}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {canUpdate && asset.status === "active" ? <RetireAssetForm assetId={id} /> : null}
    </div>
  );
}
