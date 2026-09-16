"use client";

import { useTranslations } from "next-intl";

type Props = {
  periodMonth: string;
  action?: string;
};

export function PeriodFilterForm({ periodMonth, action }: Props) {
  const t = useTranslations("finance.common");

  return (
    <form method="get" action={action} className="flex flex-wrap items-end gap-3">
      <label className="text-sm">
        <span className="mb-1 block text-slate-600">{t("periodMonth")}</span>
        <input
          type="month"
          name="period"
          defaultValue={periodMonth.slice(0, 7)}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        />
      </label>
      <button
        type="submit"
        className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
      >
        {t("applyPeriod")}
      </button>
    </form>
  );
}
