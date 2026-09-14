export type AppUserStatus = "active" | "inactive";

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
  | { kind: "active"; appUser: AppUserContext };
