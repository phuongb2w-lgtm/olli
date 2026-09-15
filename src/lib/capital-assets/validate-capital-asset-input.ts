import {
  CAPITAL_ASSET_CATEGORIES,
  type CapitalAssetCategory,
} from "@/lib/capital-assets/constants";

export type DetailedCapitalAssetInput = {
  name: string;
  originalCost: number;
  usefulLifeMonths: number;
  placedInServiceDate: string;
  categoryCode?: CapitalAssetCategory | null;
  notes?: string | null;
};

export type QuickCapitalAssetInput = {
  totalInvestment: number;
  usefulLifeMonths: number;
  placedInServiceDate: string;
  name?: string;
};

export type ValidatedDetailedCapitalAsset = {
  name: string;
  originalCost: number;
  usefulLifeMonths: number;
  placedInServiceDate: string;
  categoryCode: CapitalAssetCategory | null;
  notes: string | null;
};

export type ValidatedQuickCapitalAsset = {
  totalInvestment: number;
  usefulLifeMonths: number;
  placedInServiceDate: string;
  name: string;
};

type ValidationFailure = { ok: false; fieldErrors: Record<string, string> };

export type DetailedValidationResult =
  | { ok: true; data: ValidatedDetailedCapitalAsset }
  | ValidationFailure;

export type QuickValidationResult =
  | { ok: true; data: ValidatedQuickCapitalAsset }
  | ValidationFailure;

function parsePositiveInt(value: unknown): number | null {
  const n = typeof value === "number" ? value : Number(String(value ?? "").trim());
  if (!Number.isFinite(n) || !Number.isInteger(n) || n <= 0) return null;
  return n;
}

function parseIsoDate(value: unknown): string | null {
  const s = String(value ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const d = new Date(`${s}T00:00:00`);
  if (Number.isNaN(d.getTime())) return null;
  return s;
}

export function validateDetailedCapitalAssetInput(
  input: DetailedCapitalAssetInput,
): DetailedValidationResult {
  const fieldErrors: Record<string, string> = {};
  const name = input.name.trim();
  if (!name) fieldErrors.name = "required";

  const originalCost = parsePositiveInt(input.originalCost);
  if (originalCost === null) fieldErrors.originalCost = "invalid";

  const usefulLifeMonths = parsePositiveInt(input.usefulLifeMonths);
  if (usefulLifeMonths === null) fieldErrors.usefulLifeMonths = "invalid";

  const placedInServiceDate = parseIsoDate(input.placedInServiceDate);
  if (!placedInServiceDate) fieldErrors.placedInServiceDate = "invalid";

  if (
    input.categoryCode &&
    !CAPITAL_ASSET_CATEGORIES.includes(input.categoryCode as CapitalAssetCategory)
  ) {
    fieldErrors.categoryCode = "invalid";
  }

  if (
    Object.keys(fieldErrors).length > 0 ||
    originalCost === null ||
    usefulLifeMonths === null ||
    !placedInServiceDate
  ) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: {
      name,
      originalCost,
      usefulLifeMonths,
      placedInServiceDate,
      categoryCode: input.categoryCode ?? null,
      notes: input.notes?.trim() || null,
    },
  };
}

export function validateQuickCapitalAssetInput(
  input: QuickCapitalAssetInput,
): QuickValidationResult {
  const fieldErrors: Record<string, string> = {};

  const totalInvestment = parsePositiveInt(input.totalInvestment);
  if (totalInvestment === null) fieldErrors.totalInvestment = "invalid";

  const usefulLifeMonths = parsePositiveInt(input.usefulLifeMonths);
  if (usefulLifeMonths === null) fieldErrors.usefulLifeMonths = "invalid";

  const placedInServiceDate = parseIsoDate(input.placedInServiceDate);
  if (!placedInServiceDate) fieldErrors.placedInServiceDate = "invalid";

  if (
    Object.keys(fieldErrors).length > 0 ||
    totalInvestment === null ||
    usefulLifeMonths === null ||
    !placedInServiceDate
  ) {
    return { ok: false, fieldErrors };
  }

  return {
    ok: true,
    data: {
      totalInvestment,
      usefulLifeMonths,
      placedInServiceDate,
      name: input.name?.trim() || "Initial setup investment",
    },
  };
}
