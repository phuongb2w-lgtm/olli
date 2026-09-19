"use client";

import { useTranslations } from "next-intl";
import { useActionState } from "react";
import {
  submitSessionAttendanceAction,
  type AcademicReviewActionState,
} from "@/app/actions/academic-review";

type Props = {
  classId: string;
  sessionId: string;
  canSubmit: boolean;
};

export function SessionAcademicSubmitPanel({ classId, sessionId, canSubmit }: Props) {
  const t = useTranslations("academic.session");
  const [state, formAction, pending] = useActionState<
    AcademicReviewActionState,
    FormData
  >(submitSessionAttendanceAction, {});

  if (!canSubmit) return null;

  return (
    <form action={formAction} className="rounded-lg border border-slate-200 bg-white p-4">
      <input type="hidden" name="classId" value={classId} />
      <input type="hidden" name="sessionId" value={sessionId} />
      <p className="text-sm text-slate-600">{t("submitAttendance")}</p>
      <button
        type="submit"
        disabled={pending}
        className="mt-2 rounded bg-slate-900 px-3 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
      >
        {t("submitAttendance")}
      </button>
      {state.success ? (
        <p className="mt-2 text-sm text-green-700">{state.success}</p>
      ) : null}
      {state.error ? (
        <p className="mt-2 text-sm text-red-700">{state.error}</p>
      ) : null}
    </form>
  );
}
