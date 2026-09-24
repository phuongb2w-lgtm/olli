import {
  parseOwnerCenterSetup,
  type OwnerCenterSetupPayload,
} from "@/lib/auth/session-commercial-access";
import type { SupabaseClient } from "@supabase/supabase-js";

export type OwnerCenterSetupErrorCode =
  | "not_primary_owner"
  | "setup_already_complete"
  | "commercial_access_restricted"
  | "unknown";

export type OwnerCenterSetupResult =
  | { ok: true; setup: OwnerCenterSetupPayload }
  | { ok: false; code: OwnerCenterSetupErrorCode };

function mapRpcError(message: string | undefined): OwnerCenterSetupErrorCode {
  const normalized = (message ?? "").toLowerCase();
  if (normalized.includes("not_primary_owner")) {
    return "not_primary_owner";
  }
  if (normalized.includes("setup_already_complete")) {
    return "setup_already_complete";
  }
  if (
    normalized.includes("commercial_access_restricted") ||
    normalized.includes("42501")
  ) {
    return "commercial_access_restricted";
  }
  return "unknown";
}

export async function fetchOwnerCenterSetup(
  supabase: SupabaseClient,
): Promise<OwnerCenterSetupResult> {
  const { data, error } = await supabase.rpc("fetch_owner_center_setup");

  if (error) {
    return { ok: false, code: mapRpcError(error.message) };
  }

  const setup = parseOwnerCenterSetup(data);
  if (!setup?.name) {
    return { ok: false, code: "unknown" };
  }

  return { ok: true, setup };
}
