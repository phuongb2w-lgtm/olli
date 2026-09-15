export const PAYMENT_METHOD_CODES = [
  "cash",
  "bank_transfer",
  "card",
  "other",
] as const;

export type PaymentMethodCode = (typeof PAYMENT_METHOD_CODES)[number];

export const PAYMENT_STATUSES = ["posted", "void", "reversed"] as const;

export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

export const PAYMENT_ALLOCATION_STATUSES = ["posted", "void"] as const;

export type PaymentAllocationStatus = (typeof PAYMENT_ALLOCATION_STATUSES)[number];

export const DERIVED_PAYMENT_ALLOCATION_STATUSES = [
  "unallocated",
  "partially_allocated",
  "fully_allocated",
] as const;

export type DerivedPaymentAllocationStatus =
  (typeof DERIVED_PAYMENT_ALLOCATION_STATUSES)[number];

export const COLLECTION_STATUSES = [
  "unpaid",
  "partially_paid",
  "paid",
  "overdue",
  "void",
] as const;

export type CollectionStatus = (typeof COLLECTION_STATUSES)[number];
