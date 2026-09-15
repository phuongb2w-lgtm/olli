import {
  PAYMENT_METHOD_CODES,
  type PaymentMethodCode,
} from "@/lib/payments/constants";

export type PaymentAllocationInput = {
  chargeId: string;
  amount: number;
};

export type RecordPaymentInput = {
  guardianId: string;
  amount: number;
  paidAt?: string | null;
  methodCode?: PaymentMethodCode | null;
  referenceNumber?: string | null;
  notes?: string | null;
  studentId?: string | null;
  payerNameSnapshot?: string | null;
  idempotencyKey?: string | null;
  allocations?: PaymentAllocationInput[] | null;
};

export type AllocatePaymentInput = {
  paymentId: string;
  allocations: PaymentAllocationInput[];
  operationKey?: string | null;
};

type ValidationFailure = { ok: false; fieldErrors: Record<string, string> };

export type RecordPaymentValidationResult =
  | {
      ok: true;
      data: {
        guardianId: string;
        amount: number;
        paidAt: string | null;
        methodCode: PaymentMethodCode;
        referenceNumber: string | null;
        notes: string | null;
        studentId: string | null;
        payerNameSnapshot: string | null;
        idempotencyKey: string | null;
        allocations: { chargeId: string; amount: number }[] | null;
      };
    }
  | ValidationFailure;

export type AllocatePaymentValidationResult =
  | {
      ok: true;
      data: {
        paymentId: string;
        allocations: { chargeId: string; amount: number }[];
        operationKey: string | null;
      };
    }
  | ValidationFailure;

function parsePositiveInt(value: unknown): number | null {
  const n = typeof value === "number" ? value : Number(String(value ?? "").trim());
  if (!Number.isFinite(n) || !Number.isInteger(n) || n <= 0) return null;
  return n;
}

function parseUuid(value: unknown): string | null {
  const s = String(value ?? "").trim();
  if (!/^[0-9a-f-]{36}$/i.test(s)) return null;
  return s;
}

function parseMethodCode(value: unknown): PaymentMethodCode | null {
  const s = String(value ?? "cash").trim() as PaymentMethodCode;
  return PAYMENT_METHOD_CODES.includes(s) ? s : null;
}

function parseAllocations(
  value: unknown,
): { chargeId: string; amount: number }[] | null | "invalid" {
  if (value == null) return null;
  if (!Array.isArray(value)) return "invalid";

  const allocations: { chargeId: string; amount: number }[] = [];
  for (const item of value) {
    const chargeId = parseUuid((item as PaymentAllocationInput)?.chargeId);
    const amount = parsePositiveInt((item as PaymentAllocationInput)?.amount);
    if (!chargeId || amount == null) return "invalid";
    allocations.push({ chargeId, amount });
  }
  return allocations;
}

export function validateRecordPaymentInput(
  input: RecordPaymentInput,
): RecordPaymentValidationResult {
  const fieldErrors: Record<string, string> = {};

  const guardianId = parseUuid(input.guardianId);
  if (!guardianId) fieldErrors.guardianId = "invalid";

  const amount = parsePositiveInt(input.amount);
  if (amount == null) fieldErrors.amount = "invalid";

  const methodCode = parseMethodCode(input.methodCode);
  if (!methodCode) fieldErrors.methodCode = "invalid";

  const studentId = input.studentId ? parseUuid(input.studentId) : null;
  if (input.studentId && !studentId) fieldErrors.studentId = "invalid";

  const allocations = parseAllocations(input.allocations);
  if (allocations === "invalid") fieldErrors.allocations = "invalid";

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  const parsedAllocations = allocations === "invalid" ? null : allocations;

  return {
    ok: true,
    data: {
      guardianId: guardianId!,
      amount: amount!,
      paidAt: input.paidAt?.trim() || null,
      methodCode: methodCode!,
      referenceNumber: input.referenceNumber?.trim() || null,
      notes: input.notes?.trim() || null,
      studentId,
      payerNameSnapshot: input.payerNameSnapshot?.trim() || null,
      idempotencyKey: input.idempotencyKey?.trim() || null,
      allocations: parsedAllocations,
    },
  };
}

export function validateAllocatePaymentInput(
  input: AllocatePaymentInput,
): AllocatePaymentValidationResult {
  const fieldErrors: Record<string, string> = {};

  const paymentId = parseUuid(input.paymentId);
  if (!paymentId) fieldErrors.paymentId = "invalid";

  const allocations = parseAllocations(input.allocations);
  if (allocations === "invalid" || allocations == null || allocations.length === 0) {
    fieldErrors.allocations = "invalid";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: {
      paymentId: paymentId!,
      allocations: allocations as { chargeId: string; amount: number }[],
      operationKey: input.operationKey?.trim() || null,
    },
  };
}
