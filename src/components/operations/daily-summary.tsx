"use client";

import { useTranslations } from "next-intl";
import type { DailySummary } from "@/lib/teaching/query-daily-operations";
import { formatMinutesAsHours } from "@/lib/teaching/query-workload-analytics";

type Props = {
  summary: DailySummary;
};

export function DailySummaryCards({ summary }: Props) {
  const t = useTranslations("operationsDaily");

  const cards = [
    { key: "materialized", value: summary.materializedCount },
    { key: "inProgress", value: summary.inProgressCount },
    { key: "upcoming", value: summary.upcomingScheduledCount },
    { key: "completed", value: summary.completedCount },
    { key: "cancelled", value: summary.cancelledCount },
    { key: "projected", value: summary.projectedCount },
    { key: "unresolvedTeacher", value: summary.unresolvedProjectedCount },
    { key: "roomless", value: summary.roomlessProjectedCount },
  ] as const;

  return (
    <section
      className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-8"
      data-testid="daily-summary"
      aria-label={t("summaryLabel")}
    >
      {cards.map((card) => (
        <div
          key={card.key}
          className="rounded-lg border border-slate-200 bg-white px-3 py-2"
          data-summary-key={card.key}
        >
          <p className="text-xs text-slate-600">{t(`summary.${card.key}`)}</p>
          <p className="text-lg font-semibold tabular-nums text-slate-900">{card.value}</p>
        </div>
      ))}
      <div className="col-span-2 rounded-lg border border-slate-200 bg-white px-3 py-2 sm:col-span-4 lg:col-span-4">
        <p className="text-xs text-slate-600">{t("summary.scheduledHours")}</p>
        <p className="text-lg font-semibold tabular-nums text-slate-900">
          {formatMinutesAsHours(summary.scheduledMinutes)}
        </p>
        <p className="mt-1 text-xs text-slate-600">{t("summary.deliveredHours")}</p>
        <p className="text-sm font-medium tabular-nums text-slate-800">
          {formatMinutesAsHours(summary.deliveredScheduledMinutes)}
        </p>
      </div>
    </section>
  );
}
