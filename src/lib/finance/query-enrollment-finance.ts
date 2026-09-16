import type { SupabaseClient } from "@supabase/supabase-js";

export type EnrollmentTermsRow = {
  id: string;
  status: string;
  agreedTuitionAmount: number;
  discountAmount: number;
  netTuitionAmount: number;
  agreementDate: string;
  recognitionBasisCode: string | null;
  notes: string | null;
};

export type ScheduleItemRow = {
  id: string;
  dueDate: string;
  amount: number;
  label: string | null;
  status: string;
};

export type EnrollmentChargeRow = {
  id: string;
  amount: number;
  dueDate: string;
  status: string;
  outstandingBalance: number;
};

export async function queryEnrollmentFinanceContext(
  supabase: SupabaseClient,
  enrollmentId: string,
): Promise<{
  terms: EnrollmentTermsRow | null;
  draftTerms: EnrollmentTermsRow | null;
  schedule: ScheduleItemRow[];
  charges: EnrollmentChargeRow[];
  summary: Record<string, unknown> | null;
  error: string | null;
}> {
  const { data: termsRows } = await supabase
    .from("enrollment_financial_terms")
    .select(
      "id, status, agreed_tuition_amount, discount_amount, net_tuition_amount, agreement_date, recognition_basis_code, notes",
    )
    .eq("enrollment_id", enrollmentId)
    .in("status", ["active", "draft"])
    .order("created_at", { ascending: false });

  const activeTerms = (termsRows ?? []).find((t) => t.status === "active") ?? null;
  const draftTerms = (termsRows ?? []).find((t) => t.status === "draft") ?? null;
  const termsId = activeTerms?.id ?? draftTerms?.id ?? null;

  let schedule: ScheduleItemRow[] = [];
  if (termsId) {
    const { data: schedRows } = await supabase
      .from("enrollment_payment_schedule_item")
      .select("id, due_date, amount, label, status")
      .eq("enrollment_financial_terms_id", termsId)
      .order("due_date", { ascending: true });
    schedule = (schedRows ?? []).map((r) => ({
      id: r.id,
      dueDate: r.due_date,
      amount: Number(r.amount),
      label: r.label,
      status: r.status,
    }));
  }

  const { data: chargeRows } = await supabase
    .from("charge")
    .select("id, amount, due_date, status")
    .eq("enrollment_id", enrollmentId)
    .neq("status", "void")
    .order("due_date", { ascending: true });

  const charges: EnrollmentChargeRow[] = [];
  for (const c of chargeRows ?? []) {
    const { data: bal } = await supabase
      .from("charge_balance")
      .select("outstanding_balance")
      .eq("charge_id", c.id)
      .maybeSingle();
    charges.push({
      id: c.id,
      amount: Number(c.amount),
      dueDate: c.due_date,
      status: c.status,
      outstandingBalance: Number(bal?.outstanding_balance ?? c.amount),
    });
  }

  const { data: summary } = await supabase.rpc("get_enrollment_financial_summary", {
    p_enrollment_id: enrollmentId,
  });

  type TermsDbRow = NonNullable<typeof termsRows>[number];
  const mapTerms = (t: TermsDbRow | null): EnrollmentTermsRow | null =>
    t
      ? {
          id: t.id,
          status: t.status,
          agreedTuitionAmount: Number(t.agreed_tuition_amount),
          discountAmount: Number(t.discount_amount),
          netTuitionAmount: Number(t.net_tuition_amount),
          agreementDate: t.agreement_date,
          recognitionBasisCode: t.recognition_basis_code,
          notes: t.notes,
        }
      : null;

  return {
    terms: mapTerms(activeTerms),
    draftTerms: mapTerms(draftTerms),
    schedule,
    charges,
    summary: (summary as Record<string, unknown>) ?? null,
    error: null,
  };
}
