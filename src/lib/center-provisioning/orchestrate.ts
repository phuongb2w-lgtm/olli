import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import { createAdminClient } from "@/lib/supabase/admin";
import { CENTER_PROVISIONING_METADATA_KEY } from "@/lib/center-provisioning/constants";
import { buildPasswordSetupCallbackUrl } from "@/lib/auth/app-origin";

export type ProvisionCustomerCenterInput = {
  idempotencyKey: string;
  organizationName: string;
  ownerEmail: string;
  ownerDisplayName: string;
  ownerPreferredLocale?: "vi" | "en";
  defaultLocale?: "vi" | "en";
  timezone?: string;
  currencyCode?: string;
};

export type ProvisionCustomerCenterSuccess = {
  ok: true;
  requestId: string;
  organizationId: string;
  ownerAppUserId: string;
  authUserId: string;
  ownerEmail: string;
  resumed: boolean;
};

export type ProvisionCustomerCenterFailure = {
  ok: false;
  error: string;
  requestId?: string;
};

export type ProvisionCustomerCenterResult =
  | ProvisionCustomerCenterSuccess
  | ProvisionCustomerCenterFailure;

type BeginJson = {
  request_id: string;
  status: string;
  outcome?: string;
  organization_id?: string | null;
  owner_app_user_id?: string | null;
  auth_user_id?: string | null;
  owner_normalized_email?: string;
};

function isCompleted(row: BeginJson): row is BeginJson & {
  organization_id: string;
  owner_app_user_id: string;
  auth_user_id: string;
} {
  return (
    row.status === "completed" &&
    Boolean(row.organization_id) &&
    Boolean(row.owner_app_user_id) &&
    Boolean(row.auth_user_id)
  );
}

async function compensateAuthUser(
  admin: SupabaseClient<Database>,
  requestId: string,
  authUserId: string,
  authCreatedByThisRequest: boolean,
): Promise<void> {
  if (!authCreatedByThisRequest) {
    await admin.rpc("mark_center_provisioning_reconciliation_required", {
      p_request_id: requestId,
      p_result_code: "reconciliation_required",
    });
    return;
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(authUserId);
  if (deleteError) {
    await admin.rpc("mark_center_provisioning_reconciliation_required", {
      p_request_id: requestId,
      p_result_code: "compensation_pending",
    });
    return;
  }

  await admin.rpc("mark_center_provisioning_compensated", { p_request_id: requestId });
}

type AuthUserEnsureResult =
  | { kind: "ok"; authUserId: string; created: boolean }
  | ProvisionCustomerCenterFailure;

async function ensureAuthUserForCenterRequest(
  admin: SupabaseClient<Database>,
  row: BeginJson,
  normalizedEmail: string,
): Promise<AuthUserEnsureResult> {
  const requestId = row.request_id;

  if (row.auth_user_id) {
    return { kind: "ok", authUserId: row.auth_user_id, created: false };
  }

  const metadata = { [CENTER_PROVISIONING_METADATA_KEY]: requestId };
  const useInvite = process.env.OLLI_CENTER_PROVISION_USE_INVITE !== "false";
  const redirectTo = buildPasswordSetupCallbackUrl();

  let authUserId: string | undefined;

  if (useInvite) {
    const { data, error } = await admin.auth.admin.inviteUserByEmail(normalizedEmail, {
      data: metadata,
      redirectTo,
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

  return { kind: "ok", authUserId, created: true };
}

export async function orchestrateCustomerCenterProvisioning(
  input: ProvisionCustomerCenterInput,
): Promise<ProvisionCustomerCenterResult> {
  const admin = createAdminClient();

  const { data: beginData, error: beginError } = await admin.rpc("begin_center_provisioning", {
    p_idempotency_key: input.idempotencyKey,
    p_organization_name: input.organizationName,
    p_owner_email: input.ownerEmail,
    p_owner_display_name: input.ownerDisplayName,
    p_owner_preferred_locale: input.ownerPreferredLocale ?? "vi",
    p_default_locale: input.defaultLocale ?? "vi",
    p_timezone: input.timezone ?? "Asia/Ho_Chi_Minh",
    p_currency_code: input.currencyCode ?? "VND",
  });

  if (beginError) {
    return { ok: false, error: beginError.message };
  }

  const beginRow = beginData as BeginJson;
  const resumed = beginRow.outcome === "resume" || beginRow.outcome === "completed";

  if (isCompleted(beginRow)) {
    return {
      ok: true,
      requestId: beginRow.request_id,
      organizationId: beginRow.organization_id,
      ownerAppUserId: beginRow.owner_app_user_id,
      authUserId: beginRow.auth_user_id,
      ownerEmail: beginRow.owner_normalized_email ?? input.ownerEmail.trim().toLowerCase(),
      resumed: true,
    };
  }

  const requestId = beginRow.request_id;
  const normalizedEmail = (beginRow.owner_normalized_email ?? input.ownerEmail).trim().toLowerCase();

  const authResult = await ensureAuthUserForCenterRequest(admin, beginRow, normalizedEmail);
  if (!("kind" in authResult) || authResult.kind !== "ok") {
    return authResult as ProvisionCustomerCenterFailure;
  }

  const { authUserId, created } = authResult;

  const { error: recordError } = await admin.rpc("record_center_provisioning_auth_created", {
    p_request_id: requestId,
    p_auth_user_id: authUserId,
    p_auth_created_by_this_request: created,
  });

  if (recordError) {
    if (created) {
      await compensateAuthUser(admin, requestId, authUserId, true);
    }
    return { ok: false, error: recordError.message, requestId };
  }

  const { data: finalizeData, error: finalizeError } = await admin.rpc(
    "finalize_center_provisioning",
    { p_request_id: requestId },
  );

  if (finalizeError) {
    if (created) {
      await compensateAuthUser(admin, requestId, authUserId, true);
    }
    return { ok: false, error: finalizeError.message, requestId };
  }

  const finalizeRow = finalizeData as BeginJson;
  if (!finalizeRow.organization_id || !finalizeRow.owner_app_user_id || !finalizeRow.auth_user_id) {
    if (created) {
      await compensateAuthUser(admin, requestId, authUserId, true);
    }
    return { ok: false, error: "invalid_finalize_response", requestId };
  }

  return {
    ok: true,
    requestId,
    organizationId: finalizeRow.organization_id,
    ownerAppUserId: finalizeRow.owner_app_user_id,
    authUserId: finalizeRow.auth_user_id,
    ownerEmail: normalizedEmail,
    resumed,
  };
}
