import type { Locale } from "@/i18n/config";

/** Presentation-only; does not mutate stored canonical names. */
export function formatPortfolioNamePart(value: string | null, locale: Locale): string {
  if (!value) return "—";
  const trimmed = value.trim();
  if (!trimmed) return "—";
  if (locale === "vi") {
    return trimmed.toLocaleUpperCase("vi-VN");
  }
  return trimmed;
}

export function detailsHref(row: {
  subject_type: "lead" | "student";
  lead_id: string | null;
  student_id: string | null;
  student_details_subject_id: string | null;
}): string | null {
  if (row.subject_type === "student" && row.student_details_subject_id) {
    return `/students/${row.student_details_subject_id}/enrollments`;
  }
  if (row.lead_id) {
    return `/crm/leads/${row.lead_id}`;
  }
  return null;
}
