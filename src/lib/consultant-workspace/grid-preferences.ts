export type ConsultantGridColumnId =
  | "stt"
  | "family_name"
  | "given_name"
  | "student_code"
  | "lifecycle_status"
  | "guardian_name"
  | "guardian_phone"
  | "tuition"
  | "details"
  | "edit";

export type ConsultantGridPreferences = {
  columnVisibility?: Record<string, boolean>;
  columnSizing?: Record<string, number>;
};

export const DEFAULT_COLUMN_ORDER: ConsultantGridColumnId[] = [
  "stt",
  "family_name",
  "given_name",
  "student_code",
  "lifecycle_status",
  "guardian_name",
  "guardian_phone",
  "tuition",
  "details",
  "edit",
];

export const PROTECTED_VISIBILITY_COLUMNS = new Set<ConsultantGridColumnId>([
  "stt",
  "details",
  "edit",
]);

export const DEFAULT_COLUMN_WIDTHS: Record<string, number> = {
  stt: 72,
  family_name: 140,
  given_name: 120,
  student_code: 120,
  lifecycle_status: 120,
  guardian_name: 140,
  guardian_phone: 120,
  tuition: 160,
  details: 96,
  edit: 96,
};

export function mergeGridPreferences(
  stored: ConsultantGridPreferences | null | undefined,
): ConsultantGridPreferences {
  return {
    columnVisibility: { ...stored?.columnVisibility },
    columnSizing: { ...DEFAULT_COLUMN_WIDTHS, ...stored?.columnSizing },
  };
}
