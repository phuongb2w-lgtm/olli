"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  hasNameDobDuplicate,
  hasStudentCodeConflict,
  isStudentCodeUniqueViolation,
  parseStudentFormFields,
} from "@/lib/students/check-student-duplicates";
import type { StudentStatus } from "@/lib/students/constants";
import { validateStudentInput } from "@/lib/students/validate-student-input";
import { createClient } from "@/lib/supabase/server";

export type StudentFormValues = {
  familyName: string;
  givenName: string;
  studentCode: string;
  dateOfBirth: string;
  status: StudentStatus;
};

export type StudentActionState = {
  error?:
    | "permission_denied"
    | "student_code_conflict"
    | "save_error"
    | "not_found";
  fieldErrors?: Partial<
    Record<"familyName" | "givenName" | "studentCode" | "dateOfBirth" | "status", string>
  >;
  duplicateWarning?: boolean;
  statusChangeRequired?: {
    from: StudentStatus;
    to: StudentStatus;
  };
  values?: StudentFormValues;
};

function toFormValues(data: {
  familyName: string;
  givenName: string;
  studentCode: string | null;
  dateOfBirth: string | null;
  status: StudentStatus;
}): StudentFormValues {
  return {
    familyName: data.familyName,
    givenName: data.givenName,
    studentCode: data.studentCode ?? "",
    dateOfBirth: data.dateOfBirth ?? "",
    status: data.status,
  };
}

export async function createStudent(
  _prevState: StudentActionState,
  formData: FormData,
): Promise<StudentActionState> {
  const hasCreate = await can("student.create");
  if (!hasCreate) {
    return { error: "permission_denied" };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { error: "permission_denied" };
  }

  const fields = parseStudentFormFields(formData);
  const validation = validateStudentInput(fields);
  if (!validation.ok) {
    return {
      fieldErrors: validation.fieldErrors,
      values: {
        familyName: fields.familyName,
        givenName: fields.givenName,
        studentCode: fields.studentCode,
        dateOfBirth: fields.dateOfBirth,
        status: fields.status as StudentStatus,
      },
    };
  }

  const supabase = await createClient();
  const { data: validated } = validation;

  if (validated.studentCode) {
    const conflict = await hasStudentCodeConflict(supabase, validated.studentCode);
    if (conflict) {
      return {
        error: "student_code_conflict",
        values: toFormValues(validated),
      };
    }
  }

  if (!fields.confirmDuplicate) {
    const duplicate = await hasNameDobDuplicate(supabase, validated);
    if (duplicate) {
      return {
        duplicateWarning: true,
        values: toFormValues(validated),
      };
    }
  }

  const { error } = await supabase.from("student").insert({
    organization_id: appUser.organizationId,
    family_name: validated.familyName,
    given_name: validated.givenName,
    student_code: validated.studentCode,
    date_of_birth: validated.dateOfBirth,
    status: validated.status,
    created_by: appUser.appUserId,
    updated_by: appUser.appUserId,
  });

  if (error) {
    if (isStudentCodeUniqueViolation(error)) {
      return {
        error: "student_code_conflict",
        values: toFormValues(validated),
      };
    }
    return { error: "save_error", values: toFormValues(validated) };
  }

  revalidatePath("/students");
  redirect("/students?success=created");
}

export async function updateStudent(
  _prevState: StudentActionState,
  formData: FormData,
): Promise<StudentActionState> {
  const hasUpdate = await can("student.update");
  if (!hasUpdate) {
    return { error: "permission_denied" };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) {
    return { error: "permission_denied" };
  }

  const fields = parseStudentFormFields(formData);
  const studentId = fields.studentId;
  if (!studentId) {
    return { error: "not_found" };
  }

  const validation = validateStudentInput(fields);
  if (!validation.ok) {
    return {
      fieldErrors: validation.fieldErrors,
      values: {
        familyName: fields.familyName,
        givenName: fields.givenName,
        studentCode: fields.studentCode,
        dateOfBirth: fields.dateOfBirth,
        status: fields.status as StudentStatus,
      },
    };
  }

  const supabase = await createClient();
  const { data: existing, error: loadError } = await supabase
    .from("student")
    .select("id, status")
    .eq("id", studentId)
    .maybeSingle();

  if (loadError || !existing) {
    return { error: "not_found" };
  }

  const { data: validated } = validation;
  const originalStatus = (fields.originalStatus || existing.status) as StudentStatus;

  if (validated.status !== originalStatus && !fields.confirmStatusChange) {
    return {
      statusChangeRequired: { from: originalStatus, to: validated.status },
      values: toFormValues(validated),
    };
  }

  if (validated.studentCode) {
    const conflict = await hasStudentCodeConflict(supabase, validated.studentCode, studentId);
    if (conflict) {
      return {
        error: "student_code_conflict",
        values: toFormValues(validated),
      };
    }
  }

  const { error } = await supabase
    .from("student")
    .update({
      family_name: validated.familyName,
      given_name: validated.givenName,
      student_code: validated.studentCode,
      date_of_birth: validated.dateOfBirth,
      status: validated.status,
      updated_by: appUser.appUserId,
    })
    .eq("id", studentId);

  if (error) {
    if (isStudentCodeUniqueViolation(error)) {
      return {
        error: "student_code_conflict",
        values: toFormValues(validated),
      };
    }
    return { error: "save_error", values: toFormValues(validated) };
  }

  revalidatePath("/students");
  revalidatePath(`/students/${studentId}/edit`);
  redirect("/students?success=updated");
}
