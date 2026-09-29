"use server";

import { revalidatePath } from "next/cache";
import { can } from "@/lib/permissions/can";
import {
  fetchConsultantWorkspacePortfolio,
  type FetchPortfolioParams,
} from "@/lib/consultant-workspace/fetch-portfolio";
import type { ConsultantGridPreferences } from "@/lib/consultant-workspace/grid-preferences";
import type { ConsultantWorkspacePortfolioResult } from "@/lib/consultant-workspace/portfolio-read-model";
import { createClient } from "@/lib/supabase/server";

export type ConsultantWorkspaceActionResult =
  | { ok: true; data: ConsultantWorkspacePortfolioResult }
  | { ok: false; errorCode: "denied" | "load_failed" };

export async function fetchConsultantWorkspacePortfolioAction(
  params: FetchPortfolioParams,
): Promise<ConsultantWorkspaceActionResult> {
  if (!(await can("consultant_workspace.read"))) {
    return { ok: false, errorCode: "denied" };
  }

  const supabase = await createClient();
  const { data, error } = await fetchConsultantWorkspacePortfolio(supabase, params);

  if (error || !data) {
    return { ok: false, errorCode: "load_failed" };
  }

  return { ok: true, data };
}

export async function hideConsultantGridRowAction(
  subjectType: "lead" | "student",
  subjectId: string,
): Promise<{ ok: boolean; errorCode?: "denied" | "failed" }> {
  if (!(await can("consultant_workspace.read"))) {
    return { ok: false, errorCode: "denied" };
  }

  const supabase = await createClient();
  const { data: orgId, error: orgError } = await supabase.rpc("current_organization_id");
  const { data: userId, error: userError } = await supabase.rpc("current_app_user_id");

  if (orgError || userError || !orgId || !userId) {
    return { ok: false, errorCode: "failed" };
  }

  const { error } = await supabase.from("consultant_grid_hidden_row").upsert(
    {
      organization_id: orgId,
      app_user_id: userId,
      subject_type: subjectType,
      subject_id: subjectId,
    },
    { onConflict: "organization_id,app_user_id,subject_type,subject_id" },
  );

  if (error) {
    return { ok: false, errorCode: "failed" };
  }

  revalidatePath("/consultant");
  return { ok: true };
}

export async function restoreConsultantGridRowAction(
  subjectType: "lead" | "student",
  subjectId: string,
): Promise<{ ok: boolean; errorCode?: "denied" | "failed" }> {
  if (!(await can("consultant_workspace.read"))) {
    return { ok: false, errorCode: "denied" };
  }

  const supabase = await createClient();
  const { data: orgId, error: orgError } = await supabase.rpc("current_organization_id");
  const { data: userId, error: userError } = await supabase.rpc("current_app_user_id");

  if (orgError || userError || !orgId || !userId) {
    return { ok: false, errorCode: "failed" };
  }

  const { error } = await supabase
    .from("consultant_grid_hidden_row")
    .delete()
    .eq("organization_id", orgId)
    .eq("app_user_id", userId)
    .eq("subject_type", subjectType)
    .eq("subject_id", subjectId);

  if (error) {
    return { ok: false, errorCode: "failed" };
  }

  revalidatePath("/consultant");
  return { ok: true };
}

export async function saveConsultantGridPreferencesAction(
  preferences: ConsultantGridPreferences,
): Promise<{ ok: boolean; errorCode?: "denied" | "failed" }> {
  if (!(await can("consultant_workspace.read"))) {
    return { ok: false, errorCode: "denied" };
  }

  const supabase = await createClient();
  const { data: orgId, error: orgError } = await supabase.rpc("current_organization_id");
  const { data: userId, error: userError } = await supabase.rpc("current_app_user_id");

  if (orgError || userError || !orgId || !userId) {
    return { ok: false, errorCode: "failed" };
  }

  const { error } = await supabase.from("consultant_workspace_preference").upsert(
    {
      organization_id: orgId,
      app_user_id: userId,
      grid_preferences: preferences,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "organization_id,app_user_id" },
  );

  if (error) {
    return { ok: false, errorCode: "failed" };
  }

  return { ok: true };
}

export async function loadConsultantGridPreferencesAction(): Promise<ConsultantGridPreferences | null> {
  if (!(await can("consultant_workspace.read"))) {
    return null;
  }

  const supabase = await createClient();
  const { data: orgId } = await supabase.rpc("current_organization_id");
  const { data: userId } = await supabase.rpc("current_app_user_id");
  if (!orgId || !userId) return null;

  const { data } = await supabase
    .from("consultant_workspace_preference")
    .select("grid_preferences")
    .eq("organization_id", orgId)
    .eq("app_user_id", userId)
    .maybeSingle();

  const raw = data?.grid_preferences;
  if (!raw || typeof raw !== "object") return null;
  return raw as ConsultantGridPreferences;
}
