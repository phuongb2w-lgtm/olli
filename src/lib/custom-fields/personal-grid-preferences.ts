export type PersonalGridSurfaceKey = "students" | "finance_students";

export type PersonalGridPreferences = {
  columnVisibility: Record<string, boolean>;
  columnSizing: Record<string, number>;
  columnOrder: string[];
};

export const PERSONAL_COLUMN_PREFIX = "custom_";
export const PERSONAL_COLUMN_DEFAULT_WIDTH = 160;
export const PERSONAL_COLUMN_MIN_WIDTH = 80;
export const PERSONAL_COLUMN_MAX_WIDTH = 480;

export const EMPTY_PERSONAL_GRID_PREFERENCES: PersonalGridPreferences = {
  columnVisibility: {},
  columnSizing: {},
  columnOrder: [],
};

export function personalColumnId(fieldKey: string): string {
  return `${PERSONAL_COLUMN_PREFIX}${fieldKey}`;
}

export function clampPersonalColumnWidth(width: number): number {
  if (!Number.isFinite(width)) return PERSONAL_COLUMN_DEFAULT_WIDTH;
  return Math.min(PERSONAL_COLUMN_MAX_WIDTH, Math.max(PERSONAL_COLUMN_MIN_WIDTH, Math.round(width)));
}

export function normalizePersonalGridPreferences(raw: unknown): PersonalGridPreferences {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { ...EMPTY_PERSONAL_GRID_PREFERENCES };
  }
  const value = raw as Record<string, unknown>;
  const columnVisibility: Record<string, boolean> = {};
  if (value.columnVisibility && typeof value.columnVisibility === "object") {
    for (const [k, v] of Object.entries(value.columnVisibility as Record<string, unknown>)) {
      if (typeof v === "boolean") columnVisibility[k] = v;
    }
  }
  const columnSizing: Record<string, number> = {};
  if (value.columnSizing && typeof value.columnSizing === "object") {
    for (const [k, v] of Object.entries(value.columnSizing as Record<string, unknown>)) {
      if (typeof v === "number" && Number.isFinite(v)) columnSizing[k] = clampPersonalColumnWidth(v);
    }
  }
  const columnOrder = Array.isArray(value.columnOrder)
    ? value.columnOrder.filter((v): v is string => typeof v === "string")
    : [];
  return { columnVisibility, columnSizing, columnOrder };
}

/** Stored order first (known ids only), then any new columns in definition order. */
export function buildPersonalColumnOrder(fieldKeys: string[], storedOrder?: string[] | null): string[] {
  const ids = fieldKeys.map(personalColumnId);
  const known = new Set(ids);
  const ordered = (storedOrder ?? []).filter((id) => known.has(id));
  for (const id of ids) {
    if (!ordered.includes(id)) ordered.push(id);
  }
  return ordered;
}

export function movePersonalColumn(order: string[], colId: string, direction: -1 | 1): string[] {
  const next = [...order];
  const idx = next.indexOf(colId);
  const swap = idx + direction;
  if (idx < 0 || swap < 0 || swap >= next.length) return next;
  [next[idx], next[swap]] = [next[swap]!, next[idx]!];
  return next;
}
