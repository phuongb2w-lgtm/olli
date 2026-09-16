"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  validateConfigureWelfareFundInput,
  validateCreateCompensationRuleInput,
  validatePeriodMonth,
  type ConfigureWelfareFundInput,
  type CreateCompensationRuleInput,
} from "@/lib/personnel-cost/validate-personnel-cost-input";
import { createClient } from "@/lib/supabase/server";

export type PersonnelCostActionState = {
  error?:
    | "permission_denied"
    | "validation_error"
    | "save_error"
    | "not_found";
  fieldErrors?: Record<string, string>;
  result?: Record<string, unknown>;
};

export async function createCompensationRule(
  input: CreateCompensationRuleInput,
): Promise<PersonnelCostActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("personnel_cost.manage"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateCreateCompensationRuleInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_staff_compensation_rule", {
    p_app_user_id: parsed.data.appUserId,
    p_cost_domain_code: parsed.data.costDomainCode,
    p_compensation_basis_code: parsed.data.compensationBasisCode,
    p_amount: parsed.data.amount,
    p_effective_from: parsed.data.effectiveFrom,
    p_notes: parsed.data.notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { result: { ruleId: data as string } };
}

export async function endCompensationRule(
  ruleId: string,
  effectiveTo: string,
): Promise<PersonnelCostActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("personnel_cost.manage"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("end_staff_compensation_rule", {
    p_rule_id: ruleId,
    p_effective_to: effectiveTo,
  });

  if (error || !data) return { error: "save_error" };
  return { result: { ruleId: data as string } };
}

export async function configureWelfareFundBaseline(
  input: ConfigureWelfareFundInput,
): Promise<PersonnelCostActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("personnel_cost.manage"))) {
    return { error: "permission_denied" };
  }

  const parsed = validateConfigureWelfareFundInput(input);
  if (!parsed.ok) {
    return { error: "validation_error", fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("configure_welfare_fund_baseline", {
    p_monthly_amount: parsed.data.monthlyAmount,
    p_effective_from: parsed.data.effectiveFrom,
    p_notes: parsed.data.notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { result: { configId: data as string } };
}

export async function generatePersonnelCosts(
  periodMonth: string,
): Promise<PersonnelCostActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("personnel_cost.manage"))) {
    return { error: "permission_denied" };
  }

  const normalized = validatePeriodMonth(periodMonth);
  if (!normalized) {
    return { error: "validation_error", fieldErrors: { periodMonth: "invalid" } };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("generate_personnel_costs", {
    p_period_month: normalized,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function generateTeachingSessionPersonnelCost(
  teachingSessionId: string,
): Promise<PersonnelCostActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("personnel_cost.manage"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("generate_teaching_session_personnel_cost", {
    p_teaching_session_id: teachingSessionId,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function voidPersonnelCostEntry(
  entryId: string,
  notes?: string,
): Promise<PersonnelCostActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("personnel_cost.manage"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("void_personnel_cost_entry", {
    p_entry_id: entryId,
    p_notes: notes ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { result: { entryId: data as string } };
}
