import "server-only";

/** Centralized rate-limit policy (windows, limits, failure mode). See docs/m8/16-rate-limit-abuse-contract.md */
export type RateLimitActionId =
  | "auth.sign_in.ip"
  | "auth.sign_in.account"
  | "auth.password_reset.ip"
  | "auth.update_password.user"
  | "staff.provision.org"
  | "staff.lifecycle.org_actor"
  | "onboarding.complete_center_setup.user";

export type RateLimitPolicy = {
  actionId: RateLimitActionId;
  maxAttempts: number;
  windowSeconds: number;
  /** When limiter infrastructure fails, block (true) or allow the underlying operation (false). */
  failClosed: boolean;
};

export const RATE_LIMIT_POLICIES: Record<RateLimitActionId, RateLimitPolicy> = {
  "auth.sign_in.ip": {
    actionId: "auth.sign_in.ip",
    maxAttempts: 30,
    windowSeconds: 15 * 60,
    failClosed: false,
  },
  "auth.sign_in.account": {
    actionId: "auth.sign_in.account",
    maxAttempts: 15,
    windowSeconds: 15 * 60,
    failClosed: false,
  },
  "auth.password_reset.ip": {
    actionId: "auth.password_reset.ip",
    maxAttempts: 8,
    windowSeconds: 60 * 60,
    failClosed: true,
  },
  "auth.update_password.user": {
    actionId: "auth.update_password.user",
    maxAttempts: 12,
    windowSeconds: 60 * 60,
    failClosed: false,
  },
  "staff.provision.org": {
    actionId: "staff.provision.org",
    maxAttempts: 25,
    windowSeconds: 60 * 60,
    failClosed: true,
  },
  "staff.lifecycle.org_actor": {
    actionId: "staff.lifecycle.org_actor",
    maxAttempts: 80,
    windowSeconds: 15 * 60,
    failClosed: true,
  },
  "onboarding.complete_center_setup.user": {
    actionId: "onboarding.complete_center_setup.user",
    maxAttempts: 15,
    windowSeconds: 60 * 60,
    failClosed: false,
  },
};
