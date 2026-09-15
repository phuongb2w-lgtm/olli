import type { RecognitionBasisCode } from "@/lib/enrollment-finance/constants";
import { RECOGNITION_BASIS_CODES } from "@/lib/enrollment-finance/constants";

export type DraftEnrollmentFinancialTermsInput = {
  enrollmentId: string;
  agreedTuitionAmount: number;
  discountAmount?: number;
  agreementDate?: string;
  tuitionPlanId?: string | null;
  recognitionBasisCode?: RecognitionBasisCode | null;
  notes?: string | null;
};

export type CustomScheduleItemInput = {
  dueDate: string;
  amount: number;
  label?: string;
};

export type ValidatedDraftEnrollmentFinancialTerms = {
  enrollmentId: string;
  agreedTuitionAmount: number;
  discountAmount: number;
  agreementDate: string;
  tuitionPlanId: string | null;
  recognitionBasisCode: RecognitionBasisCode | null;
  notes: string | null;
};

type ValidationFailure = { ok: false; fieldErrors: Record<string, string> };

export type DraftTermsValidationResult =
  | { ok: true; data: ValidatedDraftEnrollmentFinancialTerms }
  | ValidationFailure;

function parseNonNegativeInt(value: unknown): number | null {
  const n = typeof value === "number" ? value : Number(String(value ?? "").trim());
  if (!Number.isFinite(n) || !Number.isInteger(n) || n < 0) return null;
  return n;
}

function parsePositiveInt(value: unknown): number | null {
  const n = parseNonNegativeInt(value);
  if (n === null || n <= 0) return null;
  return n;
}

function parseIsoDate(value: unknown): string | null {
  const s = String(value ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const d = new Date(`${s}T00:00:00`);
  if (Number.isNaN(d.getTime())) return null;
  return s;
}

export function validateDraftEnrollmentFinancialTermsInput(
  input: DraftEnrollmentFinancialTermsInput,
): DraftTermsValidationResult {
  const fieldErrors: Record<string, string> = {};

  if (!input.enrollmentId.trim()) fieldErrors.enrollmentId = "required";

  const agreed = parseNonNegativeInt(input.agreedTuitionAmount);
  if (agreed === null) fieldErrors.agreedTuitionAmount = "invalid";

  const discount = parseNonNegativeInt(input.discountAmount ?? 0);
  if (discount === null) fieldErrors.discountAmount = "invalid";

  const agreementDate = input.agreementDate
    ? parseIsoDate(input.agreementDate)
    : new Date().toISOString().slice(0, 10);

  if (!agreementDate) fieldErrors.agreementDate = "invalid";

  if (
    input.recognitionBasisCode &&
    !RECOGNITION_BASIS_CODES.includes(input.recognitionBasisCode)
  ) {
    fieldErrors.recognitionBasisCode = "invalid";
  }

  if (agreed !== null && discount !== null && agreed - discount < 0) {
    fieldErrors.netTuition = "invalid";
  }

  if (
    Object.keys(fieldErrors).length > 0 ||
    agreed === null ||
    discount === null ||
    !agreementDate
  ) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: {
      enrollmentId: input.enrollmentId.trim(),
      agreedTuitionAmount: agreed,
      discountAmount: discount,
      agreementDate,
      tuitionPlanId: input.tuitionPlanId ?? null,
      recognitionBasisCode: input.recognitionBasisCode ?? null,
      notes: input.notes?.trim() || null,
    },
  };
}

export function validateCustomScheduleItems(
  items: CustomScheduleItemInput[],
  expectedTotal: number,
): { ok: true; items: CustomScheduleItemInput[] } | ValidationFailure {
  const fieldErrors: Record<string, string> = {};
  if (!items.length) fieldErrors.schedule = "required";

  let total = 0;
  items.forEach((item, index) => {
    const amount = parsePositiveInt(item.amount);
    const dueDate = parseIsoDate(item.dueDate);
    if (amount === null) fieldErrors[`items.${index}.amount`] = "invalid";
    if (!dueDate) fieldErrors[`items.${index}.dueDate`] = "invalid";
    if (amount !== null) total += amount;
  });

  if (Object.keys(fieldErrors).length === 0 && total !== expectedTotal) {
    fieldErrors.schedule = "total_mismatch";
  }

  if (Object.keys(fieldErrors).length > 0) return { ok: false, fieldErrors };
  return { ok: true, items };
}

export function validateInstallmentCount(value: unknown): number | null {
  return parsePositiveInt(value);
}
