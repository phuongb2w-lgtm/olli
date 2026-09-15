"use client";

type Props = {
  startDate: string;
  endDate: string;
  fromLabel: string;
  toLabel: string;
  periodLabel: string;
  submitLabel: string;
};

export function ReportPeriodForm({
  startDate,
  endDate,
  fromLabel,
  toLabel,
  periodLabel,
  submitLabel,
}: Props) {
  return (
    <form method="get" className="report-no-print flex flex-wrap items-end gap-3 rounded-lg border border-slate-200 bg-white p-4">
      <fieldset className="flex flex-wrap items-end gap-3">
        <legend className="sr-only">{periodLabel}</legend>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium text-slate-700">{fromLabel}</span>
          <input
            type="date"
            name="startDate"
            defaultValue={startDate}
            className="rounded border border-slate-300 px-2 py-1.5"
            required
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium text-slate-700">{toLabel}</span>
          <input
            type="date"
            name="endDate"
            defaultValue={endDate}
            className="rounded border border-slate-300 px-2 py-1.5"
            required
          />
        </label>
        <button
          type="submit"
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
        >
          {submitLabel}
        </button>
      </fieldset>
    </form>
  );
}
