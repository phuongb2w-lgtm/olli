"use client";

import Link from "next/link";
import { useActionState, useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import {
  createLeadWithPeopleAction,
  type LeadIntakeState,
} from "@/app/actions/leads";
import { LEAD_CONTACT_RELATIONSHIPS } from "@/lib/leads/constants";
import type { EligibleAssignee } from "@/lib/leads/query-eligible-assignees";
import {
  activeCatalogItems,
  type LeadCatalogCampaign,
  type LeadCatalogSource,
} from "@/lib/leads/query-lead-catalogs";

type CandidateDraft = {
  givenName: string;
  familyName: string;
  dateOfBirth: string;
  isPrimary: boolean;
};

type ContactDraft = {
  givenName: string;
  familyName: string;
  phone: string;
  email: string;
  relationshipType: string;
  isPrimary: boolean;
};

type Props = {
  sources: LeadCatalogSource[];
  campaigns: LeadCatalogCampaign[];
  assignees: EligibleAssignee[];
  canAssign: boolean;
};

const initialState: LeadIntakeState = {};

const emptyCandidate = (): CandidateDraft => ({
  givenName: "",
  familyName: "",
  dateOfBirth: "",
  isPrimary: false,
});

const emptyContact = (): ContactDraft => ({
  givenName: "",
  familyName: "",
  phone: "",
  email: "",
  relationshipType: "guardian",
  isPrimary: false,
});

function ErrorMessage({ error }: { error?: LeadIntakeState["error"] }) {
  const t = useTranslations("crm.errors");
  if (!error) return null;
  return (
    <p className="text-sm text-red-700" role="alert">
      {t(error)}
    </p>
  );
}

export function LeadIntakeForm({ sources, campaigns, assignees, canAssign }: Props) {
  const t = useTranslations("crm.intake");
  const tRel = useTranslations("crm.intake.relationship");
  const [state, formAction, pending] = useActionState(createLeadWithPeopleAction, initialState);

  const [notesSummary, setNotesSummary] = useState("");
  const [sourceId, setSourceId] = useState("");
  const [campaignId, setCampaignId] = useState("");
  const [candidates, setCandidates] = useState<CandidateDraft[]>([emptyCandidate()]);
  const [contacts, setContacts] = useState<ContactDraft[]>([emptyContact()]);
  const [assignAfter, setAssignAfter] = useState(false);
  const [assignedUserId, setAssignedUserId] = useState("");

  const activeSources = useMemo(() => activeCatalogItems(sources), [sources]);
  const activeCampaigns = useMemo(() => activeCatalogItems(campaigns), [campaigns]);

  const payload = useMemo(
    () =>
      JSON.stringify({
        lead: {
          notes_summary: notesSummary || null,
          lead_source_id: sourceId || null,
          lead_campaign_id: campaignId || null,
        },
        candidates: candidates.map((c) => ({
          given_name: c.givenName,
          family_name: c.familyName,
          date_of_birth: c.dateOfBirth || undefined,
          is_primary_candidate: c.isPrimary,
        })),
        contacts: contacts.map((c) => ({
          given_name: c.givenName,
          family_name: c.familyName,
          phone: c.phone || undefined,
          email: c.email || undefined,
          relationship_type: c.relationshipType,
          is_primary_contact: c.isPrimary,
          is_billing_contact: c.isPrimary,
        })),
      }),
    [notesSummary, sourceId, campaignId, candidates, contacts],
  );

  return (
    <form action={formAction} className="space-y-6">
      <input type="hidden" name="payload" value={payload} />
      <input type="hidden" name="assignAfter" value={assignAfter ? "true" : "false"} />

      {state.error ? <ErrorMessage error={state.error} /> : null}
      {state.assignError && state.leadId ? (
        <div className="rounded border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900" role="alert">
          <p>{t("assignAfterFailed")}</p>
          <Link href={`/crm/leads/${state.leadId}`} className="font-medium underline">
            {t("viewCreatedLead")}
          </Link>
        </div>
      ) : null}

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <h2 className="text-base font-semibold text-slate-900">{t("leadSection")}</h2>
        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="intake-source" className="mb-1 block text-sm font-medium text-slate-700">
              {t("source")}
            </label>
            <select
              id="intake-source"
              value={sourceId}
              onChange={(e) => setSourceId(e.target.value)}
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
            <label htmlFor="intake-campaign" className="mb-1 block text-sm font-medium text-slate-700">
              {t("campaign")}
            </label>
            <select
              id="intake-campaign"
              value={campaignId}
              onChange={(e) => setCampaignId(e.target.value)}
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
            <label htmlFor="intake-notes" className="mb-1 block text-sm font-medium text-slate-700">
              {t("notes")}
            </label>
            <textarea
              id="intake-notes"
              value={notesSummary}
              onChange={(e) => setNotesSummary(e.target.value)}
              rows={3}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
        </div>
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-base font-semibold text-slate-900">{t("candidatesSection")}</h2>
          <button
            type="button"
            onClick={() => setCandidates((prev) => [...prev, emptyCandidate()])}
            className="text-sm font-medium text-slate-700 underline"
          >
            {t("addCandidate")}
          </button>
        </div>
        <div className="mt-4 space-y-4">
          {candidates.map((candidate, index) => (
            <div key={index} className="rounded border border-slate-100 p-3">
              <p className="text-sm font-medium text-slate-700">{t("candidateLabel", { index: index + 1 })}</p>
              <div className="mt-2 grid gap-3 sm:grid-cols-2">
                <div>
                  <label htmlFor={`candidate-given-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("givenName")} *
                  </label>
                  <input
                    id={`candidate-given-${index}`}
                    required
                    value={candidate.givenName}
                    onChange={(e) =>
                      setCandidates((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, givenName: e.target.value } : row)),
                      )
                    }
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label htmlFor={`candidate-family-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("familyName")} *
                  </label>
                  <input
                    id={`candidate-family-${index}`}
                    required
                    value={candidate.familyName}
                    onChange={(e) =>
                      setCandidates((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, familyName: e.target.value } : row)),
                      )
                    }
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label htmlFor={`candidate-dob-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("dateOfBirth")}
                  </label>
                  <input
                    id={`candidate-dob-${index}`}
                    type="date"
                    value={candidate.dateOfBirth}
                    onChange={(e) =>
                      setCandidates((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, dateOfBirth: e.target.value } : row)),
                      )
                    }
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div className="flex items-end">
                  <label className="flex items-center gap-2 text-sm text-slate-700">
                    <input
                      type="checkbox"
                      checked={candidate.isPrimary}
                      onChange={(e) =>
                        setCandidates((prev) =>
                          prev.map((row, i) =>
                            i === index
                              ? { ...row, isPrimary: e.target.checked }
                              : e.target.checked
                                ? { ...row, isPrimary: false }
                                : row,
                          ),
                        )
                      }
                    />
                    {t("primaryCandidate")}
                  </label>
                </div>
              </div>
              {candidates.length > 1 ? (
                <button
                  type="button"
                  onClick={() => setCandidates((prev) => prev.filter((_, i) => i !== index))}
                  className="mt-2 text-sm text-red-700 underline"
                >
                  {t("remove")}
                </button>
              ) : null}
            </div>
          ))}
        </div>
      </section>

      <section className="rounded-lg border border-slate-200 bg-white p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-base font-semibold text-slate-900">{t("contactsSection")}</h2>
          <button
            type="button"
            onClick={() => setContacts((prev) => [...prev, emptyContact()])}
            className="text-sm font-medium text-slate-700 underline"
          >
            {t("addContact")}
          </button>
        </div>
        <div className="mt-4 space-y-4">
          {contacts.map((contact, index) => (
            <div key={index} className="rounded border border-slate-100 p-3">
              <p className="text-sm font-medium text-slate-700">{t("contactLabel", { index: index + 1 })}</p>
              <div className="mt-2 grid gap-3 sm:grid-cols-2">
                <div>
                  <label htmlFor={`contact-given-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("givenName")} *
                  </label>
                  <input
                    id={`contact-given-${index}`}
                    required
                    value={contact.givenName}
                    onChange={(e) =>
                      setContacts((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, givenName: e.target.value } : row)),
                      )
                    }
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label htmlFor={`contact-family-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("familyName")} *
                  </label>
                  <input
                    id={`contact-family-${index}`}
                    required
                    value={contact.familyName}
                    onChange={(e) =>
                      setContacts((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, familyName: e.target.value } : row)),
                      )
                    }
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label htmlFor={`contact-phone-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("phone")}
                  </label>
                  <input
                    id={`contact-phone-${index}`}
                    type="tel"
                    value={contact.phone}
                    onChange={(e) =>
                      setContacts((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, phone: e.target.value } : row)),
                      )
                    }
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label htmlFor={`contact-email-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("email")}
                  </label>
                  <input
                    id={`contact-email-${index}`}
                    type="email"
                    value={contact.email}
                    onChange={(e) =>
                      setContacts((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, email: e.target.value } : row)),
                      )
                    }
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label htmlFor={`contact-rel-${index}`} className="mb-1 block text-sm text-slate-600">
                    {t("relationshipLabel")}
                  </label>
                  <select
                    id={`contact-rel-${index}`}
                    value={contact.relationshipType}
                    onChange={(e) =>
                      setContacts((prev) =>
                        prev.map((row, i) => (i === index ? { ...row, relationshipType: e.target.value } : row)),
                      )
                    }
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
                      checked={contact.isPrimary}
                      onChange={(e) =>
                        setContacts((prev) =>
                          prev.map((row, i) =>
                            i === index
                              ? { ...row, isPrimary: e.target.checked }
                              : e.target.checked
                                ? { ...row, isPrimary: false }
                                : row,
                          ),
                        )
                      }
                    />
                    {t("primaryContact")}
                  </label>
                </div>
              </div>
              {contacts.length > 1 ? (
                <button
                  type="button"
                  onClick={() => setContacts((prev) => prev.filter((_, i) => i !== index))}
                  className="mt-2 text-sm text-red-700 underline"
                >
                  {t("remove")}
                </button>
              ) : null}
            </div>
          ))}
        </div>
      </section>

      {canAssign ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4">
          <label className="flex items-center gap-2 text-sm text-slate-800">
            <input
              type="checkbox"
              checked={assignAfter}
              onChange={(e) => setAssignAfter(e.target.checked)}
            />
            {t("assignAfterCreate")}
          </label>
          {assignAfter ? (
            <div className="mt-3">
              <label htmlFor="intake-assignee" className="mb-1 block text-sm font-medium text-slate-700">
                {t("assignee")}
              </label>
              <select
                id="intake-assignee"
                name="assignedUserId"
                value={assignedUserId}
                onChange={(e) => setAssignedUserId(e.target.value)}
                required={assignAfter}
                className="w-full max-w-md rounded border border-slate-300 px-3 py-2 text-sm"
              >
                <option value="">{t("selectAssignee")}</option>
                {assignees.map((user) => (
                  <option key={user.userId} value={user.userId}>
                    {user.displayName}
                  </option>
                ))}
              </select>
            </div>
          ) : null}
        </section>
      ) : null}

      <div className="flex flex-wrap gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
        >
          {pending ? t("saving") : t("saveLead")}
        </button>
        <Link
          href="/crm/leads"
          className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
        >
          {t("cancel")}
        </Link>
      </div>
    </form>
  );
}
