import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { formatFinanceMoney, formatFinanceMargin } from "@/lib/finance/format-finance-value";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function SimulatorPage() {
  const t = await getTranslations("finance.simulator");
  const tStatus = await getTranslations("scenarioStatus");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("class_simulation.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const canManage = await can("class_simulation.manage");
  const supabase = await createClient();
  const { data: scenarios } = await supabase
    .from("class_financial_scenario")
    .select("id, scenario_name, status, planned_learner_count, economics_snapshot, class:class_id(name)")
    .order("updated_at", { ascending: false });

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">{t("title")}</h2>
        {canManage ? (
          <Link href="/finance/simulator/new" className="rounded bg-slate-900 px-4 py-2 text-sm text-white">
            {t("createScenario")}
          </Link>
        ) : null}
      </div>

      {(scenarios ?? []).length === 0 ? (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("empty")}</p>
        </section>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50">
              <tr>
                <th className="px-4 py-2 text-left">{t("scenarioName")}</th>
                <th className="px-4 py-2 text-left">{t("class")}</th>
                <th className="px-4 py-2 text-left">{t("status")}</th>
                <th className="px-4 py-2 text-right">{t("projectedRevenue")}</th>
                <th className="px-4 py-2 text-right">{t("projectedContribution")}</th>
                <th className="px-4 py-2 text-right">{t("projectedMargin")}</th>
              </tr>
            </thead>
            <tbody>
              {(scenarios ?? []).map((s) => {
                const econ = (s.economics_snapshot as Record<string, unknown> | null) ?? {};
                const cls = s.class as { name?: string } | null;
                return (
                  <tr key={s.id} className="border-t border-slate-100">
                    <td className="px-4 py-2">
                      <Link href={`/finance/simulator/${s.id}`} className="underline">
                        {s.scenario_name}
                      </Link>
                    </td>
                    <td className="px-4 py-2">{cls?.name ?? "—"}</td>
                    <td className="px-4 py-2">{tStatus(s.status as "draft")}</td>
                    <td className="px-4 py-2 text-right">
                      {formatFinanceMoney(Number(econ.projected_revenue ?? 0), locale)}
                    </td>
                    <td className="px-4 py-2 text-right">
                      {formatFinanceMoney(Number(econ.projected_contribution ?? 0), locale)}
                    </td>
                    <td className="px-4 py-2 text-right">
                      {formatFinanceMargin(econ.projected_margin_percentage as number | null, locale)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
