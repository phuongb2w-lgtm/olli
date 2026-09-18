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

type Option = { id: string; label: string };

type Props = {
  classId: string;
  sessionId: string;
  scheduledStartAt: string;
  scheduledEndAt: string;
  teacherId: string;
  roomId: string | null;
  dailyDate: string;
  teachers: Option[];
  rooms: Option[];
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

export function DailySessionOps({
  classId,
  sessionId,
  scheduledStartAt,
  scheduledEndAt,
  teacherId,
  roomId,
  dailyDate,
  teachers,
  rooms,
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

  if (!canMutate) return null;

  const formError =
    errorMessage(t, rescheduleState.error) ||
    errorMessage(t, cancelState.error) ||
    errorMessage(t, subState.error) ||
    errorMessage(t, roomState.error);

  return (
    <div
      className="mt-3 space-y-3 rounded-md border border-slate-200 bg-slate-50 p-3"
      data-testid="daily-session-ops"
    >
      {formError ? (
        <p className="text-sm text-red-700" role="alert">
          {formError}
        </p>
      ) : null}

      <div className="grid gap-3 lg:grid-cols-2">
        <form action={rescheduleAction} className="space-y-2" data-testid="reschedule-form">
          <p className="text-xs font-medium text-slate-700">{t("reschedule")}</p>
          <input type="hidden" name="classId" value={classId} />
          <input type="hidden" name="sessionId" value={sessionId} />
          <input type="hidden" name="returnTo" value="daily" />
          <input type="hidden" name="dailyDate" value={dailyDate} />
          <input
            type="datetime-local"
            name="scheduledStart"
            required
            defaultValue={toDatetimeLocalValue(scheduledStartAt)}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          />
          <input
            type="datetime-local"
            name="scheduledEnd"
            required
            defaultValue={toDatetimeLocalValue(scheduledEndAt)}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          />
          <input
            type="text"
            name="reason"
            required
            placeholder={t("reason")}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          />
          <button
            type="submit"
            disabled={reschedulePending}
            className="rounded bg-slate-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {reschedulePending ? t("saving") : t("reschedule")}
          </button>
        </form>

        <form action={cancelAction} className="space-y-2" data-testid="cancel-form">
          <p className="text-xs font-medium text-slate-700">{t("cancelSession")}</p>
          <input type="hidden" name="classId" value={classId} />
          <input type="hidden" name="sessionId" value={sessionId} />
          <input type="hidden" name="returnTo" value="daily" />
          <input type="hidden" name="dailyDate" value={dailyDate} />
          <input
            type="text"
            name="reason"
            required
            placeholder={t("reason")}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          />
          <button
            type="submit"
            disabled={cancelPending}
            className="rounded border border-red-300 px-2 py-1 text-xs font-medium text-red-800 disabled:opacity-50"
          >
            {cancelPending ? t("saving") : t("cancelSession")}
          </button>
        </form>

        <form action={subAction} className="space-y-2" data-testid="substitute-form">
          <p className="text-xs font-medium text-slate-700">{t("substituteTeacher")}</p>
          <input type="hidden" name="classId" value={classId} />
          <input type="hidden" name="sessionId" value={sessionId} />
          <input type="hidden" name="returnTo" value="daily" />
          <input type="hidden" name="dailyDate" value={dailyDate} />
          <select
            name="teacherId"
            required
            defaultValue={teacherId}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          >
            {teachers.map((opt) => (
              <option key={opt.id} value={opt.id}>
                {opt.label}
              </option>
            ))}
          </select>
          <input
            type="text"
            name="reason"
            required
            placeholder={t("reason")}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          />
          <button
            type="submit"
            disabled={subPending}
            className="rounded bg-slate-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {subPending ? t("saving") : t("substituteTeacher")}
          </button>
        </form>

        <form action={roomAction} className="space-y-2" data-testid="room-change-form">
          <p className="text-xs font-medium text-slate-700">{t("changeRoom")}</p>
          <input type="hidden" name="classId" value={classId} />
          <input type="hidden" name="sessionId" value={sessionId} />
          <input type="hidden" name="returnTo" value="daily" />
          <input type="hidden" name="dailyDate" value={dailyDate} />
          <select
            name="roomId"
            defaultValue={roomId ?? ""}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          >
            <option value="">{t("noRoom")}</option>
            {rooms.map((opt) => (
              <option key={opt.id} value={opt.id}>
                {opt.label}
              </option>
            ))}
          </select>
          <input
            type="text"
            name="reason"
            placeholder={t("reasonOptional")}
            className="w-full rounded border border-slate-300 px-2 py-1 text-sm"
          />
          <button
            type="submit"
            disabled={roomPending}
            className="rounded bg-slate-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
          >
            {roomPending ? t("saving") : t("changeRoom")}
          </button>
        </form>
      </div>
    </div>
  );
}
