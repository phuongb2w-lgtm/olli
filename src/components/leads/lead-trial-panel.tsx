"use client";

import { useActionState, useMemo, useState } from "react";
import { useTranslations } from "next-intl";
import {
  cancelLeadTrialAction,
  completeLeadTrialAction,
  markLeadTrialNoShowAction,
  rescheduleLeadTrialAction,
  scheduleLeadTrialAction,
  type LeadMutationState,
} from "@/app/actions/leads";
import type { EligibleTrialClass, TrialTeachingSession } from "@/lib/leads/query-eligible-trial-classes";
import type { LeadCandidateDetail, LeadTrialDetail, LeadTrialEventDetail } from "@/lib/leads/query-lead-detail";

type Props = {
  leadId: string;
  candidates: LeadCandidateDetail[];
  trials: LeadTrialDetail[];
  trialEvents: LeadTrialEventDetail[];
  eligibleClasses: EligibleTrialClass[];
  sessionsByClass: Record<string, TrialTeachingSession[]>;
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

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString();
}

function toLocalInputValue(iso: string | null): string {
  if (!iso) return "";
  const date = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function LeadTrialPanel({
  leadId,
  candidates,
  trials,
  trialEvents,
  eligibleClasses,
  sessionsByClass,
  canUpdate,
}: Props) {
  const t = useTranslations("crm.trial");

  const [scheduleState, scheduleAction, schedulePending] = useActionState(
    scheduleLeadTrialAction,
    initialState,
  );
  const [selectedClassId, setSelectedClassId] = useState("");
  const [selectedSessionId, setSelectedSessionId] = useState("");
  const sessions = useMemo(
    () => (selectedClassId ? sessionsByClass[selectedClassId] ?? [] : []),
    [selectedClassId, sessionsByClass],
  );

  const eventsByTrial = useMemo(() => {
    const map = new Map<string, LeadTrialEventDetail[]>();
    for (const event of trialEvents) {
      const list = map.get(event.trialId) ?? [];
      list.push(event);
      map.set(event.trialId, list);
    }
    for (const [, list] of map) {
      list.sort((a, b) => b.occurredAt.localeCompare(a.occurredAt));
    }
    return map;
  }, [trialEvents]);

  const candidateName = (candidateId: string) =>
    candidates.find((c) => c.id === candidateId)?.displayName ?? t("unknownCandidate");

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-base font-semibold text-slate-900">{t("title")}</h2>

      {trials.length === 0 ? (
        <p className="mt-3 text-sm text-slate-500">{t("emptyTrials")}</p>
      ) : (
        <ul className="mt-4 space-y-4">
          {trials.map((trial) => (
            <TrialCard
              key={trial.id}
              trial={trial}
              candidateName={candidateName(trial.candidateId)}
              events={eventsByTrial.get(trial.id) ?? []}
              eligibleClasses={eligibleClasses}
              sessionsByClass={sessionsByClass}
              canUpdate={canUpdate}
              leadId={leadId}
            />
          ))}
        </ul>
      )}

      {canUpdate && candidates.length > 0 && eligibleClasses.length > 0 ? (
        <form action={scheduleAction} className="mt-6 space-y-3 border-t border-slate-100 pt-4">
          <input type="hidden" name="leadId" value={leadId} />
          <h3 className="text-sm font-semibold text-slate-900">{t("scheduleTitle")}</h3>
          <ErrorMessage error={scheduleState.error} />

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <label htmlFor="trialCandidateId" className="mb-1 block text-sm text-slate-700">
                {t("candidate")}
              </label>
              <select
                id="trialCandidateId"
                name="candidateId"
                required
                className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                defaultValue=""
              >
                <option value="">{t("selectCandidate")}</option>
                {candidates.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.displayName}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor="trialClassId" className="mb-1 block text-sm text-slate-700">
                {t("class")}
              </label>
              <select
                id="trialClassId"
                name="classId"
                required
                className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                value={selectedClassId}
                onChange={(e) => setSelectedClassId(e.target.value)}
              >
                <option value="">{t("selectClass")}</option>
                {eligibleClasses.map((c) => (
                  <option key={c.classId} value={c.classId}>
                    {c.className}
                  </option>
                ))}
              </select>
            </div>
            <div className="sm:col-span-2">
              <label htmlFor="trialSessionId" className="mb-1 block text-sm text-slate-700">
                {t("sessionOptional")}
              </label>
              <select
                id="trialSessionId"
                name="teachingSessionId"
                className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                value={selectedSessionId}
                onChange={(e) => setSelectedSessionId(e.target.value)}
                disabled={!selectedClassId || sessions.length === 0}
              >
                <option value="">{t("noSession")}</option>
                {sessions.map((s) => (
                  <option key={s.sessionId} value={s.sessionId}>
                    {formatDateTime(s.scheduledStartAt)} — {formatDateTime(s.scheduledEndAt)}
                  </option>
                ))}
              </select>
              <p className="mt-1 text-xs text-slate-500">{t("sessionPrecedenceHint")}</p>
            </div>
            {!selectedSessionId ? (
              <>
                <div>
                  <label htmlFor="trialStartAt" className="mb-1 block text-sm text-slate-700">
                    {t("scheduledStart")}
                  </label>
                  <input
                    id="trialStartAt"
                    name="scheduledStartAt"
                    type="datetime-local"
                    required={!selectedSessionId}
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label htmlFor="trialEndAt" className="mb-1 block text-sm text-slate-700">
                    {t("scheduledEnd")}
                  </label>
                  <input
                    id="trialEndAt"
                    name="scheduledEndAt"
                    type="datetime-local"
                    required={!selectedSessionId}
                    className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
                  />
                </div>
              </>
            ) : null}
            <div className="sm:col-span-2">
              <label htmlFor="trialNote" className="mb-1 block text-sm text-slate-700">
                {t("note")}
              </label>
              <textarea
                id="trialNote"
                name="note"
                rows={2}
                className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
              />
            </div>
          </div>
          <button
            type="submit"
            disabled={schedulePending}
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            {schedulePending ? t("saving") : t("schedule")}
          </button>
        </form>
      ) : null}

      {canUpdate && eligibleClasses.length === 0 ? (
        <p className="mt-4 text-sm text-slate-500">{t("noEligibleClasses")}</p>
      ) : null}
    </section>
  );
}

function TrialCard({
  trial,
  candidateName,
  events,
  eligibleClasses,
  sessionsByClass,
  canUpdate,
  leadId,
}: {
  trial: LeadTrialDetail;
  candidateName: string;
  events: LeadTrialEventDetail[];
  eligibleClasses: EligibleTrialClass[];
  sessionsByClass: Record<string, TrialTeachingSession[]>;
  canUpdate: boolean;
  leadId: string;
}) {
  const t = useTranslations("crm.trial");
  const tStatus = useTranslations("status.trial");
  const tEvent = useTranslations("event.trial");

  const [rescheduleState, rescheduleAction, reschedulePending] = useActionState(
    rescheduleLeadTrialAction,
    initialState,
  );
  const [completeState, completeAction, completePending] = useActionState(
    completeLeadTrialAction,
    initialState,
  );
  const [cancelState, cancelAction, cancelPending] = useActionState(
    cancelLeadTrialAction,
    initialState,
  );
  const [noShowState, noShowAction, noShowPending] = useActionState(
    markLeadTrialNoShowAction,
    initialState,
  );

  const [classId, setClassId] = useState(trial.classId);
  const [sessionId, setSessionId] = useState(trial.teachingSessionId ?? "");
  const sessions = sessionsByClass[classId] ?? [];
  const isScheduled = trial.status === "scheduled";

  return (
    <li className="rounded border border-slate-100 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium text-slate-900">{candidateName}</span>
        <span className="rounded bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700">
          {tStatus(trial.status)}
        </span>
      </div>
      <dl className="mt-2 grid gap-1 text-sm sm:grid-cols-2">
        <div>
          <dt className="text-slate-600">{t("class")}</dt>
          <dd className="text-slate-900">{trial.className}</dd>
        </div>
        <div>
          <dt className="text-slate-600">{t("scheduledStart")}</dt>
          <dd className="text-slate-900">{formatDateTime(trial.scheduledStartAt)}</dd>
        </div>
        <div>
          <dt className="text-slate-600">{t("scheduledEnd")}</dt>
          <dd className="text-slate-900">{formatDateTime(trial.scheduledEndAt)}</dd>
        </div>
        {trial.teachingSessionId ? (
          <div>
            <dt className="text-slate-600">{t("session")}</dt>
            <dd className="text-slate-900">{formatDateTime(trial.scheduledStartAt)}</dd>
          </div>
        ) : null}
        {trial.outcomeNote ? (
          <div className="sm:col-span-2">
            <dt className="text-slate-600">{t("outcome")}</dt>
            <dd className="text-slate-900">{trial.outcomeNote}</dd>
          </div>
        ) : null}
      </dl>

      {events.length > 0 ? (
        <div className="mt-3">
          <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {t("historyTitle")}
          </h4>
          <ol className="mt-2 space-y-2">
            {events.map((event) => (
              <li key={event.id} className="text-sm text-slate-700">
                <span className="font-medium">{tEvent(event.eventType)}</span>
                {" · "}
                {formatDateTime(event.occurredAt)}
                {event.changedByName ? ` · ${event.changedByName}` : ""}
                {event.note ? ` — ${event.note}` : ""}
              </li>
            ))}
          </ol>
        </div>
      ) : null}

      {canUpdate && isScheduled ? (
        <div className="mt-4 space-y-4 border-t border-slate-100 pt-4">
          <form action={rescheduleAction} className="space-y-2">
            <input type="hidden" name="leadId" value={leadId} />
            <input type="hidden" name="trialId" value={trial.id} />
            <h4 className="text-sm font-medium text-slate-900">{t("rescheduleTitle")}</h4>
            <ErrorMessage error={rescheduleState.error} />
            <select
              name="classId"
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
              value={classId}
              onChange={(e) => {
                setClassId(e.target.value);
                setSessionId("");
              }}
            >
              {eligibleClasses.map((c) => (
                <option key={c.classId} value={c.classId}>
                  {c.className}
                </option>
              ))}
            </select>
            <select
              name="teachingSessionId"
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
              value={sessionId}
              onChange={(e) => setSessionId(e.target.value)}
            >
              <option value="">{t("noSession")}</option>
              {sessions.map((s) => (
                <option key={s.sessionId} value={s.sessionId}>
                  {formatDateTime(s.scheduledStartAt)}
                </option>
              ))}
            </select>
            {!sessionId ? (
              <div className="grid gap-2 sm:grid-cols-2">
                <input
                  name="scheduledStartAt"
                  type="datetime-local"
                  defaultValue={toLocalInputValue(trial.scheduledStartAt)}
                  className="rounded border border-slate-300 px-3 py-2 text-sm"
                />
                <input
                  name="scheduledEndAt"
                  type="datetime-local"
                  defaultValue={toLocalInputValue(trial.scheduledEndAt)}
                  className="rounded border border-slate-300 px-3 py-2 text-sm"
                />
              </div>
            ) : null}
            <textarea
              name="note"
              rows={2}
              placeholder={t("note")}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            <button
              type="submit"
              disabled={reschedulePending}
              className="rounded border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50 disabled:opacity-50"
            >
              {reschedulePending ? t("saving") : t("reschedule")}
            </button>
          </form>

          <form action={completeAction} className="space-y-2">
            <input type="hidden" name="leadId" value={leadId} />
            <input type="hidden" name="trialId" value={trial.id} />
            <ErrorMessage error={completeState.error} />
            <textarea
              name="outcomeNote"
              rows={2}
              placeholder={t("outcomePlaceholder")}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            <button
              type="submit"
              disabled={completePending}
              className="rounded border border-emerald-300 px-3 py-1.5 text-sm text-emerald-800 hover:bg-emerald-50 disabled:opacity-50"
            >
              {completePending ? t("saving") : t("complete")}
            </button>
          </form>

          <div className="flex flex-wrap gap-2">
            <form action={cancelAction}>
              <input type="hidden" name="leadId" value={leadId} />
              <input type="hidden" name="trialId" value={trial.id} />
              <button
                type="submit"
                disabled={cancelPending}
                className="rounded border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50 disabled:opacity-50"
              >
                {cancelPending ? t("saving") : t("cancel")}
              </button>
            </form>
            <form action={noShowAction}>
              <input type="hidden" name="leadId" value={leadId} />
              <input type="hidden" name="trialId" value={trial.id} />
              <button
                type="submit"
                disabled={noShowPending}
                className="rounded border border-amber-300 px-3 py-1.5 text-sm text-amber-900 hover:bg-amber-50 disabled:opacity-50"
              >
                {noShowPending ? t("saving") : t("noShow")}
              </button>
            </form>
          </div>
          <ErrorMessage error={cancelState.error ?? noShowState.error} />
        </div>
      ) : null}
    </li>
  );
}
