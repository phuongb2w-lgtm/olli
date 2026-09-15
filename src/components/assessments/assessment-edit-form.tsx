"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  updateAssessmentAction,
  type AssessmentActionState,
} from "@/app/actions/assessments";
import { ASSESSMENT_STATUSES, ASSESSMENT_TYPE_CODES } from "@/lib/assessments/constants";
import type { AssessmentDetail } from "@/lib/assessments/query-class-assessments";

type Props = {
  assessment: AssessmentDetail;
};

const initialState: AssessmentActionState = {};

export function AssessmentEditForm({ assessment }: Props) {
  const t = useTranslations("assessments");
  const tType = useTranslations("assessmentTypes");
  const tStatus = useTranslations("status.assessment");
  const [state, formAction, pending] = useActionState(updateAssessmentAction, initialState);

  return (
    <form action={formAction} className="space-y-4 rounded-lg border border-slate-200 bg-white p-4">
      <h3 className="text-sm font-semibold text-slate-900">{t("editAssessment")}</h3>
      <input type="hidden" name="classId" value={assessment.classId} />
      <input type="hidden" name="assessmentId" value={assessment.id} />
      {state.error === "permission_denied" ? (
        <p className="text-sm text-red-700" role="alert">{t("permissionDenied")}</p>
      ) : null}
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block text-sm sm:col-span-2">
          <span className="font-medium text-slate-700">{t("titleField")}</span>
          <input
            name="title"
            required
            defaultValue={assessment.title}
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </label>
        <label className="block text-sm">
          <span className="font-medium text-slate-700">{t("assessmentDate")}</span>
          <input
            type="date"
            name="assessedOn"
            required
            defaultValue={assessment.assessedOn}
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </label>
        <label className="block text-sm">
          <span className="font-medium text-slate-700">{t("maximumScore")}</span>
          <input
            type="number"
            name="maxScore"
            required
            min="0.01"
            step="0.01"
            defaultValue={assessment.maxScore}
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </label>
        <label className="block text-sm">
          <span className="font-medium text-slate-700">{t("assessmentType")}</span>
          <select
            name="assessmentTypeCode"
            defaultValue={assessment.assessmentTypeCode}
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          >
            {ASSESSMENT_TYPE_CODES.map((code) => (
              <option key={code} value={code}>
                {tType(code)}
              </option>
            ))}
          </select>
        </label>
        <label className="block text-sm">
          <span className="font-medium text-slate-700">{t("status")}</span>
          <select
            name="status"
            defaultValue={assessment.status}
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          >
            {ASSESSMENT_STATUSES.map((status) => (
              <option key={status} value={status}>
                {tStatus(status)}
              </option>
            ))}
          </select>
        </label>
      </div>
      <button
        type="submit"
        disabled={pending}
        className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {t("saveAssessment")}
      </button>
    </form>
  );
}
