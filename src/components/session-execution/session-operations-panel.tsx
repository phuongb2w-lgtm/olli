"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  cancelTeachingSessionAction,
  changeSessionRoomAction,
  rescheduleTeachingSessionAction,
  substituteSessionTeacherAction,
  type SessionOpsActionState,
} from "@/app/actions/session-operations";
import type { TeachingSessionChange } from "@/lib/teaching/query-session-changes";

type Option = { id: string; label: string };

type Props = {
  classId: string;
  sessionId: string;
  status: string;
  scheduledStartAt: string;
  scheduledEndAt: string;
  teacherId: string;
  roomId: string | null;
  teachers: Option[];
  rooms: Option[];
  changes: TeachingSessionChange[];
  canMutate: boolean;
};

const initialState: SessionOpsActionState = {};

function toDatetimeLocalValue(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function errorMessage(
  t: ReturnType<typeof useTranslations>,
  error: SessionOpsActionState["error"],
): string | null {
  if (!error) return null;
  const key = `errors.${error}`;
  try {
    return t(key);
  } catch {
    return t("errors.save_error");
  }
}

export function SessionOperationsPanel({
  classId,
  sessionId,
  status,
  scheduledStartAt,
  scheduledEndAt,
  teacherId,
  roomId,
  teachers,
  rooms,
  changes,
  canMutate,
}: Props) {
  const t = useTranslations("sessionOperations");
  const [rescheduleState, rescheduleAction, reschedulePending] = useActionState(
    rescheduleTeachingSessionAction,
    initialState,
  );
  const [cancelState, cancelAction, cancelPending] = useActionState(
    cancelTeachingSessionAction,
    initialState,
  );
  const [subState, subAction, subPending] = useActionState(
    substituteSessionTeacherAction,
    initialState,
  );
  const [roomState, roomAction, roomPending] = useActionState(
    changeSessionRoomAction,
    initialState,
  );

  const mutable = canMutate && status === "scheduled";
  const formError =
    errorMessage(t, rescheduleState.error) ||
    errorMessage(t, cancelState.error) ||
    errorMessage(t, subState.error) ||
    errorMessage(t, roomState.error);

  return (
    <section className="space-y-4" data-testid="session-operations">
      <h2 className="text-lg font-semibold text-slate-900">{t("title")}</h2>
      <p className="text-sm text-slate-600">{t("subtitle")}</p>

      {formError ? (
        <p className="text-sm text-red-700" role="alert">
          {formError}
        </p>
      ) : null}

      {mutable ? (
        <div className="grid gap-4 lg:grid-cols-2">
          <form
            action={rescheduleAction}
            className="space-y-3 rounded-lg border border-slate-200 bg-white p-4"
            data-testid="reschedule-form"
          >
            <h3 className="text-sm font-medium text-slate-900">{t("reschedule")}</h3>
            <input type="hidden" name="classId" value={classId} />
            <input type="hidden" name="sessionId" value={sessionId} />
            <label className="block text-sm text-slate-700">
              {t("newStart")}
              <input
                type="datetime-local"
                name="scheduledStart"
                required
                defaultValue={toDatetimeLocalValue(scheduledStartAt)}
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              />
            </label>
            <label className="block text-sm text-slate-700">
              {t("newEnd")}
              <input
                type="datetime-local"
                name="scheduledEnd"
                required
                defaultValue={toDatetimeLocalValue(scheduledEndAt)}
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              />
            </label>
            <label className="block text-sm text-slate-700">
              {t("reason")}
              <input
                type="text"
                name="reason"
                required
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              />
            </label>
            <button
              type="submit"
              disabled={reschedulePending}
              className="rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
            >
              {reschedulePending ? t("saving") : t("reschedule")}
            </button>
          </form>

          <form
            action={cancelAction}
            className="space-y-3 rounded-lg border border-slate-200 bg-white p-4"
            data-testid="cancel-form"
          >
            <h3 className="text-sm font-medium text-slate-900">{t("cancelSession")}</h3>
            <input type="hidden" name="classId" value={classId} />
            <input type="hidden" name="sessionId" value={sessionId} />
            <label className="block text-sm text-slate-700">
              {t("reason")}
              <input
                type="text"
                name="reason"
                required
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              />
            </label>
            <button
              type="submit"
              disabled={cancelPending}
              className="rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 disabled:opacity-50"
            >
              {cancelPending ? t("saving") : t("cancelSession")}
            </button>
          </form>

          <form
            action={subAction}
            className="space-y-3 rounded-lg border border-slate-200 bg-white p-4"
            data-testid="substitute-form"
          >
            <h3 className="text-sm font-medium text-slate-900">{t("substituteTeacher")}</h3>
            <input type="hidden" name="classId" value={classId} />
            <input type="hidden" name="sessionId" value={sessionId} />
            <label className="block text-sm text-slate-700">
              {t("newTeacher")}
              <select
                name="teacherId"
                required
                defaultValue={teacherId}
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              >
                {teachers.map((opt) => (
                  <option key={opt.id} value={opt.id}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block text-sm text-slate-700">
              {t("reason")}
              <input
                type="text"
                name="reason"
                required
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              />
            </label>
            <button
              type="submit"
              disabled={subPending}
              className="rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
            >
              {subPending ? t("saving") : t("substituteTeacher")}
            </button>
          </form>

          <form
            action={roomAction}
            className="space-y-3 rounded-lg border border-slate-200 bg-white p-4"
            data-testid="room-change-form"
          >
            <h3 className="text-sm font-medium text-slate-900">{t("changeRoom")}</h3>
            <input type="hidden" name="classId" value={classId} />
            <input type="hidden" name="sessionId" value={sessionId} />
            <label className="block text-sm text-slate-700">
              {t("newRoom")}
              <select
                name="roomId"
                defaultValue={roomId ?? ""}
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              >
                <option value="">{t("noRoom")}</option>
                {rooms.map((opt) => (
                  <option key={opt.id} value={opt.id}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block text-sm text-slate-700">
              {t("reasonOptional")}
              <input
                type="text"
                name="reason"
                className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              />
            </label>
            <button
              type="submit"
              disabled={roomPending}
              className="rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
            >
              {roomPending ? t("saving") : t("changeRoom")}
            </button>
          </form>
        </div>
      ) : (
        <p className="text-sm text-slate-600">{t("mutationsUnavailable")}</p>
      )}

      <div className="space-y-2" data-testid="session-change-history">
        <h3 className="text-sm font-medium text-slate-900">{t("changeHistory")}</h3>
        {changes.length === 0 ? (
          <p className="text-sm text-slate-600">{t("noHistory")}</p>
        ) : (
          <ul className="divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white">
            {changes.map((change) => (
              <li key={change.id} className="px-4 py-3 text-sm" data-change-type={change.changeType}>
                <p className="font-medium text-slate-900">
                  {t(`changeTypes.${change.changeType}`)}
                </p>
                {change.reason ? (
                  <p className="text-slate-600">
                    {t("reason")}: {change.reason}
                  </p>
                ) : null}
                <p className="text-xs text-slate-500">
                  {new Date(change.occurredAt).toLocaleString()}
                </p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
