export type StaffProvisioningErrorCode =
  | "not_authenticated"
  | "not_primary_owner"
  | "organization_inactive"
  | "invalid_role"
  | "invalid_email"
  | "invalid_input"
  | "staff_seat_limit_exceeded"
  | "member_already_exists"
  | "identity_conflict"
  | "idempotency_conflict"
  | "auth_provisioning_failed"
  | "membership_provisioning_failed"
  | "compensation_pending"
  | "provisioning_pending"
  | "reconciliation_required"
  | "not_found"
  | "unknown";

export function mapProvisioningError(message: string): StaffProvisioningErrorCode {
  const codes: StaffProvisioningErrorCode[] = [
    "not_primary_owner",
    "invalid_role",
    "invalid_email",
    "invalid_input",
    "staff_seat_limit_exceeded",
    "member_already_exists",
    "identity_conflict",
    "idempotency_conflict",
    "membership_provisioning_failed",
    "compensation_pending",
    "reconciliation_required",
    "not_found",
  ];

  for (const code of codes) {
    if (message.includes(code)) {
      return code;
    }
  }

  if (
    message.includes("invalid_processing_token") ||
    message.includes("lease_expired") ||
    message.includes("invalid_request_state")
  ) {
    return "provisioning_pending";
  }

  if (message.includes("permission_denied")) {
    return "not_primary_owner";
  }

  return "unknown";
}
