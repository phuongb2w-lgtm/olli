"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAppUser } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export type ExecutiveFollowUpActionState = {
  error?: "permission_denied" | "save_error" | "invalid_input";
  success?: string;
};

function revalidateExecutiveExceptionPaths() {
  revalidatePath("/executive");
  revalidatePath("/executive/exceptions");
}

export async function saveExecutiveExceptionFollowUpAction(
  _prev: ExecutiveFollowUpActionState,
  formData: FormData,
): Promise<ExecutiveFollowUpActionState> {
  const user = await getCurrentAppUser();
  if (!user || !(await can("report.executive.follow_up.manage"))) {
    return { error: "permission_denied" };
  }

  const exceptionKey = String(formData.get("exceptionKey") ?? "").trim();
  const domain = String(formData.get("domain") ?? "").trim();
  const exceptionCode = String(formData.get("exceptionCode") ?? "").trim();
  const entityType = String(formData.get("entityType") ?? "").trim();
  const entityId = String(formData.get("entityId") ?? "").trim();
  const status = String(formData.get("status") ?? "").trim();
  const note = String(formData.get("note") ?? "").trim();

  if (!exceptionKey || !domain || !exceptionCode || !entityType || !entityId) {
    return { error: "invalid_input" };
  }

  const allowedStatuses = ["open", "acknowledged", "resolved", "dismissed"] as const;
  type FollowUpStatus = (typeof allowedStatuses)[number];
  let followUpStatus: FollowUpStatus | undefined;
  if (status) {
    if (!allowedStatuses.includes(status as FollowUpStatus)) {
      return { error: "invalid_input" };
    }
    followUpStatus = status as FollowUpStatus;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("save_executive_exception_follow_up", {
    p_exception_key: exceptionKey,
    p_domain: domain,
    p_exception_code: exceptionCode,
    p_entity_type: entityType,
    p_entity_id: entityId,
    p_status: followUpStatus,
    p_note: note || undefined,
  });

  if (error) {
    return { error: "save_error" };
  }

  revalidateExecutiveExceptionPaths();
  return { success: "follow_up_saved" };
}
