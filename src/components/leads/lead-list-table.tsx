import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { LeadStatusBadge } from "@/components/leads/lead-status-badge";
import type { LeadListItem } from "@/lib/leads/query-lead-list";

type Props = {
  items: LeadListItem[];
};

function formatDate(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString();
}

export async function LeadListTable({ items }: Props) {
  const t = await getTranslations("crm.leads");

  return (
    <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-50">
          <tr>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("candidateColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("contactColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("statusColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("sourceColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("nextFollowUpColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("lastActivityColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("createdColumn")}
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {items.map((item) => (
            <tr key={item.id} className="hover:bg-slate-50">
              <td className="px-4 py-3">
                <Link href={`/crm/leads/${item.id}`} className="font-medium text-slate-900 hover:underline">
                  {item.primaryCandidateName ?? t("emptyValue")}
                </Link>
              </td>
              <td className="px-4 py-3 text-slate-700">{item.primaryContactName ?? t("emptyValue")}</td>
              <td className="px-4 py-3">
                <LeadStatusBadge status={item.status} />
              </td>
              <td className="px-4 py-3 text-slate-700">{item.sourceLabel ?? t("emptyValue")}</td>
              <td className="px-4 py-3 text-slate-700">{formatDate(item.nextFollowUpAt)}</td>
              <td className="px-4 py-3 text-slate-700">{formatDate(item.lastActivityAt)}</td>
              <td className="px-4 py-3 text-slate-700">{formatDate(item.createdAt)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
