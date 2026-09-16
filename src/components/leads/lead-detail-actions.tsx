"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  addLeadActivityAction,
  completeLeadFollowUpAction,
  createLeadFollowUpAction,
  transitionLeadStatusAction,
  type LeadMutationState,
} from "@/app/actions/leads";
import {
  LEAD_TRANSITION_TARGETS,
  LEAD_USER_ACTIVITY_TYPES,
  type LeadStatus,
} from "@/lib/leads/constants";

type Props = {
  leadId: string;
  status: LeadStatus;
  lostReasons: { id: string; displayName: string }[];
  pendingFollowUps: { id: string; dueAt: string; note: string | null }[];
  canUpdate: boolean;
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

export function LeadDetailActions({
  leadId,
  status,
  lostReasons,
  pendingFollowUps,
  canUpdate,
}: Props) {
  const t = useTranslations("crm.actions");
  const tStatus = useTranslations("status.lead");
  const tActivity = useTranslations("activity.lead");

  const [transitionState, transitionAction, transitionPending] = useActionState(
    transitionLeadStatusAction,
    initialState,
  );
  const [activityState, activityAction, activityPending] = useActionState(
    addLeadActivityAction,
    initialState,
  );
  const [followUpState, followUpAction, followUpPending] = useActionState(
    createLeadFollowUpAction,
    initialState,
  );
  const [completeState, completeAction, completePending] = useActionState(
    completeLeadFollowUpAction,
    initialState,
  );

  if (!canUpdate) return null;

  const targets = LEAD_TRANSITION_TARGETS[status] ?? [];

  return (
    <section className="space-y-6 rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-base font-semibold text-slate-900">{t("title")}</h2>

      {targets.length > 0 ? (
        <form action={transitionAction} className="space-y-3 border-b border-slate-100 pb-4">
          <input type="hidden" name="leadId" value={leadId} />
          <h3 className="text-sm font-medium text-slate-800">{t("transitionTitle")}</h3>
          <div className="flex flex-wrap gap-3">
            <div>
              <label htmlFor="toStatus" className="mb-1 block text-sm text-slate-700">
                {t("toStatus")}
              </label>
              <select
                id="toStatus"
                name="toStatus"
                required
                className="rounded border border-slate-300 px-3 py-2 text-sm"
              >
                <option value="">{t("selectStatus")}</option>
                {targets.map((value) => (
                  <option key={value} value={value}>
                    {tStatus(value)}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor="lostReasonId" className="mb-1 block text-sm text-slate-700">
                {t("lostReason")}
              </label>
              <select
                id="lostReasonId"
                name="lostReasonId"
                className="rounded border border-slate-300 px-3 py-2 text-sm"
              >
                <option value="">{t("lostReasonOptional")}</option>
                {lostReasons.map((reason) => (
                  <option key={reason.id} value={reason.id}>
                    {reason.displayName}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div>
            <label htmlFor="transitionNotes" className="mb-1 block text-sm text-slate-700">
              {t("notes")}
            </label>
            <textarea
              id="transitionNotes"
              name="notes"
              rows={2}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
          <button
            type="submit"
            disabled={transitionPending}
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
          >
            {transitionPending ? t("saving") : t("applyTransition")}
          </button>
          <ErrorMessage error={transitionState.error} />
        </form>
      ) : null}

      <form action={activityAction} className="space-y-3 border-b border-slate-100 pb-4">
        <input type="hidden" name="leadId" value={leadId} />
        <h3 className="text-sm font-medium text-slate-800">{t("addActivityTitle")}</h3>
        <div>
          <label htmlFor="activityType" className="mb-1 block text-sm text-slate-700">
            {t("activityType")}
          </label>
          <select
            id="activityType"
            name="activityType"
            required
            className="rounded border border-slate-300 px-3 py-2 text-sm"
          >
            {LEAD_USER_ACTIVITY_TYPES.map((type) => (
              <option key={type} value={type}>
                {tActivity(type)}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="activityContent" className="mb-1 block text-sm text-slate-700">
            {t("activityContent")}
          </label>
          <textarea
            id="activityContent"
            name="content"
            rows={3}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <button
          type="submit"
          disabled={activityPending}
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
        >
          {activityPending ? t("saving") : t("addActivity")}
        </button>
        <ErrorMessage error={activityState.error} />
      </form>

      <form action={followUpAction} className="space-y-3 border-b border-slate-100 pb-4">
        <input type="hidden" name="leadId" value={leadId} />
        <h3 className="text-sm font-medium text-slate-800">{t("createFollowUpTitle")}</h3>
        <div>
          <label htmlFor="dueAt" className="mb-1 block text-sm text-slate-700">
            {t("dueAt")}
          </label>
          <input
            id="dueAt"
            name="dueAt"
            type="datetime-local"
            required
            className="rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="followUpNote" className="mb-1 block text-sm text-slate-700">
            {t("notes")}
          </label>
          <textarea
            id="followUpNote"
            name="note"
            rows={2}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <button
          type="submit"
          disabled={followUpPending}
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
        >
          {followUpPending ? t("saving") : t("createFollowUp")}
        </button>
        <ErrorMessage error={followUpState.error} />
      </form>

      {pendingFollowUps.length > 0 ? (
        <div className="space-y-3">
          <h3 className="text-sm font-medium text-slate-800">{t("completeFollowUpTitle")}</h3>
          {pendingFollowUps.map((followUp) => (
            <form key={followUp.id} action={completeAction} className="flex flex-wrap items-end gap-2">
              <input type="hidden" name="followUpId" value={followUp.id} />
              <input type="hidden" name="leadId" value={leadId} />
              <p className="text-sm text-slate-700">
                {new Date(followUp.dueAt).toLocaleString()}
                {followUp.note ? ` — ${followUp.note}` : ""}
              </p>
              <button
                type="submit"
                disabled={completePending}
                className="rounded border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50 disabled:opacity-60"
              >
                {completePending ? t("saving") : t("markComplete")}
              </button>
            </form>
          ))}
          <ErrorMessage error={completeState.error} />
        </div>
      ) : null}
    </section>
  );
}
