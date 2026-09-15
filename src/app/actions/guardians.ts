"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import {
  hasGuardianEmailDuplicate,
  hasGuardianPhoneDuplicate,
} from "@/lib/guardians/check-guardian-duplicates";
import { linkGuardianToStudent, updateStudentGuardianLinkRecord } from "@/lib/guardians/link-guardian";
import { applyPrimaryContactFlag } from "@/lib/guardians/primary-contact";
import { searchGuardians as searchGuardiansQuery } from "@/lib/guardians/query-guardian-search";
import type { GuardianSearchItem } from "@/lib/guardians/query-guardian-search";
import { validateGuardianInput, validateLinkInput } from "@/lib/guardians/validate-guardian-input";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type GuardianFormValues = {
  familyName: string;
  givenName: string;
  phone: string;
  email: string;
};

export type LinkFormValues = {
  relationshipType: string;
  isPrimaryContact: boolean;
  isBillingContact: boolean;
};

export type GuardianActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "already_linked"
    | "primary_conflict";
  fieldErrors?: Record<string, string>;
  duplicateWarning?: "email" | "phone" | "both";
  primaryReplaceRequired?: boolean;
  values?: GuardianFormValues & Partial<LinkFormValues>;
  success?: "created" | "updated" | "linked" | "unlinked";
};

function parseGuardianFields(formData: FormData) {
  return {
    familyName: String(formData.get("familyName") ?? ""),
    givenName: String(formData.get("givenName") ?? ""),
    phone: String(formData.get("phone") ?? ""),
    email: String(formData.get("email") ?? ""),
    confirmDuplicate: formData.get("confirmDuplicate") === "true",
    studentId: String(formData.get("studentId") ?? ""),
    guardianId: formData.get("guardianId") ? String(formData.get("guardianId")) : null,
    linkId: formData.get("linkId") ? String(formData.get("linkId")) : null,
    relationshipType: String(formData.get("relationshipType") ?? "guardian"),
    isPrimaryContact: formData.get("isPrimaryContact") === "true",
    isBillingContact: formData.get("isBillingContact") === "true",
    confirmUnlink: formData.get("confirmUnlink") === "true",
    confirmPrimaryReplace: formData.get("confirmPrimaryReplace") === "true",
  };
}

function revalidateStudentGuardians(studentId: string) {
  revalidatePath(`/students/${studentId}/guardians`);
  revalidatePath("/students");
}

export async function searchGuardiansAction(query: string): Promise<{
  items: GuardianSearchItem[];
  error?: "permission_denied";
}> {
  const hasGuardianRead = await can("guardian.read");
  if (!hasGuardianRead) {
    return { items: [], error: "permission_denied" };
  }

  const supabase = await createClient();
  const items = await searchGuardiansQuery(supabase, query);
  return { items };
}

export async function createGuardian(
  _prevState: GuardianActionState,
  formData: FormData,
): Promise<GuardianActionState> {
  const hasCreate = await can("guardian.create");
  if (!hasCreate) return { error: "permission_denied" };

  const fields = parseGuardianFields(formData);
  const validation = validateGuardianInput(fields);
  if (!validation.ok) {
    return { fieldErrors: validation.fieldErrors, values: fields };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const supabase = await createClient();
  const { data: validated } = validation;

  if (!fields.confirmDuplicate) {
    const emailDup =
      validated.email && (await hasGuardianEmailDuplicate(supabase, validated.email));
    const phoneDup =
      validated.phone && (await hasGuardianPhoneDuplicate(supabase, validated.phone));
    if (emailDup || phoneDup) {
      return {
        duplicateWarning: emailDup && phoneDup ? "both" : emailDup ? "email" : "phone",
        values: fields,
      };
    }
  }

  const { data: guardian, error } = await supabase
    .from("guardian")
    .insert({
      organization_id: appUser.organizationId,
      family_name: validated.familyName,
      given_name: validated.givenName,
      phone: validated.phone,
      email: validated.email,
      status: validated.status,
      created_by: appUser.appUserId,
      updated_by: appUser.appUserId,
    })
    .select("id")
    .single();

  if (error || !guardian) {
    return { error: "save_error", values: fields };
  }

  if (fields.studentId) {
    const linkValidation = validateLinkInput(fields);
    if (!linkValidation.ok) {
      return { fieldErrors: linkValidation.fieldErrors, values: fields };
    }

    const linkResult = await linkGuardianToStudent(supabase, {
      organizationId: appUser.organizationId,
      studentId: fields.studentId,
      guardianId: guardian.id,
      link: linkValidation.data,
      actorId: appUser.appUserId,
    });

    if (!linkResult.ok) {
      return { error: linkResult.error, values: fields };
    }

    revalidateStudentGuardians(fields.studentId);
    return { success: "linked", values: fields };
  }

  return { success: "created", values: fields };
}

export async function updateGuardian(
  _prevState: GuardianActionState,
  formData: FormData,
): Promise<GuardianActionState> {
  const hasUpdate = await can("guardian.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const fields = parseGuardianFields(formData);
  const guardianId = fields.guardianId;
  const studentId = fields.studentId;
  if (!guardianId) return { error: "not_found" };

  const validation = validateGuardianInput(fields);
  if (!validation.ok) {
    return { fieldErrors: validation.fieldErrors, values: fields };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const supabase = await createClient();
  const { data: validated } = validation;

  if (!fields.confirmDuplicate) {
    const emailDup =
      validated.email &&
      (await hasGuardianEmailDuplicate(supabase, validated.email, guardianId));
    const phoneDup =
      validated.phone &&
      (await hasGuardianPhoneDuplicate(supabase, validated.phone, guardianId));
    if (emailDup || phoneDup) {
      return {
        duplicateWarning: emailDup && phoneDup ? "both" : emailDup ? "email" : "phone",
        values: fields,
      };
    }
  }

  const { error } = await supabase
    .from("guardian")
    .update({
      family_name: validated.familyName,
      given_name: validated.givenName,
      phone: validated.phone,
      email: validated.email,
      updated_by: appUser.appUserId,
    })
    .eq("id", guardianId);

  if (error) {
    return { error: "save_error", values: fields };
  }

  if (studentId) revalidateStudentGuardians(studentId);
  revalidatePath("/students");
  return { success: "updated", values: fields };
}

export async function linkExistingGuardian(
  _prevState: GuardianActionState,
  formData: FormData,
): Promise<GuardianActionState> {
  const hasCreate = await can("guardian.create");
  if (!hasCreate) return { error: "permission_denied" };

  const fields = parseGuardianFields(formData);
  if (!fields.studentId || !fields.guardianId) return { error: "not_found" };

  const linkValidation = validateLinkInput(fields);
  if (!linkValidation.ok) {
    return { fieldErrors: linkValidation.fieldErrors, values: fields };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const supabase = await createClient();
  const result = await linkGuardianToStudent(supabase, {
    organizationId: appUser.organizationId,
    studentId: fields.studentId,
    guardianId: fields.guardianId,
    link: linkValidation.data,
    actorId: appUser.appUserId,
  });

  if (!result.ok) {
    return { error: result.error, values: fields };
  }

  revalidateStudentGuardians(fields.studentId);
  return { success: "linked", values: fields };
}

export async function updateLink(
  _prevState: GuardianActionState,
  formData: FormData,
): Promise<GuardianActionState> {
  const hasUpdate = await can("guardian.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const fields = parseGuardianFields(formData);
  if (!fields.studentId || !fields.linkId) return { error: "not_found" };

  const linkValidation = validateLinkInput(fields);
  if (!linkValidation.ok) {
    return { fieldErrors: linkValidation.fieldErrors, values: fields };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const supabase = await createClient();

  if (linkValidation.data.isPrimaryContact && !fields.confirmPrimaryReplace) {
    const { data: currentPrimary } = await supabase
      .from("student_guardian")
      .select("id, guardian_id")
      .eq("student_id", fields.studentId)
      .eq("status", "active")
      .eq("is_primary_contact", true)
      .neq("id", fields.linkId)
      .maybeSingle();

    if (currentPrimary) {
      return { values: fields, primaryReplaceRequired: true };
    }
  }

  const result = await updateStudentGuardianLinkRecord(supabase, {
    linkId: fields.linkId,
    studentId: fields.studentId,
    link: linkValidation.data,
    actorId: appUser.appUserId,
  });

  if (!result.ok) {
    return { error: result.error, values: fields };
  }

  revalidateStudentGuardians(fields.studentId);
  return { success: "updated", values: fields };
}

export async function togglePrimaryContact(
  _prevState: GuardianActionState,
  formData: FormData,
): Promise<GuardianActionState> {
  const hasUpdate = await can("guardian.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const fields = parseGuardianFields(formData);
  if (!fields.studentId || !fields.linkId) return { error: "not_found" };

  const makePrimary = formData.get("makePrimary") === "true";
  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const supabase = await createClient();

  if (makePrimary && !fields.confirmPrimaryReplace) {
    const { data: currentPrimary } = await supabase
      .from("student_guardian")
      .select("id")
      .eq("student_id", fields.studentId)
      .eq("status", "active")
      .eq("is_primary_contact", true)
      .neq("id", fields.linkId)
      .maybeSingle();

    if (currentPrimary) {
      return { values: fields, primaryReplaceRequired: true };
    }
  }

  const result = await applyPrimaryContactFlag(
    supabase,
    fields.linkId,
    fields.studentId,
    makePrimary,
    appUser.appUserId,
  );

  if (!result.ok) {
    return { error: result.error, values: fields };
  }

  revalidateStudentGuardians(fields.studentId);
  return { success: "updated", values: fields };
}

export async function toggleBillingContact(
  _prevState: GuardianActionState,
  formData: FormData,
): Promise<GuardianActionState> {
  const hasUpdate = await can("guardian.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const fields = parseGuardianFields(formData);
  if (!fields.studentId || !fields.linkId) return { error: "not_found" };

  const makeBilling = formData.get("makeBilling") === "true";
  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const supabase = await createClient();
  const { error } = await supabase
    .from("student_guardian")
    .update({
      is_billing_contact: makeBilling,
      updated_by: appUser.appUserId,
    })
    .eq("id", fields.linkId)
    .eq("student_id", fields.studentId)
    .eq("status", "active");

  if (error) return { error: "save_error", values: fields };

  revalidateStudentGuardians(fields.studentId);
  return { success: "updated", values: fields };
}

export async function unlinkGuardian(
  _prevState: GuardianActionState,
  formData: FormData,
): Promise<GuardianActionState> {
  const hasUpdate = await can("guardian.update");
  if (!hasUpdate) return { error: "permission_denied" };

  const fields = parseGuardianFields(formData);
  if (!fields.studentId || !fields.linkId) return { error: "not_found" };

  if (!fields.confirmUnlink) {
    return { fieldErrors: { confirmUnlink: "required" }, values: fields };
  }

  const appUser = await getCurrentAppUser();
  if (!appUser) return { error: "permission_denied" };

  const supabase = await createClient();
  const { error } = await supabase
    .from("student_guardian")
    .update({
      status: "ended",
      updated_by: appUser.appUserId,
    })
    .eq("id", fields.linkId)
    .eq("student_id", fields.studentId)
    .eq("status", "active");

  if (error) return { error: "save_error", values: fields };

  revalidateStudentGuardians(fields.studentId);
  return { success: "unlinked", values: fields };
}
