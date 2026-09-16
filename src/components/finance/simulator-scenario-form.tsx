"use client";

import { useActionState, useEffect } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { createClassFinancialScenario, type ClassSimulationActionState } from "@/app/actions/class-simulation";

const initialState: ClassSimulationActionState = {};

async function createAction(_prev: ClassSimulationActionState, formData: FormData) {
  return createClassFinancialScenario({
    scenarioName: String(formData.get("scenarioName") ?? ""),
    plannedLearnerCount: Number(formData.get("plannedLearnerCount")),
    assumedNetTuitionPerLearner: Number(formData.get("assumedNetTuitionPerLearner")),
    plannedMonths: Number(formData.get("plannedMonths")),
    plannedSessionCount: Number(formData.get("plannedSessionCount")),
    classId: String(formData.get("classId") ?? "") || null,
    perSessionTeacherRate: Number(formData.get("perSessionTeacherRate")) || null,
    monthlySharedPersonnelAssumption: Number(formData.get("monthlySharedPersonnelAssumption")) || 0,
    monthlyOperatingOverheadAssumption: Number(formData.get("monthlyOperatingOverheadAssumption")) || 0,
    marketingSalesAssumption: Number(formData.get("marketingSalesAssumption")) || 0,
    marketingAssumptionBasis: (formData.get("marketingAssumptionBasis") as "one_time" | "monthly") ?? "one_time",
    monthlyDepreciationAssumption: Number(formData.get("monthlyDepreciationAssumption")) || 0,
  });
}

type ClassOption = { id: string; name: string };

type Props = { classes: ClassOption[] };

export function SimulatorScenarioForm({ classes }: Props) {
  const t = useTranslations("finance.simulator");
  const tAssumption = useTranslations("scenarioAssumption");
  const tCommon = useTranslations("finance.common");
  const router = useRouter();
  const [state, formAction, pending] = useActionState(createAction, initialState);

  useEffect(() => {
    if (state.scenarioId) router.push(`/finance/simulator/${state.scenarioId}`);
  }, [state.scenarioId, router]);

  return (
    <form action={formAction} className="max-w-2xl space-y-4 rounded-lg border border-slate-200 bg-white p-4 text-sm">
      <p className="text-xs uppercase tracking-wide text-violet-700">{t("projectedLabel")}</p>
      <label className="block">
        <span>{t("scenarioName")}</span>
        <input name="scenarioName" required className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
      </label>
      <label className="block">
        <span>{t("class")}</span>
        <select name="classId" className="mt-1 w-full rounded border border-slate-300 px-3 py-2">
          <option value="">{t("noClass")}</option>
          {classes.map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </select>
      </label>
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span>{t("plannedLearners")}</span>
          <input name="plannedLearnerCount" type="number" min={0} defaultValue={10} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("uniformTuition")}</span>
          <input name="assumedNetTuitionPerLearner" type="number" min={0} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("plannedMonths")}</span>
          <input name="plannedMonths" type="number" min={1} defaultValue={3} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("plannedSessions")}</span>
          <input name="plannedSessionCount" type="number" min={0} defaultValue={12} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("directTeachingRate")}</span>
          <input name="perSessionTeacherRate" type="number" min={0} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("sharedPersonnelMonthly")}</span>
          <input name="monthlySharedPersonnelAssumption" type="number" min={0} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("operatingOverheadMonthly")}</span>
          <input name="monthlyOperatingOverheadAssumption" type="number" min={0} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("marketingSales")}</span>
          <input name="marketingSalesAssumption" type="number" min={0} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
        <label className="block">
          <span>{tAssumption("depreciationMonthly")}</span>
          <input name="monthlyDepreciationAssumption" type="number" min={0} className="mt-1 w-full rounded border border-slate-300 px-3 py-2" />
        </label>
      </div>
      <div className="flex gap-3">
        <button type="submit" disabled={pending} className="rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50">
          {pending ? tCommon("saving") : t("createScenario")}
        </button>
        <Link href="/finance/simulator" className="rounded border border-slate-300 px-4 py-2 text-sm">{tCommon("cancel")}</Link>
      </div>
    </form>
  );
}
