"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import type { OperationalCalendarEntry } from "@/lib/teaching/query-operational-calendar";

type Option = { id: string; label: string };

type Props = {
  dateFrom: string;
  dateTo: string;
  classId: string;
  teacherId: string;
  roomId: string;
  classes: Option[];
  teachers: Option[];
  rooms: Option[];
  entries: OperationalCalendarEntry[];
  error: string | null;
  timezone: string;
};

function formatLocalTime(iso: string, timeZone: string) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(new Date(iso));
}

function entryBadgeKey(entry: OperationalCalendarEntry): string {
  if (entry.entryType === "projected") return "planned";
  switch (entry.sessionStatus) {
    case "cancelled":
      return "cancelled";
    case "completed":
      return "completed";
    case "in_progress":
      return "inProgress";
    default:
      return "sessionCreated";
  }
}

function badgeClass(key: string): string {
  switch (key) {
    case "cancelled":
      return "bg-slate-200 text-slate-700";
    case "completed":
      return "bg-emerald-50 text-emerald-800";
    case "inProgress":
      return "bg-sky-50 text-sky-800";
    case "planned":
      return "bg-amber-50 text-amber-900";
    default:
      return "bg-slate-100 text-slate-800";
  }
}

export function OperationalCalendarView({
  dateFrom,
  dateTo,
  classId,
  teacherId,
  roomId,
  classes,
  teachers,
  rooms,
  entries,
  error,
  timezone,
}: Props) {
  const t = useTranslations("operations");
  const router = useRouter();

  function goToday() {
    const today = new Date().toISOString().slice(0, 10);
    router.push(`/operations/calendar?from=${today}&to=${today}`);
  }

  return (
    <div className="space-y-6">
      <form method="get" action="/operations/calendar" className="space-y-4 rounded-lg border border-slate-200 bg-white p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div>
            <label htmlFor="from" className="block text-xs font-medium text-slate-600">
              {t("dateFrom")}
            </label>
            <input
              id="from"
              name="from"
              type="date"
              required
              defaultValue={dateFrom}
              className="mt-1 block rounded-md border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label htmlFor="to" className="block text-xs font-medium text-slate-600">
              {t("dateTo")}
            </label>
            <input
              id="to"
              name="to"
              type="date"
              required
              defaultValue={dateTo}
              className="mt-1 block rounded-md border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label htmlFor="classId" className="block text-xs font-medium text-slate-600">
              {t("classFilter")}
            </label>
            <select
              id="classId"
              name="classId"
              defaultValue={classId}
              className="mt-1 block min-w-[10rem] rounded-md border border-slate-300 px-3 py-2 text-sm"
            >
              <option value="">{t("allClasses")}</option>
              {classes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="teacherId" className="block text-xs font-medium text-slate-600">
              {t("teacherFilter")}
            </label>
            <select
              id="teacherId"
              name="teacherId"
              defaultValue={teacherId}
              className="mt-1 block min-w-[10rem] rounded-md border border-slate-300 px-3 py-2 text-sm"
            >
              <option value="">{t("allTeachers")}</option>
              {teachers.map((teach) => (
                <option key={teach.id} value={teach.id}>
                  {teach.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="roomId" className="block text-xs font-medium text-slate-600">
              {t("roomFilter")}
            </label>
            <select
              id="roomId"
              name="roomId"
              defaultValue={roomId}
              className="mt-1 block min-w-[10rem] rounded-md border border-slate-300 px-3 py-2 text-sm"
            >
              <option value="">{t("allRooms")}</option>
              {rooms.map((room) => (
                <option key={room.id} value={room.id}>
                  {room.label}
                </option>
              ))}
            </select>
          </div>
          <button
            type="submit"
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white"
          >
            {t("apply")}
          </button>
          <button
            type="button"
            onClick={goToday}
            className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-800"
          >
            {t("today")}
          </button>
        </div>
      </form>

      {error === "range_too_large" ? (
        <p className="text-sm text-red-700">{t("rangeTooLarge")}</p>
      ) : null}
      {error === "invalid_range" ? (
        <p className="text-sm text-red-700">{t("invalidRange")}</p>
      ) : null}
      {error === "load_error" ? (
        <p className="text-sm text-red-700">{t("loadError")}</p>
      ) : null}

      {entries.length === 0 && !error ? (
        <p className="text-sm text-slate-600">{t("empty")}</p>
      ) : (
        <ul className="divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white">
          {entries.map((entry) => {
            const badge = entryBadgeKey(entry);
            const timeLabel = `${formatLocalTime(entry.startsAt, timezone)}–${formatLocalTime(entry.endsAt, timezone)}`;
            const teacherLabel =
              entry.teacherDisplayName ??
              (entry.teacherResolutionStatus === "multiple_primary_teachers"
                ? t("teacherAmbiguous")
                : entry.teacherResolutionStatus === "teacher_not_resolved"
                  ? t("teacherUnresolved")
                  : t("emptyValue"));
            const roomLabel = entry.roomName ?? entry.roomCode ?? t("noRoom");
            const key =
              entry.teachingSessionId ??
              `${entry.classScheduleId}-${entry.occurrenceDate}-${entry.startsAt}`;

            return (
              <li
                key={key}
                data-entry-type={entry.entryType}
                data-session-status={entry.sessionStatus ?? ""}
                className={`flex flex-col gap-1 px-4 py-3 sm:flex-row sm:items-center sm:justify-between ${
                  entry.sessionStatus === "cancelled" ? "opacity-70" : ""
                }`}
              >
                <div className="min-w-0 space-y-0.5">
                  <p className="text-sm font-medium text-slate-900">
                    <span className="tabular-nums">{timeLabel}</span>
                    <span className="mx-2 text-slate-300">·</span>
                    {entry.entryType === "session" && entry.teachingSessionId ? (
                      <Link
                        href={`/classes/${entry.classId}/teaching/sessions/${entry.teachingSessionId}`}
                        className="underline decoration-slate-300 underline-offset-2 hover:decoration-slate-700"
                      >
                        {entry.className}
                      </Link>
                    ) : (
                      <Link
                        href={`/classes/${entry.classId}/teaching`}
                        className="underline decoration-slate-300 underline-offset-2 hover:decoration-slate-700"
                      >
                        {entry.className}
                      </Link>
                    )}
                  </p>
                  <p className="text-sm text-slate-600">
                    {teacherLabel}
                    <span className="mx-2 text-slate-300">·</span>
                    {roomLabel}
                  </p>
                  <p className="text-xs text-slate-500">{entry.occurrenceDate}</p>
                </div>
                <span
                  className={`inline-flex w-fit shrink-0 rounded px-2 py-0.5 text-xs font-medium ${badgeClass(badge)}`}
                >
                  {t(`status.${badge}`)}
                </span>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
