import type {
  ConsultantWorkspaceLifecycleStatus,
  ConsultantWorkspacePortfolioCapabilities,
  ConsultantWorkspaceTuitionPaymentState,
} from "@/lib/consultant-workspace/portfolio-read-model";

export type ConsultantPortfolioCustomField = {
  definition_id: string;
  field_key: string;
  label: string;
  data_type: string;
  value: string;
};

export type ConsultantPortfolioDetail = {
  portfolio_entry_id: string;
  workspace_sequence: number;
  portfolio_entered_at: string;
  lead_id: string | null;
  student_id: string | null;
  subject_type: "lead" | "student";
  display_subject_id: string;
  is_hidden: boolean;
  family_name: string | null;
  given_name: string | null;
  date_of_birth: string | null;
  personal_identification_number: string | null;
  subject_updated_at: string | null;
  student_code_official: string | null;
  student_code_display: string | null;
  student_code_is_provisional: boolean;
  lifecycle_status: string;
  enrollment_id: string | null;
  enrollment_status: string | null;
  enrollment_start_date: string | null;
  enrollment_financial_terms_id: string | null;
  course_id: string | null;
  course_name: string | null;
  class_id: string | null;
  class_name: string | null;
  tuition_total_net: number;
  tuition_paid: number;
  tuition_outstanding: number;
  tuition_payment_state: string;
  declaration_id: string | null;
  declaration_status: string | null;
  declaration_workflow_kind: string | null;
  primary_guardian_id: string | null;
  primary_guardian_family_name: string | null;
  primary_guardian_given_name: string | null;
  primary_guardian_phone: string | null;
  custom_fields: ConsultantPortfolioCustomField[];
  capabilities: ConsultantWorkspacePortfolioCapabilities;
  editable: {
    can_edit_profile: boolean;
    can_edit_date_of_birth: boolean;
    can_edit_custom_fields: boolean;
    official_student_code_locked: boolean;
  };
};

function num(v: unknown): number {
  return Number(v ?? 0);
}

export function parseConsultantPortfolioDetail(raw: Record<string, unknown>): ConsultantPortfolioDetail {
  const caps = (raw.capabilities as Record<string, unknown>) ?? {};
  const editable = (raw.editable as Record<string, unknown>) ?? {};
  const customRaw = raw.custom_fields;
  const custom_fields: ConsultantPortfolioCustomField[] = Array.isArray(customRaw)
    ? customRaw.map((item) => {
        const row = item as Record<string, unknown>;
        return {
          definition_id: String(row.definition_id ?? ""),
          field_key: String(row.field_key ?? ""),
          label: String(row.label ?? ""),
          data_type: String(row.data_type ?? "text"),
          value: String(row.value ?? ""),
        };
      })
    : [];

  return {
    portfolio_entry_id: String(raw.portfolio_entry_id),
    workspace_sequence: num(raw.workspace_sequence),
    portfolio_entered_at: String(raw.portfolio_entered_at ?? ""),
    lead_id: raw.lead_id ? String(raw.lead_id) : null,
    student_id: raw.student_id ? String(raw.student_id) : null,
    subject_type: raw.subject_type === "student" ? "student" : "lead",
    display_subject_id: String(raw.display_subject_id),
    is_hidden: Boolean(raw.is_hidden),
    family_name: raw.family_name != null ? String(raw.family_name) : null,
    given_name: raw.given_name != null ? String(raw.given_name) : null,
    date_of_birth: raw.date_of_birth != null ? String(raw.date_of_birth).slice(0, 10) : null,
    personal_identification_number:
      raw.personal_identification_number != null
        ? String(raw.personal_identification_number)
        : null,
    subject_updated_at: raw.subject_updated_at != null ? String(raw.subject_updated_at) : null,
    student_code_official: raw.student_code_official ? String(raw.student_code_official) : null,
    student_code_display: raw.student_code_display ? String(raw.student_code_display) : null,
    student_code_is_provisional: Boolean(raw.student_code_is_provisional),
    lifecycle_status: String(raw.lifecycle_status ?? "tiem_nang"),
    enrollment_id: raw.enrollment_id ? String(raw.enrollment_id) : null,
    enrollment_status: raw.enrollment_status ? String(raw.enrollment_status) : null,
    enrollment_start_date: raw.enrollment_start_date
      ? String(raw.enrollment_start_date).slice(0, 10)
      : null,
    enrollment_financial_terms_id: raw.enrollment_financial_terms_id
      ? String(raw.enrollment_financial_terms_id)
      : null,
    course_id: raw.course_id ? String(raw.course_id) : null,
    course_name: raw.course_name ? String(raw.course_name) : null,
    class_id: raw.class_id ? String(raw.class_id) : null,
    class_name: raw.class_name ? String(raw.class_name) : null,
    tuition_total_net: num(raw.tuition_total_net),
    tuition_paid: num(raw.tuition_paid),
    tuition_outstanding: num(raw.tuition_outstanding),
    tuition_payment_state: String(raw.tuition_payment_state ?? "dong_phi"),
    declaration_id: raw.declaration_id ? String(raw.declaration_id) : null,
    declaration_status: raw.declaration_status ? String(raw.declaration_status) : null,
    declaration_workflow_kind: raw.declaration_workflow_kind
      ? String(raw.declaration_workflow_kind)
      : null,
    primary_guardian_id: raw.primary_guardian_id ? String(raw.primary_guardian_id) : null,
    primary_guardian_family_name: raw.primary_guardian_family_name
      ? String(raw.primary_guardian_family_name)
      : null,
    primary_guardian_given_name: raw.primary_guardian_given_name
      ? String(raw.primary_guardian_given_name)
      : null,
    primary_guardian_phone: raw.primary_guardian_phone ? String(raw.primary_guardian_phone) : null,
    custom_fields,
    capabilities: {
      can_edit_contact: Boolean(caps.can_edit_contact),
      can_open_payment_declaration: Boolean(caps.can_open_payment_declaration),
      can_create_payment_declaration: Boolean(caps.can_create_payment_declaration),
      can_edit_payment_declaration: Boolean(caps.can_edit_payment_declaration),
      can_submit_declaration: Boolean(caps.can_submit_declaration),
      can_add_payment: Boolean(caps.can_add_payment),
      can_open_student_details: Boolean(caps.can_open_student_details),
    },
    editable: {
      can_edit_profile: Boolean(editable.can_edit_profile),
      can_edit_date_of_birth: Boolean(editable.can_edit_date_of_birth),
      can_edit_custom_fields: Boolean(editable.can_edit_custom_fields),
      official_student_code_locked: Boolean(editable.official_student_code_locked),
    },
  };
}

/** Map detail to portfolio row shape for T07 drawer reuse. */
export function portfolioDetailToDeclarationRow(
  detail: ConsultantPortfolioDetail,
): import("@/lib/consultant-workspace/portfolio-read-model").ConsultantWorkspacePortfolioRow {
  return {
    portfolio_entry_id: detail.portfolio_entry_id,
    workspace_sequence: detail.workspace_sequence,
    lead_id: detail.lead_id,
    student_id: detail.student_id,
    display_subject_id: detail.display_subject_id,
    subject_type: detail.subject_type,
    family_name: detail.family_name,
    given_name: detail.given_name,
    date_of_birth: detail.date_of_birth,
    personal_identification_number: detail.personal_identification_number,
    student_code_official: detail.student_code_official,
    student_code_display: detail.student_code_display,
    student_code_is_provisional: detail.student_code_is_provisional,
    lifecycle_status: detail.lifecycle_status as ConsultantWorkspaceLifecycleStatus,
    lifecycle_status_label: detail.lifecycle_status,
    primary_guardian_id: detail.primary_guardian_id,
    primary_guardian_name: [detail.primary_guardian_family_name, detail.primary_guardian_given_name]
      .filter(Boolean)
      .join(" ")
      .trim() || null,
    primary_guardian_phone: detail.primary_guardian_phone,
    course_id: detail.course_id,
    course_name: detail.course_name,
    class_id: detail.class_id,
    class_name: detail.class_name,
    enrollment_id: detail.enrollment_id,
    enrollment_financial_terms_id: detail.enrollment_financial_terms_id,
    tuition_total_net: detail.tuition_total_net,
    tuition_paid: detail.tuition_paid,
    tuition_outstanding: detail.tuition_outstanding,
    tuition_payment_state: detail.tuition_payment_state as ConsultantWorkspaceTuitionPaymentState,
    tuition_payment_state_label: detail.tuition_payment_state,
    declaration_id: detail.declaration_id,
    declaration_status: detail.declaration_status,
    declaration_workflow_kind: detail.declaration_workflow_kind,
    portfolio_entered_at: detail.portfolio_entered_at,
    student_details_subject_id: detail.student_id,
    is_hidden: detail.is_hidden,
    custom_fields: detail.custom_fields.map((f) => ({
      definition_id: f.definition_id,
      field_key: f.field_key,
      label: f.label,
      data_type: f.data_type,
      value: f.value,
    })),
    capabilities: detail.capabilities,
  };
}
