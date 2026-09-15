"use client";

import { useTranslations } from "next-intl";
import { recordAttendanceFormAction } from "@/app/actions/session-execution";
import type { AttendanceStatus } from "@/lib/session-execution/constants";
import { ATTENDANCE_STATUSES } from "@/lib/session-execution/constants";

type Props = {
  classId: string;
  sessionId: string;
  enrollmentId: string;
  currentStatus: AttendanceStatus | null;
  disabled?: boolean;
};

export function AttendanceButtons({
  classId,
  sessionId,
  enrollmentId,
  currentStatus,
  disabled,
}: Props) {
  const t = useTranslations("sessionExecution");
  const tStatus = useTranslations("status.attendance");

  return (
    <div className="space-y-2">
      <p className="text-xs font-medium text-slate-500">
        {currentStatus ? tStatus(currentStatus) : t("notRecorded")}
      </p>
      <div className="flex flex-wrap gap-1">
        {ATTENDANCE_STATUSES.map((status) => (
          <form key={status} action={recordAttendanceFormAction}>
            <input type="hidden" name="classId" value={classId} />
            <input type="hidden" name="sessionId" value={sessionId} />
            <input type="hidden" name="enrollmentId" value={enrollmentId} />
            <input type="hidden" name="status" value={status} />
            <button
              type="submit"
              disabled={disabled}
              aria-pressed={currentStatus === status}
              className={`rounded-md px-2.5 py-1.5 text-xs font-medium disabled:opacity-50 ${
                currentStatus === status
                  ? "bg-slate-900 text-white"
                  : "border border-slate-300 bg-white text-slate-800"
              }`}
            >
              {tStatus(status)}
            </button>
          </form>
        ))}
      </div>
    </div>
  );
}
