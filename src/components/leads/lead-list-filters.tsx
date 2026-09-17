"use client";

import { useTranslations } from "next-intl";
import {
  LEAD_IDENTITY_FILTERS,
  LEAD_LIST_STATUSES,
  LEAD_TRIAL_FILTERS,
} from "@/lib/leads/constants";
import type { EligibleAssignee } from "@/lib/leads/query-eligible-assignees";
import {
  activeCatalogItems,
  type LeadCatalogCampaign,
  type LeadCatalogSource,
} from "@/lib/leads/query-lead-catalogs";
import type { LeadListParams } from "@/lib/leads/parse-list-params";

type Props = {
  params: LeadListParams;
  assignees: EligibleAssignee[];
  sources: LeadCatalogSource[];
  campaigns: LeadCatalogCampaign[];
};

export function LeadListFilters({ params, assignees, sources, campaigns }: Props) {
  const t = useTranslations("crm.leads");
  const tStatus = useTranslations("status.lead");
  const tTrial = useTranslations("crm.trial");
  const showUserPicker = params.owner === "user";
  const activeSources = activeCatalogItems(sources);
  const activeCampaigns = activeCatalogItems(campaigns);

  return (
    <form method="get" className="flex flex-wrap items-end gap-3 rounded-lg border border-slate-200 bg-white p-4">
      {params.preset !== "all" ? <input type="hidden" name="preset" value={params.preset} /> : null}
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
        <label htmlFor="lead-source" className="mb-1 block text-sm font-medium text-slate-700">
          {t("sourceFilter")}
        </label>
        <select
          id="lead-source"
          name="sourceId"
          defaultValue={params.sourceId ?? "all"}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="all">{t("filterAll")}</option>
          <option value="unattributed">{t("unattributed")}</option>
          {activeSources.map((source) => (
            <option key={source.id} value={source.id}>
              {source.displayName}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label htmlFor="lead-campaign" className="mb-1 block text-sm font-medium text-slate-700">
          {t("campaignFilter")}
        </label>
        <select
          id="lead-campaign"
          name="campaignId"
          defaultValue={params.campaignId ?? "all"}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="all">{t("filterAll")}</option>
          <option value="unattributed">{t("unattributed")}</option>
          {activeCampaigns.map((campaign) => (
            <option key={campaign.id} value={campaign.id}>
              {campaign.name}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label htmlFor="lead-owner" className="mb-1 block text-sm font-medium text-slate-700">
          {t("ownerFilter")}
        </label>
        <select
          id="lead-owner"
          name="owner"
          defaultValue={params.owner}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="all">{t("ownerAll")}</option>
          <option value="me">{t("ownerMe")}</option>
          <option value="unassigned">{t("ownerUnassigned")}</option>
          <option value="user">{t("ownerSelectedUser")}</option>
        </select>
      </div>
      {showUserPicker ? (
        <div>
          <label htmlFor="lead-owner-user" className="mb-1 block text-sm font-medium text-slate-700">
            {t("ownerUser")}
          </label>
          <select
            id="lead-owner-user"
            name="ownerUserId"
            defaultValue={params.ownerUserId ?? ""}
            className="rounded border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">{t("selectOwnerUser")}</option>
            {assignees.map((user) => (
              <option key={user.userId} value={user.userId}>
                {user.displayName}
              </option>
            ))}
          </select>
        </div>
      ) : null}
      <div>
        <label htmlFor="lead-trial" className="mb-1 block text-sm font-medium text-slate-700">
          {tTrial("listFilter")}
        </label>
        <select
          id="lead-trial"
          name="trial"
          defaultValue={params.trial}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        >
          {LEAD_TRIAL_FILTERS.map((trial) => (
            <option key={trial} value={trial}>
              {trial === "all" ? t("filterAll") : tTrial("filterScheduled")}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label htmlFor="lead-identity" className="mb-1 block text-sm font-medium text-slate-700">
          {t("identityFilter")}
        </label>
        <select
          id="lead-identity"
          name="identity"
          defaultValue={params.identity}
          className="rounded border border-slate-300 px-3 py-2 text-sm"
        >
          {LEAD_IDENTITY_FILTERS.map((identity) => (
            <option key={identity} value={identity}>
              {t(`identity_${identity}`)}
            </option>
          ))}
        </select>
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
