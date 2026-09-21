import type { StaffCanonicalRole } from "@/lib/staff-provisioning/constants";

export type CenterAccountPerson = {
  appUserId: string;
  displayName: string;
  email: string;
  accessStatus: "active" | "inactive" | "locked";
  membershipStatus: "member" | "removed";
  preferredLocale: "vi" | "en";
};

export type CenterAccountStaffMember = CenterAccountPerson & {
  canonicalRole: StaffCanonicalRole | null;
  createdAt: string;
};

export type CenterAccountAdministration = {
  staffLimit: number;
  staffSeatsUsed: number;
  primaryOwner: CenterAccountPerson;
  staff: CenterAccountStaffMember[];
};
