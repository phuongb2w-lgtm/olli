"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type AcademicReviewActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "not_reviewable"
    | "invalid_action";
  success?: string;
};

function revalidateAcademicPaths() {
  revalidatePath("/academic/review");
  revalidatePath("/executive/quality");
}

export async function submitSessionAttendanceAction(
  _prev: AcademicReviewActionState,
  formData: FormData,
): Promise<AcademicReviewActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("attendance.record"))) {
    return { error: "permission_denied" };
  }

  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const classId = String(formData.get("classId") ?? "").trim();
  if (!sessionId) return { error: "not_found" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_session_attendance", {
    p_session_id: sessionId,
  });

  if (error) return { error: "save_error" };

  if (classId) {
    revalidatePath(`/classes/${classId}/teaching/sessions/${sessionId}`);
  }
  revalidateAcademicPaths();
  return { success: "attendance_submitted" };
}

export async function reviewAttendanceAction(
  _prev: AcademicReviewActionState,
  formData: FormData,
): Promise<AcademicReviewActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("attendance.review"))) {
    return { error: "permission_denied" };
  }

  const attendanceId = String(formData.get("attendanceId") ?? "").trim();
  const action = String(formData.get("action") ?? "").trim();
  const notes = String(formData.get("reviewNotes") ?? "").trim();

  if (!attendanceId || !["confirm", "return"].includes(action)) {
    return { error: "invalid_action" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("review_attendance", {
    p_attendance_id: attendanceId,
    p_action: action,
    p_review_notes: notes || undefined,
  });

  if (error) {
    if (error.message.includes("not_reviewable")) return { error: "not_reviewable" };
    return { error: "save_error" };
  }

  revalidateAcademicPaths();
  return { success: action === "confirm" ? "attendance_confirmed" : "attendance_returned" };
}

export async function submitAssessmentResultAction(
  _prev: AcademicReviewActionState,
  formData: FormData,
): Promise<AcademicReviewActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("assessment_result.record"))) {
    return { error: "permission_denied" };
  }

  const resultId = String(formData.get("resultId") ?? "").trim();
  const classId = String(formData.get("classId") ?? "").trim();
  const assessmentId = String(formData.get("assessmentId") ?? "").trim();

  if (!resultId) return { error: "not_found" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_assessment_result", {
    p_result_id: resultId,
  });

  if (error) return { error: "save_error" };

  if (classId && assessmentId) {
    revalidatePath(`/classes/${classId}/assessments/${assessmentId}`);
  }
  revalidateAcademicPaths();
  return { success: "score_submitted" };
}

export async function reviewAssessmentResultAction(
  _prev: AcademicReviewActionState,
  formData: FormData,
): Promise<AcademicReviewActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("assessment_result.review"))) {
    return { error: "permission_denied" };
  }

  const resultId = String(formData.get("resultId") ?? "").trim();
  const action = String(formData.get("action") ?? "").trim();
  const notes = String(formData.get("reviewNotes") ?? "").trim();

  if (!resultId || !["confirm", "return", "correct"].includes(action)) {
    return { error: "invalid_action" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("review_assessment_result", {
    p_result_id: resultId,
    p_action: action,
    p_review_notes: notes || undefined,
  });

  if (error) {
    if (error.message.includes("not_reviewable")) return { error: "not_reviewable" };
    return { error: "save_error" };
  }

  revalidateAcademicPaths();
  return { success: `score_${action}` };
}

export async function submitObservationAction(
  _prev: AcademicReviewActionState,
  formData: FormData,
): Promise<AcademicReviewActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("observation.record"))) {
    return { error: "permission_denied" };
  }

  const observationId = String(formData.get("observationId") ?? "").trim();
  const classId = String(formData.get("classId") ?? "").trim();
  const sessionId = String(formData.get("sessionId") ?? "").trim();

  if (!observationId) return { error: "not_found" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_teacher_observation", {
    p_observation_id: observationId,
  });

  if (error) return { error: "save_error" };

  if (classId && sessionId) {
    revalidatePath(`/classes/${classId}/teaching/sessions/${sessionId}`);
  }
  revalidateAcademicPaths();
  return { success: "observation_submitted" };
}

export async function reviewObservationAction(
  _prev: AcademicReviewActionState,
  formData: FormData,
): Promise<AcademicReviewActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("observation.review"))) {
    return { error: "permission_denied" };
  }

  const observationId = String(formData.get("observationId") ?? "").trim();
  const action = String(formData.get("action") ?? "").trim();
  const notes = String(formData.get("reviewNotes") ?? "").trim();

  if (!observationId || !["confirm", "return"].includes(action)) {
    return { error: "invalid_action" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("review_teacher_observation", {
    p_observation_id: observationId,
    p_action: action,
    p_review_notes: notes || undefined,
  });

  if (error) return { error: "save_error" };

  revalidateAcademicPaths();
  return { success: action === "confirm" ? "observation_confirmed" : "observation_returned" };
}

export async function translateObservationAction(
  _prev: AcademicReviewActionState,
  formData: FormData,
): Promise<AcademicReviewActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("observation.review"))) {
    return { error: "permission_denied" };
  }

  const observationId = String(formData.get("observationId") ?? "").trim();
  const translatedComment = String(formData.get("translatedComment") ?? "").trim();
  const translatedLanguage = String(formData.get("translatedLanguage") ?? "").trim();

  if (!observationId || !translatedComment) return { error: "not_found" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("translate_teacher_observation", {
    p_observation_id: observationId,
    p_translated_comment: translatedComment,
    p_translated_language: translatedLanguage || undefined,
  });

  if (error) return { error: "save_error" };

  revalidateAcademicPaths();
  return { success: "observation_translated" };
}
