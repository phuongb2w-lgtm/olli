export type CompleteCenterSetupErrorCode =
  | "not_primary_owner"
  | "setup_already_complete"
  | "commercial_access_restricted"
  | "invalid_organization_name"
  | "invalid_default_locale"
  | "invalid_timezone"
  | "invalid_preferred_locale"
  | "unknown";

export function mapCompleteCenterSetupError(
  message: string | undefined,
): CompleteCenterSetupErrorCode {
  const normalized = (message ?? "").toLowerCase();
  if (normalized.includes("not_primary_owner")) return "not_primary_owner";
  if (normalized.includes("setup_already_complete")) return "setup_already_complete";
  if (normalized.includes("commercial_access_restricted")) return "commercial_access_restricted";
  if (normalized.includes("invalid_organization_name")) return "invalid_organization_name";
  if (normalized.includes("invalid_default_locale")) return "invalid_default_locale";
  if (normalized.includes("invalid_timezone")) return "invalid_timezone";
  if (normalized.includes("invalid_preferred_locale")) return "invalid_preferred_locale";
  return "unknown";
}
