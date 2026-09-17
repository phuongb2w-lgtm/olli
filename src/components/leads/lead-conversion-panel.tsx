"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { convertLeadAction, type LeadMutationState } from "@/app/actions/leads";
import type { EligibleTrialClass } from "@/lib/leads/query-eligible-trial-classes";
import type { LeadCandidateDetail, LeadContactDetail } from "@/lib/leads/query-lead-detail";
import type { LeadIdentityBundle } from "@/lib/leads/query-lead-identity";
import type { LeadConversionDetail } from "@/lib/leads/query-lead-conversion";

type Props = {
  leadId: string;
  status: string;
  candidates: LeadCandidateDetail[];
  contacts: LeadContactDetail[];
  identity: LeadIdentityBundle;
  conversion: LeadConversionDetail | null;
  eligibleClasses: EligibleTrialClass[];
  canConvert: boolean;
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

export function LeadConversionPanel({
  leadId,
  status,
  candidates,
  contacts,
  identity,
  conversion,
  eligibleClasses,
  canConvert,
}: Props) {
  const t = useTranslations("crm.conversion");
  const tIdentity = useTranslations("crm.identity");
  const [state, formAction, pending] = useActionState(convertLeadAction, initialState);

  const isConverted = status === "converted";
  const canShowForm =
    canConvert &&
    !isConverted &&
    status !== "lost" &&
    identity.readiness.ready &&
    candidates.length > 0 &&
    contacts.length > 0;

  const needsExplicitRelationships = candidates.length > 1 || contacts.length > 1;

  if (isConverted && conversion) {
    return (
      <section className="rounded-lg border border-green-200 bg-green-50 p-4">
        <h2 className="text-base font-semibold text-green-900">{t("convertedTitle")}</h2>
        <p className="mt-1 text-sm text-green-800">
          {t("convertedAt", {
            date: new Date(conversion.convertedAt).toLocaleString(),
            by: conversion.convertedByName ?? "—",
          })}
        </p>
        <div className="mt-4 space-y-3 text-sm">
          <div>
            <h3 className="font-medium text-green-900">{t("resultStudents")}</h3>
            <ul className="mt-1 list-inside list-disc text-green-800">
              {conversion.candidates.map((c) => (
                <li key={c.leadCandidateId}>
                  {c.studentName ?? c.studentId}{" "}
                  <Link href={`/students/${c.studentId}/edit`} className="underline">
                    {t("viewStudent")}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <h3 className="font-medium text-green-900">{t("resultGuardians")}</h3>
            <ul className="mt-1 list-inside list-disc text-green-800">
              {conversion.contacts.map((c) => (
                <li key={c.leadContactId}>{c.guardianName ?? c.guardianId}</li>
              ))}
            </ul>
          </div>
          {conversion.enrollments.length > 0 ? (
            <div>
              <h3 className="font-medium text-green-900">{t("resultEnrollments")}</h3>
              <ul className="mt-1 list-inside list-disc text-green-800">
                {conversion.enrollments.map((e) => (
                  <li key={e.enrollmentId}>
                    {e.className ?? e.classId}{" "}
                    <Link href={`/classes/${e.classId}/roster`} className="underline">
                      {t("viewRoster")}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      </section>
    );
  }

  if (!canShowForm) {
    if (!canConvert) return null;
    if (!identity.readiness.ready) {
      return (
        <section className="rounded-lg border border-amber-200 bg-amber-50 p-4">
          <h2 className="text-base font-semibold text-amber-900">{t("title")}</h2>
          <p className="mt-2 text-sm text-amber-800">{tIdentity("notReady")}</p>
        </section>
      );
    }
    return null;
  }

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-base font-semibold text-slate-900">{t("title")}</h2>
      <p className="mt-1 text-sm text-slate-600">{t("intro")}</p>

      <div className="mt-4 space-y-4 text-sm">
        <div>
          <h3 className="font-medium text-slate-800">{t("reviewCandidates")}</h3>
          <ul className="mt-2 space-y-2">
            {candidates.map((candidate) => {
              const resolution = identity.candidateResolutions[candidate.id];
              return (
                <li key={candidate.id} className="rounded border border-slate-100 p-2">
                  <div className="font-medium">{candidate.displayName}</div>
                  <div className="text-slate-600">
                    {resolution?.resolutionMode === "use_existing"
                      ? tIdentity("useExisting")
                      : tIdentity("createNewAtConversion")}
                    {resolution?.studentDisplayName ? ` — ${resolution.studentDisplayName}` : ""}
                  </div>
                </li>
              );
            })}
          </ul>
        </div>

        <div>
          <h3 className="font-medium text-slate-800">{t("reviewContacts")}</h3>
          <ul className="mt-2 space-y-2">
            {contacts.map((contact) => {
              const resolution = identity.contactResolutions[contact.id];
              return (
                <li key={contact.id} className="rounded border border-slate-100 p-2">
                  <div className="font-medium">{contact.displayName}</div>
                  <div className="text-slate-600">
                    {resolution?.resolutionMode === "use_existing"
                      ? tIdentity("useExisting")
                      : tIdentity("createNewAtConversion")}
                    {resolution?.guardianDisplayName ? ` — ${resolution.guardianDisplayName}` : ""}
                  </div>
                </li>
              );
            })}
          </ul>
        </div>

        {needsExplicitRelationships ? (
          <div>
            <h3 className="font-medium text-slate-800">{t("relationshipsTitle")}</h3>
            <p className="mt-1 text-slate-600">{t("relationshipsHint")}</p>
            <div className="mt-2 space-y-2">
              {candidates.flatMap((candidate) =>
                contacts.map((contact) => (
                  <label key={`${candidate.id}-${contact.id}`} className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      name="relationship"
                      value={`${candidate.id}:${contact.id}`}
                      defaultChecked={contacts.length === 1}
                    />
                    <span>
                      {contact.displayName} → {candidate.displayName}
                    </span>
                  </label>
                )),
              )}
            </div>
          </div>
        ) : null}

        <div>
          <h3 className="font-medium text-slate-800">{t("enrollmentTitle")}</h3>
          <p className="mt-1 text-slate-600">{t("enrollmentOptional")}</p>
          {candidates.map((candidate) => (
            <div key={candidate.id} className="mt-2 flex flex-wrap items-center gap-2">
              <span className="text-slate-700">{candidate.displayName}:</span>
              <select
                name={`enrollmentClass_${candidate.id}`}
                className="rounded border border-slate-300 px-2 py-1 text-sm"
                defaultValue=""
              >
                <option value="">{t("noEnrollment")}</option>
                {eligibleClasses.map((c) => (
                  <option key={c.classId} value={c.classId}>
                    {c.className} ({c.classStatus})
                  </option>
                ))}
              </select>
            </div>
          ))}
        </div>
      </div>

      <form action={formAction} className="mt-4 space-y-3">
        <input type="hidden" name="leadId" value={leadId} />
        <p className="text-sm text-slate-600">{t("confirmation")}</p>
        <ErrorMessage error={state.error} />
        <button
          type="submit"
          disabled={pending}
          className="rounded bg-green-700 px-4 py-2 text-sm font-medium text-white hover:bg-green-800 disabled:opacity-50"
        >
          {pending ? t("converting") : t("confirmConvert")}
        </button>
      </form>
    </section>
  );
}
