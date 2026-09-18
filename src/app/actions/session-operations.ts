"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import { mapSessionOpsRpcError } from "@/lib/teaching/map-session-ops-rpc-error";

export type SessionOpsActionState = {
  error?: ReturnType<typeof mapSessionOpsRpcError>;
  success?: string;
};

function revalidateSessionSurfaces(classId: string, sessionId: string) {
  revalidatePath(`/classes/${classId}/teaching`);
  revalidatePath(`/classes/${classId}/teaching/sessions/${sessionId}`);
  revalidatePath("/operations");
}

export async function rescheduleTeachingSessionAction(
  _prev: SessionOpsActionState,
  formData: FormData,
): Promise<SessionOpsActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const startLocal = String(formData.get("scheduledStart") ?? "").trim();
  const endLocal = String(formData.get("scheduledEnd") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();

  if (!sessionId || !classId) return { error: "not_found" };
  if (!reason) return { error: "reason_required" };
  if (!startLocal || !endLocal) return { error: "invalid_interval" };

  const startAt = new Date(startLocal);
  const endAt = new Date(endLocal);
  if (Number.isNaN(startAt.getTime()) || Number.isNaN(endAt.getTime()) || endAt <= startAt) {
    return { error: "invalid_interval" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("reschedule_teaching_session", {
    p_session_id: sessionId,
    p_scheduled_start_at: startAt.toISOString(),
    p_scheduled_end_at: endAt.toISOString(),
    p_reason: reason,
  });

  if (error) return { error: mapSessionOpsRpcError(error) };
  revalidateSessionSurfaces(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=rescheduled`);
}

export async function cancelTeachingSessionAction(
  _prev: SessionOpsActionState,
  formData: FormData,
): Promise<SessionOpsActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const returnTo = String(formData.get("returnTo") ?? "").trim();

  if (!sessionId) return { error: "not_found" };
  if (!reason) return { error: "reason_required" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_teaching_session", {
    p_session_id: sessionId,
    p_reason: reason,
  });

  if (error) return { error: mapSessionOpsRpcError(error) };

  if (classId) revalidateSessionSurfaces(classId, sessionId);
  else revalidatePath("/operations");

  if (returnTo === "teaching" && classId) {
    redirect(`/classes/${classId}/teaching?success=session_cancelled`);
  }
  if (classId) {
    redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=cancelled`);
  }
  return { success: "cancelled" };
}

export async function substituteSessionTeacherAction(
  _prev: SessionOpsActionState,
  formData: FormData,
): Promise<SessionOpsActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const teacherId = String(formData.get("teacherId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();

  if (!sessionId || !classId) return { error: "not_found" };
  if (!teacherId) return { error: "invalid_teacher" };
  if (!reason) return { error: "reason_required" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("substitute_session_teacher", {
    p_session_id: sessionId,
    p_new_teacher_id: teacherId,
    p_reason: reason,
  });

  if (error) return { error: mapSessionOpsRpcError(error) };
  revalidateSessionSurfaces(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=teacher_substituted`);
}

export async function changeSessionRoomAction(
  _prev: SessionOpsActionState,
  formData: FormData,
): Promise<SessionOpsActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const roomIdRaw = String(formData.get("roomId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const roomId = roomIdRaw.length > 0 ? roomIdRaw : null;

  if (!sessionId || !classId) return { error: "not_found" };

  const supabase = await createClient();
  const rpcArgs: {
    p_session_id: string;
    p_new_room_id: string;
    p_reason?: string;
  } = {
    p_session_id: sessionId,
    // Generated Args require string; SQL accepts NULL to clear the room.
    p_new_room_id: roomId as string,
  };
  if (reason.length > 0) rpcArgs.p_reason = reason;

  const { error } = await supabase.rpc("change_session_room", rpcArgs);

  if (error) return { error: mapSessionOpsRpcError(error) };
  revalidateSessionSurfaces(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=room_changed`);
}
