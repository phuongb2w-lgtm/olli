import {
  DEFAULT_LEAD_PAGE_SIZE,
  LEAD_LIST_STATUSES,
  LEAD_OWNERSHIP_FILTERS,
  type LeadListStatus,
  type LeadOwnershipFilter,
} from "@/lib/leads/constants";

export type LeadListParams = {
  q: string;
  status: LeadListStatus;
  owner: LeadOwnershipFilter;
  ownerUserId: string | null;
  page: number;
  pageSize: number;
};

function firstString(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}

function parsePositiveInt(raw: string, fallback: number): number {
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return parsed;
}

export function parseLeadListParams(
  raw: Record<string, string | string[] | undefined>,
): LeadListParams {
  const q = firstString(raw.q).trim();
  const statusRaw = firstString(raw.status);
  const status = (LEAD_LIST_STATUSES as readonly string[]).includes(statusRaw)
    ? (statusRaw as LeadListStatus)
    : "all";
  const ownerRaw = firstString(raw.owner);
  const owner = (LEAD_OWNERSHIP_FILTERS as readonly string[]).includes(ownerRaw)
    ? (ownerRaw as LeadOwnershipFilter)
    : "all";
  const ownerUserIdRaw = firstString(raw.ownerUserId).trim();
  const ownerUserId = owner === "user" && ownerUserIdRaw ? ownerUserIdRaw : null;
  const page = parsePositiveInt(firstString(raw.page), 1);
  const pageSize = Math.min(
    100,
    parsePositiveInt(firstString(raw.pageSize), DEFAULT_LEAD_PAGE_SIZE),
  );

  return { q, status, owner, ownerUserId, page, pageSize };
}

export function clampPage(page: number, totalCount: number, pageSize: number): number {
  if (totalCount === 0) return 1;
  const maxPage = Math.max(1, Math.ceil(totalCount / pageSize));
  return Math.min(Math.max(1, page), maxPage);
}

export function isLeadSearchActive(q: string): boolean {
  return q.trim().length >= 2;
}
