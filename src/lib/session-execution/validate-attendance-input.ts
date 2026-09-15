import { ATTENDANCE_STATUSES, type AttendanceStatus } from "./constants";

export function validateAttendanceStatus(status: string): status is AttendanceStatus {
  return ATTENDANCE_STATUSES.includes(status as AttendanceStatus);
}

export function isAttendanceConflict(error: { code?: string; message?: string } | null) {
  if (!error) return false;
  if (error.code === "23505") return true;
  return error.message?.includes("duplicate") ?? false;
}

export function isCrossClassAttendance(error: { message?: string } | null) {
  if (!error?.message) return false;
  return (
    error.message.includes("class must match") ||
    error.message.includes("enrollment_not_eligible") ||
    error.message.includes("pending_enrollment")
  );
}
