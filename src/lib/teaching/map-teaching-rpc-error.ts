import type { TeachingActionState } from "@/app/actions/teaching";

export function mapTeachingRpcError(
  error: { code?: string; message?: string } | null,
): TeachingActionState["error"] {
  if (!error) return "save_error";
  const msg = error.message ?? "";

  if (error.code === "42501" || msg.includes("permission_denied")) return "permission_denied";
  if (error.code === "P0002" || msg.includes("not_found")) return "not_found";
  if (msg.includes("invalid_class_state") || msg.includes("class_closed")) return "class_closed";
  if (msg.includes("invalid_schedule_range")) return "invalid_schedule_range";
  if (msg.includes("invalid_assignment_range")) return "invalid_assignment_range";
  if (msg.includes("cross_organization_reference")) return "invalid_class";
  if (msg.includes("invalid_teacher")) return "invalid_teacher";
  if (msg.includes("room_inactive")) return "room_inactive";
  if (msg.includes("invalid_class")) return "invalid_class";
  if (msg.includes("schedule_not_active")) return "schedule_not_active";
  if (msg.includes("assignment_not_active")) return "assignment_not_active";
  if (msg.includes("duplicate_assignment") || error.code === "23505") return "duplicate_assignment";
  if (msg.includes("teacher_unavailable")) return "teacher_unavailable";
  if (msg.includes("teacher_double_booked")) return "teacher_conflict";
  if (msg.includes("room_double_booked")) return "room_conflict";
  if (msg.includes("ambiguous_teacher")) return "ambiguous_teacher";
  if (msg.includes("no_teacher")) return "no_teacher";
  if (error.code === "23P01" || msg.includes("schedule_conflict")) return "schedule_conflict";

  return "save_error";
}
