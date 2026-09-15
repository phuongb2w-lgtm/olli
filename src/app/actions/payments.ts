"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  validateAllocatePaymentInput,
  validateRecordPaymentInput,
  type AllocatePaymentInput,
  type RecordPaymentInput,
} from "@/lib/payments/validate-payment-input";
import { createClient } from "@/lib/supabase/server";

export type PaymentActionState = {
  error?:
    | "permission_denied"
    | "validation_error"
    | "save_error"
    | "not_found";
  fieldErrors?: Record<string, string>;
  payment?: Record<string, unknown>;
  suggestions?: Record<string, unknown>;
  charges?: Record<string, unknown>;
};

export async function recordPayment(
  input: RecordPaymentInput,
): Promise<PaymentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("payment.record"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateRecordPaymentInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const rpcAllocations = parsed.data.allocations?.map((item) => ({
    charge_id: item.chargeId,
    amount: item.amount,
  }));

  const { data, error } = await supabase.rpc("record_payment", {
    p_guardian_id: parsed.data.guardianId,
    p_amount: parsed.data.amount,
    p_paid_at: parsed.data.paidAt ?? undefined,
    p_method_code: parsed.data.methodCode,
    p_reference_number: parsed.data.referenceNumber ?? undefined,
    p_notes: parsed.data.notes ?? undefined,
    p_student_id: parsed.data.studentId ?? undefined,
    p_payer_name_snapshot: parsed.data.payerNameSnapshot ?? undefined,
    p_idempotency_key: parsed.data.idempotencyKey ?? undefined,
    p_allocations: rpcAllocations ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { payment: data as Record<string, unknown> };
}

export async function allocatePayment(
  input: AllocatePaymentInput,
): Promise<PaymentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("payment.record"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateAllocatePaymentInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("allocate_payment", {
    p_payment_id: parsed.data.paymentId,
    p_allocations: parsed.data.allocations.map((item) => ({
      charge_id: item.chargeId,
      amount: item.amount,
    })),
    p_operation_key: parsed.data.operationKey ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { payment: data as Record<string, unknown> };
}

export async function suggestPaymentAllocation(
  paymentId: string,
  options?: { enrollmentId?: string; studentId?: string },
): Promise<PaymentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("payment.read"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("suggest_payment_allocation", {
    p_payment_id: paymentId,
    p_enrollment_id: options?.enrollmentId ?? undefined,
    p_student_id: options?.studentId ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { suggestions: data as Record<string, unknown> };
}

export async function getPaymentDetails(paymentId: string): Promise<PaymentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("payment.read"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_payment_details", {
    p_payment_id: paymentId,
  });

  if (error || !data) return { error: "not_found" };
  return { payment: data as Record<string, unknown> };
}

export async function getEnrollmentOutstandingCharges(
  enrollmentId: string,
): Promise<PaymentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("charge.read"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_enrollment_outstanding_charges", {
    p_enrollment_id: enrollmentId,
  });

  if (error || !data) return { error: "save_error" };
  return { charges: data as Record<string, unknown> };
}

export async function reversePayment(
  paymentId: string,
  notes?: string,
): Promise<PaymentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("payment.reverse"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reverse_payment", {
    p_payment_id: paymentId,
    p_notes: notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { payment: data as Record<string, unknown> };
}

export async function reversePaymentAllocation(
  allocationId: string,
  notes?: string,
): Promise<PaymentActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("payment.reverse"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reverse_payment_allocation", {
    p_allocation_id: allocationId,
    p_notes: notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { payment: data as Record<string, unknown> };
}
