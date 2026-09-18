"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  formatMinutesAsHours,
  type OperationalPlanningGaps,
  type RoomUsageRow,
  type TeacherWorkloadRow,
} from "@/lib/teaching/query-workload-analytics";

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
  teacherRows: TeacherWorkloadRow[];
  roomRows: RoomUsageRow[];
  planningGaps: OperationalPlanningGaps | null;
  error: string | null;
};

export function WorkloadAnalyticsView({
  dateFrom,
  dateTo,
  classId,
  teacherId,
  roomId,
  classes,
  teachers,
  rooms,
  teacherRows,
  roomRows,
  planningGaps,
  error,
}: Props) {
  const t = useTranslations("operationsAnalytics");
  const router = useRouter();

  function goThisMonth() {
    const now = new Date();
    const from = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
      .toISOString()
      .slice(0, 10);
    const to = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0))
      .toISOString()
      .slice(0, 10);
    router.push(`/operations/workload?from=${from}&to=${to}`);
  }

  const errorMessage =
    error === "range_too_large"
      ? t("rangeTooLarge")
      : error === "invalid_range"
        ? t("invalidRange")
        : error === "permission_denied"
          ? t("denied")
          : error
            ? t("loadError")
            : null;

  return (
    <div className="space-y-6">
      <form
        method="get"
        action="/operations/workload"
        className="space-y-4 rounded-lg border border-slate-200 bg-white p-4"
      >
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
          <button
            type="button"
            onClick={goThisMonth}
            className="rounded-md border border-slate-300 px-3 py-2 text-sm text-slate-700 hover:bg-slate-50"
          >
            {t("thisMonth")}
          </button>
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
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
          >
            {t("apply")}
          </button>
        </div>
      </form>

      {errorMessage && (
        <p className="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
          {errorMessage}
        </p>
      )}

      {planningGaps &&
        (planningGaps.unresolvedProjectedSessionCount > 0 ||
          planningGaps.roomlessProjectedSessionCount > 0) && (
          <section className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">
            <h2 className="font-medium">{t("planningGapsTitle")}</h2>
            <ul className="mt-2 list-inside list-disc space-y-1">
              {planningGaps.unresolvedProjectedSessionCount > 0 && (
                <li>
                  {t("noAssignedTeacher", {
                    count: planningGaps.unresolvedProjectedSessionCount,
                    hours: formatMinutesAsHours(planningGaps.unresolvedProjectedMinutes),
                  })}
                </li>
              )}
              {planningGaps.roomlessProjectedSessionCount > 0 && (
                <li>
                  {t("noAssignedRoom", {
                    count: planningGaps.roomlessProjectedSessionCount,
                    hours: formatMinutesAsHours(planningGaps.roomlessProjectedMinutes),
                  })}
                </li>
              )}
            </ul>
          </section>
        )}

      <section className="space-y-3">
        <h2 className="text-lg font-semibold text-slate-900">{t("teacherWorkloadTitle")}</h2>
        <p className="text-sm text-slate-600">{t("teacherWorkloadHint")}</p>
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-600">
              <tr>
                <th className="px-4 py-3">{t("teacherColumn")}</th>
                <th className="px-4 py-3">{t("scheduledSessions")}</th>
                <th className="px-4 py-3">{t("scheduledHours")}</th>
                <th className="px-4 py-3">{t("projectedSessions")}</th>
                <th className="px-4 py-3">{t("projectedHours")}</th>
                <th className="px-4 py-3">{t("completedSessions")}</th>
                <th className="px-4 py-3">{t("deliveredHours")}</th>
                <th className="px-4 py-3">{t("inProgressSessions")}</th>
                <th className="px-4 py-3">{t("cancelledSessions")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {teacherRows.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-4 py-6 text-slate-500">
                    {t("emptyTeachers")}
                  </td>
                </tr>
              ) : (
                teacherRows.map((row) => (
                  <tr key={row.teacherId} data-teacher-id={row.teacherId}>
                    <td className="px-4 py-3 font-medium text-slate-900">
                      {row.teacherDisplayName ?? t("emptyValue")}
                    </td>
                    <td className="px-4 py-3" data-metric="materialized-sessions">
                      {row.materializedSessionCount}
                    </td>
                    <td className="px-4 py-3" data-metric="materialized-hours">
                      {formatMinutesAsHours(row.materializedScheduledMinutes)}
                    </td>
                    <td className="px-4 py-3 text-amber-900" data-metric="projected-sessions">
                      {row.projectedSessionCount}
                    </td>
                    <td className="px-4 py-3 text-amber-900" data-metric="projected-hours">
                      {formatMinutesAsHours(row.projectedMinutes)}
                    </td>
                    <td className="px-4 py-3" data-metric="completed-sessions">
                      {row.completedSessionCount}
                    </td>
                    <td className="px-4 py-3" data-metric="delivered-hours">
                      {formatMinutesAsHours(row.deliveredScheduledMinutes)}
                    </td>
                    <td className="px-4 py-3">{row.inProgressSessionCount}</td>
                    <td className="px-4 py-3">{row.cancelledSessionCount}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>

      <section className="space-y-3">
        <h2 className="text-lg font-semibold text-slate-900">{t("roomUsageTitle")}</h2>
        <p className="text-sm text-slate-600">{t("roomUsageHint")}</p>
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="min-w-full text-sm">
            <thead className="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-600">
              <tr>
                <th className="px-4 py-3">{t("roomColumn")}</th>
                <th className="px-4 py-3">{t("bookedSessions")}</th>
                <th className="px-4 py-3">{t("bookedHours")}</th>
                <th className="px-4 py-3">{t("projectedSessions")}</th>
                <th className="px-4 py-3">{t("projectedHours")}</th>
                <th className="px-4 py-3">{t("completedSessions")}</th>
                <th className="px-4 py-3">{t("deliveredHours")}</th>
                <th className="px-4 py-3">{t("cancelledSessions")}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {roomRows.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-4 py-6 text-slate-500">
                    {t("emptyRooms")}
                  </td>
                </tr>
              ) : (
                roomRows.map((row) => (
                  <tr key={row.roomId} data-room-id={row.roomId}>
                    <td className="px-4 py-3 font-medium text-slate-900">
                      {row.roomCode ? `${row.roomName} (${row.roomCode})` : row.roomName}
                    </td>
                    <td className="px-4 py-3" data-metric="materialized-sessions">
                      {row.materializedSessionCount}
                    </td>
                    <td className="px-4 py-3" data-metric="materialized-hours">
                      {formatMinutesAsHours(row.materializedBookedMinutes)}
                    </td>
                    <td className="px-4 py-3 text-amber-900" data-metric="projected-sessions">
                      {row.projectedSessionCount}
                    </td>
                    <td className="px-4 py-3 text-amber-900" data-metric="projected-hours">
                      {formatMinutesAsHours(row.projectedBookedMinutes)}
                    </td>
                    <td className="px-4 py-3">{row.completedSessionCount}</td>
                    <td className="px-4 py-3">{formatMinutesAsHours(row.deliveredScheduledMinutes)}</td>
                    <td className="px-4 py-3">{row.cancelledSessionCount}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
