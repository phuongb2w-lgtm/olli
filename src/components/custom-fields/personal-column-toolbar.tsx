"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { AddPersonalColumnDialog } from "@/components/custom-fields/add-personal-column-dialog";
import { createClient } from "@/lib/supabase/client";
import {
  normalizePersonalDataType,
  updatePersonalCustomFieldDefinition,
  type PersonalCustomFieldDefinition,
} from "@/lib/custom-fields/personal-custom-field";
import {
  PERSONAL_COLUMN_DEFAULT_WIDTH,
  PERSONAL_COLUMN_MAX_WIDTH,
  PERSONAL_COLUMN_MIN_WIDTH,
  clampPersonalColumnWidth,
  personalColumnId,
} from "@/lib/custom-fields/personal-grid-preferences";

type Props = {
  /** Active definitions in current display order. */
  definitions: PersonalCustomFieldDefinition[];
  visibility: Record<string, boolean>;
  sizing: Record<string, number>;
  filters: Record<string, string>;
  /** Hosts with their own header filter row render filters there instead. */
  showFilters?: boolean;
  onVisibilityChange: (colId: string, visible: boolean) => void;
  onWidthChange: (colId: string, width: number) => void;
  onMove: (colId: string, direction: -1 | 1) => void;
  onFilterChange: (fieldKey: string, value: string) => void;
  onCreated: (definition: PersonalCustomFieldDefinition) => void;
  onRenamed: (definitionId: string, label: string) => void;
  onArchived: (definition: PersonalCustomFieldDefinition) => void;
};

export function PersonalColumnFilterInput({
  definition,
  value,
  onChange,
  className,
}: {
  definition: PersonalCustomFieldDefinition;
  value: string;
  onChange: (value: string) => void;
  className?: string;
}) {
  const t = useTranslations("personalCustomFields");
  const type = normalizePersonalDataType(definition.data_type);
  const testId = `personal-column-filter-${personalColumnId(definition.field_key)}`;
  const base = className ?? "w-full min-w-[7rem] rounded border border-slate-300 px-2 py-0.5 text-xs";
  if (type === "boolean") {
    return (
      <select className={base} value={value} onChange={(e) => onChange(e.target.value)} data-testid={testId}>
        <option value="">{t("filterAny")}</option>
        <option value="true">{t("booleanYes")}</option>
        <option value="false">{t("booleanNo")}</option>
      </select>
    );
  }
  return (
    <input
      type={type === "date" ? "date" : "text"}
      inputMode={type === "number" ? "decimal" : undefined}
      className={base}
      placeholder={type === "number" ? t("filterNumberPlaceholder") : t("filterPlaceholder")}
      aria-label={`${t("filterPlaceholder")} ${definition.label}`}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      data-testid={testId}
    />
  );
}

export function PersonalColumnToolbar({
  definitions,
  visibility,
  sizing,
  filters,
  showFilters = true,
  onVisibilityChange,
  onWidthChange,
  onMove,
  onFilterChange,
  onCreated,
  onRenamed,
  onArchived,
}: Props) {
  const t = useTranslations("personalCustomFields");
  const [renameTarget, setRenameTarget] = useState<PersonalCustomFieldDefinition | null>(null);
  const [renameLabel, setRenameLabel] = useState("");
  const [archiveTarget, setArchiveTarget] = useState<PersonalCustomFieldDefinition | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submitRename = async () => {
    if (!renameTarget) return;
    const label = renameLabel.trim();
    if (!label) {
      setError(t("errors.labelRequired"));
      return;
    }
    setPending(true);
    setError(null);
    const result = await updatePersonalCustomFieldDefinition(createClient(), {
      definitionId: renameTarget.id,
      label,
    });
    setPending(false);
    if (!result.ok) {
      setError(t(`errors.${result.errorCode === "invalid_label" ? "invalid_label" : "updateFailed"}`));
      return;
    }
    onRenamed(renameTarget.id, label);
    setRenameTarget(null);
    setRenameLabel("");
  };

  const submitArchive = async () => {
    if (!archiveTarget) return;
    setPending(true);
    setError(null);
    const result = await updatePersonalCustomFieldDefinition(createClient(), {
      definitionId: archiveTarget.id,
      archive: true,
    });
    setPending(false);
    if (!result.ok) {
      setError(t("errors.updateFailed"));
      return;
    }
    onArchived(archiveTarget);
    setArchiveTarget(null);
  };

  return (
    <div className="space-y-2" data-testid="personal-column-toolbar">
      <div className="flex flex-wrap items-center gap-2">
        <AddPersonalColumnDialog onCreated={onCreated} />
        {definitions.length > 0 ? (
          <span className="text-xs text-slate-500">{t("manageColumns")}</span>
        ) : null}
      </div>
      {error && !renameTarget ? (
        <p className="text-sm text-red-700" role="alert">
          {error}
        </p>
      ) : null}
      {definitions.length > 0 ? (
        <div className="flex flex-wrap gap-2 text-sm">
          {definitions.map((def, index) => {
            const colId = personalColumnId(def.field_key);
            return (
              <div
                key={def.id}
                className="rounded border border-slate-200 bg-slate-50 px-2 py-1.5"
                data-testid={`personal-column-manage-${colId}`}
              >
                <div className="flex flex-wrap items-center gap-2">
                  <label className="inline-flex items-center gap-1">
                    <input
                      type="checkbox"
                      checked={visibility[colId] !== false}
                      onChange={(e) => onVisibilityChange(colId, e.target.checked)}
                      data-testid={`column-toggle-${colId}`}
                    />
                    <span className="font-medium" data-testid={`personal-column-label-${colId}`}>
                      {def.label}
                    </span>
                  </label>
                  <button
                    type="button"
                    className="text-xs underline"
                    data-testid={`personal-column-rename-${colId}`}
                    onClick={() => {
                      setError(null);
                      setRenameTarget(def);
                      setRenameLabel(def.label);
                    }}
                  >
                    {t("renameColumn")}
                  </button>
                  <button
                    type="button"
                    className="text-xs text-red-800 underline"
                    disabled={pending}
                    data-testid={`personal-column-archive-${colId}`}
                    onClick={() => {
                      setError(null);
                      setArchiveTarget(def);
                    }}
                  >
                    {t("archiveColumn")}
                  </button>
                  <button
                    type="button"
                    className="text-xs underline disabled:opacity-40"
                    aria-label={t("moveLeftLabel", { label: def.label })}
                    disabled={index === 0}
                    data-testid={`personal-column-move-left-${colId}`}
                    onClick={() => onMove(colId, -1)}
                  >
                    {t("moveLeft")}
                  </button>
                  <button
                    type="button"
                    className="text-xs underline disabled:opacity-40"
                    aria-label={t("moveRightLabel", { label: def.label })}
                    disabled={index === definitions.length - 1}
                    data-testid={`personal-column-move-right-${colId}`}
                    onClick={() => onMove(colId, 1)}
                  >
                    {t("moveRight")}
                  </button>
                  <label className="inline-flex items-center gap-1 text-xs">
                    {t("widthPx")}
                    <input
                      type="number"
                      min={PERSONAL_COLUMN_MIN_WIDTH}
                      max={PERSONAL_COLUMN_MAX_WIDTH}
                      step={10}
                      aria-label={t("widthLabel", { label: def.label })}
                      className="w-16 rounded border border-slate-300 px-1"
                      value={sizing[colId] ?? PERSONAL_COLUMN_DEFAULT_WIDTH}
                      onChange={(e) => onWidthChange(colId, clampPersonalColumnWidth(Number(e.target.value)))}
                      data-testid={`personal-column-width-${colId}`}
                    />
                  </label>
                </div>
                {showFilters ? (
                  <div className="mt-1">
                    <PersonalColumnFilterInput
                      definition={def}
                      value={filters[def.field_key] ?? ""}
                      onChange={(value) => onFilterChange(def.field_key, value)}
                    />
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>
      ) : null}
      {renameTarget ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="personal-column-rename-title"
          data-testid="personal-column-rename-dialog"
        >
          <div className="w-full max-w-sm rounded-lg border bg-white p-4 shadow-lg">
            <h4 id="personal-column-rename-title" className="font-semibold">
              {t("renameDialogTitle")}
            </h4>
            <input
              className="mt-2 w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
              value={renameLabel}
              maxLength={80}
              onChange={(e) => setRenameLabel(e.target.value)}
              data-testid="personal-column-rename-input"
            />
            {error ? (
              <p className="mt-2 text-sm text-red-700" role="alert">
                {error}
              </p>
            ) : null}
            <div className="mt-3 flex justify-end gap-2">
              <button
                type="button"
                className="text-sm underline"
                onClick={() => {
                  setRenameTarget(null);
                  setError(null);
                }}
              >
                {t("cancel")}
              </button>
              <button
                type="button"
                className="rounded bg-slate-900 px-3 py-1.5 text-sm text-white disabled:opacity-50"
                disabled={pending}
                data-testid="personal-column-rename-submit"
                onClick={() => void submitRename()}
              >
                {t("renameSubmit")}
              </button>
            </div>
          </div>
        </div>
      ) : null}
      {archiveTarget ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="personal-column-archive-title"
          data-testid="personal-column-archive-dialog"
        >
          <div className="w-full max-w-sm rounded-lg border bg-white p-4 shadow-lg">
            <h4 id="personal-column-archive-title" className="font-semibold">
              {t("archiveDialogTitle")}
            </h4>
            <p className="mt-2 text-sm text-slate-700">{t("archiveConfirm", { label: archiveTarget.label })}</p>
            <div className="mt-3 flex justify-end gap-2">
              <button type="button" className="text-sm underline" onClick={() => setArchiveTarget(null)}>
                {t("cancel")}
              </button>
              <button
                type="button"
                className="rounded bg-red-800 px-3 py-1.5 text-sm text-white disabled:opacity-50"
                disabled={pending}
                data-testid="personal-column-archive-confirm"
                onClick={() => void submitArchive()}
              >
                {t("archiveSubmit")}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
