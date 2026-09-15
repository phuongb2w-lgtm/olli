export const CAPITAL_ASSET_STATUSES = ["active", "retired"] as const;
export type CapitalAssetStatus = (typeof CAPITAL_ASSET_STATUSES)[number];

export const CAPITAL_ASSET_CATEGORIES = [
  "fit_out",
  "signage",
  "furniture",
  "equipment",
  "technology",
  "other_capital",
] as const;
export type CapitalAssetCategory = (typeof CAPITAL_ASSET_CATEGORIES)[number];

export const DEPRECIATION_METHODS = ["straight_line"] as const;
export type DepreciationMethod = (typeof DEPRECIATION_METHODS)[number];

export const DEPRECIATION_ENTRY_STATUSES = ["scheduled", "posted", "void"] as const;
export type DepreciationEntryStatus = (typeof DEPRECIATION_ENTRY_STATUSES)[number];

export const COST_DOMAIN_CAPITAL = "capital" as const;
