"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  createClassScheduleAction,
  updateClassScheduleAction,
  type TeachingActionState,
} from "@/app/actions/teaching";
import { WEEKDAY_CODES } from "@/lib/teaching/constants";
import type { RoomOption, ScheduleItem, TeacherOption } from "@/lib/teaching/query-class-teaching";
import { getRoomCapacityWarning } from "@/lib/teaching/validate-room-input";

type Props = {
  classId: string;
  classCapacity: number | null;
  teachers: TeacherOption[];
  rooms: RoomOption[];
  schedule?: ScheduleItem;
};

const initialState: TeachingActionState = {};

export function ScheduleForm({ classId, classCapacity, teachers, rooms, schedule }: Props) {
  const t = useTranslations("teaching");
  const action = schedule ? updateClassScheduleAction : createClassScheduleAction;
  const [state, formAction, pending] = useActionState(action, initialState);

  const selectedRoomId = state.values?.roomId ?? schedule?.roomId ?? "";
  const selectedRoom = rooms.find((r) => r.id === selectedRoomId);
  const capacityWarning =
    selectedRoom && getRoomCapacityWarning(classCapacity, selectedRoom.capacity);

  return (
    <form action={formAction} className="space-y-4 rounded-lg border border-slate-200 bg-white p-4">
      <h3 className="text-sm font-semibold text-slate-900">
        {schedule ? t("editSchedule") : t("addSchedule")}
      </h3>
      <input type="hidden" name="classId" value={classId} />
      {schedule ? <input type="hidden" name="scheduleId" value={schedule.id} /> : null}

      {state.error === "class_closed" ? (
        <p className="text-sm text-red-700">{t("classClosed")}</p>
      ) : null}
      {state.error === "invalid_schedule_range" ? (
        <p className="text-sm text-red-700">{t("invalidScheduleRange")}</p>
      ) : null}
      {state.error === "schedule_not_active" ? (
        <p className="text-sm text-red-700">{t("scheduleNotActive")}</p>
      ) : null}
      {state.error === "invalid_room" || state.error === "room_inactive" ? (
        <p className="text-sm text-red-700">{t("invalidRoom")}</p>
      ) : null}
      {state.error === "invalid_teacher" ? (
        <p className="text-sm text-red-700">{t("invalidTeacher")}</p>
      ) : null}
      {state.error === "teacher_unavailable" ? (
        <p className="text-sm text-red-700">{t("teacherUnavailable")}</p>
      ) : null}
      {state.error === "teacher_conflict" ? (
        <p className="text-sm text-red-700">{t("teacherConflict")}</p>
      ) : null}
      {state.error === "room_conflict" ? (
        <p className="text-sm text-red-700">{t("roomConflict")}</p>
      ) : null}
      {state.error === "schedule_conflict" ? (
        <p className="text-sm text-red-700">{t("scheduleConflict")}</p>
      ) : null}
      {state.error === "ambiguous_teacher" ? (
        <p className="text-sm text-red-700">{t("ambiguousTeacher")}</p>
      ) : null}
      {state.error === "no_teacher" ? (
        <p className="text-sm text-red-700">{t("noTeacher")}</p>
      ) : null}
      {state.error === "save_error" && !state.fieldErrors ? (
        <p className="text-sm text-red-700">{t("saveError")}</p>
      ) : null}

      <div>
        <label htmlFor="weekdayCode" className="block text-sm font-medium text-slate-700">
          {t("weekday")}
        </label>
        <select
          id="weekdayCode"
          name="weekdayCode"
          required
          defaultValue={state.values?.weekdayCode ?? schedule?.weekdayCode ?? "tue"}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          {WEEKDAY_CODES.map((code) => (
            <option key={code} value={code}>
              {t(`weekdays.${code}`)}
            </option>
          ))}
        </select>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor="startTime" className="block text-sm font-medium text-slate-700">
            {t("startTime")}
          </label>
          <input
            id="startTime"
            name="startTime"
            type="time"
            required
            defaultValue={state.values?.startTime ?? schedule?.startTime ?? ""}
            className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="endTime" className="block text-sm font-medium text-slate-700">
            {t("endTime")}
          </label>
          <input
            id="endTime"
            name="endTime"
            type="time"
            required
            defaultValue={state.values?.endTime ?? schedule?.endTime ?? ""}
            className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
          {state.fieldErrors?.endTime === "beforeStart" ? (
            <p className="mt-1 text-xs text-red-700">{t("endBeforeStart")}</p>
          ) : null}
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor="effectiveFrom" className="block text-sm font-medium text-slate-700">
            {t("effectiveFrom")}
          </label>
          <input
            id="effectiveFrom"
            name="effectiveFrom"
            type="date"
            required
            defaultValue={state.values?.effectiveFrom ?? schedule?.effectiveFrom ?? ""}
            className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="effectiveTo" className="block text-sm font-medium text-slate-700">
            {t("effectiveUntil")}
          </label>
          <input
            id="effectiveTo"
            name="effectiveTo"
            type="date"
            defaultValue={state.values?.effectiveTo ?? schedule?.effectiveTo ?? ""}
            className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
      </div>

      <div>
        <label htmlFor="roomId" className="block text-sm font-medium text-slate-700">
          {t("room")}
        </label>
        <select
          id="roomId"
          name="roomId"
          defaultValue={selectedRoomId}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">{t("noRoom")}</option>
          {rooms.map((room) => (
            <option key={room.id} value={room.id}>
              {room.label}
            </option>
          ))}
        </select>
        {capacityWarning ? (
          <p className="mt-1 text-xs text-amber-700" role="status">
            {t("roomCapacityWarning")}
          </p>
        ) : null}
      </div>

      <div>
        <label htmlFor="teacherId" className="block text-sm font-medium text-slate-700">
          {t("scheduleTeacher")}
        </label>
        <select
          id="teacherId"
          name="teacherId"
          defaultValue={state.values?.teacherId ?? schedule?.teacherId ?? ""}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">{t("useClassPrimaryTeacher")}</option>
          {teachers.map((teacher) => (
            <option key={teacher.id} value={teacher.id}>
              {teacher.label}
            </option>
          ))}
        </select>
      </div>

      <button
        type="submit"
        disabled={pending}
        className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {pending ? t("saving") : schedule ? t("saveSchedule") : t("addSchedule")}
      </button>
    </form>
  );
}
