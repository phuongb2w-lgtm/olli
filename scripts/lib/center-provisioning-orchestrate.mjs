/**
 * Trusted center provisioning orchestration (service_role + Auth Admin).
 * Mirrors src/lib/center-provisioning/orchestrate.ts for Node CLI/smoke scripts.
 */

import { createClient } from "@supabase/supabase-js";

export const CENTER_PROVISIONING_METADATA_KEY = "olli_center_provisioning_request_id";

function isCompleted(row) {
  return (
    row.status === "completed" &&
    row.organization_id &&
    row.owner_app_user_id &&
    row.auth_user_id
  );
}

async function compensateAuthUser(admin, requestId, authUserId, authCreatedByThisRequest) {
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

async function ensureAuthUserForCenterRequest(admin, row, normalizedEmail) {
  const requestId = row.request_id;

  if (row.auth_user_id) {
    return { authUserId: row.auth_user_id, created: false };
  }

  const metadata = { [CENTER_PROVISIONING_METADATA_KEY]: requestId };
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

  const authUserId = data.user?.id;
  if (!authUserId) {
    return { ok: false, error: "auth_provisioning_failed", requestId };
  }

  return { authUserId, created: true };
}

export async function orchestrateCustomerCenterProvisioning(admin, input) {
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

  const beginRow = beginData;
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
  if (authResult.ok === false) {
    return authResult;
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

  const { data: finalizeData, error: finalizeError } = await admin.rpc("finalize_center_provisioning", {
    p_request_id: requestId,
  });

  if (finalizeError) {
    if (created) {
      await compensateAuthUser(admin, requestId, authUserId, true);
    }
    return { ok: false, error: finalizeError.message, requestId };
  }

  const finalizeRow = finalizeData;
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

export function adminClientFromEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.API_URL;
  const key = process.env.SUPABASE_SECRET_KEY ?? process.env.SECRET_KEY;
  if (!url || !key) {
    throw new Error("Missing Supabase URL or SUPABASE_SECRET_KEY / SECRET_KEY");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
