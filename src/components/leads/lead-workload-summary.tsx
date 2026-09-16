import { getTranslations } from "next-intl/server";
import type { LeadWorkloadSummary } from "@/lib/leads/query-lead-workload";

type Props = {
  summary: LeadWorkloadSummary;
};

export async function LeadWorkloadSummary({ summary }: Props) {
  const t = await getTranslations("crm.leads");

  if (summary.byAssignee.length === 0 && summary.unassignedActiveCount === 0) {
    return null;
  }

  return (
    <section className="rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm text-slate-700">
      <h2 className="font-medium text-slate-900">{t("workloadTitle")}</h2>
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
        <li>
          {t("unassignedWorkload", { count: summary.unassignedActiveCount })}
        </li>
        {summary.byAssignee.map((row) => (
          <li key={row.userId}>
            {t("assigneeWorkload", { name: row.displayName, count: row.activeCount })}
          </li>
        ))}
      </ul>
    </section>
  );
}
