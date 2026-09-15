"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  recordScoreFormAction,
  type AssessmentActionState,
} from "@/app/actions/assessments";
import type { AssessmentResultRow } from "@/lib/assessments/query-class-assessments";

type Props = {
  classId: string;
  assessmentId: string;
  maxScore: number;
  row: AssessmentResultRow;
  canRecord: boolean;
};

const initialState: AssessmentActionState = {};

export function ScoreEntryRow({ classId, assessmentId, maxScore, row, canRecord }: Props) {
  const t = useTranslations("assessments");
  const [state, formAction, pending] = useActionState(recordScoreFormAction, initialState);

  if (!canRecord) {
    return (
      <div className="text-sm text-slate-700">
        {row.resultId ? (
          <>
            <span className="font-medium">{row.rawScore}</span> / {row.maxScore}
            {row.percentage !== null ? (
              <span className="text-slate-500"> ({row.percentage}%)</span>
            ) : null}
          </>
        ) : (
          <span className="text-slate-500">{t("noScoreRecorded")}</span>
        )}
      </div>
    );
  }

  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="classId" value={classId} />
      <input type="hidden" name="assessmentId" value={assessmentId} />
      <input type="hidden" name="enrollmentId" value={row.enrollmentId} />
      <label className="text-sm">
        <span className="sr-only">{t("score")}</span>
        <input
          type="number"
          name="rawScore"
          min="0"
          max={maxScore}
          step="0.01"
          defaultValue={row.rawScore ?? ""}
          placeholder="—"
          aria-label={`${t("score")} ${row.studentName}`}
          className="w-24 rounded border border-slate-300 px-2 py-1.5 text-sm"
        />
      </label>
      <span className="pb-1.5 text-sm text-slate-500">/ {maxScore}</span>
      <button
        type="submit"
        disabled={pending}
        className="rounded border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-800 disabled:opacity-50"
      >
        {row.resultId ? t("updateScore") : t("recordScores")}
      </button>
      {state.error === "score_exceeds_max" ? (
        <span className="text-xs text-red-700" role="alert">{t("scoreExceedsMaximum")}</span>
      ) : null}
      {state.error === "invalid_score" ? (
        <span className="text-xs text-red-700" role="alert">{t("invalidScore")}</span>
      ) : null}
    </form>
  );
}
