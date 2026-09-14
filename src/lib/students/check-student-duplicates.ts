import type { SupabaseClient } from "@supabase/supabase-js";
import {
  normalizeStudentCode,
  normalizedStudentCodeKey,
} from "@/lib/students/normalize-student-code";
import type { ValidatedStudentInput } from "@/lib/students/validate-student-input";

export function isStudentCodeUniqueViolation(error: { code?: string } | null): boolean {
  return error?.code === "23505";
}

/** Application pre-check; database unique index remains authoritative. */
export async function hasStudentCodeConflict(
  supabase: SupabaseClient,
  studentCode: string,
  excludeStudentId?: string,
): Promise<boolean> {
  const normalizedKey = normalizedStudentCodeKey(studentCode);

  const { data, error } = await supabase
    .from("student")
    .select("id, student_code")
    .not("student_code", "is", null);

  if (error) {
    throw error;
  }

  return (data ?? []).some((row) => {
    if (excludeStudentId && row.id === excludeStudentId) return false;
    if (!row.student_code) return false;
    return normalizedStudentCodeKey(row.student_code) === normalizedKey;
  });
}

/** Heuristic warning only — never blocks without explicit user confirmation. */
export async function hasNameDobDuplicate(
  supabase: SupabaseClient,
  input: Pick<ValidatedStudentInput, "familyName" | "givenName" | "dateOfBirth">,
  excludeStudentId?: string,
): Promise<boolean> {
  if (!input.dateOfBirth) {
    return false;
  }

  let query = supabase
    .from("student")
    .select("id", { count: "exact", head: true })
    .eq("family_name", input.familyName)
    .eq("given_name", input.givenName)
    .eq("date_of_birth", input.dateOfBirth);

  if (excludeStudentId) {
    query = query.neq("id", excludeStudentId);
  }

  const { count, error } = await query;
  if (error) {
    throw error;
  }

  return (count ?? 0) > 0;
}

export function parseStudentFormFields(formData: FormData): {
  familyName: string;
  givenName: string;
  studentCode: string;
  dateOfBirth: string;
  status: string;
  confirmDuplicate: boolean;
  confirmStatusChange: boolean;
  studentId: string | null;
  originalStatus: string;
} {
  return {
    familyName: String(formData.get("familyName") ?? ""),
    givenName: String(formData.get("givenName") ?? ""),
    studentCode: String(formData.get("studentCode") ?? ""),
    dateOfBirth: String(formData.get("dateOfBirth") ?? ""),
    status: String(formData.get("status") ?? ""),
    confirmDuplicate: formData.get("confirmDuplicate") === "true",
    confirmStatusChange: formData.get("confirmStatusChange") === "true",
    studentId: formData.get("studentId") ? String(formData.get("studentId")) : null,
    originalStatus: String(formData.get("originalStatus") ?? ""),
  };
}

export { normalizeStudentCode };
