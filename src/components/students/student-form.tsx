"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import {
  createStudent,
  updateStudent,
  type StudentActionState,
  type StudentFormValues,
} from "@/app/actions/students";
import { STUDENT_STATUSES } from "@/lib/students/constants";

type Props = {
  mode: "create" | "edit";
  initialValues: StudentFormValues;
  studentId?: string;
};

const initialActionState: StudentActionState = {};

function fieldErrorKey(code: string | undefined): string | null {
  if (!code) return null;
  const map: Record<string, string> = {
    required: "requiredField",
    invalid: "invalidDate",
    tooLong: "studentCodeTooLong",
  };
  return map[code] ?? null;
}

export function StudentForm({ mode, initialValues, studentId }: Props) {
  const t = useTranslations("students");
  const tStatus = useTranslations("status.student");
  const action = mode === "create" ? createStudent : updateStudent;
  const [state, formAction, pending] = useActionState(action, initialActionState);

  const values = state.values ?? initialValues;
  const originalStatus = initialValues.status;
  const formKey = state.values
    ? `${Boolean(state.duplicateWarning)}-${state.statusChangeRequired?.to ?? ""}-${values.familyName}-${values.givenName}`
    : "initial";

  const globalError =
    state.error === "permission_denied"
      ? t("permissionDenied")
      : state.error === "student_code_conflict"
        ? t("studentCodeExists")
        : state.error === "save_error"
          ? t("saveError")
          : state.error === "not_found"
            ? t("notFound")
            : null;

  return (
    <form key={formKey} action={formAction} className="space-y-6">
      {mode === "edit" && studentId ? (
        <input type="hidden" name="studentId" value={studentId} />
      ) : null}
      <input type="hidden" name="originalStatus" value={originalStatus} />

      <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-slate-900">{t("profileSection")}</h2>

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="familyName" className="mb-1 block text-sm font-medium">
              {t("familyName")}
            </label>
            <input
              id="familyName"
              name="familyName"
              type="text"
              required
              defaultValue={values.familyName}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            {state.fieldErrors?.familyName ? (
              <p className="mt-1 text-sm text-red-600" role="alert">
                {t(fieldErrorKey(state.fieldErrors.familyName) ?? "requiredField")}
              </p>
            ) : null}
          </div>

          <div>
            <label htmlFor="givenName" className="mb-1 block text-sm font-medium">
              {t("givenName")}
            </label>
            <input
              id="givenName"
              name="givenName"
              type="text"
              required
              defaultValue={values.givenName}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            {state.fieldErrors?.givenName ? (
              <p className="mt-1 text-sm text-red-600" role="alert">
                {t(fieldErrorKey(state.fieldErrors.givenName) ?? "requiredField")}
              </p>
            ) : null}
          </div>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="studentCode" className="mb-1 block text-sm font-medium">
              {t("studentCode")}
            </label>
            <input
              id="studentCode"
              name="studentCode"
              type="text"
              defaultValue={values.studentCode}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            {state.fieldErrors?.studentCode ? (
              <p className="mt-1 text-sm text-red-600" role="alert">
                {t(fieldErrorKey(state.fieldErrors.studentCode) ?? "saveError")}
              </p>
            ) : null}
          </div>

          <div>
            <label htmlFor="dateOfBirth" className="mb-1 block text-sm font-medium">
              {t("dateOfBirth")}
            </label>
            <input
              id="dateOfBirth"
              name="dateOfBirth"
              type="date"
              defaultValue={values.dateOfBirth}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            {state.fieldErrors?.dateOfBirth ? (
              <p className="mt-1 text-sm text-red-600" role="alert">
                {t("invalidDate")}
              </p>
            ) : null}
          </div>
        </div>
      </section>

      <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-slate-900">{t("lifecycleSection")}</h2>

        <div>
          <label htmlFor="status" className="mb-1 block text-sm font-medium">
            {t("status")}
          </label>
          <select
            id="status"
            name="status"
            defaultValue={values.status}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm sm:max-w-xs"
          >
            {STUDENT_STATUSES.map((status) => (
              <option key={status} value={status}>
                {tStatus(status)}
              </option>
            ))}
          </select>
          {state.fieldErrors?.status ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("invalidStatus")}
            </p>
          ) : null}
        </div>

        {state.statusChangeRequired ? (
          <div
            className="rounded border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900"
            role="alert"
          >
            <p className="font-medium">{t("statusChangeConfirmTitle")}</p>
            <p className="mt-1">
              {t("statusChangeConfirmMessage", {
                from: tStatus(state.statusChangeRequired.from),
                to: tStatus(state.statusChangeRequired.to),
              })}
            </p>
            <label className="mt-3 flex items-start gap-2">
              <input
                type="checkbox"
                name="confirmStatusChange"
                value="true"
                className="mt-0.5"
              />
              <span>{t("confirmStatusChange")}</span>
            </label>
          </div>
        ) : null}
      </section>

      {state.duplicateWarning ? (
        <div
          className="rounded border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900"
          role="alert"
        >
          <p className="font-medium">{t("possibleDuplicate")}</p>
          <p className="mt-1">{t("possibleDuplicateHint")}</p>
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

      <div className="flex flex-wrap gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
        >
          {pending ? t("saving") : t("save")}
        </button>
        <Link
          href="/students"
          className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
        >
          {t("cancel")}
        </Link>
      </div>
    </form>
  );
}
