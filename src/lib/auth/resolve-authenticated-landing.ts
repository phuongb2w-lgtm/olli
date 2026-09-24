import {
  COMMERCIAL_ACCESS_PATH,
  ONBOARDING_PATH,
  SUBSCRIPTION_STATUS_PATH,
} from "@/lib/auth/commercial-access-paths";
import type { SessionCommercialAccess } from "@/lib/auth/session-commercial-access";

/** UX-only: Primary Owner must finish onboarding before other restricted surfaces. */
export function sessionRequiresOnboardingRedirect(
  sessionAccess: SessionCommercialAccess,
): boolean {
  return sessionAccess.requires_center_setup === true;
}

/** Post-login and layout-adjacent UX routing (not authorization). */
export function resolveAuthenticatedLandingPath(
  sessionAccess: SessionCommercialAccess,
): string {
  if (sessionRequiresOnboardingRedirect(sessionAccess)) {
    return ONBOARDING_PATH;
  }

  if (sessionAccess.allows_normal_use === false) {
    return sessionAccess.is_primary_owner === true
      ? SUBSCRIPTION_STATUS_PATH
      : COMMERCIAL_ACCESS_PATH;
  }

  return "/";
}
