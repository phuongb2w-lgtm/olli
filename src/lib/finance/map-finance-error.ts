export type FinanceErrorCode =
  | "permission_denied"
  | "validation_error"
  | "save_error"
  | "not_found"
  | "allocation_exceeds_outstanding"
  | "schedule_total_mismatch"
  | "terms_already_active"
  | "asset_history_locked"
  | "scenario_finalized";

const PG_MESSAGE_MAP: Record<string, FinanceErrorCode> = {
  permission_denied: "permission_denied",
  allocation_exceeds_outstanding: "allocation_exceeds_outstanding",
  schedule_total_mismatch: "schedule_total_mismatch",
  terms_already_active: "terms_already_active",
  asset_history_locked: "asset_history_locked",
  scenario_finalized: "scenario_finalized",
  enrollment_not_found: "not_found",
  payment_not_found: "not_found",
};

export function mapPgErrorMessage(message: string | undefined): FinanceErrorCode | null {
  if (!message) return null;
  for (const [key, code] of Object.entries(PG_MESSAGE_MAP)) {
    if (message.includes(key)) return code;
  }
  return null;
}
