/** Mirrors src/lib/rate-limit/policy.ts for Node smoke tests. Keep in sync with contract doc. */
export const RATE_LIMIT_POLICIES = {
  "auth.sign_in.ip": { maxAttempts: 30, windowSeconds: 15 * 60 },
  "auth.sign_in.account": { maxAttempts: 15, windowSeconds: 15 * 60 },
  "auth.password_reset.ip": { maxAttempts: 8, windowSeconds: 60 * 60 },
  "auth.update_password.user": { maxAttempts: 12, windowSeconds: 60 * 60 },
  "staff.provision.org": { maxAttempts: 25, windowSeconds: 60 * 60 },
  "staff.lifecycle.org_actor": { maxAttempts: 80, windowSeconds: 15 * 60 },
  "onboarding.complete_center_setup.user": { maxAttempts: 15, windowSeconds: 60 * 60 },
};
