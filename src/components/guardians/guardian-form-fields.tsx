"use client";

import { useTranslations } from "next-intl";

type Props = {
  values: {
    familyName: string;
    givenName: string;
    phone: string;
    email: string;
  };
  fieldErrors?: Record<string, string>;
  idPrefix?: string;
};

export function GuardianFormFields({ values, fieldErrors, idPrefix = "" }: Props) {
  const t = useTranslations("guardians");

  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor={`${idPrefix}familyName`} className="mb-1 block text-sm font-medium">
            {t("familyName")}
          </label>
          <input
            id={`${idPrefix}familyName`}
            name="familyName"
            type="text"
            required
            defaultValue={values.familyName}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
          {fieldErrors?.familyName ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("requiredField")}
            </p>
          ) : null}
        </div>
        <div>
          <label htmlFor={`${idPrefix}givenName`} className="mb-1 block text-sm font-medium">
            {t("givenName")}
          </label>
          <input
            id={`${idPrefix}givenName`}
            name="givenName"
            type="text"
            required
            defaultValue={values.givenName}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
          {fieldErrors?.givenName ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("requiredField")}
            </p>
          ) : null}
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor={`${idPrefix}phone`} className="mb-1 block text-sm font-medium">
            {t("phone")}
          </label>
          <input
            id={`${idPrefix}phone`}
            name="phone"
            type="tel"
            defaultValue={values.phone}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
          {fieldErrors?.phone ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("phoneTooLong")}
            </p>
          ) : null}
        </div>
        <div>
          <label htmlFor={`${idPrefix}email`} className="mb-1 block text-sm font-medium">
            {t("email")}
          </label>
          <input
            id={`${idPrefix}email`}
            name="email"
            type="email"
            defaultValue={values.email}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
          {fieldErrors?.email ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("invalidEmail")}
            </p>
          ) : null}
        </div>
      </div>
    </>
  );
}
