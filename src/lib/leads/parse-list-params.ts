import {
  DEFAULT_LEAD_PAGE_SIZE,
  LEAD_IDENTITY_FILTERS,
  LEAD_LIST_STATUSES,
  LEAD_OWNERSHIP_FILTERS,
  LEAD_TRIAL_FILTERS,
  LEAD_WORKLIST_PRESETS,
  type LeadIdentityFilter,
  type LeadListStatus,
  type LeadOwnershipFilter,
  type LeadTrialFilter,
  type LeadWorklistPreset,
} from "@/lib/leads/constants";

export type LeadListParams = {
  q: string;
  status: LeadListStatus;
  owner: LeadOwnershipFilter;
  ownerUserId: string | null;
  trial: LeadTrialFilter;
  sourceId: string | null;
  campaignId: string | null;
  preset: LeadWorklistPreset;
  identity: LeadIdentityFilter;
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
  const trialRaw = firstString(raw.trial);
  const trial = (LEAD_TRIAL_FILTERS as readonly string[]).includes(trialRaw)
    ? (trialRaw as LeadTrialFilter)
    : "all";
  const page = parsePositiveInt(firstString(raw.page), 1);
  const pageSize = Math.min(
    100,
    parsePositiveInt(firstString(raw.pageSize), DEFAULT_LEAD_PAGE_SIZE),
  );
  const sourceIdRaw = firstString(raw.sourceId).trim();
  const sourceId =
    sourceIdRaw === "all" || !sourceIdRaw
      ? null
      : sourceIdRaw === "unattributed"
        ? "unattributed"
        : sourceIdRaw;
  const campaignIdRaw = firstString(raw.campaignId).trim();
  const campaignId =
    campaignIdRaw === "all" || !campaignIdRaw
      ? null
      : campaignIdRaw === "unattributed"
        ? "unattributed"
        : campaignIdRaw;
  const presetRaw = firstString(raw.preset);
  const preset = (LEAD_WORKLIST_PRESETS as readonly string[]).includes(presetRaw)
    ? (presetRaw as LeadWorklistPreset)
    : "all";
  const identityRaw = firstString(raw.identity);
  const identity = (LEAD_IDENTITY_FILTERS as readonly string[]).includes(identityRaw)
    ? (identityRaw as LeadIdentityFilter)
    : "all";

  let resolvedOwner = owner;
  let resolvedTrial = trial;
  let resolvedIdentity = identity;
  if (preset === "my") resolvedOwner = "me";
  if (preset === "unassigned") resolvedOwner = "unassigned";
  if (preset === "trial_scheduled") resolvedTrial = "scheduled";
  if (preset === "identity_unresolved") resolvedIdentity = "unresolved";
  if (preset === "ready_to_convert") resolvedIdentity = "ready";

  return {
    q,
    status,
    owner: resolvedOwner,
    ownerUserId,
    trial: resolvedTrial,
    sourceId,
    campaignId,
    preset,
    identity: resolvedIdentity,
    page,
    pageSize,
  };
}

export function clampPage(page: number, totalCount: number, pageSize: number): number {
  if (totalCount === 0) return 1;
  const maxPage = Math.max(1, Math.ceil(totalCount / pageSize));
  return Math.min(Math.max(1, page), maxPage);
}

export function isLeadSearchActive(q: string): boolean {
  return q.trim().length >= 2;
}
