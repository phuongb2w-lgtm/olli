"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { assignLeadAction, type LeadMutationState } from "@/app/actions/leads";
import type { EligibleAssignee } from "@/lib/leads/query-eligible-assignees";
import type { LeadAssignmentHistoryDetail } from "@/lib/leads/query-lead-detail";

type Props = {
  leadId: string;
  assignedUserId: string | null;
  assignedUserName: string | null;
  assignees: EligibleAssignee[];
  assignmentHistory: LeadAssignmentHistoryDetail[];
  canAssign: boolean;
};

const initialState: LeadMutationState = {};

function ErrorMessage({ error }: { error?: LeadMutationState["error"] }) {
  const t = useTranslations("crm.errors");
  if (!error) return null;
  return (
    <p className="text-sm text-red-700" role="alert">
      {t(error)}
    </p>
  );
}

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString();
}

export function LeadAssignmentPanel({
  leadId,
  assignedUserId,
  assignedUserName,
  assignees,
  assignmentHistory,
  canAssign,
}: Props) {
  const t = useTranslations("crm.assignment");
  const [state, action, pending] = useActionState(assignLeadAction, initialState);

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-base font-semibold text-slate-900">{t("title")}</h2>

      <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
        <div>
          <dt className="font-medium text-slate-600">{t("currentOwner")}</dt>
          <dd className="text-slate-900">
            {assignedUserName ?? t("unassignedLabel")}
          </dd>
        </div>
      </dl>

      {canAssign ? (
        <form action={action} className="mt-4 space-y-3 border-t border-slate-100 pt-4">
          <input type="hidden" name="leadId" value={leadId} />
          <div>
            <label htmlFor="assignedUserId" className="mb-1 block text-sm text-slate-700">
              {assignedUserId ? t("reassignTo") : t("assignTo")}
            </label>
            {assignees.length === 0 ? (
              <p className="text-sm text-slate-500">{t("noEligibleAssignees")}</p>
            ) : (
              <select
                id="assignedUserId"
                name="assignedUserId"
                defaultValue=""
                className="w-full max-w-md rounded border border-slate-300 px-3 py-2 text-sm"
              >
                <option value="">{t("selectAssignee")}</option>
                {assignees.map((user) => (
                  <option key={user.userId} value={user.userId}>
                    {user.displayName}
                  </option>
                ))}
              </select>
            )}
          </div>
          <div>
            <label htmlFor="assignmentNote" className="mb-1 block text-sm text-slate-700">
              {t("note")}
            </label>
            <textarea
              id="assignmentNote"
              name="note"
              rows={2}
              className="w-full max-w-md rounded border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="submit"
              disabled={pending || assignees.length === 0}
              className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
            >
              {pending ? t("saving") : assignedUserId ? t("reassign") : t("assign")}
            </button>
            {assignedUserId ? (
              <button
                type="submit"
                name="unassign"
                value="true"
                disabled={pending}
                className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-800 hover:bg-slate-50 disabled:opacity-60"
              >
                {pending ? t("saving") : t("unassign")}
              </button>
            ) : null}
          </div>
          <ErrorMessage error={state.error} />
        </form>
      ) : null}

      <div className="mt-4 border-t border-slate-100 pt-4">
        <h3 className="text-sm font-medium text-slate-800">{t("historyTitle")}</h3>
        {assignmentHistory.length === 0 ? (
          <p className="mt-2 text-sm text-slate-500">{t("emptyHistory")}</p>
        ) : (
          <ol className="mt-3 space-y-3">
            {assignmentHistory.map((entry) => (
              <li key={entry.id} className="text-sm text-slate-800">
                <p className="text-xs text-slate-500">{formatDateTime(entry.changedAt)}</p>
                <p>
                  {t("historyEntry", {
                    from: entry.previousAssigneeName ?? t("unassignedLabel"),
                    to: entry.newAssigneeName ?? t("unassignedLabel"),
                  })}
                </p>
                {entry.changedByName ? (
                  <p className="text-xs text-slate-600">{t("changedBy", { name: entry.changedByName })}</p>
                ) : null}
                {entry.note ? <p className="text-slate-600">{entry.note}</p> : null}
              </li>
            ))}
          </ol>
        )}
      </div>
    </section>
  );
}
