"use client";

import { useTranslations } from "next-intl";
import { LEAD_LIST_STATUSES } from "@/lib/leads/constants";
import type { LeadListParams } from "@/lib/leads/parse-list-params";

type Props = {
  params: LeadListParams;
};

export function LeadListFilters({ params }: Props) {
  const t = useTranslations("crm.leads");
  const tStatus = useTranslations("status.lead");

  return (
    <form method="get" className="flex flex-wrap items-end gap-3 rounded-lg border border-slate-200 bg-white p-4">
      <div className="min-w-[12rem] flex-1">
        <label htmlFor="lead-search" className="mb-1 block text-sm font-medium text-slate-700">
          {t("search")}
        </label>
        <input
          id="lead-search"
          name="q"
          type="search"
          defaultValue={params.q}
          placeholder={t("searchPlaceholder")}
          className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
        />
      </div>
      <div>
        <label htmlFor="lead-status" className="mb-1 block text-sm font-medium text-slate-700">
          {t("statusFilter")}
        </label>
        <select
          id="lead-status"
          name="status"
          defaultValue={params.status}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        >
          {LEAD_LIST_STATUSES.map((status) => (
            <option key={status} value={status}>
              {status === "all" ? t("filterAll") : tStatus(status)}
            </option>
          ))}
        </select>
      </div>
      <button
        type="submit"
        className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
      >
        {t("applyFilters")}
      </button>
    </form>
  );
}
