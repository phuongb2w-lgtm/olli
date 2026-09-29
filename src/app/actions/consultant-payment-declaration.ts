"use server";

import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type DeclarationActionResult =
  | { ok: true; declarationId: string }
  | { ok: false; errorCode: string };

function mapDeclarationError(message: string): string {
  if (message.includes("permission_denied")) return "permission_denied";
  if (message.includes("payment_exceeds_outstanding")) return "exceeds_outstanding";
  if (message.includes("no_outstanding_obligation")) return "already_settled";
  if (message.includes("declaration_already_pending")) return "already_pending";
  if (message.includes("declaration_context_incomplete")) return "context_incomplete";
  if (message.includes("declaration_not_editable")) return "not_editable";
  if (message.includes("declaration_not_submittable")) return "not_submittable";
  if (message.includes("invalid_declaration") || message.includes("invalid_payment_amount"))
    return "invalid_amount";
  if (message.includes("declaration_not_found")) return "not_found";
  return "unknown";
}

export async function refreshDeclarationFinanceAction(
  enrollmentFinancialTermsId: string,
): Promise<{ ok: true; finance: Record<string, unknown> } | { ok: false; errorCode: string }> {
  if (!(await can("consultant_revenue.declare"))) {
    return { ok: false, errorCode: "permission_denied" };
  }
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("refresh_cw2_payment_declaration_finance", {
    p_enrollment_financial_terms_id: enrollmentFinancialTermsId,
  });
  if (error || !data) {
    return { ok: false, errorCode: mapDeclarationError(error?.message ?? "") };
  }
  return { ok: true, finance: data as Record<string, unknown> };
}

export async function saveConsultantPaymentDeclarationDraftAction(input: {
  declarationId?: string | null;
  declaredAmount: number;
  description?: string;
  promotionContext?: string;
  leadId?: string | null;
  studentId?: string | null;
  courseId?: string | null;
  classId?: string | null;
  enrollmentId: string;
  enrollmentFinancialTermsId: string;
  guardianId: string;
  totalObligationAmount: number;
  idempotencyKey?: string;
}): Promise<DeclarationActionResult> {
  if (!(await can("consultant_revenue.declare"))) {
    return { ok: false, errorCode: "permission_denied" };
  }
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("save_consultant_payment_declaration_draft", {
    p_declaration_id: input.declarationId ?? undefined,
    p_declaration_date: new Date().toISOString().slice(0, 10),
    p_declared_amount: input.declaredAmount,
    p_description: input.description ?? undefined,
    p_promotion_context: input.promotionContext ?? undefined,
    p_lead_id: input.leadId ?? undefined,
    p_student_id: input.studentId ?? undefined,
    p_course_id: input.courseId ?? undefined,
    p_class_id: input.classId ?? undefined,
    p_enrollment_id: input.enrollmentId,
    p_enrollment_financial_terms_id: input.enrollmentFinancialTermsId,
    p_guardian_id: input.guardianId,
    p_total_obligation_amount: input.totalObligationAmount,
    p_idempotency_key: input.idempotencyKey ?? undefined,
  });
  if (error || !data) {
    return { ok: false, errorCode: mapDeclarationError(error?.message ?? "") };
  }
  return { ok: true, declarationId: data as string };
}

export async function submitConsultantPaymentDeclarationAction(
  declarationId: string,
): Promise<{ ok: true } | { ok: false; errorCode: string }> {
  if (!(await can("consultant_revenue.declare"))) {
    return { ok: false, errorCode: "permission_denied" };
  }
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_consultant_payment_declaration", {
    p_declaration_id: declarationId,
  });
  if (error) {
    return { ok: false, errorCode: mapDeclarationError(error.message) };
  }
  return { ok: true };
}

export async function loadDeclarationDrawerAction(declarationId: string) {
  if (!(await can("consultant_revenue.declare"))) {
    return { ok: false as const, errorCode: "permission_denied" };
  }
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_cw2_payment_declaration_drawer", {
    p_declaration_id: declarationId,
  });
  if (error || !data) {
    return { ok: false as const, errorCode: mapDeclarationError(error?.message ?? "") };
  }
  return {
    ok: true as const,
    data: data as {
      declaration: Record<string, unknown>;
      finance: Record<string, unknown> | null;
    },
  };
}
