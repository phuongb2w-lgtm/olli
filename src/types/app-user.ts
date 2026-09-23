export type AppUserStatus = "active" | "inactive" | "locked";

export type OrganizationSubscriptionStatus =
  | "provisioning"
  | "active"
  | "suspended"
  | "cancelled";

export type AppUserContext = {
  appUserId: string;
  organizationId: string;
  organizationName: string;
  organizationDefaultLocale: string;
  displayName: string;
  preferredLocale: string;
  status: AppUserStatus;
};

export type IdentityState =
  | { kind: "none" }
  | { kind: "unmapped" }
  | { kind: "inactive" }
  | { kind: "no_organization" }
  | { kind: "active"; appUser: AppUserContext }
  | {
      kind: "commercially_restricted";
      appUser: AppUserContext;
      subscriptionStatus: OrganizationSubscriptionStatus | "missing";
      isPrimaryOwner: boolean;
    };
