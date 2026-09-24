import {
  parseOwnerCommercialStatus,
  type OwnerCommercialStatusPayload,
} from "@/lib/auth/session-commercial-access";
import type { SupabaseClient } from "@supabase/supabase-js";

export type OwnerCommercialStatusErrorCode =
  | "not_primary_owner"
  | "subscription_missing"
  | "unknown";

export type OwnerCommercialStatusResult =
  | { ok: true; status: OwnerCommercialStatusPayload }
  | { ok: false; code: OwnerCommercialStatusErrorCode };

function mapRpcError(message: string | undefined): OwnerCommercialStatusErrorCode {
  const normalized = (message ?? "").toLowerCase();
  if (normalized.includes("permission_denied") || normalized.includes("42501")) {
    return "not_primary_owner";
  }
  if (normalized.includes("subscription_missing")) {
    return "subscription_missing";
  }
  return "unknown";
}

/** Authoritative Owner commercial read via `fetch_owner_commercial_status` (DB/RPC). */
export async function fetchOwnerCommercialStatus(
  supabase: SupabaseClient,
): Promise<OwnerCommercialStatusResult> {
  const { data, error } = await supabase.rpc("fetch_owner_commercial_status");

  if (error) {
    return { ok: false, code: mapRpcError(error.message) };
  }

  const status = parseOwnerCommercialStatus(data);
  if (!status) {
    return { ok: false, code: "unknown" };
  }

  return { ok: true, status };
}
