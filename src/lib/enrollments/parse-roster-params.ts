import {
  ENROLLMENT_STATUSES,
  PAGE_SIZES,
  ROSTER_STATUS_FILTERS,
  type PageSize,
  type RosterStatusFilter,
} from "@/lib/enrollments/constants";

export type RosterListParams = {
  q: string;
  status: RosterStatusFilter;
  page: number;
  pageSize: PageSize;
};

const MIN_SEARCH_LENGTH = 2;

export function isRosterSearchActive(q: string): boolean {
  return q.trim().length >= MIN_SEARCH_LENGTH;
}

export function parseRosterListParams(
  raw: Record<string, string | string[] | undefined>,
): RosterListParams {
  const q = pickString(raw.q).trim();

  const statusRaw = pickString(raw.status);
  const status: RosterStatusFilter = ROSTER_STATUS_FILTERS.includes(
    statusRaw as RosterStatusFilter,
  )
    ? (statusRaw as RosterStatusFilter)
    : "operational";

  const pageSizeRaw = Number.parseInt(pickString(raw.pageSize), 10);
  const pageSize: PageSize = PAGE_SIZES.includes(pageSizeRaw as PageSize)
    ? (pageSizeRaw as PageSize)
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
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}

export function statusFilterToDbStatuses(
  filter: RosterStatusFilter,
): string[] | null {
  if (filter === "all") return null;
  if (filter === "operational") return ["pending", "active"];
  if (ENROLLMENT_STATUSES.includes(filter as (typeof ENROLLMENT_STATUSES)[number])) {
    return [filter];
  }
  return ["pending", "active"];
}
