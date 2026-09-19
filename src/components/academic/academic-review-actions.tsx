"use client";

import { useTranslations } from "next-intl";
import { useActionState } from "react";
import {
  reviewAssessmentResultAction,
  reviewAttendanceAction,
  reviewObservationAction,
  translateObservationAction,
  type AcademicReviewActionState,
} from "@/app/actions/academic-review";

type Props = {
  entityType: "attendance" | "assessment_result" | "teacher_observation";
  recordId: string;
  canReview: boolean;
  canTranslate?: boolean;
  originalComment?: string | null;
};

export function AcademicReviewActions({
  entityType,
  recordId,
  canReview,
  canTranslate = false,
  originalComment,
}: Props) {
  const t = useTranslations("academic.review");
  const [reviewState, reviewAction, reviewPending] = useActionState<
    AcademicReviewActionState,
    FormData
  >(
    entityType === "attendance"
      ? reviewAttendanceAction
      : entityType === "assessment_result"
        ? reviewAssessmentResultAction
        : reviewObservationAction,
    {},
  );
  const [translateState, translateAction, translatePending] = useActionState<
    AcademicReviewActionState,
    FormData
  >(translateObservationAction, {});

  if (!canReview) return null;

  const idField =
    entityType === "attendance"
      ? "attendanceId"
      : entityType === "assessment_result"
        ? "resultId"
        : "observationId";

  return (
    <div className="space-y-4">
      <form action={reviewAction} className="space-y-3 rounded-lg border border-slate-200 bg-white p-4">
        <input type="hidden" name={idField} value={recordId} />
        <label className="block text-sm">
          <span className="text-slate-600">{t("return")}</span>
          <textarea
            name="reviewNotes"
            rows={2}
            className="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </label>
        <div className="flex flex-wrap gap-2">
          <button
            type="submit"
            name="action"
            value="confirm"
            disabled={reviewPending}
            className="rounded bg-green-700 px-3 py-2 text-sm font-medium text-white"
          >
            {t("confirm")}
          </button>
          <button
            type="submit"
            name="action"
            value="return"
            disabled={reviewPending}
            className="rounded bg-amber-600 px-3 py-2 text-sm font-medium text-white"
          >
            {t("return")}
          </button>
          {entityType === "assessment_result" ? (
            <button
              type="submit"
              name="action"
              value="correct"
              disabled={reviewPending}
              className="rounded bg-slate-700 px-3 py-2 text-sm font-medium text-white"
            >
              {t("correctScore")}
            </button>
          ) : null}
        </div>
        {reviewState.success ? (
          <p className="text-sm text-green-700">{reviewState.success}</p>
        ) : null}
        {reviewState.error ? (
          <p className="text-sm text-red-700">{reviewState.error}</p>
        ) : null}
      </form>

      {canTranslate && entityType === "teacher_observation" ? (
        <form
          action={translateAction}
          className="space-y-3 rounded-lg border border-slate-200 bg-white p-4"
        >
          <input type="hidden" name="observationId" value={recordId} />
          {originalComment ? (
            <p className="text-sm text-slate-700">
              <span className="font-medium">Original: </span>
              {originalComment}
            </p>
          ) : null}
          <label className="block text-sm">
            <span className="text-slate-600">{t("translate")}</span>
            <textarea
              name="translatedComment"
              rows={3}
              required
              className="mt-1 w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
          </label>
          <input
            name="translatedLanguage"
            placeholder="en"
            className="rounded border border-slate-300 px-3 py-2 text-sm"
          />
          <button
            type="submit"
            disabled={translatePending}
            className="rounded bg-slate-900 px-3 py-2 text-sm font-medium text-white"
          >
            {t("translate")}
          </button>
          {translateState.success ? (
            <p className="text-sm text-green-700">{translateState.success}</p>
          ) : null}
        </form>
      ) : null}
    </div>
  );
}
