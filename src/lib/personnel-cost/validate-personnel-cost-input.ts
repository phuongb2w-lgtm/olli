import {
  COMPENSATION_BASIS_CODES,
  PERSONNEL_COST_DOMAINS,
  type CompensationBasisCode,
  type PersonnelCostDomain,
} from "./constants";

export type CreateCompensationRuleInput = {
  appUserId: string;
  costDomainCode: PersonnelCostDomain;
  compensationBasisCode: CompensationBasisCode;
  amount: number;
  effectiveFrom: string;
  notes?: string;
};

export type ConfigureWelfareFundInput = {
  monthlyAmount: number;
  effectiveFrom: string;
  notes?: string;
};

function isPositiveInteger(value: number): boolean {
  return Number.isInteger(value) && value > 0;
}

function isValidDate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

export function validateCreateCompensationRuleInput(
  input: CreateCompensationRuleInput,
): { ok: true; data: CreateCompensationRuleInput } | { ok: false; fieldErrors: Record<string, string> } {
  const fieldErrors: Record<string, string> = {};

  if (!input.appUserId?.trim()) fieldErrors.appUserId = "required";
  if (!PERSONNEL_COST_DOMAINS.includes(input.costDomainCode)) fieldErrors.costDomainCode = "invalid";
  if (!COMPENSATION_BASIS_CODES.includes(input.compensationBasisCode)) {
    fieldErrors.compensationBasisCode = "invalid";
  }
  if (!isPositiveInteger(input.amount)) fieldErrors.amount = "invalid";
  if (!isValidDate(input.effectiveFrom)) fieldErrors.effectiveFrom = "invalid";

  if (Object.keys(fieldErrors).length > 0) return { ok: false, fieldErrors };
  return { ok: true, data: input };
}

export function validateConfigureWelfareFundInput(
  input: ConfigureWelfareFundInput,
): { ok: true; data: ConfigureWelfareFundInput } | { ok: false; fieldErrors: Record<string, string> } {
  const fieldErrors: Record<string, string> = {};

  if (!isPositiveInteger(input.monthlyAmount)) fieldErrors.monthlyAmount = "invalid";
  if (!isValidDate(input.effectiveFrom)) fieldErrors.effectiveFrom = "invalid";

  if (Object.keys(fieldErrors).length > 0) return { ok: false, fieldErrors };
  return { ok: true, data: input };
}

export function validatePeriodMonth(value: string): string | null {
  if (!isValidDate(value)) return null;
  const [year, month] = value.split("-");
  return `${year}-${month}-01`;
}
