"use client";

import { useTranslations } from "next-intl";

type Props = {
  startDate: string;
  endDate: string;
  action?: string;
  showComparisonToggle?: boolean;
  comparePrevious?: boolean;
};

export function ReportingPeriodFilterForm({
  startDate,
  endDate,
  action,
  showComparisonToggle = true,
  comparePrevious = true,
}: Props) {
  const t = useTranslations("finance.intelligence");

  return (
    <form method="get" action={action} className="flex flex-wrap items-end gap-3">
      <label className="text-sm">
        <span className="mb-1 block text-slate-600">{t("startDate")}</span>
        <input
          type="date"
          name="start"
          defaultValue={startDate}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        />
      </label>
      <label className="text-sm">
        <span className="mb-1 block text-slate-600">{t("endDate")}</span>
        <input
          type="date"
          name="end"
          defaultValue={endDate}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        />
      </label>
      {showComparisonToggle ? (
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input
            type="checkbox"
            name="compare"
            value="1"
            defaultChecked={comparePrevious}
            className="rounded border-slate-300"
          />
          {t("comparePrevious")}
        </label>
      ) : null}
      <button
        type="submit"
        className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
      >
        {t("applyPeriod")}
      </button>
    </form>
  );
}
