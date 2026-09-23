import type { Json } from "@/types/database";

export type SessionCommercialAccess = {
  organization_id?: string;
  allows_normal_use?: boolean;
  subscription_status?: string | null;
  is_primary_owner?: boolean;
};

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
};

export function parseOwnerCommercialStatus(data: Json | null): OwnerCommercialStatusPayload | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return null;
  }
  return data as OwnerCommercialStatusPayload;
}
