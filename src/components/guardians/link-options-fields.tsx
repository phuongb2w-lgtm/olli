"use client";

import { useTranslations } from "next-intl";
import { RELATIONSHIP_TYPES } from "@/lib/guardians/constants";

type Props = {
  relationshipType?: string;
  isPrimaryContact?: boolean;
  isBillingContact?: boolean;
  idPrefix?: string;
};

export function LinkOptionsFields({
  relationshipType = "guardian",
  isPrimaryContact = false,
  isBillingContact = false,
  idPrefix = "",
}: Props) {
  const t = useTranslations("guardians");
  const tRel = useTranslations("guardians.relationship");

  return (
    <div className="space-y-3">
      <div>
        <label htmlFor={`${idPrefix}relationshipType`} className="mb-1 block text-sm font-medium">
          {t("relationshipLabel")}
        </label>
        <select
          id={`${idPrefix}relationshipType`}
          name="relationshipType"
          defaultValue={relationshipType}
          className="w-full rounded border border-slate-300 px-3 py-2 text-sm sm:max-w-xs"
        >
          {RELATIONSHIP_TYPES.map((type) => (
            <option key={type} value={type}>
              {tRel(type)}
            </option>
          ))}
        </select>
      </div>
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium text-slate-700">{t("contactRoles")}</legend>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="isPrimaryContact"
            value="true"
            defaultChecked={isPrimaryContact}
          />
          <span>{t("primaryContact")}</span>
        </label>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            name="isBillingContact"
            value="true"
            defaultChecked={isBillingContact}
          />
          <span>{t("billingContact")}</span>
        </label>
      </fieldset>
    </div>
  );
}
