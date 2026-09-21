import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  findAuthUserByProvisioningRequest,
  verifyAuthUserCorrelation,
} from "@/lib/staff-provisioning/auth-reconcile";
import {
  PROVISIONING_METADATA_KEY,
  type StaffCanonicalRole,
} from "@/lib/staff-provisioning/constants";
import { mapProvisioningError, type StaffProvisioningErrorCode } from "@/lib/staff-provisioning/errors";

export type ProvisionStaffInput = {
  email: string;
  displayName: string;
  canonicalRole: StaffCanonicalRole;
  idempotencyKey: string;
  preferredLocale?: "vi" | "en";
};

export type ProvisionStaffSuccess = {
  ok: true;
  appUserId: string;
  email: string;
  canonicalRole: string;
  requestId: string;
  pending?: boolean;
};

export type ProvisionStaffFailure = {
  ok: false;
  error: StaffProvisioningErrorCode;
  requestId?: string;
};

export type ProvisionStaffResult = ProvisionStaffSuccess | ProvisionStaffFailure;

type RequestJson = {
  request_id: string;
  status: string;
  outcome?: string;
  normalized_email: string;
  canonical_role: string;
  auth_user_id: string | null;
  app_user_id: string | null;
  processing_token?: string | null;
};

function isCompleted(row: RequestJson): row is RequestJson & { app_user_id: string } {
  return row.status === "completed" && Boolean(row.app_user_id);
}

async function compensateRequest(admin: SupabaseClient<Database>, requestId: string): Promise<void> {
  const { data: row, error } = await admin
    .from("staff_provisioning_request")
    .select("auth_user_id, auth_created_by_this_request, normalized_email, status")
    .eq("id", requestId)
    .maybeSingle();

  if (error || !row?.auth_user_id || !row.auth_created_by_this_request) {
    await admin.rpc("mark_provisioning_reconciliation_required", {
      p_request_id: requestId,
      p_result_code: "reconciliation_required",
    });
    return;
  }

  const verified = await verifyAuthUserCorrelation(
    admin,
    row.auth_user_id,
    requestId,
    row.normalized_email,
  );

  if (!verified) {
    await admin.rpc("mark_provisioning_reconciliation_required", {
      p_request_id: requestId,
      p_result_code: "reconciliation_required",
    });
    return;
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(row.auth_user_id);
  if (deleteError) {
    await admin.rpc("mark_provisioning_reconciliation_required", {
      p_request_id: requestId,
      p_result_code: "compensation_pending",
    });
    return;
  }

  await admin.rpc("mark_provisioning_compensated", { p_request_id: requestId });
}

async function ensureAuthUserForRequest(
  admin: SupabaseClient<Database>,
  _userClient: SupabaseClient<Database>,
  row: RequestJson,
  processingToken: string,
): Promise<{ authUserId: string } | ProvisionStaffFailure> {
  const requestId = row.request_id;
  const normalizedEmail = row.normalized_email;

  if (row.auth_user_id) {
    const ok = await verifyAuthUserCorrelation(admin, row.auth_user_id, requestId, normalizedEmail);
    if (!ok) {
      await admin.rpc("mark_provisioning_reconciliation_required", {
        p_request_id: requestId,
        p_result_code: "reconciliation_required",
      });
      return { ok: false, error: "reconciliation_required", requestId };
    }
    if (row.status === "auth_created" || row.status === "auth_pending") {
      const { error: recordError } = await admin.rpc("record_provisioning_auth_created", {
        p_request_id: requestId,
        p_auth_user_id: row.auth_user_id,
        p_processing_token: processingToken,
      });
      if (recordError && !recordError.message.includes("invalid_request_state")) {
        return { ok: false, error: mapProvisioningError(recordError.message), requestId };
      }
    }
    return { authUserId: row.auth_user_id };
  }

  const { user: correlated, exhausted } = await findAuthUserByProvisioningRequest(
    admin,
    requestId,
    normalizedEmail,
  );

  if (correlated) {
    const { error: recordError } = await admin.rpc("record_provisioning_auth_created", {
      p_request_id: requestId,
      p_auth_user_id: correlated.id,
      p_processing_token: processingToken,
    });
    if (recordError) {
      return { ok: false, error: mapProvisioningError(recordError.message), requestId };
    }
    return { authUserId: correlated.id };
  }

  if (!exhausted) {
    await admin.rpc("mark_provisioning_reconciliation_required", {
      p_request_id: requestId,
      p_result_code: "reconciliation_required",
    });
    return { ok: false, error: "reconciliation_required", requestId };
  }

  const metadata = { [PROVISIONING_METADATA_KEY]: requestId };
  const useInvite = process.env.OLLI_STAFF_PROVISION_USE_INVITE !== "false";

  let authUserId: string | undefined;

  if (useInvite) {
    const { data, error } = await admin.auth.admin.inviteUserByEmail(normalizedEmail, {
      data: metadata,
    });
    if (error) {
      if (error.message.toLowerCase().includes("already")) {
        return { ok: false, error: "identity_conflict", requestId };
      }
      return { ok: false, error: "auth_provisioning_failed", requestId };
    }
    authUserId = data.user?.id;
  } else {
    const { data, error } = await admin.auth.admin.createUser({
      email: normalizedEmail,
      email_confirm: true,
      user_metadata: metadata,
    });
    if (error) {
      if (error.message.toLowerCase().includes("already")) {
        return { ok: false, error: "identity_conflict", requestId };
      }
      return { ok: false, error: "auth_provisioning_failed", requestId };
    }
    authUserId = data.user?.id;
  }

  if (!authUserId) {
    return { ok: false, error: "auth_provisioning_failed", requestId };
  }

  const verified = await verifyAuthUserCorrelation(admin, authUserId, requestId, normalizedEmail);
  if (!verified) {
    return { ok: false, error: "auth_provisioning_failed", requestId };
  }

  const { error: recordError } = await admin.rpc("record_provisioning_auth_created", {
    p_request_id: requestId,
    p_auth_user_id: authUserId,
    p_processing_token: processingToken,
  });

  if (recordError) {
    return { ok: false, error: mapProvisioningError(recordError.message), requestId };
  }

  return { authUserId };
}

export async function orchestrateStaffProvisioning(
  userClient: SupabaseClient<Database>,
  input: ProvisionStaffInput,
): Promise<ProvisionStaffResult> {
  const admin = createAdminClient();

  const { data: beginData, error: beginError } = await userClient.rpc("begin_staff_provisioning", {
    p_idempotency_key: input.idempotencyKey,
    p_email: input.email,
    p_display_name: input.displayName,
    p_canonical_role: input.canonicalRole,
    p_preferred_locale: input.preferredLocale ?? "vi",
  });

  if (beginError) {
    return { ok: false, error: mapProvisioningError(beginError.message) };
  }

  const beginRow = beginData as RequestJson;

  if (isCompleted(beginRow)) {
    return {
      ok: true,
      appUserId: beginRow.app_user_id,
      email: beginRow.normalized_email,
      canonicalRole: beginRow.canonical_role,
      requestId: beginRow.request_id,
    };
  }

  const requestId = beginRow.request_id;

  const { data: claimData, error: claimError } = await userClient.rpc(
    "claim_provisioning_auth_execution",
    {
      p_request_id: requestId,
      p_processing_token: undefined,
    },
  );

  if (claimError) {
    return { ok: false, error: mapProvisioningError(claimError.message), requestId };
  }

  const claimRow = claimData as RequestJson & {
    outcome?: string;
    processing_token?: string | null;
  };

  if (claimRow.outcome === "completed" && claimRow.app_user_id) {
    return {
      ok: true,
      appUserId: claimRow.app_user_id,
      email: claimRow.normalized_email,
      canonicalRole: claimRow.canonical_role,
      requestId,
    };
  }

  if (claimRow.outcome === "provisioning_pending") {
    return { ok: false, error: "provisioning_pending", requestId };
  }

  const processingToken = claimRow.processing_token;
  if (!processingToken) {
    return { ok: false, error: "provisioning_pending", requestId };
  }

  const authResult = await ensureAuthUserForRequest(admin, userClient, claimRow, processingToken);
  if (!("authUserId" in authResult)) {
    return authResult;
  }

  const { data: finalizeData, error: finalizeError } = await admin.rpc("finalize_staff_provisioning", {
    p_request_id: requestId,
  });

  const finalizeRow = finalizeData as RequestJson & { outcome?: string };
  if (!finalizeError && finalizeRow?.outcome === "staff_seat_limit_exceeded") {
    await compensateRequest(admin, requestId);
    return { ok: false, error: "staff_seat_limit_exceeded", requestId };
  }

  if (finalizeError) {
    const code = mapProvisioningError(finalizeError.message);
    if (
      code === "staff_seat_limit_exceeded" ||
      code === "member_already_exists" ||
      code === "identity_conflict" ||
      code === "membership_provisioning_failed" ||
      code === "not_primary_owner"
    ) {
      await compensateRequest(admin, requestId);
    }
    if (code === "staff_seat_limit_exceeded" || code === "member_already_exists") {
      return { ok: false, error: code, requestId };
    }
    if (finalizeError.message.includes("compensation_pending")) {
      return { ok: false, error: "compensation_pending", requestId };
    }
    return { ok: false, error: code, requestId };
  }

  const finalRow = finalizeData as RequestJson;
  if (!finalRow.app_user_id) {
    return { ok: false, error: "membership_provisioning_failed", requestId };
  }

  return {
    ok: true,
    appUserId: finalRow.app_user_id,
    email: finalRow.normalized_email,
    canonicalRole: finalRow.canonical_role,
    requestId,
  };
}
