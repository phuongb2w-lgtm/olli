"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import {
  isEnrollmentEligibleOnAssessmentDate,
  isEnrollmentVisibleForAssessmentResult,
} from "@/lib/assessments/eligibility";
import { fetchAssessmentDetail } from "@/lib/assessments/query-class-assessments";
import {
  validateAssessmentInput,
  validateScoreInput,
} from "@/lib/assessments/validate-assessment-input";
import type { EnrollmentStatus } from "@/lib/enrollments/constants";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type AssessmentActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "class_closed"
    | "invalid_score"
    | "score_exceeds_max"
    | "cross_class"
    | "not_eligible"
    | "pending_enrollment"
    | "duplicate_result";
  fieldErrors?: Record<string, string>;
  success?: string;
};

function revalidateAssessment(classId: string, assessmentId?: string) {
  revalidatePath(`/classes/${classId}/assessments`);
  if (assessmentId) {
    revalidatePath(`/classes/${classId}/assessments/${assessmentId}`);
  }
}

async function loadClass(classId: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("class")
    .select("id, status, organization_id")
    .eq("id", classId)
    .maybeSingle();
  return data;
}

async function assertEnrollmentForAssessment(
  enrollmentId: string,
  classId: string,
  assessmentDate: string,
) {
  const supabase = await createClient();
  const { data: enrollment } = await supabase
    .from("enrollment")
    .select("id, class_id, student_id, start_date, end_date, status")
    .eq("id", enrollmentId)
    .maybeSingle();
  if (!enrollment || enrollment.class_id !== classId) {
    return { ok: false as const, error: "not_found" as const };
  }
  const row = {
    startDate: enrollment.start_date,
    endDate: enrollment.end_date,
    status: enrollment.status as EnrollmentStatus,
  };
  if (!isEnrollmentVisibleForAssessmentResult(row, assessmentDate)) {
    if (enrollment.status === "pending") return { ok: false as const, error: "pending_enrollment" as const };
    if (!isEnrollmentEligibleOnAssessmentDate(row, assessmentDate)) {
      return { ok: false as const, error: "not_eligible" as const };
    }
    return { ok: false as const, error: "not_eligible" as const };
  }
  return { ok: true as const, enrollment };
}

function isDuplicateResult(error: { code?: string; message?: string } | null) {
  if (!error) return false;
  if (error.code === "23505") return true;
  return error.message?.includes("duplicate") ?? false;
}

function isCrossClassError(error: { message?: string } | null) {
  if (!error?.message) return false;
  return (
    error.message.includes("assessment_class_mismatch") ||
    error.message.includes("enrollment_not_eligible") ||
    error.message.includes("pending_enrollment") ||
    error.message.includes("invalid_raw_score") ||
    error.message.includes("invalid_max_score")
  );
}

export async function createAssessmentAction(
  _prev: AssessmentActionState,
  formData: FormData,
): Promise<AssessmentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("assessment.create"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "");
  const classRow = await loadClass(classId);
  if (!classRow) return { error: "not_found" };
  if (classRow.status === "closed") return { error: "class_closed" };

  const parsed = validateAssessmentInput({
    title: String(formData.get("title") ?? ""),
    assessedOn: String(formData.get("assessedOn") ?? ""),
    maxScore: String(formData.get("maxScore") ?? ""),
    assessmentTypeCode: String(formData.get("assessmentTypeCode") ?? ""),
    status: String(formData.get("status") ?? "open"),
  });
  if (!parsed.ok) {
    return {
      error: "save_error",
      fieldErrors: Object.fromEntries(
        Object.entries(parsed.fieldErrors).map(([k, v]) => [k, v]),
      ),
    };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("assessment")
    .insert({
      organization_id: user.organizationId,
      class_id: classId,
      title: parsed.value.title,
      assessed_on: parsed.value.assessedOn,
      max_score: parsed.value.maxScore,
      assessment_type_code: parsed.value.assessmentTypeCode,
      status: parsed.value.status,
      created_by: user.appUserId,
      updated_by: user.appUserId,
    })
    .select("id")
    .single();

  if (error || !data) return { error: "save_error" };

  revalidateAssessment(classId);
  redirect(`/classes/${classId}/assessments/${data.id}?success=assessment_created`);
}

export async function updateAssessmentAction(
  _prev: AssessmentActionState,
  formData: FormData,
): Promise<AssessmentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("assessment.create"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "");
  const assessmentId = String(formData.get("assessmentId") ?? "");
  const classRow = await loadClass(classId);
  if (!classRow) return { error: "not_found" };

  const parsed = validateAssessmentInput({
    title: String(formData.get("title") ?? ""),
    assessedOn: String(formData.get("assessedOn") ?? ""),
    maxScore: String(formData.get("maxScore") ?? ""),
    assessmentTypeCode: String(formData.get("assessmentTypeCode") ?? ""),
    status: String(formData.get("status") ?? "open"),
  });
  if (!parsed.ok) {
    return {
      error: "save_error",
      fieldErrors: Object.fromEntries(
        Object.entries(parsed.fieldErrors).map(([k, v]) => [k, v]),
      ),
    };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("assessment")
    .update({
      title: parsed.value.title,
      assessed_on: parsed.value.assessedOn,
      max_score: parsed.value.maxScore,
      assessment_type_code: parsed.value.assessmentTypeCode,
      status: parsed.value.status,
      updated_by: user.appUserId,
    })
    .eq("id", assessmentId)
    .eq("class_id", classId);

  if (error) return { error: "save_error" };

  revalidateAssessment(classId, assessmentId);
  redirect(`/classes/${classId}/assessments/${assessmentId}?success=assessment_updated`);
}

export async function recordScoreAction(
  _prev: AssessmentActionState,
  formData: FormData,
): Promise<AssessmentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("assessment_result.record"))) {
    return { error: "permission_denied" };
  }

  const classId = String(formData.get("classId") ?? "");
  const assessmentId = String(formData.get("assessmentId") ?? "");
  const enrollmentId = String(formData.get("enrollmentId") ?? "");
  const rawScoreRaw = String(formData.get("rawScore") ?? "");

  const supabase = await createClient();
  const assessment = await fetchAssessmentDetail(supabase, classId, assessmentId);
  if (!assessment) return { error: "not_found" };

  const enrollmentCheck = await assertEnrollmentForAssessment(
    enrollmentId,
    classId,
    assessment.assessedOn,
  );
  if (!enrollmentCheck.ok) {
    if (enrollmentCheck.error === "pending_enrollment") return { error: "pending_enrollment" };
    if (enrollmentCheck.error === "not_eligible") return { error: "not_eligible" };
    return { error: "cross_class" };
  }

  const scoreParsed = validateScoreInput(rawScoreRaw, assessment.maxScore);
  if (!scoreParsed.ok) {
    if (scoreParsed.error === "exceeds_max") return { error: "score_exceeds_max" };
    return { error: "invalid_score" };
  }

  const { data: existing } = await supabase
    .from("assessment_result")
    .select("id, status")
    .eq("assessment_id", assessmentId)
    .eq("enrollment_id", enrollmentId)
    .maybeSingle();

  if (existing) {
    const { error } = await supabase
      .from("assessment_result")
      .update({
        raw_score: scoreParsed.rawScore,
        max_score: assessment.maxScore,
        status: "corrected",
        updated_by: user.appUserId,
      })
      .eq("id", existing.id);
    if (error) {
      if (isCrossClassError(error)) return { error: "cross_class" };
      return { error: "save_error" };
    }
  } else {
    const { error } = await supabase.from("assessment_result").insert({
      organization_id: user.organizationId,
      assessment_id: assessmentId,
      enrollment_id: enrollmentId,
      raw_score: scoreParsed.rawScore,
      max_score: assessment.maxScore,
      status: "draft",
      recorded_by: user.appUserId,
      updated_by: user.appUserId,
    });
    if (error) {
      if (isDuplicateResult(error)) return { error: "duplicate_result" };
      if (isCrossClassError(error)) return { error: "cross_class" };
      return { error: "save_error" };
    }
  }

  revalidateAssessment(classId, assessmentId);
  revalidatePath(`/students/${enrollmentCheck.enrollment.student_id}/reports/progress`);
  redirect(`/classes/${classId}/assessments/${assessmentId}?success=results_updated`);
}

export async function recordScoreFormAction(
  prev: AssessmentActionState,
  formData: FormData,
): Promise<AssessmentActionState> {
  return recordScoreAction(prev, formData);
}
