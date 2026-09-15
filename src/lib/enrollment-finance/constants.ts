export const PAYMENT_PLAN_MODES = [
  "full_upfront",
  "deposit_remainder",
  "equal_installments",
  "custom",
] as const;

export type PaymentPlanMode = (typeof PAYMENT_PLAN_MODES)[number];

export const RECOGNITION_BASIS_CODES = [
  "per_lesson",
  "stage_checkpoint",
  "deferred",
] as const;

export type RecognitionBasisCode = (typeof RECOGNITION_BASIS_CODES)[number];

export const FINANCIAL_TERMS_STATUSES = [
  "draft",
  "active",
  "superseded",
  "cancelled",
] as const;

export type FinancialTermsStatus = (typeof FINANCIAL_TERMS_STATUSES)[number];
