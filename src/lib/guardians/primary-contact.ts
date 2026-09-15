import type { SupabaseClient } from "@supabase/supabase-js";
import { isPrimaryContactUniqueViolation } from "@/lib/guardians/check-guardian-duplicates";

export async function clearActivePrimaryContacts(
  supabase: SupabaseClient,
  studentId: string,
  updatedBy: string,
  excludeLinkId?: string,
): Promise<void> {
  let query = supabase
    .from("student_guardian")
    .update({ is_primary_contact: false, updated_by: updatedBy })
    .eq("student_id", studentId)
    .eq("status", "active")
    .eq("is_primary_contact", true);

  if (excludeLinkId) {
    query = query.neq("id", excludeLinkId);
  }

  const { error } = await query;
  if (error) throw error;
}

export async function applyPrimaryContactFlag(
  supabase: SupabaseClient,
  linkId: string,
  studentId: string,
  makePrimary: boolean,
  updatedBy: string,
): Promise<{ ok: true } | { ok: false; error: "primary_conflict" | "save_error" }> {
  if (!makePrimary) {
    const { error } = await supabase
      .from("student_guardian")
      .update({ is_primary_contact: false, updated_by: updatedBy })
      .eq("id", linkId)
      .eq("student_id", studentId)
      .eq("status", "active");

    if (error) return { ok: false, error: "save_error" };
    return { ok: true };
  }

  await clearActivePrimaryContacts(supabase, studentId, updatedBy, linkId);

  const { error } = await supabase
    .from("student_guardian")
    .update({ is_primary_contact: true, updated_by: updatedBy })
    .eq("id", linkId)
    .eq("student_id", studentId)
    .eq("status", "active");

  if (error) {
    if (isPrimaryContactUniqueViolation(error)) {
      return { ok: false, error: "primary_conflict" };
    }
    return { ok: false, error: "save_error" };
  }

  return { ok: true };
}

export { isPrimaryContactUniqueViolation };
