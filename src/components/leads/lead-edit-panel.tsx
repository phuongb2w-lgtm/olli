"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  updateLeadCandidateAction,
  updateLeadContactAction,
  updateLeadOperationalAction,
  type LeadMutationState,
} from "@/app/actions/leads";
import { LEAD_CONTACT_RELATIONSHIPS, type LeadStatus } from "@/lib/leads/constants";
import type {
  LeadCandidateDetail,
  LeadContactDetail,
} from "@/lib/leads/query-lead-detail";
import {
  activeCatalogItems,
  type LeadCatalogCampaign,
  type LeadCatalogSource,
} from "@/lib/leads/query-lead-catalogs";

type Props = {
  leadId: string;
  status: LeadStatus;
  notesSummary: string | null;
  leadSourceId: string | null;
  leadCampaignId: string | null;
  candidates: LeadCandidateDetail[];
  contacts: LeadContactDetail[];
  sources: LeadCatalogSource[];
  campaigns: LeadCatalogCampaign[];
  canUpdate: boolean;
};

const initialState: LeadMutationState = {};

function ErrorMessage({ error }: { error?: LeadMutationState["error"] }) {
  const t = useTranslations("crm.errors");
  if (!error) return null;
  return (
    <p className="text-sm text-red-700" role="alert">
      {t(error)}
    </p>
  );
}

export function LeadEditPanel({
  leadId,
  status,
  notesSummary,
  leadSourceId,
  leadCampaignId,
  candidates,
  contacts,
  sources,
  campaigns,
  canUpdate,
}: Props) {
  const t = useTranslations("crm.intake");
  const isConverted = status === "converted";

  const [operationalState, operationalAction, operationalPending] = useActionState(
    updateLeadOperationalAction,
    initialState,
  );

  if (!canUpdate) return null;

  const activeSources = activeCatalogItems(sources);
  const activeCampaigns = activeCatalogItems(campaigns);

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-base font-semibold text-slate-900">{t("editSection")}</h2>
      {isConverted ? (
        <p className="mt-2 text-sm text-slate-600">{t("convertedReadOnlyHint")}</p>
      ) : (
        <>
          <form action={operationalAction} className="mt-4 space-y-4">
            <input type="hidden" name="leadId" value={leadId} />
            <ErrorMessage error={operationalState.error} />
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <label htmlFor="edit-source" className="mb-1 block text-sm font-medium text-slate-700">
                  {t("source")}
                </label>
                <select
                  id="edit-source"
                  name="leadSourceId"
                  defaultValue={leadSourceId ?? ""}
                  className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                >
                  <option value="">{t("sourceOptional")}</option>
                  {activeSources.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.displayName}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="edit-campaign" className="mb-1 block text-sm font-medium text-slate-700">
                  {t("campaign")}
                </label>
                <select
                  id="edit-campaign"
                  name="leadCampaignId"
                  defaultValue={leadCampaignId ?? ""}
                  className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                >
                  <option value="">{t("campaignOptional")}</option>
                  {activeCampaigns.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
              </div>
              <div className="sm:col-span-2">
                <label htmlFor="edit-notes" className="mb-1 block text-sm font-medium text-slate-700">
                  {t("notes")}
                </label>
                <textarea
                  id="edit-notes"
                  name="notesSummary"
                  defaultValue={notesSummary ?? ""}
                  rows={3}
                  className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                />
              </div>
            </div>
            <button
              type="submit"
              disabled={operationalPending}
              className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
            >
              {operationalPending ? t("saving") : t("saveLeadDetails")}
            </button>
          </form>

          <div className="mt-6 space-y-4">
            {candidates.map((candidate) => (
              <CandidateEditForm key={candidate.id} leadId={leadId} candidate={candidate} />
            ))}
            {contacts.map((contact) => (
              <ContactEditForm key={contact.id} leadId={leadId} contact={contact} />
            ))}
          </div>
        </>
      )}
    </section>
  );
}

function CandidateEditForm({
  leadId,
  candidate,
}: {
  leadId: string;
  candidate: LeadCandidateDetail;
}) {
  const t = useTranslations("crm.intake");
  const [state, action, pending] = useActionState(updateLeadCandidateAction, initialState);

  return (
    <form action={action} className="rounded border border-slate-100 p-3">
      <p className="text-sm font-medium text-slate-800">{t("editCandidate")}</p>
      <input type="hidden" name="leadId" value={leadId} />
      <input type="hidden" name="candidateId" value={candidate.id} />
      <ErrorMessage error={state.error} />
      <div className="mt-2 grid gap-3 sm:grid-cols-2">
        <div>
          <label htmlFor={`edit-cand-given-${candidate.id}`} className="mb-1 block text-sm text-slate-600">
            {t("givenName")}
          </label>
          <input
            id={`edit-cand-given-${candidate.id}`}
            name="givenName"
            defaultValue={candidate.givenName}
            required
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`edit-cand-family-${candidate.id}`} className="mb-1 block text-sm text-slate-600">
            {t("familyName")}
          </label>
          <input
            id={`edit-cand-family-${candidate.id}`}
            name="familyName"
            defaultValue={candidate.familyName}
            required
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`edit-cand-dob-${candidate.id}`} className="mb-1 block text-sm text-slate-600">
            {t("dateOfBirth")}
          </label>
          <input
            id={`edit-cand-dob-${candidate.id}`}
            name="dateOfBirth"
            type="date"
            defaultValue={candidate.dateOfBirth ?? ""}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div className="flex items-end">
          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input
              type="checkbox"
              name="isPrimaryCandidate"
              value="true"
              defaultChecked={candidate.isPrimaryCandidate}
            />
            {t("primaryCandidate")}
          </label>
        </div>
      </div>
      <button
        type="submit"
        disabled={pending}
        className="mt-3 rounded border border-slate-300 px-3 py-1.5 text-sm text-slate-800 hover:bg-slate-50 disabled:opacity-60"
      >
        {pending ? t("saving") : t("saveCandidate")}
      </button>
    </form>
  );
}

function ContactEditForm({
  leadId,
  contact,
}: {
  leadId: string;
  contact: LeadContactDetail;
}) {
  const t = useTranslations("crm.intake");
  const tRel = useTranslations("crm.intake.relationship");
  const [state, action, pending] = useActionState(updateLeadContactAction, initialState);

  return (
    <form action={action} className="rounded border border-slate-100 p-3">
      <p className="text-sm font-medium text-slate-800">{t("editContact")}</p>
      <input type="hidden" name="leadId" value={leadId} />
      <input type="hidden" name="contactId" value={contact.id} />
      <ErrorMessage error={state.error} />
      <div className="mt-2 grid gap-3 sm:grid-cols-2">
        <div>
          <label htmlFor={`edit-contact-given-${contact.id}`} className="mb-1 block text-sm text-slate-600">
            {t("givenName")}
          </label>
          <input
            id={`edit-contact-given-${contact.id}`}
            name="givenName"
            defaultValue={contact.givenName}
            required
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`edit-contact-family-${contact.id}`} className="mb-1 block text-sm text-slate-600">
            {t("familyName")}
          </label>
          <input
            id={`edit-contact-family-${contact.id}`}
            name="familyName"
            defaultValue={contact.familyName}
            required
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`edit-contact-phone-${contact.id}`} className="mb-1 block text-sm text-slate-600">
            {t("phone")}
          </label>
          <input
            id={`edit-contact-phone-${contact.id}`}
            name="phone"
            type="tel"
            defaultValue={contact.phone ?? ""}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`edit-contact-email-${contact.id}`} className="mb-1 block text-sm text-slate-600">
            {t("email")}
          </label>
          <input
            id={`edit-contact-email-${contact.id}`}
            name="email"
            type="email"
            defaultValue={contact.email ?? ""}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`edit-contact-rel-${contact.id}`} className="mb-1 block text-sm text-slate-600">
            {t("relationshipLabel")}
          </label>
          <select
            id={`edit-contact-rel-${contact.id}`}
            name="relationshipType"
            defaultValue={contact.relationshipType}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          >
            {LEAD_CONTACT_RELATIONSHIPS.map((rel) => (
              <option key={rel} value={rel}>
                {tRel(rel)}
              </option>
            ))}
          </select>
        </div>
        <div className="flex items-end">
          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input
              type="checkbox"
              name="isPrimaryContact"
              value="true"
              defaultChecked={contact.isPrimaryContact}
            />
            {t("primaryContact")}
          </label>
        </div>
      </div>
      <button
        type="submit"
        disabled={pending}
        className="mt-3 rounded border border-slate-300 px-3 py-1.5 text-sm text-slate-800 hover:bg-slate-50 disabled:opacity-60"
      >
        {pending ? t("saving") : t("saveContact")}
      </button>
    </form>
  );
}
