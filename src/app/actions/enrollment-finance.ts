"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import {
  validateCustomScheduleItems,
  validateDraftEnrollmentFinancialTermsInput,
  validateInstallmentCount,
  type CustomScheduleItemInput,
  type DraftEnrollmentFinancialTermsInput,
} from "@/lib/enrollment-finance/validate-enrollment-finance-input";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type EnrollmentFinanceActionState = {
  error?:
    | "permission_denied"
    | "validation_error"
    | "save_error"
    | "not_found";
  fieldErrors?: Record<string, string>;
  termsId?: string;
  chargesCreated?: number;
  summary?: Record<string, unknown>;
};

export async function createDraftEnrollmentFinancialTerms(
  input: DraftEnrollmentFinancialTermsInput,
): Promise<EnrollmentFinanceActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("charge.create"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateDraftEnrollmentFinancialTermsInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_enrollment_financial_terms", {
    p_enrollment_id: parsed.data.enrollmentId,
    p_agreed_tuition_amount: parsed.data.agreedTuitionAmount,
    p_discount_amount: parsed.data.discountAmount,
    p_agreement_date: parsed.data.agreementDate,
    p_tuition_plan_id: parsed.data.tuitionPlanId ?? undefined,
    p_recognition_basis_code: parsed.data.recognitionBasisCode ?? undefined,
    p_notes: parsed.data.notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { termsId: data as string };
}

export async function updateDraftEnrollmentFinancialTerms(
  termsId: string,
  input: Omit<DraftEnrollmentFinancialTermsInput, "enrollmentId">,
): Promise<EnrollmentFinanceActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("charge.create"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateDraftEnrollmentFinancialTermsInput({
    enrollmentId: "placeholder",
    ...input,
  });
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("update_draft_enrollment_financial_terms", {
    p_terms_id: termsId,
    p_agreed_tuition_amount: parsed.data.agreedTuitionAmount,
    p_discount_amount: parsed.data.discountAmount,
    p_agreement_date: parsed.data.agreementDate,
    p_tuition_plan_id: parsed.data.tuitionPlanId ?? undefined,
    p_recognition_basis_code: parsed.data.recognitionBasisCode ?? undefined,
    p_notes: parsed.data.notes ?? undefined,
  });

  if (error) return { error: "save_error" };
  return { termsId };
}

export async function setFullUpfrontPaymentSchedule(
  termsId: string,
  dueDate: string,
): Promise<EnrollmentFinanceActionState> {
  return runScheduleRpc(termsId, "set_enrollment_payment_schedule_full_upfront", {
    p_terms_id: termsId,
    p_due_date: dueDate,
  });
}

export async function setDepositRemainderPaymentSchedule(
  termsId: string,
  depositAmount: number,
  depositDueDate: string,
  remainderDueDate: string,
): Promise<EnrollmentFinanceActionState> {
  if (depositAmount <= 0) {
    return { error: "validation_error", fieldErrors: { depositAmount: "invalid" } };
  }
  return runScheduleRpc(termsId, "set_enrollment_payment_schedule_deposit_remainder", {
    p_terms_id: termsId,
    p_deposit_amount: depositAmount,
    p_deposit_due_date: depositDueDate,
    p_remainder_due_date: remainderDueDate,
  });
}

export async function setEqualInstallmentPaymentSchedule(
  termsId: string,
  installmentCount: number,
  firstDueDate: string,
): Promise<EnrollmentFinanceActionState> {
  const count = validateInstallmentCount(installmentCount);
  if (!count) {
    return { error: "validation_error", fieldErrors: { installmentCount: "invalid" } };
  }
  return runScheduleRpc(termsId, "set_enrollment_payment_schedule_installments", {
    p_terms_id: termsId,
    p_installment_count: count,
    p_first_due_date: firstDueDate,
  });
}

export async function setCustomPaymentSchedule(
  termsId: string,
  items: CustomScheduleItemInput[],
  expectedNetTuition: number,
): Promise<EnrollmentFinanceActionState> {
  const parsed = validateCustomScheduleItems(items, expectedNetTuition);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const schedule = parsed.items.map((item) => ({
    due_date: item.dueDate,
    amount: item.amount,
    label: item.label ?? null,
  }));

  return runScheduleRpc(termsId, "set_enrollment_payment_schedule_custom", {
    p_terms_id: termsId,
    p_schedule: schedule,
  });
}

export async function activateEnrollmentFinancialTerms(
  termsId: string,
): Promise<EnrollmentFinanceActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("charge.create"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("activate_enrollment_financial_terms", {
    p_terms_id: termsId,
  });

  if (error) return { error: "save_error" };
  return { termsId };
}

export async function generateEnrollmentCharges(
  termsId: string,
): Promise<EnrollmentFinanceActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("charge.create"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("generate_enrollment_charges", {
    p_terms_id: termsId,
  });

  if (error) return { error: "save_error" };
  return { termsId, chargesCreated: data as number };
}

export async function getEnrollmentFinancialSummary(
  enrollmentId: string,
): Promise<EnrollmentFinanceActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("charge.read"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_enrollment_financial_summary", {
    p_enrollment_id: enrollmentId,
  });

  if (error) return { error: "save_error" };
  return { summary: data as Record<string, unknown> };
}

async function runScheduleRpc(
  termsId: string,
  rpcName:
    | "set_enrollment_payment_schedule_full_upfront"
    | "set_enrollment_payment_schedule_deposit_remainder"
    | "set_enrollment_payment_schedule_installments"
    | "set_enrollment_payment_schedule_custom",
  args: object,
): Promise<EnrollmentFinanceActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("charge.create"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc(rpcName, args as never);

  if (error) return { error: "save_error" };
  return { termsId };
}
