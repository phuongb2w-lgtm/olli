"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import type { CourseStatus } from "@/lib/academic/constants";
import {
  isCourseCodeConflict,
  validateCourseInput,
} from "@/lib/academic/validate-course-input";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type CourseFormValues = {
  code: string;
  name: string;
  levelCode: string;
  status: CourseStatus;
};

export type CourseActionState = {
  error?: "permission_denied" | "course_code_conflict" | "save_error" | "not_found";
  fieldErrors?: Partial<Record<"code" | "name" | "levelCode" | "status", string>>;
  values?: CourseFormValues;
};

function parseCourseFormFields(formData: FormData) {
  return {
    courseId: String(formData.get("courseId") ?? "").trim(),
    code: String(formData.get("code") ?? ""),
    name: String(formData.get("name") ?? ""),
    levelCode: String(formData.get("levelCode") ?? ""),
    status: String(formData.get("status") ?? ""),
  };
}

function toFormValues(data: {
  code: string;
  name: string;
  levelCode: string | null;
  status: CourseStatus;
}): CourseFormValues {
  return {
    code: data.code,
    name: data.name,
    levelCode: data.levelCode ?? "",
    status: data.status,
  };
}

export async function createCourse(
  _prevState: CourseActionState,
  formData: FormData,
): Promise<CourseActionState> {
  const hasCreate = await can("enrollment.create");
  if (!hasCreate) {
    return { error: "permission_denied" };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { error: "permission_denied" };
  }

  const fields = parseCourseFormFields(formData);
  const validation = validateCourseInput(fields);
  if (!validation.ok) {
    return {
      fieldErrors: validation.fieldErrors,
      values: {
        code: fields.code,
        name: fields.name,
        levelCode: fields.levelCode,
        status: fields.status as CourseStatus,
      },
    };
  }

  const supabase = await createClient();
  const { data: validated } = validation;

  const { error } = await supabase.from("course").insert({
    organization_id: appUser.organizationId,
    code: validated.code,
    name: validated.name,
    level_code: validated.levelCode,
    status: validated.status,
    created_by: appUser.appUserId,
    updated_by: appUser.appUserId,
  });

  if (error) {
    if (isCourseCodeConflict(error)) {
      return {
        error: "course_code_conflict",
        values: toFormValues(validated),
      };
    }
    return { error: "save_error", values: toFormValues(validated) };
  }

  revalidatePath("/courses");
  revalidatePath("/classes");
  redirect("/courses?success=created");
}

export async function updateCourse(
  _prevState: CourseActionState,
  formData: FormData,
): Promise<CourseActionState> {
  const hasUpdate = await can("enrollment.update");
  if (!hasUpdate) {
    return { error: "permission_denied" };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { error: "permission_denied" };
  }

  const fields = parseCourseFormFields(formData);
  const courseId = fields.courseId;
  if (!courseId) {
    return { error: "not_found" };
  }

  const validation = validateCourseInput(fields);
  if (!validation.ok) {
    return {
      fieldErrors: validation.fieldErrors,
      values: {
        code: fields.code,
        name: fields.name,
        levelCode: fields.levelCode,
        status: fields.status as CourseStatus,
      },
    };
  }

  const supabase = await createClient();
  const { data: existing, error: loadError } = await supabase
    .from("course")
    .select("id")
    .eq("id", courseId)
    .maybeSingle();

  if (loadError || !existing) {
    return { error: "not_found" };
  }

  const { data: validated } = validation;

  const { error } = await supabase
    .from("course")
    .update({
      code: validated.code,
      name: validated.name,
      level_code: validated.levelCode,
      status: validated.status,
      updated_by: appUser.appUserId,
    })
    .eq("id", courseId);

  if (error) {
    if (isCourseCodeConflict(error)) {
      return {
        error: "course_code_conflict",
        values: toFormValues(validated),
      };
    }
    return { error: "save_error", values: toFormValues(validated) };
  }

  revalidatePath("/courses");
  revalidatePath("/classes");
  redirect("/courses?success=updated");
}
