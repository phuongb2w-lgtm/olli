import {
  STUDENT_PAGE_SIZES,
  STUDENT_STATUSES,
  type StudentListParams,
  type StudentListStatusFilter,
  type StudentPageSize,
} from "@/lib/students/types";

const MIN_SEARCH_LENGTH = 2;

export function isSearchActive(q: string): boolean {
  return q.trim().length >= MIN_SEARCH_LENGTH;
}

export function parseStudentListParams(
  raw: Record<string, string | string[] | undefined>,
): StudentListParams {
  const q = pickString(raw.q).trim();

  const statusRaw = pickString(raw.status);
  const status: StudentListStatusFilter = STUDENT_STATUSES.includes(
    statusRaw as (typeof STUDENT_STATUSES)[number],
  )
    ? (statusRaw as StudentListStatusFilter)
    : "all";

  const pageSizeRaw = Number.parseInt(pickString(raw.pageSize), 10);
  const pageSize: StudentPageSize = STUDENT_PAGE_SIZES.includes(
    pageSizeRaw as StudentPageSize,
  )
    ? (pageSizeRaw as StudentPageSize)
    : 25;

  const pageRaw = Number.parseInt(pickString(raw.page), 10);
  const page = Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : 1;

  return { q, status, page, pageSize };
}

export function clampPage(page: number, totalCount: number, pageSize: number): number {
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));
  return Math.min(Math.max(1, page), totalPages);
}

function pickString(value: string | string[] | undefined): string {
  if (Array.isArray(value)) {
    return value[0] ?? "";
  }
  return value ?? "";
}
