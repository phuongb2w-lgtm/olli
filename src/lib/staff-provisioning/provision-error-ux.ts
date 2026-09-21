import type { StaffProvisioningErrorCode } from "@/lib/staff-provisioning/errors";

export type ProvisionErrorUx = {
  messageKey: string;
  retryable: boolean;
  classification: "retry" | "terminal" | "support";
};

const ERROR_UX: Record<StaffProvisioningErrorCode, ProvisionErrorUx> = {
  not_authenticated: {
    messageKey: "notAuthenticated",
    retryable: false,
    classification: "terminal",
  },
  not_primary_owner: {
    messageKey: "notPrimaryOwner",
    retryable: false,
    classification: "terminal",
  },
  organization_inactive: {
    messageKey: "organizationInactive",
    retryable: false,
    classification: "terminal",
  },
  invalid_role: {
    messageKey: "invalidRole",
    retryable: false,
    classification: "terminal",
  },
  invalid_email: {
    messageKey: "invalidEmail",
    retryable: false,
    classification: "terminal",
  },
  invalid_input: {
    messageKey: "invalidInput",
    retryable: false,
    classification: "terminal",
  },
  staff_seat_limit_exceeded: {
    messageKey: "staffSeatLimitExceeded",
    retryable: false,
    classification: "terminal",
  },
  member_already_exists: {
    messageKey: "memberAlreadyExists",
    retryable: false,
    classification: "terminal",
  },
  identity_conflict: {
    messageKey: "identityConflict",
    retryable: false,
    classification: "terminal",
  },
  idempotency_conflict: {
    messageKey: "idempotencyConflict",
    retryable: false,
    classification: "terminal",
  },
  auth_provisioning_failed: {
    messageKey: "authProvisioningFailed",
    retryable: true,
    classification: "retry",
  },
  membership_provisioning_failed: {
    messageKey: "membershipProvisioningFailed",
    retryable: true,
    classification: "retry",
  },
  compensation_pending: {
    messageKey: "compensationPending",
    retryable: true,
    classification: "retry",
  },
  provisioning_pending: {
    messageKey: "provisioningPending",
    retryable: true,
    classification: "retry",
  },
  reconciliation_required: {
    messageKey: "reconciliationRequired",
    retryable: false,
    classification: "support",
  },
  not_found: {
    messageKey: "notFound",
    retryable: false,
    classification: "terminal",
  },
  unknown: {
    messageKey: "unknown",
    retryable: true,
    classification: "retry",
  },
};

export function getProvisionErrorUx(code: StaffProvisioningErrorCode): ProvisionErrorUx {
  return ERROR_UX[code] ?? ERROR_UX.unknown;
}
