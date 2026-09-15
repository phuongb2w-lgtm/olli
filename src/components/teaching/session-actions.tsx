"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  cancelSessionAction,
  completeSessionAction,
  type TeachingActionState,
} from "@/app/actions/teaching";
import type { SessionStatus } from "@/lib/teaching/constants";

type Props = {
  classId: string;
  sessionId: string;
  status: SessionStatus;
};

const initialState: TeachingActionState = {};

export function SessionActions({ classId, sessionId, status }: Props) {
  const t = useTranslations("teaching");
  const [cancelState, cancelAction, cancelPending] = useActionState(
    cancelSessionAction,
    initialState,
  );
  const [completeState, completeAction, completePending] = useActionState(
    completeSessionAction,
    initialState,
  );

  if (status !== "scheduled" && status !== "in_progress") return null;

  return (
    <div className="flex flex-wrap gap-2">
      <form action={completeAction}>
        <input type="hidden" name="classId" value={classId} />
        <input type="hidden" name="sessionId" value={sessionId} />
        <button
          type="submit"
          disabled={completePending}
          className="rounded-md border border-slate-300 px-2 py-1 text-xs font-medium text-slate-900 disabled:opacity-50"
        >
          {completePending ? t("saving") : t("completeSession")}
        </button>
      </form>
      <form action={cancelAction}>
        <input type="hidden" name="classId" value={classId} />
        <input type="hidden" name="sessionId" value={sessionId} />
        <button
          type="submit"
          disabled={cancelPending}
          className="rounded-md border border-red-300 px-2 py-1 text-xs font-medium text-red-800 disabled:opacity-50"
        >
          {cancelPending ? t("saving") : t("cancelSession")}
        </button>
      </form>
      {cancelState.error || completeState.error ? (
        <p className="w-full text-xs text-red-700">{t("saveError")}</p>
      ) : null}
    </div>
  );
}
