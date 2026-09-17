"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";
import {
  validateEndUnavailabilityInput,
  validateOneOffUnavailabilityInput,
  validateRecurringUnavailabilityInput,
} from "@/lib/teaching/validate-unavailability-input";

export type TeacherUnavailabilityActionState = {
  error?:
    | "permission_denied"
    | "save_error"
    | "not_found"
    | "invalid_teacher"
    | "duplicate";
  fieldErrors?: Record<string, string>;
  values?: Record<string, string>;
  success?: string;
};

async function assertTeacherInOrg(teacherId: string, organizationId: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("teacher")
    .select("id, organization_id, status")
    .eq("id", teacherId)
    .maybeSingle();
  if (!data || data.organization_id !== organizationId) return null;
  return data;
}

function isDuplicateError(error: { code?: string; message?: string } | null) {
  if (!error) return false;
  return error.code === "23505" || (error.message ?? "").includes("duplicate");
}

export async function createRecurringUnavailabilityAction(
  _prev: TeacherUnavailabilityActionState,
  formData: FormData,
): Promise<TeacherUnavailabilityActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.create"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateRecurringUnavailabilityInput({
    teacherId: String(formData.get("teacherId") ?? ""),
    weekdayCode: String(formData.get("weekdayCode") ?? "") as never,
    startTime: String(formData.get("startTime") ?? ""),
    endTime: String(formData.get("endTime") ?? ""),
    effectiveFrom: String(formData.get("effectiveFrom") ?? ""),
    effectiveTo: String(formData.get("effectiveTo") ?? ""),
    reason: String(formData.get("reason") ?? ""),
  });

  if (!parsed.ok || !parsed.data) {
    return {
      error: "save_error",
      fieldErrors: parsed.fieldErrors,
      values: Object.fromEntries([...formData.entries()].map(([k, v]) => [k, String(v)])),
    };
  }

  const teacher = await assertTeacherInOrg(parsed.data.teacherId, user.organizationId);
  if (!teacher) return { error: "invalid_teacher" };

  const supabase = await createClient();
  const { error } = await supabase.from("teacher_unavailability").insert({
    organization_id: user.organizationId,
    teacher_id: parsed.data.teacherId,
    block_type: "recurring",
    weekday_code: parsed.data.weekdayCode,
    start_time: parsed.data.startTime,
    end_time: parsed.data.endTime,
    effective_from: parsed.data.effectiveFrom,
    effective_to: parsed.data.effectiveTo,
    reason: parsed.data.reason,
    status: "active",
    created_by: user.appUserId,
    updated_by: user.appUserId,
  });

  if (isDuplicateError(error)) return { error: "duplicate" };
  if (error) return { error: "save_error" };

  revalidatePath("/classes");
  return { success: "recurring_created" };
}

export async function createOneOffUnavailabilityAction(
  _prev: TeacherUnavailabilityActionState,
  formData: FormData,
): Promise<TeacherUnavailabilityActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.create"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateOneOffUnavailabilityInput({
    teacherId: String(formData.get("teacherId") ?? ""),
    startsAt: String(formData.get("startsAt") ?? ""),
    endsAt: String(formData.get("endsAt") ?? ""),
    reason: String(formData.get("reason") ?? ""),
  });

  if (!parsed.ok || !parsed.data) {
    return {
      error: "save_error",
      fieldErrors: parsed.fieldErrors,
      values: Object.fromEntries([...formData.entries()].map(([k, v]) => [k, String(v)])),
    };
  }

  const teacher = await assertTeacherInOrg(parsed.data.teacherId, user.organizationId);
  if (!teacher) return { error: "invalid_teacher" };

  const supabase = await createClient();
  const { error } = await supabase.from("teacher_unavailability").insert({
    organization_id: user.organizationId,
    teacher_id: parsed.data.teacherId,
    block_type: "one_off",
    starts_at: parsed.data.startsAt,
    ends_at: parsed.data.endsAt,
    reason: parsed.data.reason,
    status: "active",
    created_by: user.appUserId,
    updated_by: user.appUserId,
  });

  if (isDuplicateError(error)) return { error: "duplicate" };
  if (error) return { error: "save_error" };

  revalidatePath("/classes");
  return { success: "one_off_created" };
}

export async function updateRecurringUnavailabilityAction(
  _prev: TeacherUnavailabilityActionState,
  formData: FormData,
): Promise<TeacherUnavailabilityActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const blockId = String(formData.get("blockId") ?? "").trim();
  const parsed = validateRecurringUnavailabilityInput({
    teacherId: String(formData.get("teacherId") ?? ""),
    weekdayCode: String(formData.get("weekdayCode") ?? "") as never,
    startTime: String(formData.get("startTime") ?? ""),
    endTime: String(formData.get("endTime") ?? ""),
    effectiveFrom: String(formData.get("effectiveFrom") ?? ""),
    effectiveTo: String(formData.get("effectiveTo") ?? ""),
    reason: String(formData.get("reason") ?? ""),
  });

  if (!parsed.ok || !parsed.data) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("teacher_unavailability")
    .select("id, status, block_type")
    .eq("id", blockId)
    .maybeSingle();

  if (!existing || existing.block_type !== "recurring" || existing.status !== "active") {
    return { error: "not_found" };
  }

  const teacher = await assertTeacherInOrg(parsed.data.teacherId, user.organizationId);
  if (!teacher) return { error: "invalid_teacher" };

  const { error } = await supabase
    .from("teacher_unavailability")
    .update({
      weekday_code: parsed.data.weekdayCode,
      start_time: parsed.data.startTime,
      end_time: parsed.data.endTime,
      effective_from: parsed.data.effectiveFrom,
      effective_to: parsed.data.effectiveTo,
      reason: parsed.data.reason,
      updated_by: user.appUserId,
    })
    .eq("id", blockId);

  if (isDuplicateError(error)) return { error: "duplicate" };
  if (error) return { error: "save_error" };

  revalidatePath("/classes");
  return { success: "recurring_updated" };
}

export async function updateOneOffUnavailabilityAction(
  _prev: TeacherUnavailabilityActionState,
  formData: FormData,
): Promise<TeacherUnavailabilityActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const blockId = String(formData.get("blockId") ?? "").trim();
  const parsed = validateOneOffUnavailabilityInput({
    teacherId: String(formData.get("teacherId") ?? ""),
    startsAt: String(formData.get("startsAt") ?? ""),
    endsAt: String(formData.get("endsAt") ?? ""),
    reason: String(formData.get("reason") ?? ""),
  });

  if (!parsed.ok || !parsed.data) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("teacher_unavailability")
    .select("id, status, block_type")
    .eq("id", blockId)
    .maybeSingle();

  if (!existing || existing.block_type !== "one_off" || existing.status !== "active") {
    return { error: "not_found" };
  }

  const teacher = await assertTeacherInOrg(parsed.data.teacherId, user.organizationId);
  if (!teacher) return { error: "invalid_teacher" };

  const { error } = await supabase
    .from("teacher_unavailability")
    .update({
      starts_at: parsed.data.startsAt,
      ends_at: parsed.data.endsAt,
      reason: parsed.data.reason,
      updated_by: user.appUserId,
    })
    .eq("id", blockId);

  if (isDuplicateError(error)) return { error: "duplicate" };
  if (error) return { error: "save_error" };

  revalidatePath("/classes");
  return { success: "one_off_updated" };
}

export async function endTeacherUnavailabilityAction(
  _prev: TeacherUnavailabilityActionState,
  formData: FormData,
): Promise<TeacherUnavailabilityActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("enrollment.update"))) {
    return { error: "permission_denied" };
  }

  const blockId = String(formData.get("blockId") ?? "").trim();
  const effectiveTo = String(formData.get("effectiveTo") ?? "").trim();
  const parsed = validateEndUnavailabilityInput(effectiveTo);
  if (!parsed.ok) {
    return { error: "save_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data: existing } = await supabase
    .from("teacher_unavailability")
    .select("id, status, block_type, effective_to")
    .eq("id", blockId)
    .maybeSingle();

  if (!existing || existing.status !== "active") {
    return { error: "not_found" };
  }

  const { error } = await supabase
    .from("teacher_unavailability")
    .update({
      status: "ended",
      updated_by: user.appUserId,
      ...(existing.block_type === "recurring" && parsed.data.effectiveTo
        ? { effective_to: parsed.data.effectiveTo }
        : {}),
    })
    .eq("id", blockId);

  if (error) return { error: "save_error" };

  revalidatePath("/classes");
  return { success: "ended" };
}
