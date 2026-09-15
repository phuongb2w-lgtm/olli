"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  markAllPresentAction,
  type SessionExecutionActionState,
} from "@/app/actions/session-execution";

type Props = {
  classId: string;
  sessionId: string;
  hasNonPresentRecorded: boolean;
  disabled?: boolean;
};

const initialState: SessionExecutionActionState = {};

export function MarkAllPresentForm({
  classId,
  sessionId,
  hasNonPresentRecorded,
  disabled,
}: Props) {
  const t = useTranslations("sessionExecution");
  const [state, formAction, pending] = useActionState(markAllPresentAction, initialState);

  return (
    <form action={formAction} className="flex flex-wrap items-center gap-3">
      <input type="hidden" name="classId" value={classId} />
      <input type="hidden" name="sessionId" value={sessionId} />
      {hasNonPresentRecorded ? (
        <label className="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" name="confirmOverwriteNonPresent" value="true" />
          {t("confirmOverwriteNonPresent")}
        </label>
      ) : null}
      {state.error === "confirm_required" ? (
        <p className="text-sm text-amber-800">{t("confirmOverwriteRequired")}</p>
      ) : null}
      <button
        type="submit"
        disabled={disabled || pending}
        className="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-900 disabled:opacity-50"
      >
        {pending ? t("saving") : t("markAllPresent")}
      </button>
    </form>
  );
}
