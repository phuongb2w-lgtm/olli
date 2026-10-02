"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";
import {
  loadPersonalGridPreferencesAction,
  savePersonalGridPreferencesAction,
} from "@/app/actions/personal-grid-preferences";
import { PersonalColumnToolbar } from "@/components/custom-fields/personal-column-toolbar";
import { PersonalFieldInput, PersonalFieldValue } from "@/components/custom-fields/personal-field-input";
import { createClient } from "@/lib/supabase/client";
import {
  fetchPersonalCustomFieldDefinitions,
  fetchPersonalCustomFieldValuesBulk,
  matchesPersonalFieldFilter,
  savePersonalCustomFieldValuesForStudent,
  type PersonalCustomFieldDefinition,
  type PersonalValueMap,
} from "@/lib/custom-fields/personal-custom-field";
import {
  EMPTY_PERSONAL_GRID_PREFERENCES,
  PERSONAL_COLUMN_DEFAULT_WIDTH,
  buildPersonalColumnOrder,
  clampPersonalColumnWidth,
  movePersonalColumn,
  personalColumnId,
  type PersonalGridPreferences,
  type PersonalGridSurfaceKey,
} from "@/lib/custom-fields/personal-grid-preferences";

export type PersonalGridBaseColumn<T> = {
  id: string;
  header: ReactNode;
  cell: (row: T) => ReactNode;
  className?: string;
};

type Props<T extends { id: string }> = {
  surface: PersonalGridSurfaceKey;
  rows: T[];
  baseColumns: PersonalGridBaseColumn<T>[];
  rowActions?: (row: T) => ReactNode;
  rowTestId: string;
  actionsHeader: string;
};

function usePersonalGridPreferences(surface: PersonalGridSurfaceKey) {
  const [prefs, setPrefs] = useState<PersonalGridPreferences>(EMPTY_PERSONAL_GRID_PREFERENCES);
  const [loaded, setLoaded] = useState(false);
  const [pendingSaves, setPendingSaves] = useState(0);
  const latest = useRef<PersonalGridPreferences>(EMPTY_PERSONAL_GRID_PREFERENCES);
  const chain = useRef<Promise<unknown>>(Promise.resolve());

  useEffect(() => {
    let cancelled = false;
    void loadPersonalGridPreferencesAction(surface).then((stored) => {
      if (cancelled) return;
      const next = stored ?? EMPTY_PERSONAL_GRID_PREFERENCES;
      latest.current = next;
      setPrefs(next);
      setLoaded(true);
    });
    return () => {
      cancelled = true;
    };
  }, [surface]);

  const persist = useCallback(
    (next: PersonalGridPreferences) => {
      latest.current = next;
      setPrefs(next);
      setPendingSaves((n) => n + 1);
      chain.current = chain.current
        .then(() => savePersonalGridPreferencesAction(surface, latest.current))
        .catch(() => undefined)
        .finally(() => setPendingSaves((n) => n - 1));
    },
    [surface],
  );

  const update = useCallback(
    (fn: (current: PersonalGridPreferences) => PersonalGridPreferences) => persist(fn(latest.current)),
    [persist],
  );

  return { prefs, setPrefsLocal: setPrefs, loaded, saving: pendingSaves > 0, update };
}

export function PersonalFieldsGrid<T extends { id: string }>({
  surface,
  rows,
  baseColumns,
  rowActions,
  rowTestId,
  actionsHeader,
}: Props<T>) {
  const t = useTranslations("personalCustomFields");
  const [defs, setDefs] = useState<PersonalCustomFieldDefinition[] | null>(null);
  const [values, setValues] = useState<PersonalValueMap>({});
  const [filters, setFilters] = useState<Record<string, string>>({});
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const { prefs, setPrefsLocal, loaded: prefsLoaded, saving: prefsSaving, update } =
    usePersonalGridPreferences(surface);

  const rowIdsKey = useMemo(() => rows.map((r) => r.id).join(","), [rows]);

  useEffect(() => {
    let cancelled = false;
    void fetchPersonalCustomFieldDefinitions(createClient()).then((data) => {
      if (!cancelled) setDefs(data);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const reloadValues = useCallback(async () => {
    const ids = rowIdsKey ? rowIdsKey.split(",") : [];
    const map = await fetchPersonalCustomFieldValuesBulk(createClient(), {
      subjectType: "student",
      subjectIds: ids,
    });
    setValues(map);
  }, [rowIdsKey]);

  useEffect(() => {
    if (defs === null) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- values hydrate asynchronously after defs load
    void reloadValues();
  }, [defs, reloadValues]);

  const activeDefs = useMemo(() => (defs ?? []).filter((d) => d.status === "active"), [defs]);
  const orderedDefs = useMemo(() => {
    const byId = new Map(activeDefs.map((d) => [personalColumnId(d.field_key), d]));
    return buildPersonalColumnOrder(
      activeDefs.map((d) => d.field_key),
      prefs.columnOrder,
    )
      .map((id) => byId.get(id))
      .filter((d): d is PersonalCustomFieldDefinition => Boolean(d));
  }, [activeDefs, prefs.columnOrder]);
  const visibleDefs = useMemo(
    () => orderedDefs.filter((d) => prefs.columnVisibility[personalColumnId(d.field_key)] !== false),
    [orderedDefs, prefs.columnVisibility],
  );

  const filteredRows = useMemo(() => {
    const active = visibleDefs.filter((d) => (filters[d.field_key] ?? "").trim() !== "");
    if (active.length === 0) return rows;
    return rows.filter((row) =>
      active.every((d) =>
        matchesPersonalFieldFilter(d.data_type, values[row.id]?.[d.field_key] ?? "", filters[d.field_key] ?? ""),
      ),
    );
  }, [rows, visibleDefs, filters, values]);

  const widthOf = (colId: string) => prefs.columnSizing[colId] ?? PERSONAL_COLUMN_DEFAULT_WIDTH;

  const currentOrder = () => orderedDefs.map((d) => personalColumnId(d.field_key));

  const startResize = (colId: string, startX: number) => {
    const startWidth = widthOf(colId);
    let width = startWidth;
    const onMove = (e: PointerEvent) => {
      width = clampPersonalColumnWidth(startWidth + e.clientX - startX);
      setPrefsLocal((p) => ({ ...p, columnSizing: { ...p.columnSizing, [colId]: width } }));
    };
    const onUp = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      update((p) => ({ ...p, columnSizing: { ...p.columnSizing, [colId]: width } }));
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
  };

  const startEdit = (rowId: string) => {
    const row = values[rowId] ?? {};
    const next: Record<string, string> = {};
    for (const d of visibleDefs) next[d.field_key] = row[d.field_key] ?? "";
    setDraft(next);
    setSaveError(null);
    setEditingId(rowId);
  };

  const saveRow = async (rowId: string) => {
    setSaving(true);
    setSaveError(null);
    const payload = visibleDefs.map((d) => ({ field_key: d.field_key, value: draft[d.field_key] ?? "" }));
    const result = await savePersonalCustomFieldValuesForStudent(createClient(), {
      studentId: rowId,
      values: payload,
    });
    setSaving(false);
    if (!result.ok) {
      setSaveError(t("errors.saveFailed"));
      return;
    }
    setValues((prev) => ({ ...prev, [rowId]: { ...(prev[rowId] ?? {}), ...draft } }));
    setEditingId(null);
    void reloadValues();
  };

  const ready = defs !== null && prefsLoaded;

  return (
    <div className="space-y-2" data-testid={`personal-fields-grid-${surface}`} data-ready={ready ? "true" : "false"}>
      <PersonalColumnToolbar
        definitions={orderedDefs}
        visibility={prefs.columnVisibility}
        sizing={prefs.columnSizing}
        filters={filters}
        onVisibilityChange={(colId, visible) =>
          update((p) => ({ ...p, columnVisibility: { ...p.columnVisibility, [colId]: visible } }))
        }
        onWidthChange={(colId, width) =>
          update((p) => ({ ...p, columnSizing: { ...p.columnSizing, [colId]: width } }))
        }
        onMove={(colId, direction) =>
          update((p) => ({ ...p, columnOrder: movePersonalColumn(currentOrder(), colId, direction) }))
        }
        onFilterChange={(fieldKey, value) => setFilters((f) => ({ ...f, [fieldKey]: value }))}
        onCreated={(definition) => setDefs((d) => [...(d ?? []), definition])}
        onRenamed={(id, label) => setDefs((d) => (d ?? []).map((x) => (x.id === id ? { ...x, label } : x)))}
        onArchived={(definition) => {
          const colId = personalColumnId(definition.field_key);
          setDefs((d) => (d ?? []).filter((x) => x.id !== definition.id));
          setFilters((f) => {
            const next = { ...f };
            delete next[definition.field_key];
            return next;
          });
          if (editingId) setEditingId(null);
          update((p) => {
            const columnVisibility = { ...p.columnVisibility };
            const columnSizing = { ...p.columnSizing };
            delete columnVisibility[colId];
            delete columnSizing[colId];
            return { columnVisibility, columnSizing, columnOrder: p.columnOrder.filter((id) => id !== colId) };
          });
        }}
      />
      <span
        className="sr-only"
        data-testid="personal-grid-prefs-status"
        data-state={!prefsLoaded ? "loading" : prefsSaving ? "saving" : "saved"}
      >
        {prefsSaving ? t("prefsSaving") : t("prefsSaved")}
      </span>
      {saveError ? (
        <p className="text-sm text-red-700" role="alert">
          {saveError}
        </p>
      ) : null}
      <div className="hidden overflow-x-auto lg:block">
        <table className="min-w-full divide-y divide-slate-200 text-sm">
          <thead className="bg-slate-50">
            <tr>
              {baseColumns.map((col) => (
                <th key={col.id} className={col.className ?? "px-4 py-3 text-left font-medium text-slate-700"}>
                  {col.header}
                </th>
              ))}
              {visibleDefs.map((d) => {
                const colId = personalColumnId(d.field_key);
                const width = widthOf(colId);
                return (
                  <th
                    key={d.id}
                    className="relative px-4 py-3 text-left font-medium text-slate-700"
                    style={{ width, minWidth: width, maxWidth: width }}
                    data-testid={`column-header-${colId}`}
                  >
                    <span className="block truncate">{d.label}</span>
                    <span
                      role="separator"
                      aria-orientation="vertical"
                      aria-label={t("resizeColumn", { label: d.label })}
                      className="absolute right-0 top-0 h-full w-1.5 cursor-col-resize select-none bg-slate-200 hover:bg-slate-400"
                      data-testid={`personal-column-resize-${colId}`}
                      onPointerDown={(e) => {
                        e.preventDefault();
                        startResize(colId, e.clientX);
                      }}
                    />
                  </th>
                );
              })}
              <th className="px-4 py-3 text-left font-medium text-slate-700">
                <span className="sr-only">{actionsHeader}</span>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200 bg-white">
            {filteredRows.map((row) => {
              const isEditing = editingId === row.id;
              return (
                <tr key={row.id} data-testid={rowTestId} data-row-id={row.id}>
                  {baseColumns.map((col) => (
                    <td key={col.id} className="px-4 py-3 text-slate-700">
                      {col.cell(row)}
                    </td>
                  ))}
                  {visibleDefs.map((d) => {
                    const colId = personalColumnId(d.field_key);
                    const width = widthOf(colId);
                    return (
                      <td
                        key={`${row.id}-${d.id}`}
                        className="px-4 py-3"
                        style={{ width, minWidth: width, maxWidth: width }}
                      >
                        {isEditing ? (
                          <PersonalFieldInput
                            dataType={d.data_type}
                            label={d.label}
                            value={draft[d.field_key] ?? ""}
                            onChange={(value) => setDraft((p) => ({ ...p, [d.field_key]: value }))}
                            testId={`personal-input-${colId}-${row.id}`}
                          />
                        ) : (
                          <span className="block truncate">
                            <PersonalFieldValue
                              dataType={d.data_type}
                              value={values[row.id]?.[d.field_key]}
                              testId={`personal-value-${colId}-${row.id}`}
                            />
                          </span>
                        )}
                      </td>
                    );
                  })}
                  <td className="px-4 py-3">
                    <div className="flex flex-col gap-1">
                      {visibleDefs.length > 0 ? (
                        isEditing ? (
                          <div className="flex gap-2">
                            <button
                              type="button"
                              className="text-left text-sm font-medium text-slate-900 underline disabled:opacity-50"
                              disabled={saving}
                              onClick={() => void saveRow(row.id)}
                              data-testid={`personal-row-save-${row.id}`}
                            >
                              {t("saveValues")}
                            </button>
                            <button
                              type="button"
                              className="text-left text-sm text-slate-600 underline"
                              onClick={() => setEditingId(null)}
                              data-testid={`personal-row-cancel-${row.id}`}
                            >
                              {t("cancel")}
                            </button>
                          </div>
                        ) : (
                          <button
                            type="button"
                            className="text-left text-sm font-medium text-slate-900 underline"
                            onClick={() => startEdit(row.id)}
                            data-testid={`personal-row-edit-${row.id}`}
                          >
                            {t("editRow")}
                          </button>
                        )
                      ) : null}
                      {rowActions ? rowActions(row) : null}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-slate-500 lg:hidden">{t("desktopGridHint")}</p>
    </div>
  );
}
