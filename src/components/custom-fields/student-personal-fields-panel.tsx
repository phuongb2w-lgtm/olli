"use client";

import { useCallback, useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { createClient } from "@/lib/supabase/client";
import {
  fetchPersonalCustomFieldDefinitions,
  fetchPersonalCustomFieldValuesForStudent,
  savePersonalCustomFieldValuesForStudent,
  type PersonalCustomFieldDefinition,
} from "@/lib/custom-fields/personal-custom-field";
import { AddPersonalColumnDialog } from "@/components/custom-fields/add-personal-column-dialog";

type Props = {
  studentId: string;
  canManage: boolean;
};

export function StudentPersonalFieldsPanel({ studentId, canManage }: Props) {
  const t = useTranslations("personalCustomFields");
  const [defs, setDefs] = useState<PersonalCustomFieldDefinition[]>([]);
  const [values, setValues] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const reload = useCallback(async () => {
    const supabase = createClient();
    const [definitions, rows] = await Promise.all([
      fetchPersonalCustomFieldDefinitions(supabase),
      fetchPersonalCustomFieldValuesForStudent(supabase, studentId),
    ]);
    setDefs(definitions);
    const next: Record<string, string> = {};
    for (const row of rows) next[row.field_key] = row.value ?? "";
    for (const d of definitions) {
      if (next[d.field_key] === undefined) next[d.field_key] = "";
    }
    setValues(next);
  }, [studentId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reload hydrates panel after async fetch
    void reload();
  }, [reload]);

  if (!canManage && defs.length === 0) return null;

  const save = async () => {
    setSaving(true);
    setMessage(null);
    const supabase = createClient();
    const payload = defs.map((d) => ({
      field_key: d.field_key,
      value: values[d.field_key] ?? "",
    }));
    const result = await savePersonalCustomFieldValuesForStudent(supabase, {
      studentId,
      values: payload,
    });
    setSaving(false);
    if (!result.ok) {
      setMessage(t("errors.saveFailed"));
      return;
    }
    setMessage(t("saved"));
    void reload();
  };

  return (
    <section
      className="rounded-lg border border-slate-200 bg-white p-4"
      data-testid="student-personal-custom-fields"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-base font-semibold text-slate-900">{t("studentPanelTitle")}</h2>
        {canManage ? (
          <AddPersonalColumnDialog
            onCreated={(definition) => {
              setDefs((prev) => [...prev, definition]);
              setValues((prev) => ({ ...prev, [definition.field_key]: "" }));
            }}
          />
        ) : null}
      </div>
      <p className="mt-1 text-xs text-slate-600">{t("scopePersonalHint")}</p>
      {defs.length === 0 ? (
        <p className="mt-3 text-sm text-slate-600">{t("empty")}</p>
      ) : (
        <ul className="mt-3 space-y-3">
          {defs.map((def) => (
            <li key={def.id}>
              <label className="block text-sm font-medium text-slate-800">{def.label}</label>
              {canManage ? (
                <input
                  className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
                  value={values[def.field_key] ?? ""}
                  onChange={(e) =>
                    setValues((prev) => ({ ...prev, [def.field_key]: e.target.value }))
                  }
                  data-testid={`student-personal-field-${def.field_key}`}
                />
              ) : (
                <p className="mt-1 text-sm text-slate-700">{values[def.field_key] || "—"}</p>
              )}
            </li>
          ))}
        </ul>
      )}
      {canManage && defs.length > 0 ? (
        <button
          type="button"
          className="mt-4 rounded bg-slate-900 px-3 py-1.5 text-sm text-white disabled:opacity-50"
          disabled={saving}
          onClick={() => void save()}
          data-testid="student-personal-fields-save"
        >
          {t("saveValues")}
        </button>
      ) : null}
      {message ? <p className="mt-2 text-sm text-slate-700">{message}</p> : null}
    </section>
  );
}
