import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import { STAFF_CANONICAL_ROLES } from "@/lib/staff-provisioning/constants";
import type {
  CenterAccountAdministration,
  CenterAccountPerson,
  CenterAccountStaffMember,
} from "@/lib/center-accounts/types";

type RpcPerson = {
  app_user_id: string;
  display_name: string;
  email: string;
  access_status: string;
  membership_status: string;
  preferred_locale: string;
};

type RpcStaff = RpcPerson & {
  canonical_role: string | null;
  created_at: string;
};

type RpcPayload = {
  staff_limit: number;
  staff_seats_used: number;
  primary_owner: RpcPerson;
  staff: RpcStaff[];
  removed_staff?: RpcStaff[];
};

function mapPerson(row: RpcPerson): CenterAccountPerson {
  return {
    appUserId: row.app_user_id,
    displayName: row.display_name,
    email: row.email,
    accessStatus: row.access_status as CenterAccountPerson["accessStatus"],
    membershipStatus: row.membership_status as CenterAccountPerson["membershipStatus"],
    preferredLocale: row.preferred_locale as CenterAccountPerson["preferredLocale"],
  };
}

function mapStaffRole(code: string | null): CenterAccountStaffMember["canonicalRole"] {
  if (!code) return null;
  return (STAFF_CANONICAL_ROLES as readonly string[]).includes(code)
    ? (code as CenterAccountStaffMember["canonicalRole"])
    : null;
}

export async function fetchCenterAccountAdministration(
  supabase: SupabaseClient<Database>,
): Promise<{ data: CenterAccountAdministration | null; error: string | null }> {
  const { data, error } = await supabase.rpc("fetch_center_account_administration");

  if (error) {
    if (error.message.includes("permission_denied")) {
      return { data: null, error: "permission_denied" };
    }
    return { data: null, error: error.message };
  }

  if (!data || typeof data !== "object") {
    return { data: null, error: "invalid_response" };
  }

  const payload = data as RpcPayload;

  return {
    data: {
      staffLimit: payload.staff_limit,
      staffSeatsUsed: payload.staff_seats_used,
      primaryOwner: mapPerson(payload.primary_owner),
      staff: (payload.staff ?? []).map((row) => ({
        ...mapPerson(row),
        canonicalRole: mapStaffRole(row.canonical_role),
        createdAt: row.created_at,
      })),
      removedStaff: (payload.removed_staff ?? []).map((row) => ({
        ...mapPerson(row),
        canonicalRole: mapStaffRole(row.canonical_role),
        createdAt: row.created_at,
      })),
    },
    error: null,
  };
}
