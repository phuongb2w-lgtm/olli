import type { SupabaseClient } from "@supabase/supabase-js";

export type PaymentListItem = {
  id: string;
  paidAt: string;
  payerName: string | null;
  guardianId: string;
  studentId: string | null;
  studentName: string | null;
  methodCode: string;
  amount: number;
  allocatedAmount: number;
  unallocatedAmount: number;
  status: string;
  allocationStatus: string;
  referenceNumber: string | null;
};

export async function queryPaymentsList(
  supabase: SupabaseClient,
): Promise<{ items: PaymentListItem[]; error: string | null }> {
  const { data, error } = await supabase
    .from("payment")
    .select(
      "id, paid_at, payer_name_snapshot, guardian_id, student_id, method_code, amount, status, reference_number",
    )
    .order("paid_at", { ascending: false })
    .limit(100);

  if (error) return { items: [], error: "load_error" };

  const paymentIds = (data ?? []).map((p) => p.id);
  const allocatedByPayment = new Map<string, number>();
  const studentNames = new Map<string, string>();

  if (paymentIds.length > 0) {
    const { data: allocRows } = await supabase
      .from("payment_allocation")
      .select("payment_id, amount")
      .eq("status", "posted")
      .in("payment_id", paymentIds);

    for (const row of allocRows ?? []) {
      allocatedByPayment.set(
        row.payment_id,
        (allocatedByPayment.get(row.payment_id) ?? 0) + Number(row.amount),
      );
    }
  }

  const studentIds = [...new Set((data ?? []).map((p) => p.student_id).filter(Boolean))] as string[];
  if (studentIds.length > 0) {
    const { data: students } = await supabase
      .from("student")
      .select("id, given_name, family_name")
      .in("id", studentIds);
    for (const s of students ?? []) {
      studentNames.set(s.id, `${s.family_name ?? ""} ${s.given_name ?? ""}`.trim());
    }
  }

  const items: PaymentListItem[] = (data ?? []).map((row) => {
    const allocatedAmount = allocatedByPayment.get(row.id) ?? 0;
    const amount = Number(row.amount);
    const unallocatedAmount = Math.max(amount - allocatedAmount, 0);
    let allocationStatus = "unallocated";
    if (allocatedAmount > 0 && unallocatedAmount > 0) allocationStatus = "partially_allocated";
    if (unallocatedAmount === 0 && allocatedAmount > 0) allocationStatus = "fully_allocated";

    return {
      id: row.id,
      paidAt: row.paid_at,
      payerName: row.payer_name_snapshot,
      guardianId: row.guardian_id,
      studentId: row.student_id,
      studentName: row.student_id ? studentNames.get(row.student_id) ?? null : null,
      methodCode: row.method_code,
      amount,
      allocatedAmount,
      unallocatedAmount,
      status: row.status,
      allocationStatus,
      referenceNumber: row.reference_number,
    };
  });

  return { items, error: null };
}
