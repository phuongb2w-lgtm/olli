"use server";

import {
  normalizePersonalGridPreferences,
  type PersonalGridPreferences,
  type PersonalGridSurfaceKey,
} from "@/lib/custom-fields/personal-grid-preferences";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

const SURFACES: readonly PersonalGridSurfaceKey[] = ["students", "finance_students"];

async function canManagePersonalFields(): Promise<boolean> {
  return (await can("student_personal_field.manage")) || (await can("consultant_custom_field.manage"));
}

export async function loadPersonalGridPreferencesAction(
  surface: PersonalGridSurfaceKey,
): Promise<PersonalGridPreferences | null> {
  if (!SURFACES.includes(surface) || !(await canManagePersonalFields())) return null;

  const supabase = await createClient();
  const { data: orgId } = await supabase.rpc("current_organization_id");
  const { data: userId } = await supabase.rpc("current_app_user_id");
  if (!orgId || !userId) return null;

  const { data } = await supabase
    .from("personal_grid_preference")
    .select("preferences")
    .eq("organization_id", orgId)
    .eq("app_user_id", userId)
    .eq("surface_key", surface)
    .maybeSingle();

  return normalizePersonalGridPreferences(data?.preferences);
}

export async function savePersonalGridPreferencesAction(
  surface: PersonalGridSurfaceKey,
  preferences: PersonalGridPreferences,
): Promise<{ ok: boolean; errorCode?: "denied" | "failed" }> {
  if (!SURFACES.includes(surface) || !(await canManagePersonalFields())) {
    return { ok: false, errorCode: "denied" };
  }

  const supabase = await createClient();
  const { data: orgId, error: orgError } = await supabase.rpc("current_organization_id");
  const { data: userId, error: userError } = await supabase.rpc("current_app_user_id");
  if (orgError || userError || !orgId || !userId) {
    return { ok: false, errorCode: "failed" };
  }

  const { error } = await supabase.from("personal_grid_preference").upsert(
    {
      organization_id: orgId,
      app_user_id: userId,
      surface_key: surface,
      preferences: normalizePersonalGridPreferences(preferences),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "organization_id,app_user_id,surface_key" },
  );

  return error ? { ok: false, errorCode: "failed" } : { ok: true };
}
