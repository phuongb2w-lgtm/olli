"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type ExpenseActionState = {
  error?: "permission_denied" | "validation_error" | "save_error";
  fieldErrors?: Record<string, string>;
  expenseId?: string;
};

export async function createExpense(input: {
  expenseCategoryId: string;
  amount: number;
  incurredDate: string;
  classId?: string | null;
  notes?: string | null;
}): Promise<ExpenseActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("expense.create"))) {
    return { error: "permission_denied" };
  }

  const amount = Number(input.amount);
  if (!Number.isInteger(amount) || amount <= 0) {
    return { error: "validation_error", fieldErrors: { amount: "invalid" } };
  }

  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.incurredDate)) {
    return { error: "validation_error", fieldErrors: { incurredDate: "invalid" } };
  }

  const supabase = await createClient();
  const { data: category, error: catError } = await supabase
    .from("expense_category")
    .select("id, cost_group_id")
    .eq("id", input.expenseCategoryId)
    .maybeSingle();

  if (catError || !category) {
    return { error: "validation_error", fieldErrors: { expenseCategoryId: "invalid" } };
  }

  const { data, error } = await supabase
    .from("expense")
    .insert({
      organization_id: user.organizationId,
      expense_category_id: category.id,
      cost_group_id: category.cost_group_id,
      amount,
      incurred_date: input.incurredDate,
      class_id: input.classId ?? null,
      description: input.notes?.trim() || null,
      status: "posted",
    })
    .select("id")
    .single();

  if (error || !data) return { error: "save_error" };
  return { expenseId: data.id };
}
