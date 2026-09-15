"use client";

type Props = {
  label: string;
};

export function ReportPrintButton({ label }: Props) {
  return (
    <button
      type="button"
      onClick={() => window.print()}
      className="report-no-print rounded border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
    >
      {label}
    </button>
  );
}
