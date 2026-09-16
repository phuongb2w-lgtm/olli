import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { SimulatorScenarioActions } from "@/components/finance/simulator-scenario-actions";
import { ProjectedVsActualPanel } from "@/components/finance/projected-vs-actual-panel";
import { getClassFinancialScenario } from "@/app/actions/class-simulation";
import { formatFinanceMargin, formatFinanceMoney } from "@/lib/finance/format-finance-value";
import { can } from "@/lib/permissions/can";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ scenarioId: string }> };

export default async function SimulatorScenarioDetailPage({ params }: Props) {
  const t = await getTranslations("finance.simulator");
  const tStatus = await getTranslations("scenarioStatus");
  const { scenarioId } = await params;
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("class_simulation.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const { result, error } = await getClassFinancialScenario(scenarioId);
  if (error || !result) notFound();

  const scenario = (result as Record<string, unknown>).scenario as Record<string, unknown>;
  const economics = (result as Record<string, unknown>).economics as Record<string, unknown>;
  const isDraft = scenario.status === "draft";
  const canManage = await can("class_simulation.manage");
  const classId = scenario.class_id as string | null;

  return (
    <div className="space-y-6">
      <Link href="/finance/simulator" className="text-sm text-slate-600 underline">
        ← {t("backToList")}
      </Link>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">{String(scenario.scenario_name)}</h2>
          <p className="text-sm text-slate-600">
            {tStatus(String(scenario.status) as "draft")} · <span className="text-violet-700">{t("projectedLabel")}</span>
          </p>
        </div>
        {canManage ? (
          <SimulatorScenarioActions scenarioId={scenarioId} isDraft={isDraft} />
        ) : null}
      </div>

      <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div className="rounded-lg border border-violet-200 bg-violet-50 p-4">
          <p className="text-xs uppercase text-violet-700">{t("projectedRevenue")}</p>
          <p className="text-lg font-semibold">{formatFinanceMoney(Number(economics.projected_revenue), locale)}</p>
        </div>
        <div className="rounded-lg border border-violet-200 bg-violet-50 p-4">
          <p className="text-xs uppercase text-violet-700">{t("projectedCost")}</p>
          <p className="text-lg font-semibold">{formatFinanceMoney(Number(economics.projected_total_cost), locale)}</p>
        </div>
        <div className="rounded-lg border border-violet-200 bg-violet-50 p-4">
          <p className="text-xs uppercase text-violet-700">{t("projectedContribution")}</p>
          <p className="text-lg font-semibold">{formatFinanceMoney(Number(economics.projected_contribution), locale)}</p>
        </div>
        <div className="rounded-lg border border-violet-200 bg-violet-50 p-4">
          <p className="text-xs uppercase text-violet-700">{t("projectedMargin")}</p>
          <p className="text-lg font-semibold">{formatFinanceMargin(economics.projected_margin_percentage as number | null, locale)}</p>
        </div>
        <div className="rounded-lg border border-violet-200 bg-violet-50 p-4">
          <p className="text-xs uppercase text-violet-700">{t("breakEvenLearners")}</p>
          <p className="text-lg font-semibold">{String(economics.break_even_learner_count ?? "—")}</p>
        </div>
      </section>

      {classId ? <ProjectedVsActualPanel scenarioId={scenarioId} classId={classId} /> : null}

      {isDraft && canManage ? (
        <p className="text-sm text-slate-600">{t("draftHint")}</p>
      ) : !isDraft ? (
        <p className="text-sm text-slate-600">{t("finalizedHint")}</p>
      ) : null}
    </div>
  );
}
