import { getTranslations } from "next-intl/server";
import { AttendanceButtons } from "@/components/session-execution/attendance-buttons";
import { MarkAllPresentForm } from "@/components/session-execution/mark-all-present-form";
import { ObservationForm } from "@/components/session-execution/observation-form";
import type {
  ObservationIndicator,
  SessionRosterItem,
} from "@/lib/session-execution/query-session-execution";
import type { SessionExecutionStatus } from "@/lib/session-execution/constants";

type Props = {
  classId: string;
  sessionId: string;
  sessionStatus: SessionExecutionStatus;
  roster: SessionRosterItem[];
  indicators: ObservationIndicator[];
  canRecordAttendance: boolean;
  canRecordObservation: boolean;
};

export async function SessionRoster({
  classId,
  sessionId,
  sessionStatus,
  roster,
  indicators,
  canRecordAttendance,
  canRecordObservation,
}: Props) {
  const t = await getTranslations("sessionExecution");
  const tStatus = await getTranslations("status.attendance");
  const disabled = sessionStatus === "cancelled";
  const canMark = canRecordAttendance && !disabled;
  const canObserve = canRecordObservation && !disabled;

  const hasNonPresentRecorded = roster.some(
    (row) =>
      row.attendanceStatus !== null &&
      row.attendanceStatus !== "present" &&
      row.enrollmentStatus === "active",
  );

  if (roster.length === 0) {
    return <p className="text-sm text-slate-600">{t("emptyRoster")}</p>;
  }

  return (
    <div className="space-y-4">
      {canMark ? (
        <MarkAllPresentForm
          classId={classId}
          sessionId={sessionId}
          hasNonPresentRecorded={hasNonPresentRecorded}
        />
      ) : null}

      <div className="hidden overflow-x-auto lg:block">
        <table className="min-w-full divide-y divide-slate-200 text-sm">
          <thead className="bg-slate-50">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("student")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("studentCode")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("attendance")}</th>
              <th className="px-4 py-3 text-left font-medium text-slate-700">{t("observation")}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200 bg-white">
            {roster.map((row) => (
              <tr key={row.enrollmentId}>
                <td className="px-4 py-3 font-medium text-slate-900">{row.studentName}</td>
                <td className="px-4 py-3 text-slate-700">{row.studentCode ?? "—"}</td>
                <td className="px-4 py-3">
                  {canMark ? (
                    <AttendanceButtons
                      classId={classId}
                      sessionId={sessionId}
                      enrollmentId={row.enrollmentId}
                      currentStatus={row.attendanceStatus}
                    />
                  ) : (
                    <span className="text-slate-700">
                      {row.attendanceStatus
                        ? tStatus(row.attendanceStatus)
                        : t("notRecorded")}
                    </span>
                  )}
                </td>
                <td className="px-4 py-3">
                  {canObserve ? (
                    <ObservationForm
                      classId={classId}
                      sessionId={sessionId}
                      enrollmentId={row.enrollmentId}
                      indicators={indicators}
                      initialComment={row.observationComment}
                      initialRatings={row.ratings}
                    />
                  ) : row.observationId ? (
                    <span className="text-slate-600">{t("observationRecorded")}</span>
                  ) : (
                    <span className="text-slate-500">{t("noObservation")}</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <ul className="space-y-3 lg:hidden">
        {roster.map((row) => (
          <li
            key={row.enrollmentId}
            className="rounded-lg border border-slate-200 bg-white p-4 text-sm"
          >
            <div className="flex items-start justify-between gap-2">
              <div>
                <p className="font-medium text-slate-900">{row.studentName}</p>
                <p className="text-slate-600">{row.studentCode ?? "—"}</p>
              </div>
            </div>
            <div className="mt-3">
              {canMark ? (
                <AttendanceButtons
                  classId={classId}
                  sessionId={sessionId}
                  enrollmentId={row.enrollmentId}
                  currentStatus={row.attendanceStatus}
                />
              ) : (
                <p className="text-slate-700">
                  {row.attendanceStatus
                    ? tStatus(row.attendanceStatus)
                    : t("notRecorded")}
                </p>
              )}
            </div>
            {canObserve ? (
              <ObservationForm
                classId={classId}
                sessionId={sessionId}
                enrollmentId={row.enrollmentId}
                indicators={indicators}
                initialComment={row.observationComment}
                initialRatings={row.ratings}
              />
            ) : null}
          </li>
        ))}
      </ul>
    </div>
  );
}
