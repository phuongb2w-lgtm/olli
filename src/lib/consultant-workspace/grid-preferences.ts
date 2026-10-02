export type ConsultantGridColumnId =
  | "stt"
  | "family_name"
  | "given_name"
  | "date_of_birth"
  | "student_code"
  | "personal_identification_number"
  | "lifecycle_status"
  | "guardian_name"
  | "guardian_phone"
  | "tuition"
  | "details"
  | "edit";

export type ConsultantGridPreferences = {
  columnVisibility?: Record<string, boolean>;
  columnSizing?: Record<string, number>;
  columnOrder?: string[];
};

export const DEFAULT_COLUMN_ORDER: ConsultantGridColumnId[] = [
  "stt",
  "family_name",
  "given_name",
  "date_of_birth",
  "student_code",
  "personal_identification_number",
  "lifecycle_status",
  "guardian_name",
  "guardian_phone",
  "tuition",
  "details",
  "edit",
];

/**
 * Intake-critical columns: always visible so inline Lưu captures DOB/names.
 * Other columns (guardian, tuition, PIN, etc.) remain user-toggleable.
 */
export const PROTECTED_VISIBILITY_COLUMNS = new Set<string>([
  "stt",
  "family_name",
  "given_name",
  "date_of_birth",
  "edit",
]);

/** Default-on columns for new users; still hideable except PROTECTED set. */
export const INTAKE_DEFAULT_VISIBLE_COLUMNS = new Set<string>([
  "student_code",
  "lifecycle_status",
  "guardian_name",
  "guardian_phone",
  "tuition",
  "details",
]);

export const DEFAULT_COLUMN_VISIBILITY: Record<string, boolean> = {
  personal_identification_number: false,
  date_of_birth: true,
  student_code: true,
};

export const DEFAULT_COLUMN_WIDTHS: Record<string, number> = {
  stt: 72,
  family_name: 172,
  given_name: 120,
  date_of_birth: 128,
  student_code: 120,
  personal_identification_number: 140,
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
  const visibility: Record<string, boolean> = {
    ...DEFAULT_COLUMN_VISIBILITY,
    ...stored?.columnVisibility,
  };
  for (const key of PROTECTED_VISIBILITY_COLUMNS) {
    visibility[key] = true;
  }
  for (const key of INTAKE_DEFAULT_VISIBLE_COLUMNS) {
    if (visibility[key] === undefined) visibility[key] = true;
  }
  if (visibility.personal_identification_number === undefined) {
    visibility.personal_identification_number = false;
  }
  return {
    columnVisibility: visibility,
    columnSizing: { ...DEFAULT_COLUMN_WIDTHS, ...stored?.columnSizing },
    columnOrder: stored?.columnOrder,
  };
}

export function buildConsultantColumnOrder(
  customFieldKeys: string[],
  storedOrder?: string[] | null,
): string[] {
  const customIds = customFieldKeys.map((k) => `custom_${k}`);
  const canonical = [
    ...DEFAULT_COLUMN_ORDER.filter((id) => id !== "details" && id !== "edit"),
    ...customIds,
    "details",
    "edit",
  ];
  if (!storedOrder?.length) return canonical;
  const known = new Set(canonical);
  const ordered = storedOrder.filter((id) => known.has(id));
  for (const id of canonical) {
    if (!ordered.includes(id)) ordered.push(id);
  }
  return ordered;
}
