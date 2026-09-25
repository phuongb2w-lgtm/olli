import type { StaffLifecycleErrorCode } from "@/lib/staff-lifecycle/errors";

export function lifecycleErrorMessageKey(code: StaffLifecycleErrorCode): string {
  const map: Record<StaffLifecycleErrorCode, string> = {
    not_authenticated: "notAuthenticated",
    not_primary_owner: "notPrimaryOwner",
    organization_inactive: "organizationInactive",
    target_not_found: "targetNotFound",
    target_is_primary_owner: "targetIsPrimaryOwner",
    target_not_member: "targetNotMember",
    target_already_removed: "targetAlreadyRemoved",
    target_already_suspended: "targetAlreadySuspended",
    target_already_active: "targetAlreadyActive",
    invalid_role: "invalidRole",
    staff_seat_limit_exceeded: "staffSeatLimitExceeded",
    identity_conflict: "identityConflict",
    removed_member_exists: "removedMemberExists",
    lifecycle_conflict: "lifecycleConflict",
    rate_limited: "rateLimited",
    unknown: "unknown",
  };
  return map[code];
}
