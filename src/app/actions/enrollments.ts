"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import {
  canEnrollInClass,
  isCreateStatusAllowedForClass,
} from "@/lib/enrollments/class-enrollment-rules";
import { countOperationalEnrollments, isCapacityExceeded } from "@/lib/enrollments/capacity";
import type { CreateEnrollmentStatus } from "@/lib/enrollments/constants";
import { searchStudentsForEnrollment } from "@/lib/enrollments/query-student-search";
import type { StudentSearchItem } from "@/lib/enrollments/query-student-search";
import {
  isCapacityReached,
  isOverlapConflict,
  validateCreateEnrollmentInput,
} from "@/lib/enrollments/validate-enrollment-input";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import type { ClassStatus } from "@/lib/academic/constants";

export type EnrollmentFormValues = {
  studentId: string;
  classId: string;
  startDate: string;
  status: CreateEnrollmentStatus;
};

export type EnrollmentActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "overlap_conflict"
    | "capacity_reached"
    | "class_closed"
    | "invalid_class_status"
    | "invalid_student"
    | "invalid_class";
  fieldErrors?: Partial<Record<"studentId" | "classId" | "startDate" | "status", string>>;
  confirmRequired?: "withdraw" | "complete";
  values?: EnrollmentFormValues;
  success?: "created" | "withdrawn" | "completed" | "transferred";
};

export type TransferFormValues = {
  destinationClassId: string;
  startDate: string;
  status: CreateEnrollmentStatus;
};

export type TransferActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "overlap_conflict"
    | "capacity_reached"
    | "class_closed"
    | "invalid_class";
  fieldErrors?: Partial<Record<"destinationClassId" | "startDate" | "status", string>>;
  values?: TransferFormValues;
  success?: boolean;
};

function parseCreateFields(formData: FormData) {
  return {
    studentId: String(formData.get("studentId") ?? "").trim(),
    classId: String(formData.get("classId") ?? "").trim(),
    startDate: String(formData.get("startDate") ?? ""),
    status: String(formData.get("status") ?? "pending"),
    returnTo: String(formData.get("returnTo") ?? "roster").trim(),
  };
}

function revalidateEnrollmentPaths(studentId: string, classId: string) {
  revalidatePath(`/classes/${classId}/roster`);
  revalidatePath(`/students/${studentId}/enrollments`);
  revalidatePath("/classes");
  revalidatePath("/students");
}

export async function searchStudentsForEnrollmentAction(
  query: string,
): Promise<{ items: StudentSearchItem[]; error?: "permission_denied" }> {
  const hasCreate = await can("enrollment.create");
  if (!hasCreate) return { items: [], error: "permission_denied" };

  const supabase = await createClient();
  const items = await searchStudentsForEnrollment(supabase, query);
  return { items };
}

async function loadClassForEnrollment(
  supabase: Awaited<ReturnType<typeof createClient>>,
  classId: string,
) {
  const { data, error } = await supabase
    .from("class")
    .select("id, status, capacity")
    .eq("id", classId)
    .maybeSingle();
  if (error || !data) return null;
  return data;
}

async function loadStudentForEnrollment(
  supabase: Awaited<ReturnType<typeof createClient>>,
  studentId: string,
) {
  const { data, error } = await supabase
    .from("student")
    .select("id, status")
    .eq("id", studentId)
    .maybeSingle();
  if (error || !data) return null;
  return data;
}

export async function createEnrollment(
  _prevState: EnrollmentActionState,
  formData: FormData,
): Promise<EnrollmentActionState> {
  const hasCreate = await can("enrollment.create");
  if (!hasCreate) return { error: "permission_denied" };

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const fields = parseCreateFields(formData);
  const validation = validateCreateEnrollmentInput(fields);
  if (!validation.ok) {
    return {
      fieldErrors: validation.fieldErrors,
      values: {
        studentId: fields.studentId,
        classId: fields.classId,
        startDate: fields.startDate,
        status: fields.status as CreateEnrollmentStatus,
      },
    };
  }

  const supabase = await createClient();
  const { data: validated } = validation;

  const [student, cls] = await Promise.all([
    loadStudentForEnrollment(supabase, validated.studentId),
    loadClassForEnrollment(supabase, validated.classId),
  ]);

  if (!student) {
    return {
      error: "invalid_student",
      values: {
        studentId: validated.studentId,
        classId: validated.classId,
        startDate: validated.startDate,
        status: validated.status,
      },
    };
  }

  if (!cls) {
    return {
      error: "invalid_class",
      values: {
        studentId: validated.studentId,
        classId: validated.classId,
        startDate: validated.startDate,
        status: validated.status,
      },
    };
  }

  if (!canEnrollInClass(cls.status as ClassStatus)) {
    return { error: "class_closed", values: toFormValues(validated) };
  }

  if (
    !isCreateStatusAllowedForClass(
      cls.status as ClassStatus,
      validated.status,
    )
  ) {
    return { error: "invalid_class_status", values: toFormValues(validated) };
  }

  const operationalCount = await countOperationalEnrollments(supabase, validated.classId);
  if (isCapacityExceeded(cls.capacity, operationalCount)) {
    return { error: "capacity_reached", values: toFormValues(validated) };
  }

  const { error } = await supabase.from("enrollment").insert({
    organization_id: appUser.organizationId,
    student_id: validated.studentId,
    class_id: validated.classId,
    start_date: validated.startDate,
    status: validated.status,
    created_by: appUser.appUserId,
    updated_by: appUser.appUserId,
  });

  if (error) {
    if (isOverlapConflict(error)) {
      return { error: "overlap_conflict", values: toFormValues(validated) };
    }
    return { error: "save_error", values: toFormValues(validated) };
  }

  revalidateEnrollmentPaths(validated.studentId, validated.classId);

  if (fields.returnTo === "student") {
    redirect(`/students/${validated.studentId}/enrollments?success=created`);
  }
  redirect(`/classes/${validated.classId}/roster?success=created`);
}

function toFormValues(data: {
  studentId: string;
  classId: string;
  startDate: string;
  status: CreateEnrollmentStatus;
}): EnrollmentFormValues {
  return {
    studentId: data.studentId,
    classId: data.classId,
    startDate: data.startDate,
    status: data.status,
  };
}

export async function withdrawEnrollment(
  _prevState: EnrollmentActionState,
  formData: FormData,
): Promise<EnrollmentActionState> {
  const hasUpdate = await can("enrollment.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const confirmWithdraw = formData.get("confirmWithdraw") === "true";
  const endDateRaw = String(formData.get("endDate") ?? "").trim();

  if (!enrollmentId) return { error: "not_found" };

  const supabase = await createClient();
  const { data: enrollment, error: loadError } = await supabase
    .from("enrollment")
    .select("id, student_id, class_id, status, start_date")
    .eq("id", enrollmentId)
    .maybeSingle();

  if (loadError || !enrollment) return { error: "not_found" };
  if (enrollment.status !== "pending" && enrollment.status !== "active") {
    return { error: "save_error" };
  }

  if (!confirmWithdraw) {
    return { confirmRequired: "withdraw" };
  }

  const endDate = endDateRaw || new Date().toISOString().slice(0, 10);
  if (endDate < enrollment.start_date) {
    return { error: "save_error" };
  }

  const { error } = await supabase
    .from("enrollment")
    .update({
      status: "withdrawn",
      end_date: endDate,
      updated_by: appUser.appUserId,
    })
    .eq("id", enrollmentId);

  if (error) return { error: "save_error" };

  revalidateEnrollmentPaths(enrollment.student_id, enrollment.class_id);
  redirect(`/classes/${enrollment.class_id}/roster?success=withdrawn`);
}

export async function completeEnrollment(
  _prevState: EnrollmentActionState,
  formData: FormData,
): Promise<EnrollmentActionState> {
  const hasUpdate = await can("enrollment.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const confirmComplete = formData.get("confirmComplete") === "true";
  const endDateRaw = String(formData.get("endDate") ?? "").trim();

  if (!enrollmentId) return { error: "not_found" };

  const supabase = await createClient();
  const { data: enrollment, error: loadError } = await supabase
    .from("enrollment")
    .select("id, student_id, class_id, status, start_date")
    .eq("id", enrollmentId)
    .maybeSingle();

  if (loadError || !enrollment) return { error: "not_found" };
  if (enrollment.status !== "pending" && enrollment.status !== "active") {
    return { error: "save_error" };
  }

  if (!confirmComplete) {
    return { confirmRequired: "complete" };
  }

  const endDate = endDateRaw || new Date().toISOString().slice(0, 10);
  if (endDate < enrollment.start_date) {
    return { error: "save_error" };
  }

  const { error } = await supabase
    .from("enrollment")
    .update({
      status: "completed",
      end_date: endDate,
      updated_by: appUser.appUserId,
    })
    .eq("id", enrollmentId);

  if (error) return { error: "save_error" };

  revalidateEnrollmentPaths(enrollment.student_id, enrollment.class_id);
  redirect(`/classes/${enrollment.class_id}/roster?success=completed`);
}

export async function transferEnrollment(
  _prevState: TransferActionState,
  formData: FormData,
): Promise<TransferActionState> {
  const hasUpdate = await can("enrollment.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const enrollmentId = String(formData.get("enrollmentId") ?? "").trim();
  const destinationClassId = String(formData.get("destinationClassId") ?? "").trim();
  const startDate = String(formData.get("startDate") ?? "").trim();
  const status = String(formData.get("status") ?? "pending") as CreateEnrollmentStatus;
  const confirmTransfer = formData.get("confirmTransfer") === "true";

  const values: TransferFormValues = {
    destinationClassId,
    startDate,
    status,
  };

  if (!enrollmentId) return { error: "not_found", values };
  if (!destinationClassId || !startDate) {
    return {
      fieldErrors: {
        destinationClassId: !destinationClassId ? "required" : undefined,
        startDate: !startDate ? "required" : undefined,
      },
      values,
    };
  }

  if (!confirmTransfer) {
    return { fieldErrors: { destinationClassId: "confirmRequired" }, values };
  }

  const supabase = await createClient();
  const { data: source, error: loadError } = await supabase
    .from("enrollment")
    .select("id, student_id, class_id, status")
    .eq("id", enrollmentId)
    .maybeSingle();

  if (loadError || !source) return { error: "not_found", values };
  if (source.status !== "pending" && source.status !== "active") {
    return { error: "save_error", values };
  }

  const callRpc = supabase.rpc.bind(supabase) as (
    fn: string,
    args: Record<string, unknown>,
  ) => ReturnType<typeof supabase.rpc>;

  const { error } = await callRpc("transfer_enrollment", {
    p_source_enrollment_id: enrollmentId,
    p_destination_class_id: destinationClassId,
    p_destination_start_date: startDate,
    p_destination_status: status,
  });

  if (error) {
    const message = error.message ?? "";
    if (isOverlapConflict(error) || message.includes("overlap_conflict")) {
      return { error: "overlap_conflict", values };
    }
    if (isCapacityReached(error) || message.includes("capacity_reached")) {
      return { error: "capacity_reached", values };
    }
    if (message.includes("class_closed")) {
      return { error: "class_closed", values };
    }
    if (message.includes("invalid_class")) {
      return { error: "invalid_class", values };
    }
    if (message.includes("permission_denied")) {
      return { error: "permission_denied", values };
    }
    return { error: "save_error", values };
  }

  revalidateEnrollmentPaths(source.student_id, source.class_id);
  revalidateEnrollmentPaths(source.student_id, destinationClassId);
  redirect(`/classes/${destinationClassId}/roster?success=transferred`);
}
