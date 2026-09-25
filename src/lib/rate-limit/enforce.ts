import "server-only";

import { createAdminClient } from "@/lib/supabase/admin";
import {
  buildRateLimitBucketKey,
  hashRateLimitSubject,
  normalizeEmailForRateLimit,
} from "@/lib/rate-limit/fingerprint";
import {
  RATE_LIMIT_POLICIES,
  type RateLimitActionId,
  type RateLimitPolicy,
} from "@/lib/rate-limit/policy";
import { getTrustedClientIpFingerprint } from "@/lib/rate-limit/request-ip";

export type RateLimitDecision = {
  allowed: boolean;
  retryAfterSeconds?: number;
};

type ConsumeResult = {
  allowed?: boolean;
  retry_after_seconds?: number | null;
};

function logRateLimitEvent(payload: {
  actionId: RateLimitActionId;
  allowed: boolean;
  infrastructureFailure?: boolean;
}): void {
  if (process.env.NODE_ENV === "test") {
    return;
  }
  console.info(
    JSON.stringify({
      category: "rate_limit",
      action: payload.actionId,
      allowed: payload.allowed,
      infrastructure_failure: payload.infrastructureFailure === true,
    }),
  );
}

function isRateLimitEnforcementDisabled(): boolean {
  return process.env.OLLI_RATE_LIMIT_DISABLED === "1";
}

async function consumePolicy(
  policy: RateLimitPolicy,
  subject: string,
): Promise<RateLimitDecision> {
  if (isRateLimitEnforcementDisabled()) {
    return { allowed: true };
  }

  const bucketKey = buildRateLimitBucketKey(policy.actionId, subject);
  try {
    const admin = createAdminClient();
    const { data, error } = await admin.rpc("consume_app_rate_limit", {
      p_bucket_key: bucketKey,
      p_max_attempts: policy.maxAttempts,
      p_window_seconds: policy.windowSeconds,
    });

    if (error || !data || typeof data !== "object" || Array.isArray(data)) {
      logRateLimitEvent({
        actionId: policy.actionId,
        allowed: !policy.failClosed,
        infrastructureFailure: true,
      });
      return { allowed: !policy.failClosed };
    }

    const parsed = data as ConsumeResult;
    const allowed = parsed.allowed === true;
    const retryAfterSeconds =
      typeof parsed.retry_after_seconds === "number" ? parsed.retry_after_seconds : undefined;

    logRateLimitEvent({ actionId: policy.actionId, allowed });
    return allowed ? { allowed: true } : { allowed: false, retryAfterSeconds };
  } catch {
    logRateLimitEvent({
      actionId: policy.actionId,
      allowed: !policy.failClosed,
      infrastructureFailure: true,
    });
    return { allowed: !policy.failClosed };
  }
}

function mergeDecisions(decisions: RateLimitDecision[]): RateLimitDecision {
  const blocked = decisions.filter((d) => !d.allowed);
  if (blocked.length === 0) {
    return { allowed: true };
  }
  const retryAfterSeconds = blocked.reduce<number | undefined>((max, d) => {
    if (d.retryAfterSeconds === undefined) {
      return max;
    }
    if (max === undefined) {
      return d.retryAfterSeconds;
    }
    return Math.max(max, d.retryAfterSeconds);
  }, undefined);
  return { allowed: false, retryAfterSeconds };
}

export async function enforceRateLimits(
  checks: { actionId: RateLimitActionId; subject: string }[],
): Promise<RateLimitDecision> {
  const decisions: RateLimitDecision[] = [];
  for (const check of checks) {
    const policy = RATE_LIMIT_POLICIES[check.actionId];
    decisions.push(await consumePolicy(policy, check.subject));
  }
  return mergeDecisions(decisions);
}

export async function enforceSignInRateLimit(email: string): Promise<RateLimitDecision> {
  const ipSubject = await getTrustedClientIpFingerprint();
  const accountSubject = hashRateLimitSubject(
    normalizeEmailForRateLimit(email) || "account:empty",
  );
  return enforceRateLimits([
    { actionId: "auth.sign_in.ip", subject: ipSubject },
    { actionId: "auth.sign_in.account", subject: accountSubject },
  ]);
}

export async function enforcePasswordResetRateLimit(): Promise<RateLimitDecision> {
  const ipSubject = await getTrustedClientIpFingerprint();
  return enforceRateLimits([{ actionId: "auth.password_reset.ip", subject: ipSubject }]);
}

export async function enforceUpdatePasswordRateLimit(authUserId: string): Promise<RateLimitDecision> {
  return enforceRateLimits([
    {
      actionId: "auth.update_password.user",
      subject: hashRateLimitSubject(`auth:${authUserId}`),
    },
  ]);
}

export async function enforceStaffProvisionRateLimit(input: {
  organizationId: string;
  actorAppUserId: string;
}): Promise<RateLimitDecision> {
  return enforceRateLimits([
    {
      actionId: "staff.provision.org",
      subject: hashRateLimitSubject(`org:${input.organizationId}:actor:${input.actorAppUserId}`),
    },
  ]);
}

export async function enforceStaffLifecycleRateLimit(input: {
  organizationId: string;
  actorAppUserId: string;
}): Promise<RateLimitDecision> {
  return enforceRateLimits([
    {
      actionId: "staff.lifecycle.org_actor",
      subject: hashRateLimitSubject(`org:${input.organizationId}:actor:${input.actorAppUserId}`),
    },
  ]);
}

export async function enforceCompleteCenterSetupRateLimit(appUserId: string): Promise<RateLimitDecision> {
  return enforceRateLimits([
    {
      actionId: "onboarding.complete_center_setup.user",
      subject: hashRateLimitSubject(`app_user:${appUserId}`),
    },
  ]);
}
