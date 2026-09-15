"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  saveObservationAction,
  type SessionExecutionActionState,
} from "@/app/actions/session-execution";
import type { ObservationIndicator } from "@/lib/session-execution/query-session-execution";

type Props = {
  classId: string;
  sessionId: string;
  enrollmentId: string;
  indicators: ObservationIndicator[];
  initialComment: string | null;
  initialRatings: Record<string, string>;
  disabled?: boolean;
};

const initialState: SessionExecutionActionState = {};

export function ObservationForm({
  classId,
  sessionId,
  enrollmentId,
  indicators,
  initialComment,
  initialRatings,
  disabled,
}: Props) {
  const t = useTranslations("sessionExecution");
  const tIndicator = useTranslations("observationIndicators");
  const tRating = useTranslations("observationRatings");
  const [state, formAction, pending] = useActionState(saveObservationAction, initialState);

  return (
    <form action={formAction} className="mt-3 space-y-3 rounded-md border border-slate-100 bg-slate-50 p-3">
      <input type="hidden" name="classId" value={classId} />
      <input type="hidden" name="sessionId" value={sessionId} />
      <input type="hidden" name="enrollmentId" value={enrollmentId} />

      <p className="text-xs font-semibold uppercase tracking-wide text-slate-600">
        {t("learnerObservation")}
      </p>

      {state.error === "permission_denied" ? (
        <p className="text-xs text-red-700">{t("permissionDenied")}</p>
      ) : null}

      {indicators.map((indicator) => (
        <div key={indicator.code}>
          <label
            htmlFor={`rating-${enrollmentId}-${indicator.code}`}
            className="block text-xs font-medium text-slate-700"
          >
            {tIndicator(indicator.code)}
          </label>
          <select
            id={`rating-${enrollmentId}-${indicator.code}`}
            name={`rating_${indicator.code}`}
            defaultValue={initialRatings[indicator.code] ?? ""}
            disabled={disabled || pending}
            className="mt-1 block w-full rounded-md border border-slate-300 px-2 py-1.5 text-sm"
          >
            <option value="">{t("noRating")}</option>
            <option value="low">{tRating("low")}</option>
            <option value="medium">{tRating("medium")}</option>
            <option value="high">{tRating("high")}</option>
          </select>
        </div>
      ))}

      <div>
        <label
          htmlFor={`comment-${enrollmentId}`}
          className="block text-xs font-medium text-slate-700"
        >
          {t("teacherComment")}
        </label>
        <textarea
          id={`comment-${enrollmentId}`}
          name="comment"
          rows={2}
          defaultValue={initialComment ?? ""}
          disabled={disabled || pending}
          className="mt-1 block w-full rounded-md border border-slate-300 px-2 py-1.5 text-sm"
        />
      </div>

      <button
        type="submit"
        disabled={disabled || pending}
        className="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-900 disabled:opacity-50"
      >
        {pending ? t("saving") : t("saveObservation")}
      </button>
    </form>
  );
}
