"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type ClassEconomicsActionState = {
  error?: "permission_denied" | "validation_error" | "save_error" | "not_found";
  fieldErrors?: Record<string, string>;
  result?: Record<string, unknown>;
};

function isValidDate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

export async function runClassCostAllocation(
  periodMonth: string,
): Promise<ClassEconomicsActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("cost_allocation.manage"))) {
    return { error: "permission_denied" };
  }

  if (!isValidDate(periodMonth)) {
    return { error: "validation_error", fieldErrors: { periodMonth: "invalid" } };
  }

  const normalized = `${periodMonth.slice(0, 7)}-01`;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("run_class_cost_allocation", {
    p_period_month: normalized,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function getClassEconomics(
  classId: string,
  periodFrom: string,
  periodTo: string,
): Promise<ClassEconomicsActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_economics.read"))) {
    return { error: "permission_denied" };
  }

  if (!isValidDate(periodFrom) || !isValidDate(periodTo)) {
    return { error: "validation_error", fieldErrors: { period: "invalid" } };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_class_economics", {
    p_class_id: classId,
    p_period_from: periodFrom,
    p_period_to: periodTo,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function getOrganizationCostReconciliation(
  periodMonth: string,
): Promise<ClassEconomicsActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_economics.read"))) {
    return { error: "permission_denied" };
  }

  if (!isValidDate(periodMonth)) {
    return { error: "validation_error", fieldErrors: { periodMonth: "invalid" } };
  }

  const normalized = `${periodMonth.slice(0, 7)}-01`;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_organization_cost_reconciliation", {
    p_period_month: normalized,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}
