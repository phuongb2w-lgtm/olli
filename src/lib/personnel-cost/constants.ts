export const PERSONNEL_COST_DOMAINS = ["personnel", "marketing_sales"] as const;

export const COMPENSATION_BASIS_CODES = ["monthly_fixed", "per_session"] as const;

export type PersonnelCostDomain = (typeof PERSONNEL_COST_DOMAINS)[number];
export type CompensationBasisCode = (typeof COMPENSATION_BASIS_CODES)[number];
