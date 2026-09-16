"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  validateLessonCount,
  validateSetRecognitionStagesInput,
  type SetRecognitionStagesInput,
} from "@/lib/revenue-recognition/validate-revenue-recognition-input";
import { createClient } from "@/lib/supabase/server";

export type RevenueRecognitionActionState = {
  error?:
    | "permission_denied"
    | "validation_error"
    | "save_error"
    | "not_found";
  fieldErrors?: Record<string, string>;
  result?: Record<string, unknown>;
};

export async function initializePerLessonRecognition(
  termsId: string,
  lessonCount: number,
): Promise<RevenueRecognitionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("revenue.recognize"))) {
    return { error: "permission_denied" };
  }

  const count = validateLessonCount(lessonCount);
  if (!count) {
    return { error: "validation_error", fieldErrors: { lessonCount: "invalid" } };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("initialize_enrollment_per_lesson_recognition", {
    p_terms_id: termsId,
    p_lesson_count: count,
  });

  if (error || !data) return { error: "save_error" };
  return { result: { configId: data as string } };
}

export async function setRecognitionStages(
  input: SetRecognitionStagesInput,
): Promise<RevenueRecognitionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("revenue.recognize"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateSetRecognitionStagesInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_enrollment_recognition_stages", {
    p_terms_id: parsed.data.termsId,
    p_stages: parsed.data.stages.map((stage) => ({
      sequence_number: stage.sequenceNumber,
      amount: stage.amount,
      assessment_id: stage.assessmentId ?? null,
      label: stage.label ?? null,
    })),
  });

  if (error || !data) return { error: "save_error" };
  return { result: { configId: data as string } };
}

export async function recognizeEnrollmentRevenue(
  enrollmentId: string,
): Promise<RevenueRecognitionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("revenue.recognize"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("recognize_enrollment_revenue", {
    p_enrollment_id: enrollmentId,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function recognizeTeachingSessionRevenue(
  teachingSessionId: string,
): Promise<RevenueRecognitionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("revenue.recognize"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("recognize_teaching_session_revenue", {
    p_teaching_session_id: teachingSessionId,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function voidRevenueRecognitionEvent(
  eventId: string,
  notes?: string,
): Promise<RevenueRecognitionActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("revenue.recognize"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("void_revenue_recognition_event", {
    p_event_id: eventId,
    p_notes: notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}
