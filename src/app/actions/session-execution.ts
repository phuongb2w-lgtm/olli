"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import {
  isEnrollmentEligibleOnSessionDate,
  isEnrollmentOperationalForAttendance,
  isEnrollmentVisibleOnSessionRoster,
  resolveSessionOccurrenceDate,
} from "@/lib/session-execution/roster-eligibility";
import {
  fetchSessionExecutionContext,
  fetchSessionRoster,
  countAttendanceProgress,
} from "@/lib/session-execution/query-session-execution";
import {
  isAttendanceConflict,
  isCrossClassAttendance,
  validateAttendanceStatus,
} from "@/lib/session-execution/validate-attendance-input";
import type { EnrollmentStatus } from "@/lib/enrollments/constants";
export type SessionExecutionActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "invalid_status"
    | "invalid_session_status"
    | "confirm_required"
    | "duplicate_attendance"
    | "cross_class"
    | "not_eligible"
    | "pending_enrollment";
  success?: string;
};

function revalidateSession(classId: string, sessionId: string) {
  revalidatePath(`/classes/${classId}/teaching`);
  revalidatePath(`/classes/${classId}/teaching/sessions/${sessionId}`);
}

async function loadSession(classId: string, sessionId: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("teaching_session")
    .select("id, class_id, status, occurrence_date, scheduled_start_at, teacher_id")
    .eq("id", sessionId)
    .eq("class_id", classId)
    .maybeSingle();
  if (!data) return null;
  return data;
}

async function assertEnrollmentForSession(
  enrollmentId: string,
  classId: string,
  sessionDate: string,
  requireOperational: boolean,
) {
  const supabase = await createClient();
  const { data: enrollment } = await supabase
    .from("enrollment")
    .select("id, class_id, start_date, end_date, status")
    .eq("id", enrollmentId)
    .maybeSingle();
  if (!enrollment || enrollment.class_id !== classId) return { ok: false as const, error: "not_found" as const };

  const row = {
    id: enrollment.id,
    studentId: "",
    startDate: enrollment.start_date,
    endDate: enrollment.end_date,
    status: enrollment.status as EnrollmentStatus,
  };

  if (!isEnrollmentEligibleOnSessionDate(row, sessionDate)) {
    return { ok: false as const, error: "not_eligible" as const };
  }

  if (requireOperational) {
    if (!isEnrollmentOperationalForAttendance(row, sessionDate)) {
      if (enrollment.status === "pending") return { ok: false as const, error: "pending_enrollment" as const };
      return { ok: false as const, error: "not_eligible" as const };
    }
  } else if (!isEnrollmentVisibleOnSessionRoster(row, sessionDate)) {
    if (enrollment.status === "pending") return { ok: false as const, error: "pending_enrollment" as const };
    return { ok: false as const, error: "not_eligible" as const };
  }

  return { ok: true as const, enrollment };
}

export async function startSessionAction(
  _prev: SessionExecutionActionState,
  formData: FormData,
): Promise<SessionExecutionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const session = await loadSession(classId, sessionId);
  if (!session) return { error: "not_found" };
  if (session.status !== "scheduled") return { error: "invalid_session_status" };

  const supabase = await createClient();
  const { error } = await supabase
    .from("teaching_session")
    .update({ status: "in_progress", updated_by: user.appUserId })
    .eq("id", sessionId);

  if (error) return { error: "save_error" };
  revalidateSession(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=started`);
}

export async function completeSessionAction(
  _prev: SessionExecutionActionState,
  formData: FormData,
): Promise<SessionExecutionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const confirmUnrecorded = String(formData.get("confirmUnrecorded") ?? "") === "true";

  const supabase = await createClient();
  const context = await fetchSessionExecutionContext(supabase, classId, sessionId);
  if (!context) return { error: "not_found" };
  if (context.status !== "in_progress") {
    return { error: "invalid_session_status" };
  }

  const roster = await fetchSessionRoster(supabase, context);
  const progress = countAttendanceProgress(roster);
  if (progress.notRecorded > 0 && !confirmUnrecorded) {
    return { error: "confirm_required" };
  }

  const { error } = await supabase
    .from("teaching_session")
    .update({ status: "completed", updated_by: user.appUserId })
    .eq("id", sessionId);

  if (error) return { error: "save_error" };
  revalidateSession(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=completed`);
}

export async function cancelSessionExecutionAction(
  _prev: SessionExecutionActionState,
  formData: FormData,
): Promise<SessionExecutionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const session = await loadSession(classId, sessionId);
  if (!session) return { error: "not_found" };
  if (session.status !== "scheduled" && session.status !== "in_progress") {
    return { error: "invalid_session_status" };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("teaching_session")
    .update({ status: "cancelled", updated_by: user.appUserId })
    .eq("id", sessionId);

  if (error) return { error: "save_error" };
  revalidateSession(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=cancelled`);
}

export async function recordAttendanceFormAction(formData: FormData): Promise<void> {
  await recordAttendanceAction({}, formData);
}

export async function recordAttendanceAction(
  _prev: SessionExecutionActionState,
  formData: FormData,
): Promise<SessionExecutionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("attendance.record"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const statusRaw = String(formData.get("status") ?? "").trim();

  if (!validateAttendanceStatus(statusRaw)) return { error: "invalid_status" };

  const session = await loadSession(classId, sessionId);
  if (!session) return { error: "not_found" };

  const sessionDate = resolveSessionOccurrenceDate({
    occurrenceDate: session.occurrence_date,
    scheduledStartAt: session.scheduled_start_at,
  });

  const enrollmentCheck = await assertEnrollmentForSession(
    enrollmentId,
    classId,
    sessionDate,
    true,
  );
  if (!enrollmentCheck.ok) return { error: enrollmentCheck.error };

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("attendance")
    .select("id")
    .eq("teaching_session_id", sessionId)
    .eq("enrollment_id", enrollmentId)
    .maybeSingle();

  if (existing) {
    const { error } = await supabase
      .from("attendance")
      .update({
        status: statusRaw,
        updated_by: user.appUserId,
        recorded_by: user.appUserId,
        recorded_at: new Date().toISOString(),
      })
      .eq("id", existing.id);
    if (error) {
      if (isCrossClassAttendance(error)) return { error: "cross_class" };
      return { error: "save_error" };
    }
  } else {
    const { error } = await supabase.from("attendance").insert({
      organization_id: user.organizationId,
      teaching_session_id: sessionId,
      enrollment_id: enrollmentId,
      status: statusRaw,
      recorded_by: user.appUserId,
      updated_by: user.appUserId,
    });
    if (error) {
      if (isAttendanceConflict(error)) return { error: "duplicate_attendance" };
      if (isCrossClassAttendance(error)) return { error: "cross_class" };
      if (error.message?.includes("pending_enrollment")) return { error: "pending_enrollment" };
      return { error: "save_error" };
    }
  }

  revalidateSession(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=attendance_recorded`);
}

export async function markAllPresentAction(
  _prev: SessionExecutionActionState,
  formData: FormData,
): Promise<SessionExecutionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("attendance.record"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const overwriteNonPresent =
    String(formData.get("confirmOverwriteNonPresent") ?? "") === "true";

  const supabase = await createClient();
  const context = await fetchSessionExecutionContext(supabase, classId, sessionId);
  if (!context) return { error: "not_found" };

  const roster = await fetchSessionRoster(supabase, context);
  const sessionDate = context.occurrenceDate;

  const targets = roster.filter((row) => {
    const eligible = isEnrollmentOperationalForAttendance(
      {
        id: row.enrollmentId,
        studentId: row.studentId,
        startDate: row.enrollmentStartDate,
        endDate: row.enrollmentEndDate,
        status: row.enrollmentStatus,
      },
      sessionDate,
    );
    if (!eligible) return false;
    if (row.attendanceStatus && row.attendanceStatus !== "present" && !overwriteNonPresent) {
      return false;
    }
    return row.attendanceStatus !== "present";
  });

  const hasSkippedNonPresent = roster.some(
    (row) =>
      row.attendanceStatus &&
      row.attendanceStatus !== "present" &&
      !overwriteNonPresent &&
      row.enrollmentStatus === "active",
  );
  if (hasSkippedNonPresent && !overwriteNonPresent) {
    return { error: "confirm_required" };
  }

  for (const row of targets) {
    const enrollmentCheck = await assertEnrollmentForSession(
      row.enrollmentId,
      classId,
      sessionDate,
      true,
    );
    if (!enrollmentCheck.ok) continue;

    const { data: existing } = await supabase
      .from("attendance")
      .select("id")
      .eq("teaching_session_id", sessionId)
      .eq("enrollment_id", row.enrollmentId)
      .maybeSingle();

    if (existing) {
      await supabase
        .from("attendance")
        .update({
          status: "present",
          updated_by: user.appUserId,
          recorded_by: user.appUserId,
        })
        .eq("id", existing.id);
    } else {
      await supabase.from("attendance").insert({
        organization_id: user.organizationId,
        teaching_session_id: sessionId,
        enrollment_id: row.enrollmentId,
        status: "present",
        recorded_by: user.appUserId,
        updated_by: user.appUserId,
      });
    }
  }

  revalidateSession(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=attendance_bulk`);
}

export async function saveObservationAction(
  _prev: SessionExecutionActionState,
  formData: FormData,
): Promise<SessionExecutionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("observation.record"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const comment = String(formData.get("comment") ?? "").trim();

  const session = await loadSession(classId, sessionId);
  if (!session) return { error: "not_found" };

  const sessionDate = resolveSessionOccurrenceDate({
    occurrenceDate: session.occurrence_date,
    scheduledStartAt: session.scheduled_start_at,
  });

  const enrollmentCheck = await assertEnrollmentForSession(
    enrollmentId,
    classId,
    sessionDate,
    false,
  );
  if (!enrollmentCheck.ok) return { error: enrollmentCheck.error };

  const supabase = await createClient();
  const { data: existingObs } = await supabase
    .from("teacher_observation")
    .select("id")
    .eq("teaching_session_id", sessionId)
    .eq("enrollment_id", enrollmentId)
    .neq("status", "void")
    .maybeSingle();

  let observationId = existingObs?.id;

  if (observationId) {
    const { error } = await supabase
      .from("teacher_observation")
      .update({
        comment: comment || null,
        status: "recorded",
        updated_by: user.appUserId,
      })
      .eq("id", observationId);
    if (error) return { error: "save_error" };
  } else {
    const { data: created, error } = await supabase
      .from("teacher_observation")
      .insert({
        organization_id: user.organizationId,
        enrollment_id: enrollmentId,
        class_id: classId,
        teacher_id: session.teacher_id,
        teaching_session_id: sessionId,
        observed_at: session.scheduled_start_at,
        comment: comment || null,
        status: "recorded",
        created_by: user.appUserId,
        updated_by: user.appUserId,
      })
      .select("id")
      .single();
    if (error || !created) return { error: "save_error" };
    observationId = created.id;
  }

  const indicatorCodes = [...formData.keys()]
    .filter((k) => k.startsWith("rating_"))
    .map((k) => k.replace("rating_", ""));

  for (const code of indicatorCodes) {
    const ratingCode = String(formData.get(`rating_${code}`) ?? "").trim();
    if (!ratingCode || !["low", "medium", "high"].includes(ratingCode)) continue;

    const { data: existingRating } = await supabase
      .from("observation_rating")
      .select("id")
      .eq("teacher_observation_id", observationId!)
      .eq("indicator_code", code)
      .maybeSingle();

    if (existingRating) {
      await supabase
        .from("observation_rating")
        .update({ rating_code: ratingCode })
        .eq("id", existingRating.id);
    } else {
      await supabase.from("observation_rating").insert({
        organization_id: user.organizationId,
        teacher_observation_id: observationId!,
        indicator_code: code,
        rating_code: ratingCode,
      });
    }
  }

  revalidateSession(classId, sessionId);
  redirect(`/classes/${classId}/teaching/sessions/${sessionId}?success=observation_saved`);
}
