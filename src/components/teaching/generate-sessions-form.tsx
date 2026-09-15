"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { generateSessionsAction, type TeachingActionState } from "@/app/actions/teaching";

type Props = {
  classId: string;
  scheduleId: string;
  defaultRangeStart: string;
  defaultRangeEnd: string;
};

const initialState: TeachingActionState = {};

export function GenerateSessionsForm({
  classId,
  scheduleId,
  defaultRangeStart,
  defaultRangeEnd,
}: Props) {
  const t = useTranslations("teaching");
  const [state, formAction, pending] = useActionState(generateSessionsAction, initialState);

  return (
    <form action={formAction} className="space-y-3">
      <p className="text-xs font-medium uppercase tracking-wide text-slate-500">
        {t("generateSessions")}
      </p>
      <input type="hidden" name="classId" value={classId} />
      <input type="hidden" name="scheduleId" value={scheduleId} />

      {state.error === "ambiguous_teacher" ? (
        <p className="text-xs text-red-700">{t("ambiguousTeacher")}</p>
      ) : null}
      {state.error === "no_teacher" ? (
        <p className="text-xs text-red-700">{t("noTeacher")}</p>
      ) : null}
      {state.error === "schedule_conflict" ? (
        <p className="text-xs text-red-700">{t("scheduleConflict")}</p>
      ) : null}
      {state.error === "schedule_not_active" ? (
        <p className="text-xs text-red-700">{t("scheduleNotActive")}</p>
      ) : null}

      <div className="grid gap-2 sm:grid-cols-2">
        <div>
          <label htmlFor={`rangeStart-${scheduleId}`} className="block text-xs text-slate-600">
            {t("generationRangeStart")}
          </label>
          <input
            id={`rangeStart-${scheduleId}`}
            name="rangeStart"
            type="date"
            required
            defaultValue={defaultRangeStart}
            className="mt-1 block w-full rounded-md border border-slate-300 px-2 py-1.5 text-sm"
          />
        </div>
        <div>
          <label htmlFor={`rangeEnd-${scheduleId}`} className="block text-xs text-slate-600">
            {t("generationRangeEnd")}
          </label>
          <input
            id={`rangeEnd-${scheduleId}`}
            name="rangeEnd"
            type="date"
            required
            defaultValue={defaultRangeEnd}
            className="mt-1 block w-full rounded-md border border-slate-300 px-2 py-1.5 text-sm"
          />
        </div>
      </div>

      <button
        type="submit"
        disabled={pending}
        className="rounded-md bg-slate-800 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50"
      >
        {pending ? t("generating") : t("generateSessions")}
      </button>
    </form>
  );
}
