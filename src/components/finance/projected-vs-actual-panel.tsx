import { getTranslations } from "next-intl/server";
import { getProjectedVsActualClassEconomics } from "@/app/actions/class-simulation";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";

type Props = { scenarioId: string; classId: string };

export async function ProjectedVsActualPanel({ scenarioId }: Props) {
  const t = await getTranslations("finance.simulator");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  const { result } = await getProjectedVsActualClassEconomics(
    scenarioId,
    "2000-01-01",
    "2099-12-31",
  );
  if (!result) return null;

  const r = result as Record<string, unknown>;
  const projected = r.projected as Record<string, unknown>;
  const actual = r.actual as Record<string, unknown>;
  const variance = r.variance as Record<string, unknown>;

  return (
    <section className="space-y-3">
      <h3 className="font-medium">{t("projectedVsActual")}</h3>
      <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
        <table className="min-w-full text-sm">
          <thead className="bg-slate-50">
            <tr>
              <th className="px-4 py-2 text-left">{t("metric")}</th>
              <th className="px-4 py-2 text-right">{t("projectedColumn")}</th>
              <th className="px-4 py-2 text-right">{t("actualColumn")}</th>
              <th className="px-4 py-2 text-right">{t("varianceColumn")}</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-t border-slate-100">
              <td className="px-4 py-2">{t("projectedRevenue")}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(projected.projected_revenue ?? projected.recognized_revenue), locale)}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(actual.recognized_revenue), locale)}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(variance.revenue), locale)}</td>
            </tr>
            <tr className="border-t border-slate-100">
              <td className="px-4 py-2">{t("projectedCost")}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(projected.projected_total_cost ?? projected.total_cost), locale)}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(actual.total_cost), locale)}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(variance.total_cost), locale)}</td>
            </tr>
            <tr className="border-t border-slate-100">
              <td className="px-4 py-2">{t("projectedContribution")}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(projected.projected_contribution ?? projected.contribution), locale)}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(actual.contribution), locale)}</td>
              <td className="px-4 py-2 text-right">{formatFinanceMoney(Number(variance.contribution), locale)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  );
}
