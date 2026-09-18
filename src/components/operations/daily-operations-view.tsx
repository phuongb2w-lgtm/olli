"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { DailyOccurrenceList } from "@/components/operations/daily-occurrence-list";
import { DailySummaryCards } from "@/components/operations/daily-summary";
import type {
  DailyAttentionItem,
  DailyOperationsEntry,
  DailySummary,
} from "@/lib/teaching/query-daily-operations";

type Option = { id: string; label: string };

type Props = {
  date: string;
  today: string;
  isToday: boolean;
  classId: string;
  teacherId: string;
  roomId: string;
  classes: Option[];
  teachers: Option[];
  rooms: Option[];
  entries: DailyOperationsEntry[];
  summary: DailySummary;
  attentionItems: DailyAttentionItem[];
  error: string | null;
  timezone: string;
  canMutate: boolean;
};

function shiftDate(isoDate: string, deltaDays: number): string {
  const [y, m, d] = isoDate.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + deltaDays));
  return dt.toISOString().slice(0, 10);
}

function buildQuery(date: string, classId: string, teacherId: string, roomId: string): string {
  const params = new URLSearchParams();
  params.set("date", date);
  if (classId) params.set("classId", classId);
  if (teacherId) params.set("teacherId", teacherId);
  if (roomId) params.set("roomId", roomId);
  return params.toString();
}

export function DailyOperationsView({
  date,
  today,
  isToday,
  classId,
  teacherId,
  roomId,
  classes,
  teachers,
  rooms,
  entries,
  summary,
  attentionItems,
  error,
  timezone,
  canMutate,
}: Props) {
  const t = useTranslations("operationsDaily");
  const router = useRouter();

  const errorMessage =
    error === "invalid_date"
      ? t("invalidDate")
      : error === "permission_denied"
        ? t("denied")
        : error === "invalid_class"
          ? t("invalidClass")
          : error === "invalid_teacher"
            ? t("invalidTeacher")
            : error === "invalid_room"
              ? t("invalidRoom")
              : error
                ? t("loadError")
                : null;

  function navigate(nextDate: string) {
    router.push(`/operations?${buildQuery(nextDate, classId, teacherId, roomId)}`);
  }

  return (
    <div className="space-y-6" data-testid="daily-operations-view">
      <DailySummaryCards summary={summary} />

      <section
        className="rounded-lg border border-slate-200 bg-white p-4"
        data-testid="planning-gaps-banner"
      >
        <h2 className="text-sm font-semibold text-slate-900">{t("attentionTitle")}</h2>
        {attentionItems.length === 0 ? (
          <p className="mt-2 text-sm text-slate-600">{t("noPlanningGaps")}</p>
        ) : (
          <ul className="mt-2 space-y-1">
            {attentionItems.map((item) => (
              <li key={item.id} className="text-sm text-amber-900">
                {t(item.labelKey, { className: item.className })}
              </li>
            ))}
          </ul>
        )}
      </section>

      <form
        method="get"
        action="/operations"
        className="space-y-4 rounded-lg border border-slate-200 bg-white p-4"
      >
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex items-end gap-1">
            <button
              type="button"
              onClick={() => navigate(shiftDate(date, -1))}
              className="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-800"
              aria-label={t("previousDay")}
            >
              ←
            </button>
            <div>
              <label htmlFor="date" className="block text-xs font-medium text-slate-600">
                {t("dateLabel")}
              </label>
              <input
                id="date"
                name="date"
                type="date"
                required
                defaultValue={date}
                className="mt-1 block rounded-md border border-slate-300 px-3 py-2 text-sm"
              />
            </div>
            <button
              type="button"
              onClick={() => navigate(shiftDate(date, 1))}
              className="rounded-md border border-slate-300 px-3 py-2 text-sm font-medium text-slate-800"
              aria-label={t("nextDay")}
            >
              →
            </button>
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
          {!isToday ? (
            <button
              type="button"
              onClick={() => navigate(today)}
              className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-800"
            >
              {t("today")}
            </button>
          ) : null}
        </div>
        {isToday ? (
          <p className="text-xs text-slate-500">{t("viewingToday", { date })}</p>
        ) : (
          <p className="text-xs text-slate-500">{t("viewingDate", { date })}</p>
        )}
      </form>

      {errorMessage ? (
        <p className="text-sm text-red-700" role="alert">
          {errorMessage}
        </p>
      ) : null}

      <DailyOccurrenceList
        entries={entries}
        timezone={timezone}
        isToday={isToday}
        dailyDate={date}
        teachers={teachers}
        rooms={rooms}
        canMutate={canMutate}
      />
    </div>
  );
}
