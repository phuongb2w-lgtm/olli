import type { SupabaseClient } from "@supabase/supabase-js";
import { isPrimaryContactUniqueViolation } from "@/lib/guardians/check-guardian-duplicates";
import { applyPrimaryContactFlag, clearActivePrimaryContacts } from "@/lib/guardians/primary-contact";
import type { ValidatedLinkInput } from "@/lib/guardians/validate-guardian-input";

export type LinkGuardianResult =
  | { ok: true; linkId: string; reactivated: boolean }
  | { ok: false; error: "already_linked" | "primary_conflict" | "save_error" | "not_found" };

export async function linkGuardianToStudent(
  supabase: SupabaseClient,
  params: {
    organizationId: string;
    studentId: string;
    guardianId: string;
    link: ValidatedLinkInput;
    actorId: string;
  },
): Promise<LinkGuardianResult> {
  const { organizationId, studentId, guardianId, link, actorId } = params;

  const { data: existing, error: findError } = await supabase
    .from("student_guardian")
    .select("id, status")
    .eq("student_id", studentId)
    .eq("guardian_id", guardianId)
    .maybeSingle();

  if (findError) {
    return { ok: false, error: "save_error" };
  }

  if (existing?.status === "active") {
    return { ok: false, error: "already_linked" };
  }

  let linkId: string;

  if (existing?.status === "ended") {
    const { data: reactivated, error: reactivateError } = await supabase
      .from("student_guardian")
      .update({
        status: "active",
        relationship_type: link.relationshipType,
        is_primary_contact: false,
        is_billing_contact: link.isBillingContact,
        updated_by: actorId,
      })
      .eq("id", existing.id)
      .select("id")
      .single();

    if (reactivateError || !reactivated) {
      return { ok: false, error: "save_error" };
    }
    linkId = reactivated.id;
  } else {
    const { data: inserted, error: insertError } = await supabase
      .from("student_guardian")
      .insert({
        organization_id: organizationId,
        student_id: studentId,
        guardian_id: guardianId,
        relationship_type: link.relationshipType,
        is_primary_contact: false,
        is_billing_contact: link.isBillingContact,
        status: "active",
        created_by: actorId,
        updated_by: actorId,
      })
      .select("id")
      .single();

    if (insertError || !inserted) {
      if (isPrimaryContactUniqueViolation(insertError)) {
        return { ok: false, error: "primary_conflict" };
      }
      return { ok: false, error: "save_error" };
    }
    linkId = inserted.id;
  }

  if (link.isPrimaryContact) {
    const primaryResult = await applyPrimaryContactFlag(
      supabase,
      linkId,
      studentId,
      true,
      actorId,
    );
    if (!primaryResult.ok) {
      return { ok: false, error: primaryResult.error };
    }
  }

  return { ok: true, linkId, reactivated: existing?.status === "ended" };
}

export async function updateStudentGuardianLinkRecord(
  supabase: SupabaseClient,
  params: {
    linkId: string;
    studentId: string;
    link: ValidatedLinkInput;
    actorId: string;
  },
): Promise<{ ok: true } | { ok: false; error: "primary_conflict" | "save_error" | "not_found" }> {
  const { linkId, studentId, link, actorId } = params;

  const { data: existing, error: loadError } = await supabase
    .from("student_guardian")
    .select("id, status")
    .eq("id", linkId)
    .eq("student_id", studentId)
    .maybeSingle();

  if (loadError || !existing || existing.status !== "active") {
    return { ok: false, error: "not_found" };
  }

  if (link.isPrimaryContact) {
    await clearActivePrimaryContacts(supabase, studentId, actorId, linkId);
  }

  const { error: updateError } = await supabase
    .from("student_guardian")
    .update({
      relationship_type: link.relationshipType,
      is_billing_contact: link.isBillingContact,
      is_primary_contact: link.isPrimaryContact,
      updated_by: actorId,
    })
    .eq("id", linkId);

  if (updateError) {
    if (isPrimaryContactUniqueViolation(updateError)) {
      return { ok: false, error: "primary_conflict" };
    }
    return { ok: false, error: "save_error" };
  }

  return { ok: true };
}
