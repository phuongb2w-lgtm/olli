"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  cancelSessionExecutionAction,
  completeSessionAction,
  startSessionAction,
  type SessionExecutionActionState,
} from "@/app/actions/session-execution";
import type { SessionExecutionStatus } from "@/lib/session-execution/constants";

type Props = {
  classId: string;
  sessionId: string;
  status: SessionExecutionStatus;
  notRecordedCount: number;
};

const initialState: SessionExecutionActionState = {};

export function SessionStatusActions({
  classId,
  sessionId,
  status,
  notRecordedCount,
}: Props) {
  const t = useTranslations("sessionExecution");
  const [startState, startAction, startPending] = useActionState(startSessionAction, initialState);
  const [completeState, completeAction, completePending] = useActionState(
    completeSessionAction,
    initialState,
  );
  const [cancelState, cancelAction, cancelPending] = useActionState(
    cancelSessionExecutionAction,
    initialState,
  );

  const error =
    startState.error || completeState.error || cancelState.error;

  return (
    <div className="space-y-3">
      {error === "confirm_required" ? (
        <p className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-900" role="status">
          {t("confirmUnrecorded", { count: notRecordedCount })}
        </p>
      ) : null}
      {error === "permission_denied" ? (
        <p className="text-sm text-red-700">{t("permissionDenied")}</p>
      ) : null}

      <div className="flex flex-wrap gap-2">
        {status === "scheduled" ? (
          <>
            <form action={startAction}>
              <input type="hidden" name="classId" value={classId} />
              <input type="hidden" name="sessionId" value={sessionId} />
              <button
                type="submit"
                disabled={startPending}
                className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
              >
                {startPending ? t("saving") : t("startSession")}
              </button>
            </form>
            <form action={cancelAction}>
              <input type="hidden" name="classId" value={classId} />
              <input type="hidden" name="sessionId" value={sessionId} />
              <button
                type="submit"
                disabled={cancelPending}
                className="rounded-md border border-red-300 px-4 py-2 text-sm font-medium text-red-800 disabled:opacity-50"
              >
                {cancelPending ? t("saving") : t("cancelSession")}
              </button>
            </form>
          </>
        ) : null}

        {status === "in_progress" ? (
          <>
            <form action={completeAction} className="flex flex-wrap items-end gap-2">
              <input type="hidden" name="classId" value={classId} />
              <input type="hidden" name="sessionId" value={sessionId} />
              {notRecordedCount > 0 ? (
                <label className="flex items-center gap-2 text-sm text-slate-700">
                  <input type="checkbox" name="confirmUnrecorded" value="true" />
                  {t("confirmCompleteWithUnrecorded")}
                </label>
              ) : null}
              <button
                type="submit"
                disabled={completePending}
                className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
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
                className="rounded-md border border-red-300 px-4 py-2 text-sm font-medium text-red-800 disabled:opacity-50"
              >
                {cancelPending ? t("saving") : t("cancelSession")}
              </button>
            </form>
          </>
        ) : null}
      </div>
    </div>
  );
}
