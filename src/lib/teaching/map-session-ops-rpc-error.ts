import type { TeachingActionState } from "@/app/actions/teaching";

export type SessionOpsError = NonNullable<TeachingActionState["error"]> | SessionOpsOnlyError;

type SessionOpsOnlyError =
  | "session_not_found"
  | "invalid_session_state"
  | "reason_required"
  | "same_schedule_time"
  | "same_teacher"
  | "same_room"
  | "financial_effect_exists"
  | "attendance_already_recorded"
  | "already_cancelled"
  | "invalid_interval";

export function mapSessionOpsRpcError(
  error: { code?: string; message?: string } | null,
): SessionOpsError {
  if (!error) return "save_error";
  const msg = error.message ?? "";

  if (error.code === "42501" || msg.includes("permission_denied")) return "permission_denied";
  if (msg.includes("session_not_found") || (error.code === "P0002" && msg.includes("session")))
    return "session_not_found";
  if (error.code === "P0002" || msg.includes("not_found")) return "not_found";
  if (msg.includes("invalid_session_state")) return "invalid_session_state";
  if (msg.includes("reason_required")) return "reason_required";
  if (msg.includes("same_schedule_time")) return "same_schedule_time";
  if (msg.includes("same_teacher")) return "same_teacher";
  if (msg.includes("same_room")) return "same_room";
  if (msg.includes("financial_effect_exists")) return "financial_effect_exists";
  if (msg.includes("attendance_already_recorded")) return "attendance_already_recorded";
  if (msg.includes("already_cancelled")) return "already_cancelled";
  if (msg.includes("invalid_interval")) return "invalid_interval";
  if (msg.includes("teacher_unavailable")) return "teacher_unavailable";
  if (msg.includes("teacher_double_booked")) return "teacher_conflict";
  if (msg.includes("room_double_booked")) return "room_conflict";
  if (msg.includes("room_inactive")) return "room_inactive";
  if (msg.includes("invalid_teacher")) return "invalid_teacher";
  if (msg.includes("invalid_room")) return "invalid_room";
  if (error.code === "23P01" || msg.includes("schedule_conflict")) return "schedule_conflict";

  return "save_error";
}
