"use server";

import { revalidatePath } from "next/cache";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type FinanceReviewActionResult =
  | { ok: true }
  | { ok: false; errorCode: string };

function mapReviewError(message: string): string {
  if (message.includes("permission_denied")) return "permission_denied";
  if (message.includes("declaration_not_found")) return "not_found";
  if (message.includes("declaration_not_confirmable")) return "not_confirmable";
  if (message.includes("declaration_not_reviewable")) return "not_reviewable";
  if (message.includes("depends_on_declaration_not_confirmed")) return "depends_on_unconfirmed";
  if (message.includes("identity_not_ready") || message.includes("strong_match_ack_required"))
    return "identity_not_ready";
  if (message.includes("declaration_enrollment_context_required")) return "enrollment_context_required";
  if (message.includes("lead_conversion_failed")) return "lead_conversion_failed";
  if (message.includes("payment_exceeds_outstanding")) return "exceeds_outstanding";
  if (message.includes("invalid_review_action")) return "invalid_action";
  return "unknown";
}

function revalidateConsultantRevenue() {
  revalidatePath("/finance/consultant-revenue");
  revalidatePath("/finance");
}

export async function confirmConsultantPaymentDeclarationAction(input: {
  declarationId: string;
  paidAt?: string;
  methodCode?: string;
}): Promise<FinanceReviewActionResult> {
  if (!(await can("consultant_revenue.review")) || !(await can("payment.record"))) {
    return { ok: false, errorCode: "permission_denied" };
  }
  const supabase = await createClient();
  const { error } = await supabase.rpc("confirm_consultant_payment_declaration", {
    p_declaration_id: input.declarationId,
    p_paid_at: input.paidAt ?? undefined,
    p_method_code: input.methodCode ?? undefined,
  });
  if (error) {
    const errorCode = mapReviewError(error.message);
    console.error("[consultant-revenue-review] confirm", {
      errorCode,
      code: error.code,
      message: error.message,
      details: error.details,
      hint: error.hint,
    });
    return { ok: false, errorCode };
  }
  revalidateConsultantRevenue();
  return { ok: true };
}

export async function rejectConsultantRevenueDeclarationAction(input: {
  declarationId: string;
  reviewNotes?: string;
}): Promise<FinanceReviewActionResult> {
  if (!(await can("consultant_revenue.review"))) {
    return { ok: false, errorCode: "permission_denied" };
  }
  const supabase = await createClient();
  const { error } = await supabase.rpc("review_consultant_revenue_declaration", {
    p_declaration_id: input.declarationId,
    p_action: "reject",
    p_review_notes: input.reviewNotes?.trim() || undefined,
  });
  if (error) {
    return { ok: false, errorCode: mapReviewError(error.message) };
  }
  revalidateConsultantRevenue();
  return { ok: true };
}
