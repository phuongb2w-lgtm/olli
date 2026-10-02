/** CW2-T05: Consultant workspace portfolio read model (RPC contract types). */

export type ConsultantWorkspaceLifecycleStatus =
  | "tiem_nang"
  | "ghi_danh"
  | "dang_hoc"
  | "tot_nghiep";

export type ConsultantWorkspaceTuitionPaymentState =
  | "chua_nop_phi"
  | "chua_coc"
  | "coc_cho_xac_nhan"
  | "da_coc"
  | "nop_phi"
  | "full_phi"
  | "cho_xac_nhan"
  | "con_hoc_phi"
  | "sap_het_hoc_phi"
  | "het_hoc_phi"
  | "con_thieu"
  | "da_du_ky"
  | "co_so_du"
  | "dong_phi"
  | "coc_phi"
  | "mot_phan";

export type ConsultantWorkspacePortfolioCapabilities = {
  can_edit_contact: boolean;
  can_open_payment_declaration: boolean;
  can_create_payment_declaration: boolean;
  can_edit_payment_declaration: boolean;
  can_submit_declaration: boolean;
  can_add_payment: boolean;
  can_open_student_details: boolean;
};

export type ConsultantWorkspaceCustomFieldValue = {
  definition_id: string;
  field_key: string;
  label: string;
  data_type: string;
  value: string;
};

export type ConsultantWorkspacePortfolioRow = {
  portfolio_entry_id: string;
  workspace_sequence: number;
  lead_id: string | null;
  student_id: string | null;
  display_subject_id: string;
  subject_type: "lead" | "student";
  family_name: string | null;
  given_name: string | null;
  student_code_official: string | null;
  student_code_display: string | null;
  student_code_is_provisional: boolean;
  lifecycle_status: ConsultantWorkspaceLifecycleStatus;
  lifecycle_status_label: string;
  primary_guardian_id: string | null;
  primary_guardian_name: string | null;
  primary_guardian_phone: string | null;
  course_id: string | null;
  course_name: string | null;
  class_id: string | null;
  class_name: string | null;
  enrollment_id: string | null;
  enrollment_financial_terms_id: string | null;
  tuition_total_net: number;
  tuition_paid: number;
  tuition_outstanding: number;
  tuition_pending_declaration?: number;
  tuition_payment_state: ConsultantWorkspaceTuitionPaymentState;
  tuition_payment_state_label: string;
  tuition_billing_mode?: "course_lump_sum" | "periodic" | null;
  tuition_periodic_lessons_remaining?: number | null;
  tuition_carry_forward_credit?: number;
  declaration_id: string | null;
  declaration_status: string | null;
  declaration_workflow_kind: string | null;
  portfolio_entered_at: string;
  student_details_subject_id: string | null;
  is_hidden: boolean;
  custom_fields: ConsultantWorkspaceCustomFieldValue[];
  capabilities: ConsultantWorkspacePortfolioCapabilities;
};

export type ConsultantWorkspacePortfolioCursor = {
  workspace_sequence: number;
  portfolio_entry_id: string;
};

export type ConsultantWorkspacePortfolioFilters = {
  consultant_user_id?: string;
  lifecycle_status?: ConsultantWorkspaceLifecycleStatus;
  tuition_payment_state?: ConsultantWorkspaceTuitionPaymentState;
  declaration_status?: string;
  course_id?: string;
  name_search?: string;
  family_name?: string;
  given_name?: string;
  student_code?: string;
  guardian_phone?: string;
};

export type ConsultantWorkspacePortfolioResult = {
  rows: ConsultantWorkspacePortfolioRow[];
  next_cursor: ConsultantWorkspacePortfolioCursor | null;
  has_more: boolean;
};

export function parseConsultantWorkspacePortfolioResult(
  raw: unknown,
): ConsultantWorkspacePortfolioResult {
  if (!raw || typeof raw !== "object") {
    return { rows: [], next_cursor: null, has_more: false };
  }
  const o = raw as Record<string, unknown>;
  const rows = Array.isArray(o.rows) ? (o.rows as ConsultantWorkspacePortfolioRow[]) : [];
  const next_cursor =
    o.next_cursor && typeof o.next_cursor === "object"
      ? (o.next_cursor as ConsultantWorkspacePortfolioCursor)
      : null;
  return {
    rows,
    next_cursor,
    has_more: Boolean(o.has_more),
  };
}
