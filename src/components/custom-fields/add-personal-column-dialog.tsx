"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { createClient } from "@/lib/supabase/client";
import {
  createPersonalCustomFieldDefinition,
  type PersonalCustomFieldDataType,
  type PersonalCustomFieldDefinition,
} from "@/lib/custom-fields/personal-custom-field";

type Props = {
  onCreated: (definition: PersonalCustomFieldDefinition) => void;
};

export function AddPersonalColumnDialog({ onCreated }: Props) {
  const t = useTranslations("personalCustomFields");
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState("");
  const [dataType, setDataType] = useState<PersonalCustomFieldDataType>("text");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const reset = () => {
    setLabel("");
    setDataType("text");
    setError(null);
  };

  const submit = async () => {
    setError(null);
    if (!label.trim()) {
      setError(t("errors.labelRequired"));
      return;
    }
    setPending(true);
    const supabase = createClient();
    const result = await createPersonalCustomFieldDefinition(supabase, {
      label: label.trim(),
      dataType,
    });
    setPending(false);
    if (!result.ok) {
      setError(t(`errors.${result.errorCode}` as "errors.unknown"));
      return;
    }
    onCreated(result.definition);
    setOpen(false);
    reset();
  };

  return (
    <>
      <button
        type="button"
        className="rounded border border-dashed border-slate-400 px-2 py-1 text-sm font-medium text-slate-800 hover:bg-slate-50"
        data-testid="add-custom-column"
        onClick={() => setOpen(true)}
      >
        {t("addColumn")}
      </button>
      {open ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="add-custom-column-title"
          data-testid="add-custom-column-dialog"
        >
          <div className="w-full max-w-sm rounded-lg border border-slate-200 bg-white p-4 shadow-lg">
            <h4 id="add-custom-column-title" className="text-base font-semibold text-slate-900">
              {t("dialogTitle")}
            </h4>
            <div className="mt-3 space-y-3 text-sm">
              <label className="block">
                <span className="text-slate-700">{t("columnName")}</span>
                <input
                  className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                  value={label}
                  onChange={(e) => setLabel(e.target.value)}
                  data-testid="custom-column-label"
                />
              </label>
              <label className="block">
                <span className="text-slate-700">{t("dataType")}</span>
                <select
                  className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
                  value={dataType}
                  onChange={(e) => setDataType(e.target.value as PersonalCustomFieldDataType)}
                  data-testid="custom-column-data-type"
                >
                  <option value="text">{t("types.text")}</option>
                  <option value="number">{t("types.number")}</option>
                  <option value="date">{t("types.date")}</option>
                  <option value="boolean">{t("types.boolean")}</option>
                </select>
              </label>
              <p className="text-xs text-slate-600">{t("scopePersonalHint")}</p>
              {error ? (
                <p className="text-red-700" role="alert">
                  {error}
                </p>
              ) : null}
            </div>
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                className="rounded border border-slate-300 px-3 py-1.5 text-sm"
                onClick={() => {
                  setOpen(false);
                  reset();
                }}
              >
                {t("cancel")}
              </button>
              <button
                type="button"
                className="rounded bg-slate-900 px-3 py-1.5 text-sm text-white disabled:opacity-50"
                disabled={pending}
                data-testid="custom-column-submit"
                onClick={() => void submit()}
              >
                {t("submit")}
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
