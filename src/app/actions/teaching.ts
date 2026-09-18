"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import type { ClassStatus } from "@/lib/academic/constants";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import {
  isRoomConflict,
  isScheduleConflict,
  isTeacherConflict,
  validateGenerationRange,
  validateScheduleInput,
  type ScheduleFormValues,
} from "@/lib/teaching/validate-schedule-input";
import {
  validateRoomInput,
  type RoomFormValues,
} from "@/lib/teaching/validate-room-input";
import {
  validateTeacherAssignmentInput,
  type TeacherAssignmentFormValues,
} from "@/lib/teaching/validate-teacher-assignment-input";
import { mapTeachingRpcError } from "@/lib/teaching/map-teaching-rpc-error";

export type TeachingActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "class_closed"
    | "invalid_class"
    | "invalid_teacher"
    | "invalid_room"
    | "room_inactive"
    | "schedule_conflict"
    | "room_conflict"
    | "teacher_conflict"
    | "teacher_unavailable"
    | "schedule_not_active"
    | "assignment_not_active"
    | "ambiguous_teacher"
    | "no_teacher"
    | "invalid_range"
    | "invalid_schedule_range"
    | "invalid_assignment_range"
    | "duplicate_assignment"
    | "range_too_large"
    | "session_not_cancellable"
    | "session_not_completable";
  fieldErrors?: Record<string, string>;
  values?: Record<string, string>;
  success?: string;
};

function revalidateTeaching(classId: string) {
  revalidatePath(`/classes/${classId}/teaching`);
  revalidatePath("/classes");
}

function revalidateRooms() {
  revalidatePath("/rooms");
}

async function assertClassInOrg(classId: string, organizationId: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("class")
    .select("id, status, organization_id, term_start_date, term_end_date")
    .eq("id", classId)
    .maybeSingle();
  if (!data || data.organization_id !== organizationId) return null;
  return data as {
    id: string;
    status: ClassStatus;
    organization_id: string;
    term_start_date: string | null;
    term_end_date: string | null;
  };
}

function parseScheduleFields(formData: FormData): Partial<ScheduleFormValues> {
  return {
    weekdayCode: String(formData.get("weekdayCode") ?? "") as ScheduleFormValues["weekdayCode"],
    startTime: String(formData.get("startTime") ?? ""),
    endTime: String(formData.get("endTime") ?? ""),
    effectiveFrom: String(formData.get("effectiveFrom") ?? ""),
    effectiveTo: String(formData.get("effectiveTo") ?? ""),
    roomId: String(formData.get("roomId") ?? ""),
    teacherId: String(formData.get("teacherId") ?? ""),
  };
}

export async function createClassScheduleAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.create"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };

  const parsed = validateScheduleInput(parseScheduleFields(formData), {
    classStatus: classRow.status,
    termStart: classRow.term_start_date,
    termEnd: classRow.term_end_date,
  });
  if (!parsed.ok || !parsed.data) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors, values: formDataToValues(formData) };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_class_schedule", {
    p_class_id: classId,
    p_weekday_code: parsed.data.weekdayCode,
    p_start_time: parsed.data.startTime,
    p_end_time: parsed.data.endTime,
    p_effective_from: parsed.data.effectiveFrom,
    p_effective_to: parsed.data.effectiveTo ?? undefined,
    p_room_id: parsed.data.roomId ?? undefined,
    p_teacher_id: parsed.data.teacherId ?? undefined,
  });

  if (error) return { error: mapTeachingRpcError(error) };
  revalidateTeaching(classId);
  redirect(`/classes/${classId}/teaching?success=schedule_created`);
}

export async function updateClassScheduleAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const scheduleId = String(formData.get("scheduleId") ?? "").trim();
  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };

  const parsed = validateScheduleInput(parseScheduleFields(formData), {
    classStatus: classRow.status,
    termStart: classRow.term_start_date,
    termEnd: classRow.term_end_date,
  });
  if (!parsed.ok || !parsed.data) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors, values: formDataToValues(formData) };
  }

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("class_schedule")
    .select("id")
    .eq("id", scheduleId)
    .eq("class_id", classId)
    .maybeSingle();
  if (!existing) return { error: "not_found" };

  const { error } = await supabase.rpc("update_class_schedule", {
    p_schedule_id: scheduleId,
    p_weekday_code: parsed.data.weekdayCode,
    p_start_time: parsed.data.startTime,
    p_end_time: parsed.data.endTime,
    p_effective_from: parsed.data.effectiveFrom,
    p_effective_to: parsed.data.effectiveTo ?? undefined,
    p_room_id: parsed.data.roomId ?? undefined,
    p_teacher_id: parsed.data.teacherId ?? undefined,
  });

  if (error) return { error: mapTeachingRpcError(error) };
  revalidateTeaching(classId);
  redirect(`/classes/${classId}/teaching?success=schedule_updated`);
}

export async function endClassScheduleAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const scheduleId = String(formData.get("scheduleId") ?? "").trim();
  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("end_class_schedule", {
    p_schedule_id: scheduleId,
  });

  if (error) return { error: mapTeachingRpcError(error) };
  revalidateTeaching(classId);
  redirect(`/classes/${classId}/teaching?success=schedule_ended`);
}

export async function createTeacherAssignmentAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.create"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };

  const parsed = validateTeacherAssignmentInput(
    {
      teacherId: String(formData.get("teacherId") ?? ""),
      roleCode: String(formData.get("roleCode") ?? "primary") as TeacherAssignmentFormValues["roleCode"],
      effectiveFrom: String(formData.get("effectiveFrom") ?? ""),
      effectiveTo: String(formData.get("effectiveTo") ?? ""),
    },
    { classStatus: classRow.status },
  );
  if (!parsed.ok || !parsed.data) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors, values: formDataToValues(formData) };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("create_class_teacher_assignment", {
    p_class_id: classId,
    p_teacher_id: parsed.data.teacherId,
    p_role_code: parsed.data.roleCode,
    p_effective_from: parsed.data.effectiveFrom,
    p_effective_to: parsed.data.effectiveTo ?? undefined,
  });

  if (error) return { error: mapTeachingRpcError(error) };
  revalidateTeaching(classId);
  redirect(`/classes/${classId}/teaching?success=teacher_assigned`);
}

export async function endTeacherAssignmentAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const assignmentId = String(formData.get("assignmentId") ?? "").trim();
  const effectiveTo = String(formData.get("effectiveTo") ?? "").trim();
  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("end_class_teacher_assignment", {
    p_assignment_id: assignmentId,
    p_effective_to: effectiveTo || new Date().toISOString().slice(0, 10),
  });

  if (error) return { error: mapTeachingRpcError(error) };
  revalidateTeaching(classId);
  redirect(`/classes/${classId}/teaching?success=teacher_ended`);
}

export async function generateSessionsAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.create"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const scheduleId = String(formData.get("scheduleId") ?? "").trim();
  const rangeStart = String(formData.get("rangeStart") ?? "").trim();
  const rangeEnd = String(formData.get("rangeEnd") ?? "").trim();

  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };
  if (classRow.status === "closed") return { error: "class_closed" };

  const parsed = validateGenerationRange(rangeStart, rangeEnd);
  if (!parsed.ok) {
    return { error: "invalid_range", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("generate_teaching_sessions", {
    p_class_schedule_id: scheduleId,
    p_range_start: rangeStart,
    p_range_end: rangeEnd,
  });

  if (error) {
    const mapped = mapTeachingRpcError(error);
    if (mapped !== "save_error") return { error: mapped };
    const msg = error.message ?? "";
    if (msg.includes("invalid_range") || msg.includes("range_too_large")) {
      return { error: msg.includes("range_too_large") ? "range_too_large" : "invalid_range" };
    }
    if (isScheduleConflict(error) || isRoomConflict(error) || isTeacherConflict(error)) {
      return { error: "schedule_conflict" };
    }
    return { error: "save_error" };
  }

  revalidateTeaching(classId);
  redirect(`/classes/${classId}/teaching?success=sessions_generated&count=${data ?? 0}`);
}

export async function cancelSessionAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim() || "Cancelled from teaching list";
  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };

  const supabase = await createClient();
  const { data: session } = await supabase
    .from("teaching_session")
    .select("id, status")
    .eq("id", sessionId)
    .eq("class_id", classId)
    .maybeSingle();
  if (!session) return { error: "not_found" };
  if (session.status !== "scheduled") {
    return { error: "session_not_cancellable" };
  }

  const { error } = await supabase.rpc("cancel_teaching_session", {
    p_session_id: sessionId,
    p_reason: reason,
  });

  if (error) {
    const mapped = mapTeachingRpcError(error);
    if (mapped !== "save_error") return { error: mapped };
    if (error.message?.includes("invalid_session_state")) return { error: "session_not_cancellable" };
    if (error.message?.includes("attendance_already_recorded")) return { error: "session_not_cancellable" };
    if (error.message?.includes("financial_effect_exists")) return { error: "session_not_cancellable" };
    return { error: "save_error" };
  }
  revalidateTeaching(classId);
  revalidatePath("/operations");
  redirect(`/classes/${classId}/teaching?success=session_cancelled`);
}

export async function completeSessionAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const classRow = await assertClassInOrg(classId, user.organizationId);
  if (!classRow) return { error: "invalid_class" };

  const supabase = await createClient();
  const { data: session } = await supabase
    .from("teaching_session")
    .select("id, status")
    .eq("id", sessionId)
    .eq("class_id", classId)
    .maybeSingle();
  if (!session) return { error: "not_found" };
  if (session.status !== "scheduled" && session.status !== "in_progress") {
    return { error: "session_not_completable" };
  }

  const { error } = await supabase
    .from("teaching_session")
    .update({ status: "completed", updated_by: user.appUserId })
    .eq("id", sessionId);

  if (error) return { error: "save_error" };
  revalidateTeaching(classId);
  redirect(`/classes/${classId}/teaching?success=session_completed`);
}

export async function createRoomAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.create"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateRoomInput({
    name: String(formData.get("name") ?? ""),
    code: String(formData.get("code") ?? ""),
    capacity: String(formData.get("capacity") ?? ""),
    notes: String(formData.get("notes") ?? ""),
    status: String(formData.get("status") ?? "active") as RoomFormValues["status"],
  });
  if (!parsed.ok || !parsed.data) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors, values: formDataToValues(formData) };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("room").insert({
    organization_id: user.organizationId,
    name: parsed.data.name,
    code: parsed.data.code,
    capacity: parsed.data.capacity,
    notes: parsed.data.notes,
    status: parsed.data.status,
    created_by: user.appUserId,
    updated_by: user.appUserId,
  });

  if (error) return { error: "save_error" };
  revalidateRooms();
  redirect("/rooms?success=created");
}

export async function updateRoomAction(
  _prev: TeachingActionState,
  formData: FormData,
): Promise<TeachingActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const roomId = String(formData.get("roomId") ?? "").trim();
  const parsed = validateRoomInput({
    name: String(formData.get("name") ?? ""),
    code: String(formData.get("code") ?? ""),
    capacity: String(formData.get("capacity") ?? ""),
    notes: String(formData.get("notes") ?? ""),
    status: String(formData.get("status") ?? "active") as RoomFormValues["status"],
  });
  if (!parsed.ok || !parsed.data) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors, values: formDataToValues(formData) };
  }

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("room")
    .select("id")
    .eq("id", roomId)
    .maybeSingle();
  if (!existing) return { error: "not_found" };

  const { error } = await supabase
    .from("room")
    .update({
      name: parsed.data.name,
      code: parsed.data.code,
      capacity: parsed.data.capacity,
      notes: parsed.data.notes,
      status: parsed.data.status,
      updated_by: user.appUserId,
    })
    .eq("id", roomId);

  if (error) return { error: "save_error" };
  revalidateRooms();
  redirect(`/rooms/${roomId}/edit?success=updated`);
}

function formDataToValues(formData: FormData): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === "string") values[key] = value;
  }
  return values;
}
