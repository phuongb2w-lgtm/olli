"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  endTeacherAssignmentAction,
  type TeachingActionState,
} from "@/app/actions/teaching";

type Props = {
  classId: string;
  assignmentId: string;
};

const initialState: TeachingActionState = {};

export function EndTeacherAssignmentForm({ classId, assignmentId }: Props) {
  const t = useTranslations("teaching");
  const [state, formAction, pending] = useActionState(endTeacherAssignmentAction, initialState);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="classId" value={classId} />
      <input type="hidden" name="assignmentId" value={assignmentId} />
      <div>
        <label htmlFor={`end-${assignmentId}`} className="sr-only">
          {t("effectiveUntil")}
        </label>
        <input
          id={`end-${assignmentId}`}
          name="effectiveTo"
          type="date"
          defaultValue={today}
          className="rounded-md border border-slate-300 px-3 py-1.5 text-sm"
        />
      </div>
      <button
        type="submit"
        disabled={pending}
        className="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-900 disabled:opacity-50"
      >
        {pending ? t("saving") : t("endAssignment")}
      </button>
      {state.error ? <p className="w-full text-xs text-red-700">{t("saveError")}</p> : null}
    </form>
  );
}
