import type { CrmConsultantProductivityRow } from "@/lib/reporting/crm-admissions-read-model";

type Props = {
  rows: CrmConsultantProductivityRow[];
  headers: {
    consultant: string;
    currentOwned: string;
    cohortLeads: string;
    activities: string;
    trials: string;
    conversionsInPeriod: string;
    cohortConversionRate: string;
    approvedDeclarations: string;
    pendingDeclarations: string;
  };
  emptyLabel: string;
};

function formatRate(rate: number | null): string {
  if (rate === null) return "—";
  return `${(rate * 100).toFixed(1)}%`;
}

export function ConsultantProductivityTable({ rows, headers, emptyLabel }: Props) {
  if (rows.length === 0) {
    return <p className="text-sm text-slate-600">{emptyLabel}</p>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="border-b border-slate-200 text-left text-slate-600">
            <th className="px-2 py-2 font-medium">{headers.consultant}</th>
            <th className="px-2 py-2 font-medium">{headers.currentOwned}</th>
            <th className="px-2 py-2 font-medium">{headers.cohortLeads}</th>
            <th className="px-2 py-2 font-medium">{headers.activities}</th>
            <th className="px-2 py-2 font-medium">{headers.trials}</th>
            <th className="px-2 py-2 font-medium">{headers.conversionsInPeriod}</th>
            <th className="px-2 py-2 font-medium">{headers.cohortConversionRate}</th>
            <th className="px-2 py-2 font-medium">{headers.approvedDeclarations}</th>
            <th className="px-2 py-2 font-medium">{headers.pendingDeclarations}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.consultant_user_id} className="border-b border-slate-100">
              <td className="px-2 py-2">{row.display_name}</td>
              <td className="px-2 py-2">{row.current_leads_owned}</td>
              <td className="px-2 py-2">{row.cohort_leads}</td>
              <td className="px-2 py-2">{row.activities_recorded}</td>
              <td className="px-2 py-2">{row.trials_scheduled}</td>
              <td className="px-2 py-2">{row.conversions_in_period}</td>
              <td className="px-2 py-2">{formatRate(row.cohort_conversion_rate)}</td>
              <td className="px-2 py-2">{row.approved_declarations_amount}</td>
              <td className="px-2 py-2">{row.pending_declarations_amount}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
