export const SCENARIO_STATUS_CODES = ["draft", "finalized"] as const;

export const TUITION_ASSUMPTION_MODES = ["uniform_tuition"] as const;

export const MARKETING_ASSUMPTION_BASIS_CODES = ["one_time", "monthly"] as const;

export type ScenarioStatusCode = (typeof SCENARIO_STATUS_CODES)[number];
export type TuitionAssumptionMode = (typeof TUITION_ASSUMPTION_MODES)[number];
export type MarketingAssumptionBasisCode = (typeof MARKETING_ASSUMPTION_BASIS_CODES)[number];
