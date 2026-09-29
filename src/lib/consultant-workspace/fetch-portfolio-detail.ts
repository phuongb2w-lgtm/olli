import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import {
  parseConsultantPortfolioDetail,
  type ConsultantPortfolioDetail,
} from "@/lib/consultant-workspace/portfolio-detail-read-model";

export async function fetchConsultantPortfolioEntryDetail(
  supabase: SupabaseClient<Database>,
  portfolioEntryId: string,
): Promise<{ data: ConsultantPortfolioDetail | null; error: string | null }> {
  const { data, error } = await supabase.rpc("get_consultant_portfolio_entry_detail", {
    p_portfolio_entry_id: portfolioEntryId,
  });

  if (error) {
    return { data: null, error: error.message };
  }
  if (!data || typeof data !== "object") {
    return { data: null, error: "not_found" };
  }

  return {
    data: parseConsultantPortfolioDetail(data as Record<string, unknown>),
    error: null,
  };
}

function mapSaveError(message: string): string {
  if (message.includes("permission_denied")) return "permission_denied";
  if (message.includes("portfolio_entry_not_found")) return "not_found";
  if (message.includes("profile_conflict")) return "conflict";
  if (message.includes("invalid_profile_name")) return "invalid_name";
  if (message.includes("invalid_custom_field")) return "invalid_custom_field";
  return "unknown";
}

export async function saveConsultantPortfolioProfile(
  supabase: SupabaseClient<Database>,
  input: {
    portfolioEntryId: string;
    familyName: string;
    givenName: string;
    dateOfBirth?: string | null;
    guardianFamilyName?: string | null;
    guardianGivenName?: string | null;
    guardianPhone?: string | null;
    expectedSubjectUpdatedAt?: string | null;
  },
): Promise<{ ok: true; detail: ConsultantPortfolioDetail } | { ok: false; errorCode: string }> {
  const { data, error } = await supabase.rpc("save_consultant_portfolio_profile", {
    p_portfolio_entry_id: input.portfolioEntryId,
    p_family_name: input.familyName.trim(),
    p_given_name: input.givenName.trim(),
    p_date_of_birth: input.dateOfBirth || undefined,
    p_guardian_family_name: input.guardianFamilyName?.trim() || undefined,
    p_guardian_given_name: input.guardianGivenName?.trim() || undefined,
    p_guardian_phone: input.guardianPhone?.trim() || undefined,
    p_expected_subject_updated_at: input.expectedSubjectUpdatedAt || undefined,
  });

  if (error || !data) {
    return { ok: false, errorCode: mapSaveError(error?.message ?? "") };
  }

  return {
    ok: true,
    detail: parseConsultantPortfolioDetail(data as Record<string, unknown>),
  };
}

export async function saveConsultantPortfolioCustomFields(
  supabase: SupabaseClient<Database>,
  input: {
    portfolioEntryId: string;
    values: { field_key: string; value: string }[];
  },
): Promise<{ ok: true; detail: ConsultantPortfolioDetail } | { ok: false; errorCode: string }> {
  const { data, error } = await supabase.rpc("save_consultant_portfolio_custom_fields", {
    p_portfolio_entry_id: input.portfolioEntryId,
    p_values: input.values,
  });

  if (error || !data) {
    return { ok: false, errorCode: mapSaveError(error?.message ?? "") };
  }

  return {
    ok: true,
    detail: parseConsultantPortfolioDetail(data as Record<string, unknown>),
  };
}
