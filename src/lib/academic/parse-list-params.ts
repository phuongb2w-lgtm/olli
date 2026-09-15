import { CLASS_STATUSES, PAGE_SIZES, type PageSize } from "@/lib/academic/constants";

const MIN_SEARCH_LENGTH = 2;

export type ClassListStatusFilter = "all" | (typeof CLASS_STATUSES)[number];

export type ClassListParams = {
  q: string;
  status: ClassListStatusFilter;
  course: string;
  page: number;
  pageSize: PageSize;
};

export type CourseListParams = {
  page: number;
  pageSize: PageSize;
};

export function isSearchActive(q: string): boolean {
  return q.trim().length >= MIN_SEARCH_LENGTH;
}

export function parseClassListParams(
  raw: Record<string, string | string[] | undefined>,
): ClassListParams {
  const q = pickString(raw.q).trim();

  const statusRaw = pickString(raw.status);
  const status: ClassListStatusFilter = CLASS_STATUSES.includes(
    statusRaw as (typeof CLASS_STATUSES)[number],
  )
    ? (statusRaw as ClassListStatusFilter)
    : "all";

  const course = pickString(raw.course).trim();

  const pageSizeRaw = Number.parseInt(pickString(raw.pageSize), 10);
  const pageSize: PageSize = PAGE_SIZES.includes(pageSizeRaw as PageSize)
    ? (pageSizeRaw as PageSize)
    : 25;

  const pageRaw = Number.parseInt(pickString(raw.page), 10);
  const page = Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : 1;

  return { q, status, course, page, pageSize };
}

export function parseCourseListParams(
  raw: Record<string, string | string[] | undefined>,
): CourseListParams {
  const pageSizeRaw = Number.parseInt(pickString(raw.pageSize), 10);
  const pageSize: PageSize = PAGE_SIZES.includes(pageSizeRaw as PageSize)
    ? (pageSizeRaw as PageSize)
    : 25;

  const pageRaw = Number.parseInt(pickString(raw.page), 10);
  const page = Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : 1;

  return { page, pageSize };
}

export function clampPage(page: number, totalCount: number, pageSize: number): number {
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));
  return Math.min(Math.max(1, page), totalPages);
}

function pickString(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}
