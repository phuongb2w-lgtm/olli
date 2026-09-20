"use client";

import { useActionState } from "react";
import {
  saveExecutiveExceptionFollowUpAction,
  type ExecutiveFollowUpActionState,
} from "@/app/actions/executive-exceptions";
import type { ExecutiveExceptionRow } from "@/lib/reporting/executive-read-model";

type Props = {
  row: ExecutiveExceptionRow;
  labels: {
    followUpTitle: string;
    statusLabel: string;
    noteLabel: string;
    notePlaceholder: string;
    save: string;
    saving: string;
    permissionDenied: string;
    saveError: string;
    statusOpen: string;
    statusAcknowledged: string;
    statusResolved: string;
    statusDismissed: string;
    sourceActive: string;
    sourceInactive: string;
    followUpNone: string;
  };
  canManage: boolean;
};

const initialState: ExecutiveFollowUpActionState = {};

export function ExecutiveExceptionFollowUpForm({ row, labels, canManage }: Props) {
  const [state, formAction, pending] = useActionState(
    saveExecutiveExceptionFollowUpAction,
    initialState,
  );

  const currentStatus = row.followUp?.status ?? "open";

  return (
    <div className="space-y-3 rounded border border-slate-200 bg-white p-3">
      <div className="flex flex-wrap items-center gap-2 text-xs">
        <span
          className={
            row.sourceCurrentlyDetected
              ? "rounded bg-amber-100 px-2 py-0.5 text-amber-900"
              : "rounded bg-slate-100 px-2 py-0.5 text-slate-700"
          }
        >
          {row.sourceCurrentlyDetected ? labels.sourceActive : labels.sourceInactive}
        </span>
        <span className="text-slate-600">
          {row.followUp ? labels.statusLabel : labels.followUpNone}:{" "}
          {row.followUp?.status ?? "—"}
        </span>
      </div>

      {canManage ? (
        <form
          key={`${row.exceptionKey}-${row.followUp?.status ?? "none"}-${row.followUp?.updatedAt ?? ""}`}
          action={formAction}
          className="space-y-3"
        >
          <input type="hidden" name="exceptionKey" value={row.exceptionKey} />
          <input type="hidden" name="domain" value={row.domain} />
          <input type="hidden" name="exceptionCode" value={row.exceptionCode} />
          <input type="hidden" name="entityType" value={row.entityType} />
          <input type="hidden" name="entityId" value={row.entityId} />

          <div>
            <label className="text-xs font-medium text-slate-700" htmlFor={`status-${row.exceptionKey}`}>
              {labels.statusLabel}
            </label>
            <select
              id={`status-${row.exceptionKey}`}
              name="status"
              defaultValue={currentStatus}
              className="mt-1 block w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
            >
              <option value="open">{labels.statusOpen}</option>
              <option value="acknowledged">{labels.statusAcknowledged}</option>
              <option value="resolved">{labels.statusResolved}</option>
              <option value="dismissed">{labels.statusDismissed}</option>
            </select>
          </div>

          <div>
            <label className="text-xs font-medium text-slate-700" htmlFor={`note-${row.exceptionKey}`}>
              {labels.noteLabel}
            </label>
            <textarea
              id={`note-${row.exceptionKey}`}
              name="note"
              rows={2}
              defaultValue={row.followUp?.latestNote ?? ""}
              placeholder={labels.notePlaceholder}
              className="mt-1 block w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
            />
          </div>

          <button
            type="submit"
            disabled={pending}
            className="rounded bg-slate-900 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-60"
          >
            {pending ? labels.saving : labels.save}
          </button>

          {state.error === "permission_denied" ? (
            <p className="text-xs text-red-700">{labels.permissionDenied}</p>
          ) : null}
          {state.error === "save_error" ? (
            <p className="text-xs text-red-700">{labels.saveError}</p>
          ) : null}
        </form>
      ) : null}

      {!canManage && row.followUp?.latestNote ? (
        <p className="text-sm text-slate-700">{row.followUp.latestNote}</p>
      ) : null}
    </div>
  );
}
