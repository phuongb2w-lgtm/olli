/**
 * M5 consultant revenue declaration vs canonical finance semantics.
 * Approval validates the declaration; it does not book ledger revenue.
 */

export const CONSULTANT_DECLARATION_STATUS = {
  pending: "pending",
  returned: "returned",
  approved: "approved",
  rejected: "rejected",
} as const;

export type ConsultantDeclarationStatus =
  (typeof CONSULTANT_DECLARATION_STATUS)[keyof typeof CONSULTANT_DECLARATION_STATUS];

/** Consultant submitted a revenue claim — not canonical finance. */
export function isDeclaredConsultantRevenue(status: string): boolean {
  return (
    status === CONSULTANT_DECLARATION_STATUS.pending ||
    status === CONSULTANT_DECLARATION_STATUS.returned
  );
}

/** Accountant validated the declaration — still NOT cash/recognized revenue unless linked. */
export function isApprovedConsultantDeclaration(status: string): boolean {
  return status === CONSULTANT_DECLARATION_STATUS.approved;
}

/**
 * Canonical M2 cash requires a posted payment record.
 * Optional future link: consultant_revenue_declaration.approved_payment_id.
 */
export function declarationCountsAsCanonicalCash(input: {
  status: string;
  approvedPaymentId: string | null;
}): boolean {
  return (
    isApprovedConsultantDeclaration(input.status) &&
    input.approvedPaymentId !== null
  );
}

/** Recognized revenue always comes from posted revenue_recognition_event (M2). */
export const RECOGNIZED_REVENUE_EVIDENCE =
  "revenue_recognition_event.status = posted" as const;
