"use client";

import { useTranslations } from "next-intl";
import { normalizePersonalDataType } from "@/lib/custom-fields/personal-custom-field";

export function PersonalFieldInput({
  dataType,
  value,
  onChange,
  testId,
  label,
  className,
}: {
  dataType: string;
  value: string;
  onChange: (value: string) => void;
  testId: string;
  label: string;
  className?: string;
}) {
  const t = useTranslations("personalCustomFields");
  const type = normalizePersonalDataType(dataType);
  const base = className ?? "w-full min-w-[6rem] rounded border border-slate-300 px-2 py-1 text-sm";
  if (type === "boolean") {
    return (
      <select
        className={base}
        aria-label={label}
        value={value === "true" || value === "false" ? value : ""}
        onChange={(e) => onChange(e.target.value)}
        data-testid={testId}
      >
        <option value="">—</option>
        <option value="true">{t("booleanYes")}</option>
        <option value="false">{t("booleanNo")}</option>
      </select>
    );
  }
  return (
    <input
      type={type === "date" ? "date" : type === "number" ? "number" : "text"}
      step={type === "number" ? "any" : undefined}
      className={base}
      aria-label={label}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      data-testid={testId}
    />
  );
}

export function PersonalFieldValue({
  dataType,
  value,
  testId,
}: {
  dataType: string;
  value: string | null | undefined;
  testId?: string;
}) {
  const t = useTranslations("personalCustomFields");
  const type = normalizePersonalDataType(dataType);
  const raw = (value ?? "").trim();
  let display = raw || "—";
  if (raw && type === "boolean") display = raw === "true" ? t("booleanYes") : t("booleanNo");
  if (raw && type === "date") {
    const m = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m) display = `${m[3]}/${m[2]}/${m[1]}`;
  }
  return <span data-testid={testId}>{display}</span>;
}
