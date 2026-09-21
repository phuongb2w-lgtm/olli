"use client";

import { useCallback, useState, useTransition } from "react";
import { useTranslations } from "next-intl";
import {
  provisionStaffAccount,
  type ProvisionStaffAccountState,
} from "@/app/actions/staff-provisioning";
import { STAFF_CANONICAL_ROLES, type StaffCanonicalRole } from "@/lib/staff-provisioning/constants";
import { getProvisionErrorUx } from "@/lib/staff-provisioning/provision-error-ux";

type LockedPayload = {
  email: string;
  displayName: string;
  canonicalRole: StaffCanonicalRole;
  preferredLocale: "vi" | "en";
};

type Props = {
  seatsFull: boolean;
  defaultLocale: "vi" | "en";
};

const emptyDraft = (locale: "vi" | "en"): LockedPayload => ({
  email: "",
  displayName: "",
  canonicalRole: "teacher",
  preferredLocale: locale,
});

export function ProvisionStaffForm({ seatsFull, defaultLocale }: Props) {
  const t = useTranslations("users.provision");
  const tRoles = useTranslations("roles");
  const [draft, setDraft] = useState<LockedPayload>(() => emptyDraft(defaultLocale));
  const [idempotencyKey, setIdempotencyKey] = useState<string | null>(null);
  const [lockedPayload, setLockedPayload] = useState<LockedPayload | null>(null);
  const [result, setResult] = useState<ProvisionStaffAccountState | null>(null);
  const [pending, startTransition] = useTransition();

  const errorUx =
    result && !result.ok ? getProvisionErrorUx(result.error) : null;

  const success = result?.ok === true;
  const retryable = Boolean(errorUx?.retryable);
  const terminal = errorUx?.classification === "terminal";
  const support = errorUx?.classification === "support";

  const attemptActive = lockedPayload !== null && idempotencyKey !== null;
  const unresolvedAttempt = attemptActive && (pending || retryable);
  const fieldsFrozen = attemptActive && !terminal && !support && !success;

  const display = lockedPayload ?? draft;
  const disableCreate = seatsFull && !unresolvedAttempt;

  const resetForNewAttempt = useCallback(() => {
    setIdempotencyKey(null);
    setLockedPayload(null);
    setResult(null);
    setDraft(emptyDraft(defaultLocale));
  }, [defaultLocale]);

  const runProvision = useCallback(
    (payload: LockedPayload, key: string) => {
      startTransition(async () => {
        const next = await provisionStaffAccount({
          email: payload.email,
          displayName: payload.displayName,
          canonicalRole: payload.canonicalRole,
          idempotencyKey: key,
          preferredLocale: payload.preferredLocale,
        });
        setResult(next);
        if (next.ok) {
          setIdempotencyKey(null);
          setLockedPayload(null);
          setDraft(emptyDraft(defaultLocale));
        }
      });
    },
    [defaultLocale],
  );

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (pending) return;

    if (retryable && lockedPayload && idempotencyKey) {
      runProvision(lockedPayload, idempotencyKey);
      return;
    }

    if (disableCreate || terminal || support) return;

    const payload: LockedPayload = {
      email: draft.email.trim(),
      displayName: draft.displayName.trim(),
      canonicalRole: draft.canonicalRole,
      preferredLocale: draft.preferredLocale,
    };

    const key = idempotencyKey ?? crypto.randomUUID();
    if (!idempotencyKey) {
      setIdempotencyKey(key);
    }
    setLockedPayload(payload);
    setResult(null);
    runProvision(payload, key);
  };

  const updateDraft = (patch: Partial<LockedPayload>) => {
    if (fieldsFrozen) return;
    setDraft((prev) => ({ ...prev, ...patch }));
  };

  const errorMessage = errorUx ? t(`errors.${errorUx.messageKey}`) : null;

  return (
    <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-sm font-semibold text-slate-900">{t("title")}</h2>

      {success ? (
        <p
          className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800"
          role="status"
        >
          {t("success")}
        </p>
      ) : null}

      {disableCreate && !unresolvedAttempt ? (
        <p className="text-sm text-amber-800" role="status">
          {t("seatsFullHint")}
        </p>
      ) : null}

      <form onSubmit={handleSubmit} className="space-y-4" noValidate>
        {idempotencyKey ? (
          <span data-testid="provision-idempotency-key" className="sr-only">
            {idempotencyKey}
          </span>
        ) : null}

        <div className="space-y-1">
          <label htmlFor="staff-email" className="block text-sm font-medium text-slate-700">
            {t("emailLabel")}
          </label>
          <input
            id="staff-email"
            name="email"
            type="email"
            autoComplete="off"
            required
            disabled={fieldsFrozen || pending}
            value={display.email}
            onChange={(e) => updateDraft({ email: e.target.value })}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-100"
          />
        </div>

        <div className="space-y-1">
          <label htmlFor="staff-display-name" className="block text-sm font-medium text-slate-700">
            {t("displayNameLabel")}
          </label>
          <input
            id="staff-display-name"
            name="displayName"
            type="text"
            required
            disabled={fieldsFrozen || pending}
            value={display.displayName}
            onChange={(e) => updateDraft({ displayName: e.target.value })}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-100"
          />
        </div>

        <div className="space-y-1">
          <label htmlFor="staff-role" className="block text-sm font-medium text-slate-700">
            {t("roleLabel")}
          </label>
          <select
            id="staff-role"
            name="canonicalRole"
            required
            disabled={fieldsFrozen || pending}
            value={display.canonicalRole}
            onChange={(e) =>
              updateDraft({ canonicalRole: e.target.value as StaffCanonicalRole })
            }
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-100"
          >
            {STAFF_CANONICAL_ROLES.map((role) => (
              <option key={role} value={role}>
                {tRoles(roleLabelKey(role))}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1">
          <label htmlFor="staff-locale" className="block text-sm font-medium text-slate-700">
            {t("localeLabel")}
          </label>
          <select
            id="staff-locale"
            name="preferredLocale"
            disabled={fieldsFrozen || pending}
            value={display.preferredLocale}
            onChange={(e) =>
              updateDraft({ preferredLocale: e.target.value as "vi" | "en" })
            }
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-100"
          >
            <option value="vi">{t("localeVi")}</option>
            <option value="en">{t("localeEn")}</option>
          </select>
        </div>

        {errorMessage ? (
          <p
            className={
              support
                ? "rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
                : "rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800"
            }
            role="alert"
          >
            {errorMessage}
          </p>
        ) : null}

        <div className="flex flex-wrap gap-3">
          {retryable && lockedPayload && idempotencyKey ? (
            <button
              type="submit"
              disabled={pending}
              className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
            >
              {pending ? t("continuing") : t("continueSetup")}
            </button>
          ) : (
            <button
              type="submit"
              disabled={pending || disableCreate || terminal || support}
              className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-60"
            >
              {pending ? t("submitting") : t("submit")}
            </button>
          )}

          {terminal || support ? (
            <button
              type="button"
              onClick={resetForNewAttempt}
              className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-800 hover:bg-slate-50"
            >
              {t("startNew")}
            </button>
          ) : null}
        </div>
      </form>
    </section>
  );
}

function roleLabelKey(role: StaffCanonicalRole): string {
  const map = {
    accountant: "accountant",
    consultant: "consultant",
    academic_operations: "academicOperations",
    teacher: "teacher",
  } as const;
  return map[role];
}
