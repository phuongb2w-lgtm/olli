"use server";

import { revalidatePath } from "next/cache";
import { can } from "@/lib/permissions/can";
import type { ConsultantPortfolioDetail } from "@/lib/consultant-workspace/portfolio-detail-read-model";
import {
  saveConsultantPortfolioCustomFields,
  saveConsultantPortfolioProfile,
} from "@/lib/consultant-workspace/fetch-portfolio-detail";
import { createClient } from "@/lib/supabase/server";

export type PortfolioDetailSaveResult =
  | { ok: true; detail: ConsultantPortfolioDetail }
  | { ok: false; errorCode: string };

export async function saveConsultantPortfolioProfileAction(input: {
  portfolioEntryId: string;
  familyName: string;
  givenName: string;
  dateOfBirth?: string | null;
  guardianFamilyName?: string | null;
  guardianGivenName?: string | null;
  guardianPhone?: string | null;
  expectedSubjectUpdatedAt?: string | null;
}): Promise<PortfolioDetailSaveResult> {
  if (!(await can("consultant_workspace.update"))) {
    return { ok: false, errorCode: "permission_denied" };
  }

  const supabase = await createClient();
  const result = await saveConsultantPortfolioProfile(supabase, input);
  if (!result.ok) return result;

  revalidatePath("/consultant");
  revalidatePath(`/consultant/portfolio/${input.portfolioEntryId}`);

  return result;
}

export async function saveConsultantPortfolioCustomFieldsAction(input: {
  portfolioEntryId: string;
  values: { field_key: string; value: string }[];
}): Promise<PortfolioDetailSaveResult> {
  if (!(await can("consultant_custom_field.manage"))) {
    return { ok: false, errorCode: "permission_denied" };
  }

  const supabase = await createClient();
  const result = await saveConsultantPortfolioCustomFields(supabase, input);
  if (!result.ok) return result;

  revalidatePath("/consultant");
  revalidatePath(`/consultant/portfolio/${input.portfolioEntryId}`);

  return result;
}
