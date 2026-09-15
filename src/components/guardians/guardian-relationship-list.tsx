"use client";

import { useActionState, useState } from "react";
import { useTranslations } from "next-intl";
import {
  toggleBillingContact,
  togglePrimaryContact,
  unlinkGuardian,
  updateGuardian,
  updateLink,
  type GuardianActionState,
} from "@/app/actions/guardians";
import { GuardianFormFields } from "@/components/guardians/guardian-form-fields";
import { LinkOptionsFields } from "@/components/guardians/link-options-fields";
import type { StudentGuardianLinkItem } from "@/lib/guardians/query-student-guardians";

type Props = {
  studentId: string;
  active: StudentGuardianLinkItem[];
  ended: StudentGuardianLinkItem[];
  canUpdate: boolean;
};

const initialState: GuardianActionState = {};

function RelationshipRow({
  studentId,
  link,
  canUpdate,
}: {
  studentId: string;
  link: StudentGuardianLinkItem;
  canUpdate: boolean;
}) {
  const t = useTranslations("guardians");
  const tRel = useTranslations("guardians.relationship");
  const [editOpen, setEditOpen] = useState(false);
  const [linkState, linkAction, linkPending] = useActionState(updateLink, initialState);
  const [primaryState, primaryAction, primaryPending] = useActionState(
    togglePrimaryContact,
    initialState,
  );
  const [, billingAction, billingPending] = useActionState(toggleBillingContact, initialState);
  const [unlinkState, unlinkAction, unlinkPending] = useActionState(unlinkGuardian, initialState);
  const [guardianState, guardianAction, guardianPending] = useActionState(
    updateGuardian,
    initialState,
  );

  return (
    <li className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="font-medium text-slate-900">{link.guardianName}</p>
          <p className="text-sm text-slate-600">
            {tRel(link.relationshipType)}
            {link.phone ? ` · ${link.phone}` : ""}
            {link.email ? ` · ${link.email}` : ""}
          </p>
          <div className="mt-2 flex flex-wrap gap-2 text-xs">
            {link.isPrimaryContact ? (
              <span className="rounded-full bg-blue-100 px-2 py-0.5 font-medium text-blue-900">
                {t("primaryContact")} ✓
              </span>
            ) : (
              <span className="rounded-full bg-slate-100 px-2 py-0.5 text-slate-600">
                {t("primaryContact")} —
              </span>
            )}
            {link.isBillingContact ? (
              <span className="rounded-full bg-emerald-100 px-2 py-0.5 font-medium text-emerald-900">
                {t("billingContact")} ✓
              </span>
            ) : (
              <span className="rounded-full bg-slate-100 px-2 py-0.5 text-slate-600">
                {t("billingContact")} —
              </span>
            )}
          </div>
        </div>
        {canUpdate ? (
          <button
            type="button"
            onClick={() => setEditOpen(!editOpen)}
            className="text-sm font-medium text-slate-900 underline"
          >
            {editOpen ? t("cancel") : t("editGuardian")}
          </button>
        ) : null}
      </div>

      {canUpdate ? (
        <div className="mt-4 flex flex-wrap gap-2">
          {!link.isPrimaryContact ? (
            <form action={primaryAction} className="space-y-2">
              <input type="hidden" name="studentId" value={studentId} />
              <input type="hidden" name="linkId" value={link.linkId} />
              <input type="hidden" name="makePrimary" value="true" />
              {primaryState.primaryReplaceRequired ? (
                <label className="flex items-start gap-2 text-xs">
                  <input type="checkbox" name="confirmPrimaryReplace" value="true" />
                  <span>{t("confirmPrimaryReplace")}</span>
                </label>
              ) : null}
              <button
                type="submit"
                disabled={primaryPending}
                className="rounded border border-slate-300 px-3 py-1.5 text-xs font-medium hover:bg-slate-50"
              >
                {t("makePrimary")}
              </button>
            </form>
          ) : (
            <form action={primaryAction}>
              <input type="hidden" name="studentId" value={studentId} />
              <input type="hidden" name="linkId" value={link.linkId} />
              <input type="hidden" name="makePrimary" value="false" />
              <button
                type="submit"
                disabled={primaryPending}
                className="rounded border border-slate-300 px-3 py-1.5 text-xs font-medium hover:bg-slate-50"
              >
                {t("removePrimary")}
              </button>
            </form>
          )}

          <form action={billingAction}>
            <input type="hidden" name="studentId" value={studentId} />
            <input type="hidden" name="linkId" value={link.linkId} />
            <input
              type="hidden"
              name="makeBilling"
              value={link.isBillingContact ? "false" : "true"}
            />
            <button
              type="submit"
              disabled={billingPending}
              className="rounded border border-slate-300 px-3 py-1.5 text-xs font-medium hover:bg-slate-50"
            >
              {link.isBillingContact ? t("removeBilling") : t("makeBilling")}
            </button>
          </form>
        </div>
      ) : null}

      {primaryState.primaryReplaceRequired ? (
        <p className="mt-2 text-sm text-amber-800" role="alert">
          {t("primaryReplaceHint")}
        </p>
      ) : null}

      {primaryState.error === "primary_conflict" || linkState.error === "primary_conflict" ? (
        <p className="mt-2 text-sm text-red-600" role="alert">
          {t("primaryConflict")}
        </p>
      ) : null}

      {editOpen && canUpdate ? (
        <div className="mt-4 space-y-6 border-t border-slate-200 pt-4">
          <form action={guardianAction} className="space-y-4">
            <input type="hidden" name="studentId" value={studentId} />
            <input type="hidden" name="guardianId" value={link.guardianId} />
            <p className="text-sm font-medium text-slate-800">{t("editGuardianMaster")}</p>
            <p className="text-xs text-slate-600">{t("sharedRecordHint")}</p>
            <GuardianFormFields
              values={
                guardianState.values ?? {
                  familyName: link.familyName,
                  givenName: link.givenName,
                  phone: link.phone ?? "",
                  email: link.email ?? "",
                }
              }
              fieldErrors={guardianState.fieldErrors}
              idPrefix={`edit-${link.linkId}-`}
            />
            {guardianState.duplicateWarning ? (
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" name="confirmDuplicate" value="true" />
                <span>{t("continueAnyway")}</span>
              </label>
            ) : null}
            {guardianState.success === "updated" ? (
              <p className="text-sm text-green-700">{t("updatedSuccess")}</p>
            ) : null}
            <button
              type="submit"
              disabled={guardianPending}
              className="rounded bg-slate-900 px-3 py-1.5 text-sm font-medium text-white"
            >
              {guardianPending ? t("saving") : t("saveGuardian")}
            </button>
          </form>

          <form action={linkAction} className="space-y-4">
            <input type="hidden" name="studentId" value={studentId} />
            <input type="hidden" name="linkId" value={link.linkId} />
            <p className="text-sm font-medium text-slate-800">{t("editRelationship")}</p>
            <LinkOptionsFields
              relationshipType={link.relationshipType}
              isPrimaryContact={link.isPrimaryContact}
              isBillingContact={link.isBillingContact}
              idPrefix={`rel-${link.linkId}-`}
            />
            {linkState.primaryReplaceRequired ? (
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" name="confirmPrimaryReplace" value="true" />
                <span>{t("confirmPrimaryReplace")}</span>
              </label>
            ) : null}
            <button
              type="submit"
              disabled={linkPending}
              className="rounded border border-slate-300 px-3 py-1.5 text-sm font-medium"
            >
              {linkPending ? t("saving") : t("saveRelationship")}
            </button>
          </form>

          <form action={unlinkAction} className="space-y-3 border-t border-slate-200 pt-4">
            <input type="hidden" name="studentId" value={studentId} />
            <input type="hidden" name="linkId" value={link.linkId} />
            <p className="text-sm font-medium text-slate-800">{t("unlink")}</p>
            <p className="text-xs text-slate-600">{t("unlinkConfirmMessage")}</p>
            <label className="flex items-start gap-2 text-sm">
              <input type="checkbox" name="confirmUnlink" value="true" required />
              <span>{t("confirmUnlink")}</span>
            </label>
            {unlinkState.fieldErrors?.confirmUnlink ? (
              <p className="text-sm text-red-600">{t("confirmUnlinkRequired")}</p>
            ) : null}
            {unlinkState.success === "unlinked" ? (
              <p className="text-sm text-green-700">{t("unlinkedSuccess")}</p>
            ) : null}
            <button
              type="submit"
              disabled={unlinkPending}
              className="rounded border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-50"
            >
              {unlinkPending ? t("saving") : t("unlink")}
            </button>
          </form>
        </div>
      ) : null}
    </li>
  );
}

export function GuardianRelationshipList({ studentId, active, ended, canUpdate }: Props) {
  const t = useTranslations("guardians");

  if (active.length === 0 && ended.length === 0) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
        <p>{t("noGuardiansLinked")}</p>
      </section>
    );
  }

  return (
    <div className="space-y-6">
      {active.length > 0 ? (
        <ul className="space-y-3">
          {active.map((link) => (
            <RelationshipRow
              key={link.linkId}
              studentId={studentId}
              link={link}
              canUpdate={canUpdate}
            />
          ))}
        </ul>
      ) : (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("noGuardiansLinked")}</p>
        </section>
      )}

      {ended.length > 0 ? (
        <section>
          <h2 className="mb-2 text-sm font-semibold text-slate-700">{t("endedLinks")}</h2>
          <ul className="space-y-2">
            {ended.map((link) => (
              <li
                key={link.linkId}
                className="rounded border border-dashed border-slate-200 px-4 py-3 text-sm text-slate-500"
              >
                {link.guardianName} — {t("ended")}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
