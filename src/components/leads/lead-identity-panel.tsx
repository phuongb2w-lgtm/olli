"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  clearLeadCandidateIdentityAction,
  clearLeadContactIdentityAction,
  resolveLeadCandidateIdentityAction,
  resolveLeadContactIdentityAction,
  type LeadMutationState,
} from "@/app/actions/leads";
import type { LeadCandidateDetail, LeadContactDetail } from "@/lib/leads/query-lead-detail";
import type { LeadIdentityBundle } from "@/lib/leads/query-lead-identity";

type Props = {
  leadId: string;
  candidates: LeadCandidateDetail[];
  contacts: LeadContactDetail[];
  identity: LeadIdentityBundle;
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

function MatchReasonList({ reasons }: { reasons: string[] }) {
  const t = useTranslations("crm.identity.matchReason");
  if (reasons.length === 0) return null;
  return (
    <ul className="mt-1 list-inside list-disc text-xs text-slate-600">
      {reasons.map((reason) => (
        <li key={reason}>{t(reason as "same_name_and_dob")}</li>
      ))}
    </ul>
  );
}

function ResolutionBadge({
  mode,
  isStale,
}: {
  mode: "use_existing" | "create_new" | null;
  isStale: boolean;
}) {
  const t = useTranslations("crm.identity");
  if (isStale) {
    return (
      <span className="rounded bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-900">
        {t("staleReviewRequired")}
      </span>
    );
  }
  if (!mode) {
    return (
      <span className="rounded bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700">
        {t("unresolved")}
      </span>
    );
  }
  if (mode === "use_existing") {
    return (
      <span className="rounded bg-green-50 px-2 py-0.5 text-xs font-medium text-green-800">
        {t("useExisting")}
      </span>
    );
  }
  return (
    <span className="rounded bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-800">
      {t("createNew")}
    </span>
  );
}

function CandidateIdentityCard({
  leadId,
  candidate,
  identity,
  canUpdate,
}: {
  leadId: string;
  candidate: LeadCandidateDetail;
  identity: LeadIdentityBundle;
  canUpdate: boolean;
}) {
  const t = useTranslations("crm.identity");
  const [state, action, pending] = useActionState(resolveLeadCandidateIdentityAction, initialState);
  const [clearState, clearAction, clearPending] = useActionState(
    clearLeadCandidateIdentityAction,
    initialState,
  );

  const resolution = identity.candidateResolutions[candidate.id];
  const matches = identity.candidateMatches[candidate.id] ?? [];
  const hasStrongMatch = matches.some((m) => m.confidence === "strong");
  const mode = resolution?.resolutionMode ?? null;

  return (
    <li className="rounded border border-slate-100 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium text-slate-900">{candidate.displayName}</span>
        <ResolutionBadge mode={mode} isStale={resolution?.isStale ?? false} />
      </div>

      {mode === "use_existing" && resolution?.studentDisplayName ? (
        <p className="mt-2 text-sm text-slate-700">
          {t("selectedStudent")}: {resolution.studentDisplayName}
        </p>
      ) : null}

      {matches.length > 0 ? (
        <div className="mt-3">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">
            {t("possibleMatches")}
          </p>
          <ul className="mt-2 space-y-2">
            {matches.map((match) => (
              <li key={match.studentId} className="rounded bg-slate-50 p-2 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium text-slate-900">{match.displayName}</span>
                  <span className="text-xs text-slate-600">
                    {match.confidence === "strong" ? t("strongMatch") : t("possibleMatch")}
                  </span>
                </div>
                <MatchReasonList reasons={match.matchReasons} />
                {canUpdate ? (
                  <form action={action} className="mt-2">
                    <input type="hidden" name="leadId" value={leadId} />
                    <input type="hidden" name="candidateId" value={candidate.id} />
                    <input type="hidden" name="resolutionMode" value="use_existing" />
                    <input type="hidden" name="studentId" value={match.studentId} />
                    <button
                      type="submit"
                      disabled={pending}
                      className="text-xs font-medium text-slate-900 underline hover:no-underline disabled:opacity-50"
                    >
                      {t("useExisting")}
                    </button>
                  </form>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      ) : (
        <p className="mt-2 text-sm text-slate-500">{t("noMatches")}</p>
      )}

      {canUpdate ? (
        <div className="mt-3 space-y-2">
          {hasStrongMatch ? (
            <p className="text-sm text-amber-800">{t("duplicateWarning")}</p>
          ) : null}
          <form action={action} className="flex flex-wrap items-center gap-2">
            <input type="hidden" name="leadId" value={leadId} />
            <input type="hidden" name="candidateId" value={candidate.id} />
            <input type="hidden" name="resolutionMode" value="create_new" />
            {hasStrongMatch ? (
              <label className="flex items-center gap-2 text-sm text-slate-700">
                <input type="checkbox" name="acknowledgeStrongMatch" value="true" />
                {t("acknowledgeStrongMatch")}
              </label>
            ) : null}
            <button
              type="submit"
              disabled={pending}
              className="rounded border border-slate-300 px-3 py-1 text-sm text-slate-800 hover:bg-slate-50 disabled:opacity-50"
            >
              {t("createNewAtConversion")}
            </button>
          </form>
          {mode ? (
            <form action={clearAction}>
              <input type="hidden" name="leadId" value={leadId} />
              <input type="hidden" name="candidateId" value={candidate.id} />
              <button
                type="submit"
                disabled={clearPending}
                className="text-xs text-slate-600 underline hover:no-underline disabled:opacity-50"
              >
                {t("resetResolution")}
              </button>
            </form>
          ) : null}
          <ErrorMessage error={state.error ?? clearState.error} />
        </div>
      ) : null}
    </li>
  );
}

function ContactIdentityCard({
  leadId,
  contact,
  identity,
  canUpdate,
}: {
  leadId: string;
  contact: LeadContactDetail;
  identity: LeadIdentityBundle;
  canUpdate: boolean;
}) {
  const t = useTranslations("crm.identity");
  const [state, action, pending] = useActionState(resolveLeadContactIdentityAction, initialState);
  const [clearState, clearAction, clearPending] = useActionState(
    clearLeadContactIdentityAction,
    initialState,
  );

  const resolution = identity.contactResolutions[contact.id];
  const matches = identity.contactMatches[contact.id] ?? [];
  const hasStrongMatch = matches.some((m) => m.confidence === "strong");
  const mode = resolution?.resolutionMode ?? null;

  return (
    <li className="rounded border border-slate-100 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium text-slate-900">{contact.displayName}</span>
        <ResolutionBadge mode={mode} isStale={resolution?.isStale ?? false} />
      </div>

      {mode === "use_existing" && resolution?.guardianDisplayName ? (
        <p className="mt-2 text-sm text-slate-700">
          {t("selectedGuardian")}: {resolution.guardianDisplayName}
        </p>
      ) : null}

      {matches.length > 0 ? (
        <div className="mt-3">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-500">
            {t("possibleMatches")}
          </p>
          <ul className="mt-2 space-y-2">
            {matches.map((match) => (
              <li key={match.guardianId} className="rounded bg-slate-50 p-2 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium text-slate-900">{match.displayName}</span>
                  <span className="text-xs text-slate-600">
                    {match.confidence === "strong" ? t("strongMatch") : t("possibleMatch")}
                  </span>
                </div>
                <MatchReasonList reasons={match.matchReasons} />
                {canUpdate ? (
                  <form action={action} className="mt-2">
                    <input type="hidden" name="leadId" value={leadId} />
                    <input type="hidden" name="contactId" value={contact.id} />
                    <input type="hidden" name="resolutionMode" value="use_existing" />
                    <input type="hidden" name="guardianId" value={match.guardianId} />
                    <button
                      type="submit"
                      disabled={pending}
                      className="text-xs font-medium text-slate-900 underline hover:no-underline disabled:opacity-50"
                    >
                      {t("useExisting")}
                    </button>
                  </form>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      ) : (
        <p className="mt-2 text-sm text-slate-500">{t("noMatches")}</p>
      )}

      {canUpdate ? (
        <div className="mt-3 space-y-2">
          {hasStrongMatch ? (
            <p className="text-sm text-amber-800">{t("duplicateWarning")}</p>
          ) : null}
          <form action={action} className="flex flex-wrap items-center gap-2">
            <input type="hidden" name="leadId" value={leadId} />
            <input type="hidden" name="contactId" value={contact.id} />
            <input type="hidden" name="resolutionMode" value="create_new" />
            {hasStrongMatch ? (
              <label className="flex items-center gap-2 text-sm text-slate-700">
                <input type="checkbox" name="acknowledgeStrongMatch" value="true" />
                {t("acknowledgeStrongMatch")}
              </label>
            ) : null}
            <button
              type="submit"
              disabled={pending}
              className="rounded border border-slate-300 px-3 py-1 text-sm text-slate-800 hover:bg-slate-50 disabled:opacity-50"
            >
              {t("createNewAtConversion")}
            </button>
          </form>
          {mode ? (
            <form action={clearAction}>
              <input type="hidden" name="leadId" value={leadId} />
              <input type="hidden" name="contactId" value={contact.id} />
              <button
                type="submit"
                disabled={clearPending}
                className="text-xs text-slate-600 underline hover:no-underline disabled:opacity-50"
              >
                {t("resetResolution")}
              </button>
            </form>
          ) : null}
          <ErrorMessage error={state.error ?? clearState.error} />
        </div>
      ) : null}
    </li>
  );
}

export function LeadIdentityPanel({ leadId, candidates, contacts, identity, canUpdate }: Props) {
  const t = useTranslations("crm.identity");

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <div className="flex flex-wrap items-center gap-3">
        <h2 className="text-base font-semibold text-slate-900">{t("title")}</h2>
        {identity.readiness.ready ? (
          <span className="rounded bg-green-50 px-2 py-0.5 text-xs font-medium text-green-800">
            {t("readyForConversion")}
          </span>
        ) : (
          <span className="rounded bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-900">
            {t("notReady")}
          </span>
        )}
      </div>
      <p className="mt-2 text-sm text-slate-600">{t("intro")}</p>

      <div className="mt-4 grid gap-6 lg:grid-cols-2">
        <div>
          <h3 className="text-sm font-semibold text-slate-800">{t("candidatesSection")}</h3>
          <ul className="mt-2 space-y-3">
            {candidates.map((candidate) => (
              <CandidateIdentityCard
                key={candidate.id}
                leadId={leadId}
                candidate={candidate}
                identity={identity}
                canUpdate={canUpdate}
              />
            ))}
            {candidates.length === 0 ? (
              <li className="text-sm text-slate-500">{t("emptyCandidates")}</li>
            ) : null}
          </ul>
        </div>
        <div>
          <h3 className="text-sm font-semibold text-slate-800">{t("contactsSection")}</h3>
          <ul className="mt-2 space-y-3">
            {contacts.map((contact) => (
              <ContactIdentityCard
                key={contact.id}
                leadId={leadId}
                contact={contact}
                identity={identity}
                canUpdate={canUpdate}
              />
            ))}
            {contacts.length === 0 ? (
              <li className="text-sm text-slate-500">{t("emptyContacts")}</li>
            ) : null}
          </ul>
        </div>
      </div>

      {identity.events.length > 0 ? (
        <div className="mt-6">
          <h3 className="text-sm font-semibold text-slate-800">{t("historyTitle")}</h3>
          <ul className="mt-2 space-y-2 text-sm text-slate-700">
            {identity.events.slice(0, 8).map((event) => (
              <li key={event.id}>
                <span className="text-slate-500">{new Date(event.changedAt).toLocaleString()}</span>
                {" — "}
                {event.previousResolutionMode ?? t("unresolved")} →{" "}
                {event.newResolutionMode ?? t("unresolved")}
                {event.changedByName ? ` (${event.changedByName})` : ""}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  );
}
