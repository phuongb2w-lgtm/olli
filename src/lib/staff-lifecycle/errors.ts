export type StaffLifecycleErrorCode =
  | "not_authenticated"
  | "not_primary_owner"
  | "organization_inactive"
  | "target_not_found"
  | "target_is_primary_owner"
  | "target_not_member"
  | "target_already_removed"
  | "target_already_suspended"
  | "target_already_active"
  | "invalid_role"
  | "staff_seat_limit_exceeded"
  | "identity_conflict"
  | "removed_member_exists"
  | "lifecycle_conflict"
  | "rate_limited"
  | "unknown";

const LIFECYCLE_CODES: StaffLifecycleErrorCode[] = [
  "not_authenticated",
  "not_primary_owner",
  "organization_inactive",
  "target_is_primary_owner",
  "target_already_removed",
  "target_already_suspended",
  "target_already_active",
  "target_not_member",
  "target_not_found",
  "invalid_role",
  "staff_seat_limit_exceeded",
  "identity_conflict",
  "removed_member_exists",
  "lifecycle_conflict",
];

export function mapLifecycleError(message: string): StaffLifecycleErrorCode {
  for (const code of LIFECYCLE_CODES) {
    if (message.includes(code)) {
      return code;
    }
  }

  if (message.includes("permission_denied") || message.includes("not_primary_owner")) {
    return "not_primary_owner";
  }

  return "unknown";
}
