import type { Json } from "@/types/database";

export type SessionCommercialAccess = {
  organization_id?: string;
  allows_normal_use?: boolean;
  subscription_status?: string | null;
  is_primary_owner?: boolean;
  requires_center_setup?: boolean;
  setup_completed?: boolean;
};

export type OwnerCenterSetupPayload = {
  organization_id?: string;
  name?: string;
  default_locale?: string;
  timezone?: string;
  preferred_locale?: string;
  subscription_status?: string | null;
};

export function parseOwnerCenterSetup(data: Json | null): OwnerCenterSetupPayload | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return null;
  }
  return data as OwnerCenterSetupPayload;
}

export function parseSessionCommercialAccess(data: Json | null): SessionCommercialAccess {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return {};
  }
  return data as SessionCommercialAccess;
}

export type OwnerCommercialStatusPayload = {
  plan_code?: string;
  plan_name?: string;
  subscription_status?: string;
  staff_limit?: number;
  staff_seats_used?: number;
  organization_status?: string;
  activated_at?: string | null;
  suspended_at?: string | null;
  cancelled_at?: string | null;
};

export function parseOwnerCommercialStatus(data: Json | null): OwnerCommercialStatusPayload | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return null;
  }
  return data as OwnerCommercialStatusPayload;
}
