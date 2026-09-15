"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { endClassScheduleAction, type TeachingActionState } from "@/app/actions/teaching";

type Props = {
  classId: string;
  scheduleId: string;
};

const initialState: TeachingActionState = {};

export function EndScheduleForm({ classId, scheduleId }: Props) {
  const t = useTranslations("teaching");
  const [state, formAction, pending] = useActionState(endClassScheduleAction, initialState);

  return (
    <form action={formAction}>
      <input type="hidden" name="classId" value={classId} />
      <input type="hidden" name="scheduleId" value={scheduleId} />
      <button
        type="submit"
        disabled={pending}
        className="rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-900 disabled:opacity-50"
      >
        {pending ? t("saving") : t("endSchedule")}
      </button>
      {state.error ? <p className="mt-1 text-xs text-red-700">{t("saveError")}</p> : null}
    </form>
  );
}
