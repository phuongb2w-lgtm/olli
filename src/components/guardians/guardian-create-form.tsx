"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { createGuardian, type GuardianActionState } from "@/app/actions/guardians";
import { GuardianFormFields } from "@/components/guardians/guardian-form-fields";
import { LinkOptionsFields } from "@/components/guardians/link-options-fields";

type Props = {
  studentId: string;
  canCreate: boolean;
};

const initialState: GuardianActionState = {};

export function GuardianCreateForm({ studentId, canCreate }: Props) {
  const t = useTranslations("guardians");
  const [state, formAction, pending] = useActionState(createGuardian, initialState);

  if (!canCreate) return null;

  const values = state.values ?? {
    familyName: "",
    givenName: "",
    phone: "",
    email: "",
    relationshipType: "guardian",
  };

  const formKey = state.values
    ? `${state.duplicateWarning}-${state.success}-${values.familyName}`
    : "initial";

  const duplicateMessage =
    state.duplicateWarning === "both"
      ? t("possibleDuplicateBoth")
      : state.duplicateWarning === "email"
        ? t("possibleDuplicateEmail")
        : state.duplicateWarning === "phone"
          ? t("possibleDuplicatePhone")
          : null;

  const globalError =
    state.error === "permission_denied"
      ? t("permissionDenied")
      : state.error === "primary_conflict"
        ? t("primaryConflict")
        : state.error === "save_error"
          ? t("saveError")
          : state.error === "already_linked"
            ? t("alreadyLinked")
            : null;

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
      <h2 className="text-sm font-semibold text-slate-900">{t("addGuardian")}</h2>
      <p className="mt-1 text-sm text-slate-600">{t("sharedRecordHint")}</p>

      {state.success === "linked" ? (
        <p className="mt-3 text-sm text-green-700" role="status">
          {t("linkedSuccess")}
        </p>
      ) : null}

      <form key={formKey} action={formAction} className="mt-4 space-y-4">
        <input type="hidden" name="studentId" value={studentId} />
        <GuardianFormFields values={values} fieldErrors={state.fieldErrors} idPrefix="create-" />
        <LinkOptionsFields
          relationshipType={values.relationshipType}
          isPrimaryContact={values.isPrimaryContact}
          isBillingContact={values.isBillingContact}
          idPrefix="create-"
        />

        {duplicateMessage ? (
          <div className="rounded border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
            <p className="font-medium">{t("possibleDuplicate")}</p>
            <p className="mt-1">{duplicateMessage}</p>
            <label className="mt-3 flex items-start gap-2">
              <input type="checkbox" name="confirmDuplicate" value="true" className="mt-0.5" />
              <span>{t("continueAnyway")}</span>
            </label>
          </div>
        ) : null}

        {globalError ? (
          <p className="text-sm text-red-600" role="alert">
            {globalError}
          </p>
        ) : null}

        <button
          type="submit"
          disabled={pending}
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
        >
          {pending ? t("saving") : t("addGuardian")}
        </button>
      </form>
    </section>
  );
}
