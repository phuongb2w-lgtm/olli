"use server";

import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type ClassSimulationActionState = {
  error?: "permission_denied" | "validation_error" | "save_error" | "not_found";
  fieldErrors?: Record<string, string>;
  result?: Record<string, unknown>;
  scenarioId?: string;
};

function isValidDate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

export async function createClassFinancialScenario(input: {
  scenarioName: string;
  plannedLearnerCount: number;
  assumedNetTuitionPerLearner: number;
  plannedMonths: number;
  plannedSessionCount: number;
  classId?: string | null;
  perSessionTeacherRate?: number | null;
  staffCompensationRuleId?: string | null;
  monthlySharedPersonnelAssumption?: number;
  monthlyOperatingOverheadAssumption?: number;
  marketingSalesAssumption?: number;
  marketingAssumptionBasis?: "one_time" | "monthly";
  monthlyDepreciationAssumption?: number;
  capacitySnapshot?: number | null;
}): Promise<ClassSimulationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_simulation.manage"))) {
    return { error: "permission_denied" };
  }

  if (!input.scenarioName.trim() || input.plannedMonths <= 0) {
    return { error: "validation_error" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_class_financial_scenario", {
    p_scenario_name: input.scenarioName.trim(),
    p_planned_learner_count: input.plannedLearnerCount,
    p_assumed_net_tuition_per_learner: input.assumedNetTuitionPerLearner,
    p_planned_months: input.plannedMonths,
    p_planned_session_count: input.plannedSessionCount,
    p_class_id: input.classId ?? undefined,
    p_per_session_teacher_rate: input.perSessionTeacherRate ?? undefined,
    p_staff_compensation_rule_id: input.staffCompensationRuleId ?? undefined,
    p_monthly_shared_personnel_assumption: input.monthlySharedPersonnelAssumption ?? 0,
    p_monthly_operating_overhead_assumption: input.monthlyOperatingOverheadAssumption ?? 0,
    p_marketing_sales_assumption: input.marketingSalesAssumption ?? 0,
    p_marketing_assumption_basis: input.marketingAssumptionBasis ?? "one_time",
    p_monthly_depreciation_assumption: input.monthlyDepreciationAssumption ?? 0,
    p_capacity_snapshot: input.capacitySnapshot ?? undefined,
  });

  if (error || !data) return { error: "save_error" };
  return { scenarioId: data as string };
}

export async function updateClassFinancialScenario(
  scenarioId: string,
  input: Partial<{
    scenarioName: string;
    plannedLearnerCount: number;
    assumedNetTuitionPerLearner: number;
    plannedMonths: number;
    plannedSessionCount: number;
    perSessionTeacherRate: number | null;
    staffCompensationRuleId: string | null;
    monthlySharedPersonnelAssumption: number;
    monthlyOperatingOverheadAssumption: number;
    marketingSalesAssumption: number;
    marketingAssumptionBasis: "one_time" | "monthly";
    monthlyDepreciationAssumption: number;
  }>,
): Promise<ClassSimulationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_simulation.manage"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("update_class_financial_scenario", {
    p_scenario_id: scenarioId,
    p_scenario_name: input.scenarioName,
    p_planned_learner_count: input.plannedLearnerCount,
    p_assumed_net_tuition_per_learner: input.assumedNetTuitionPerLearner,
    p_planned_months: input.plannedMonths,
    p_planned_session_count: input.plannedSessionCount,
    p_per_session_teacher_rate: input.perSessionTeacherRate ?? undefined,
    p_staff_compensation_rule_id: input.staffCompensationRuleId ?? undefined,
    p_monthly_shared_personnel_assumption: input.monthlySharedPersonnelAssumption,
    p_monthly_operating_overhead_assumption: input.monthlyOperatingOverheadAssumption,
    p_marketing_sales_assumption: input.marketingSalesAssumption,
    p_marketing_assumption_basis: input.marketingAssumptionBasis,
    p_monthly_depreciation_assumption: input.monthlyDepreciationAssumption,
  });

  if (error || !data) return { error: "save_error" };
  return { scenarioId: data as string };
}

export async function finalizeClassFinancialScenario(
  scenarioId: string,
): Promise<ClassSimulationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_simulation.manage"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("finalize_class_financial_scenario", {
    p_scenario_id: scenarioId,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function cloneClassFinancialScenario(
  scenarioId: string,
): Promise<ClassSimulationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_simulation.manage"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("clone_class_financial_scenario", {
    p_scenario_id: scenarioId,
  });

  if (error || !data) return { error: "save_error" };
  return { scenarioId: data as string };
}

export async function getClassFinancialScenario(
  scenarioId: string,
): Promise<ClassSimulationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_simulation.read"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_class_financial_scenario", {
    p_scenario_id: scenarioId,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function compareClassFinancialScenarios(input: {
  classId?: string;
  scenarioIds?: string[];
}): Promise<ClassSimulationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_simulation.read"))) {
    return { error: "permission_denied" };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("compare_class_financial_scenarios", {
    p_class_id: input.classId,
    p_scenario_ids: input.scenarioIds,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}

export async function getProjectedVsActualClassEconomics(
  scenarioId: string,
  periodFrom: string,
  periodTo: string,
): Promise<ClassSimulationActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("class_simulation.read"))) {
    return { error: "permission_denied" };
  }

  if (!isValidDate(periodFrom) || !isValidDate(periodTo)) {
    return { error: "validation_error", fieldErrors: { period: "invalid" } };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_projected_vs_actual_class_economics", {
    p_scenario_id: scenarioId,
    p_period_from: periodFrom,
    p_period_to: periodTo,
  });

  if (error || !data) return { error: "save_error" };
  return { result: data as Record<string, unknown> };
}
