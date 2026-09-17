"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  upsertLeadCampaignCatalogAction,
  upsertLeadLostReasonCatalogAction,
  upsertLeadSourceCatalogAction,
  type LeadCatalogState,
} from "@/app/actions/leads";
import type {
  LeadCatalogCampaign,
  LeadCatalogLostReason,
  LeadCatalogSource,
} from "@/lib/leads/query-lead-catalogs";

type Props = {
  sources: LeadCatalogSource[];
  campaigns: LeadCatalogCampaign[];
  lostReasons: LeadCatalogLostReason[];
};

const initialState: LeadCatalogState = {};

function CatalogError({ error }: { error?: LeadCatalogState["error"] }) {
  const t = useTranslations("crm.errors");
  if (!error) return null;
  return (
    <p className="text-sm text-red-700" role="alert">
      {t(error)}
    </p>
  );
}

export function CrmSettingsView({ sources, campaigns, lostReasons }: Props) {
  const t = useTranslations("crm.settings");

  return (
    <div className="space-y-8">
      <CatalogSection
        title={t("sourcesTitle")}
        empty={t("emptySources")}
        items={sources.map((s) => ({
          id: s.id,
          label: s.displayName,
          code: s.code,
          status: s.status,
        }))}
        renderCreate={(state, action, pending) => (
          <form action={action} className="mt-4 grid gap-3 sm:grid-cols-4">
            <CatalogError error={state.error} />
            {state.success ? (
              <p className="sm:col-span-4 text-sm text-green-700" role="status">
                {t("saved")}
              </p>
            ) : null}
            <input name="code" required placeholder={t("code")} className="rounded border px-3 py-2 text-sm" />
            <input
              name="displayName"
              required
              placeholder={t("displayName")}
              className="rounded border px-3 py-2 text-sm sm:col-span-2"
            />
            <button
              type="submit"
              disabled={pending}
              className="rounded bg-slate-900 px-3 py-2 text-sm text-white disabled:opacity-60"
            >
              {t("addSource")}
            </button>
          </form>
        )}
        createAction={upsertLeadSourceCatalogAction}
        renderEdit={(item, state, action, pending) => (
          <form action={action} className="flex flex-wrap items-end gap-2">
            <input type="hidden" name="id" value={item.id} />
            <input type="hidden" name="code" value={item.code} />
            <input
              name="displayName"
              defaultValue={item.label}
              required
              className="min-w-[10rem] rounded border px-2 py-1 text-sm"
            />
            <select name="status" defaultValue={item.status} className="rounded border px-2 py-1 text-sm">
              <option value="active">{t("statusActive")}</option>
              <option value="inactive">{t("statusInactive")}</option>
            </select>
            <button type="submit" disabled={pending} className="text-sm underline">
              {t("save")}
            </button>
            <CatalogError error={state.error} />
          </form>
        )}
        editAction={upsertLeadSourceCatalogAction}
      />

      <CatalogSection
        title={t("campaignsTitle")}
        empty={t("emptyCampaigns")}
        items={campaigns.map((c) => ({
          id: c.id,
          label: c.name,
          code: c.code,
          status: c.status,
        }))}
        renderCreate={(state, action, pending) => (
          <form action={action} className="mt-4 grid gap-3 sm:grid-cols-4">
            <CatalogError error={state.error} />
            <input name="code" required placeholder={t("code")} className="rounded border px-3 py-2 text-sm" />
            <input name="name" required placeholder={t("name")} className="rounded border px-3 py-2 text-sm" />
            <button
              type="submit"
              disabled={pending}
              className="rounded bg-slate-900 px-3 py-2 text-sm text-white disabled:opacity-60"
            >
              {t("addCampaign")}
            </button>
          </form>
        )}
        createAction={upsertLeadCampaignCatalogAction}
        renderEdit={(item, state, action, pending) => (
          <form action={action} className="flex flex-wrap items-end gap-2">
            <input type="hidden" name="id" value={item.id} />
            <input type="hidden" name="code" value={item.code} />
            <input
              name="name"
              defaultValue={item.label}
              required
              className="min-w-[10rem] rounded border px-2 py-1 text-sm"
            />
            <select name="status" defaultValue={item.status} className="rounded border px-2 py-1 text-sm">
              <option value="active">{t("statusActive")}</option>
              <option value="inactive">{t("statusInactive")}</option>
              <option value="archived">{t("statusArchived")}</option>
            </select>
            <button type="submit" disabled={pending} className="text-sm underline">
              {t("save")}
            </button>
            <CatalogError error={state.error} />
          </form>
        )}
        editAction={upsertLeadCampaignCatalogAction}
      />

      <CatalogSection
        title={t("lostReasonsTitle")}
        empty={t("emptyLostReasons")}
        items={lostReasons.map((r) => ({
          id: r.id,
          label: r.displayName,
          code: r.code,
          status: r.status,
        }))}
        renderCreate={(state, action, pending) => (
          <form action={action} className="mt-4 grid gap-3 sm:grid-cols-4">
            <CatalogError error={state.error} />
            <input name="code" required placeholder={t("code")} className="rounded border px-3 py-2 text-sm" />
            <input
              name="displayName"
              required
              placeholder={t("displayName")}
              className="rounded border px-3 py-2 text-sm sm:col-span-2"
            />
            <button
              type="submit"
              disabled={pending}
              className="rounded bg-slate-900 px-3 py-2 text-sm text-white disabled:opacity-60"
            >
              {t("addLostReason")}
            </button>
          </form>
        )}
        createAction={upsertLeadLostReasonCatalogAction}
        renderEdit={(item, state, action, pending) => (
          <form action={action} className="flex flex-wrap items-end gap-2">
            <input type="hidden" name="id" value={item.id} />
            <input type="hidden" name="code" value={item.code} />
            <input
              name="displayName"
              defaultValue={item.label}
              required
              className="min-w-[10rem] rounded border px-2 py-1 text-sm"
            />
            <select name="status" defaultValue={item.status} className="rounded border px-2 py-1 text-sm">
              <option value="active">{t("statusActive")}</option>
              <option value="inactive">{t("statusInactive")}</option>
            </select>
            <button type="submit" disabled={pending} className="text-sm underline">
              {t("save")}
            </button>
            <CatalogError error={state.error} />
          </form>
        )}
        editAction={upsertLeadLostReasonCatalogAction}
      />
    </div>
  );
}

type CatalogItem = { id: string; label: string; code: string; status: string };

type CatalogEditRenderer = (
  item: CatalogItem,
  state: LeadCatalogState,
  action: (payload: FormData) => void,
  pending: boolean,
) => React.ReactElement | null;

type CatalogCreateRenderer = (
  state: LeadCatalogState,
  action: (payload: FormData) => void,
  pending: boolean,
) => React.ReactElement | null;

function CatalogSection({
  title,
  empty,
  items,
  renderCreate,
  createAction,
  renderEdit,
  editAction,
}: {
  title: string;
  empty: string;
  items: CatalogItem[];
  renderCreate: CatalogCreateRenderer;
  createAction: typeof upsertLeadSourceCatalogAction;
  renderEdit: CatalogEditRenderer;
  editAction: typeof upsertLeadSourceCatalogAction;
}) {
  const [createState, createFormAction, createPending] = useActionState(createAction, initialState);

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-base font-semibold text-slate-900">{title}</h2>
      {items.length === 0 ? <p className="mt-2 text-sm text-slate-500">{empty}</p> : null}
      <ul className="mt-3 space-y-3">
        {items.map((item) => (
          <CatalogRow key={item.id} item={item} renderEdit={renderEdit} editAction={editAction} />
        ))}
      </ul>
      {renderCreate(createState, createFormAction, createPending)}
    </section>
  );
}

function CatalogRow({
  item,
  renderEdit,
  editAction,
}: {
  item: CatalogItem;
  renderEdit: CatalogEditRenderer;
  editAction: typeof upsertLeadSourceCatalogAction;
}) {
  const [state, action, pending] = useActionState(editAction, initialState);
  return (
    <li className="border-b border-slate-100 pb-3 last:border-0">
      <div className="text-xs text-slate-500">{item.code}</div>
      {renderEdit(item, state, action, pending)}
    </li>
  );
}
