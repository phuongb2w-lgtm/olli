"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  cloneClassFinancialScenario,
  finalizeClassFinancialScenario,
} from "@/app/actions/class-simulation";

type Props = { scenarioId: string; isDraft: boolean };

export function SimulatorScenarioActions({ scenarioId, isDraft }: Props) {
  const t = useTranslations("finance.simulator");
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function handleFinalize() {
    startTransition(async () => {
      await finalizeClassFinancialScenario(scenarioId);
      router.refresh();
    });
  }

  function handleClone() {
    startTransition(async () => {
      const result = await cloneClassFinancialScenario(scenarioId);
      if (result.scenarioId) router.push(`/finance/simulator/${result.scenarioId}`);
    });
  }

  return (
    <div className="flex gap-2">
      {isDraft ? (
        <button
          type="button"
          onClick={handleFinalize}
          disabled={pending}
          className="rounded bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-50"
        >
          {t("finalizeScenario")}
        </button>
      ) : null}
      <button
        type="button"
        onClick={handleClone}
        disabled={pending}
        className="rounded border border-slate-300 px-4 py-2 text-sm disabled:opacity-50"
      >
        {t("cloneScenario")}
      </button>
    </div>
  );
}
