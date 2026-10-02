import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

export type PersonalCustomFieldDataType = "text" | "number" | "date" | "boolean";

export type PersonalCustomFieldDefinition = {
  id: string;
  field_key: string;
  label: string;
  data_type: string;
  sort_order: number;
  status: string;
};

export function slugifyCustomFieldKey(label: string, attempt = 0): string {
  const base = label
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40);
  const stem = base.match(/^[a-z]/) ? base : `f_${base || "note"}`;
  const suffix = attempt > 0 ? `_${attempt}` : "";
  return `${stem}${suffix}`.slice(0, 49);
}

export async function fetchPersonalCustomFieldDefinitions(
  supabase: SupabaseClient<Database>,
): Promise<PersonalCustomFieldDefinition[]> {
  const { data, error } = await supabase
    .from("consultant_custom_field_definition")
    .select("id, field_key, label, data_type, sort_order, status")
    .eq("status", "active")
    .order("sort_order")
    .order("label");
  if (error || !data) return [];
  return data as PersonalCustomFieldDefinition[];
}

type CreateFieldRpc = {
  id: string;
  field_key: string;
  label: string;
  data_type: string;
  sort_order: number;
  status: string;
};

export async function createPersonalCustomFieldDefinition(
  supabase: SupabaseClient<Database>,
  input: { label: string; dataType: PersonalCustomFieldDataType },
): Promise<{ ok: true; definition: PersonalCustomFieldDefinition } | { ok: false; errorCode: string }> {
  const { data, error } = await supabase.rpc("create_personal_custom_field_definition", {
    p_label: input.label.trim(),
    p_data_type: input.dataType,
  });
  if (error || !data || typeof data !== "object") {
    if (error?.message.includes("permission_denied")) return { ok: false, errorCode: "permission_denied" };
    if (error?.message.includes("invalid_data_type")) return { ok: false, errorCode: "invalid_data_type" };
    if (error?.message.includes("custom_field_key_reserved")) {
      return { ok: false, errorCode: "key_reserved" };
    }
    if (error?.message.includes("invalid_label")) return { ok: false, errorCode: "invalid_label" };
    return { ok: false, errorCode: "unknown" };
  }
  const row = data as CreateFieldRpc;
  return {
    ok: true,
    definition: {
      id: String(row.id),
      field_key: String(row.field_key),
      label: String(row.label),
      data_type: String(row.data_type),
      sort_order: Number(row.sort_order ?? 0),
      status: String(row.status ?? "active"),
    },
  };
}

export async function updatePersonalCustomFieldDefinition(
  supabase: SupabaseClient<Database>,
  input: { definitionId: string; label?: string; archive?: boolean },
): Promise<{ ok: boolean; errorCode?: string }> {
  const { error } = await supabase.rpc("update_personal_custom_field_definition", {
    p_field_definition_id: input.definitionId,
    p_label: input.label?.trim() || undefined,
    p_status: input.archive ? "archived" : undefined,
  });
  if (error) {
    if (error.message.includes("permission_denied")) return { ok: false, errorCode: "permission_denied" };
    if (error.message.includes("invalid_label")) return { ok: false, errorCode: "invalid_label" };
    return { ok: false, errorCode: "unknown" };
  }
  return { ok: true };
}

export async function savePersonalCustomFieldValuesForStudent(
  supabase: SupabaseClient<Database>,
  input: {
    studentId: string;
    values: { field_key: string; value: string }[];
  },
): Promise<{ ok: boolean; errorCode?: string }> {
  const { error } = await supabase.rpc("save_personal_custom_field_values", {
    p_subject_type: "student",
    p_subject_id: input.studentId,
    p_values: input.values,
  });
  if (error) {
    if (error.message.includes("permission_denied")) return { ok: false, errorCode: "permission_denied" };
    return { ok: false, errorCode: "unknown" };
  }
  return { ok: true };
}

export type PersonalValueMap = Record<string, Record<string, string>>;

export async function fetchPersonalCustomFieldValuesBulk(
  supabase: SupabaseClient<Database>,
  input: { subjectType: "student" | "lead"; subjectIds: string[] },
): Promise<PersonalValueMap> {
  if (input.subjectIds.length === 0) return {};
  const { data, error } = await supabase.rpc("list_personal_custom_field_values_bulk", {
    p_subject_type: input.subjectType,
    p_subject_ids: input.subjectIds,
  });
  if (error || !Array.isArray(data)) return {};
  const map: PersonalValueMap = {};
  for (const entry of data as { subject_id: string; field_key: string; value: string }[]) {
    const row = (map[entry.subject_id] ??= {});
    row[entry.field_key] = entry.value ?? "";
  }
  return map;
}

export function normalizePersonalDataType(dataType: string): PersonalCustomFieldDataType {
  return dataType === "number" || dataType === "date" || dataType === "boolean" ? dataType : "text";
}

function foldText(value: string): string {
  return value.normalize("NFD").replace(/\p{M}/gu, "").replace(/\u0111/g, "d").replace(/\u0110/g, "D").toLowerCase().trim();
}

/**
 * text: accent-insensitive contains; number: "=n", ">n", ">=n", "<n", "<=n" or plain n (equals);
 * date: exact ISO day; boolean: "true" | "false".
 */
export function matchesPersonalFieldFilter(dataType: string, value: string, filter: string): boolean {
  const needle = filter.trim();
  if (needle === "") return true;
  const type = normalizePersonalDataType(dataType);
  const raw = (value ?? "").trim();
  if (type === "boolean") return (raw === "true" ? "true" : "false") === needle;
  if (type === "date") return raw === needle;
  if (type === "number") {
    const m = needle.match(/^(>=|<=|>|<|=)?\s*(-?\d+(?:[.,]\d+)?)$/);
    if (!m) return false;
    if (raw === "") return false;
    const left = Number(raw.replace(",", "."));
    const right = Number(m[2]!.replace(",", "."));
    if (!Number.isFinite(left)) return false;
    switch (m[1]) {
      case ">":
        return left > right;
      case ">=":
        return left >= right;
      case "<":
        return left < right;
      case "<=":
        return left <= right;
      default:
        return left === right;
    }
  }
  return foldText(raw).includes(foldText(needle));
}

type PersonalValueRow = { field_key: string; label: string; data_type: string; value: string };

export async function fetchPersonalCustomFieldValuesForStudent(
  supabase: SupabaseClient<Database>,
  studentId: string,
): Promise<PersonalValueRow[]> {
  const { data, error } = await supabase.rpc("list_personal_custom_field_values", {
    p_subject_type: "student",
    p_subject_id: studentId,
  });
  if (error || !Array.isArray(data)) return [];
  return data as PersonalValueRow[];
}
