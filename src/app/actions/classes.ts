"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import {
  CLASS_LIFECYCLE_CONFIRM_STATUSES,
  type ClassStatus,
} from "@/lib/academic/constants";
import { validateClassInput } from "@/lib/academic/validate-class-input";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type ClassFormValues = {
  name: string;
  courseId: string;
  termStartDate: string;
  termEndDate: string;
  capacity: string;
  status: ClassStatus;
};

export type ClassActionState = {
  error?: "permission_denied" | "save_error" | "not_found" | "invalid_course";
  fieldErrors?: Partial<
    Record<"name" | "courseId" | "termStartDate" | "termEndDate" | "capacity" | "status", string>
  >;
  statusChangeRequired?: {
    from: ClassStatus;
    to: ClassStatus;
  };
  values?: ClassFormValues;
};

function parseClassFormFields(formData: FormData) {
  return {
    classId: String(formData.get("classId") ?? "").trim(),
    originalStatus: String(formData.get("originalStatus") ?? "").trim(),
    confirmStatusChange: formData.get("confirmStatusChange") === "true",
    name: String(formData.get("name") ?? ""),
    courseId: String(formData.get("courseId") ?? ""),
    termStartDate: String(formData.get("termStartDate") ?? ""),
    termEndDate: String(formData.get("termEndDate") ?? ""),
    capacity: String(formData.get("capacity") ?? ""),
    status: String(formData.get("status") ?? ""),
  };
}

function toFormValues(data: {
  name: string;
  courseId: string;
  termStartDate: string | null;
  termEndDate: string | null;
  capacity: number | null;
  status: ClassStatus;
}): ClassFormValues {
  return {
    name: data.name,
    courseId: data.courseId,
    termStartDate: data.termStartDate ?? "",
    termEndDate: data.termEndDate ?? "",
    capacity: data.capacity != null ? String(data.capacity) : "",
    status: data.status,
  };
}

async function courseExistsInOrg(
  supabase: Awaited<ReturnType<typeof createClient>>,
  courseId: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("course")
    .select("id")
    .eq("id", courseId)
    .maybeSingle();
  return !error && Boolean(data);
}

export async function createClass(
  _prevState: ClassActionState,
  formData: FormData,
): Promise<ClassActionState> {
  const hasCreate = await can("enrollment.create");
  if (!hasCreate) {
    return { error: "permission_denied" };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { error: "permission_denied" };
  }

  const fields = parseClassFormFields(formData);
  const validation = validateClassInput(fields);
  if (!validation.ok) {
    return {
      fieldErrors: validation.fieldErrors,
      values: {
        name: fields.name,
        courseId: fields.courseId,
        termStartDate: fields.termStartDate,
        termEndDate: fields.termEndDate,
        capacity: fields.capacity,
        status: fields.status as ClassStatus,
      },
    };
  }

  const supabase = await createClient();
  const { data: validated } = validation;

  const courseOk = await courseExistsInOrg(supabase, validated.courseId);
  if (!courseOk) {
    return {
      error: "invalid_course",
      values: toFormValues(validated),
    };
  }

  const { error } = await supabase.from("class").insert({
    organization_id: appUser.organizationId,
    course_id: validated.courseId,
    name: validated.name,
    term_start_date: validated.termStartDate,
    term_end_date: validated.termEndDate,
    capacity: validated.capacity,
    status: validated.status,
    created_by: appUser.appUserId,
    updated_by: appUser.appUserId,
  });

  if (error) {
    return { error: "save_error", values: toFormValues(validated) };
  }

  revalidatePath("/classes");
  redirect("/classes?success=created");
}

export async function updateClass(
  _prevState: ClassActionState,
  formData: FormData,
): Promise<ClassActionState> {
  const hasUpdate = await can("enrollment.update");
  if (!hasUpdate) {
    return { error: "permission_denied" };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { error: "permission_denied" };
  }

  const fields = parseClassFormFields(formData);
  const classId = fields.classId;
  if (!classId) {
    return { error: "not_found" };
  }

  const validation = validateClassInput(fields);
  if (!validation.ok) {
    return {
      fieldErrors: validation.fieldErrors,
      values: {
        name: fields.name,
        courseId: fields.courseId,
        termStartDate: fields.termStartDate,
        termEndDate: fields.termEndDate,
        capacity: fields.capacity,
        status: fields.status as ClassStatus,
      },
    };
  }

  const supabase = await createClient();
  const { data: existing, error: loadError } = await supabase
    .from("class")
    .select("id, status")
    .eq("id", classId)
    .maybeSingle();

  if (loadError || !existing) {
    return { error: "not_found" };
  }

  const { data: validated } = validation;
  const originalStatus = (fields.originalStatus || existing.status) as ClassStatus;

  if (
    validated.status !== originalStatus &&
    CLASS_LIFECYCLE_CONFIRM_STATUSES.includes(validated.status) &&
    !fields.confirmStatusChange
  ) {
    return {
      statusChangeRequired: { from: originalStatus, to: validated.status },
      values: toFormValues(validated),
    };
  }

  const courseOk = await courseExistsInOrg(supabase, validated.courseId);
  if (!courseOk) {
    return {
      error: "invalid_course",
      values: toFormValues(validated),
    };
  }

  const { error } = await supabase
    .from("class")
    .update({
      course_id: validated.courseId,
      name: validated.name,
      term_start_date: validated.termStartDate,
      term_end_date: validated.termEndDate,
      capacity: validated.capacity,
      status: validated.status,
      updated_by: appUser.appUserId,
    })
    .eq("id", classId);

  if (error) {
    return { error: "save_error", values: toFormValues(validated) };
  }

  revalidatePath("/classes");
  revalidatePath(`/classes/${classId}/edit`);
  redirect("/classes?success=updated");
}
