import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

type DbClient = SupabaseClient<Database>;

export type CrmReportFinancials = {
  charged_amount: number | null;
  collected_amount: number | null;
  recognized_revenue: number | null;
};

export type CrmReportSourceRow = {
  lead_source_id: string | null;
  code: string;
  display_name: string;
  status: string;
  leads_created: number;
  qualified_leads: number;
  trial_scheduled_leads: number;
  trial_completed_leads: number;
  converted_leads: number;
  enrolled_leads: number;
  conversion_rate: number;
  financials: CrmReportFinancials | null;
};

export type CrmReportCampaignRow = {
  lead_campaign_id: string | null;
  code: string;
  name: string;
  status: string;
  lead_source_id: string | null;
  leads_created: number;
  conversions_in_period: number;
  enrollments_from_conversions: number;
  campaign_spend: number | null;
  financials: CrmReportFinancials | null;
};

export type CrmReportFunnel = {
  leads_created: number;
  contacted_leads: number;
  qualified_leads: number;
  trial_scheduled_leads: number;
  trial_completed_leads: number;
  converted_leads: number;
  cohort_converted_leads: number;
  enrolled_leads: number;
  lost_leads: number;
  converted_students: number;
  enrollments_from_conversions: number;
  conversions_without_enrollment: number;
  trial_events_scheduled: number;
  trial_events_completed: number;
  conversion_rate: number;
  lost_rate: number;
  trial_scheduling_rate: number;
  trial_completion_rate: number;
  trial_to_conversion_rate: number;
  converted_to_enrolled_rate: number;
};

export type CrmAttributionReport = {
  period: { start_date: string; end_date: string };
  semantics: Record<string, string>;
  permissions: {
    can_view_charged: boolean;
    can_view_collected: boolean;
    can_view_recognized_revenue: boolean;
  };
  funnel: CrmReportFunnel;
  sources: CrmReportSourceRow[];
  campaigns: CrmReportCampaignRow[];
  lost_reasons: Array<{
    lost_reason_id: string;
    code: string;
    display_name: string;
    lost_count: number;
    share_of_lost: number;
  }>;
  referrals: {
    guardian_referral_conversions: number;
    student_referral_conversions: number;
  };
};

export async function queryCrmAttributionReport(
  supabase: DbClient,
  startDate: string,
  endDate: string,
): Promise<{ report: CrmAttributionReport | null; error: boolean }> {
  const { data, error } = await supabase.rpc("get_crm_attribution_report", {
    p_start_date: startDate,
    p_end_date: endDate,
  });

  if (error || !data || typeof data !== "object") {
    return { report: null, error: true };
  }

  return { report: data as CrmAttributionReport, error: false };
}
