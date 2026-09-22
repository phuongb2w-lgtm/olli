"use client";

import { useState, useTransition } from "react";
import { useTranslations } from "next-intl";
import {
  changeStaffRole,
  reactivateStaff,
  removeStaff,
  restoreRemovedStaff,
  suspendStaff,
  type StaffLifecycleResult,
} from "@/app/actions/staff-lifecycle";
import { lifecycleErrorMessageKey } from "@/lib/staff-lifecycle/error-ux";
import type { CenterAccountStaffMember } from "@/lib/center-accounts/types";
import { STAFF_CANONICAL_ROLES, type StaffCanonicalRole } from "@/lib/staff-provisioning/constants";

type ActionKind = "changeRole" | "suspend" | "reactivate" | "remove" | "restore" | null;

type Props = {
  member: CenterAccountStaffMember;
  staffSeatsUsed: number;
  staffLimit: number;
  variant: "current" | "removed";
  includeTestIds?: boolean;
};

function roleLabelKey(role: StaffCanonicalRole): string {
  const map = {
    accountant: "accountant",
    consultant: "consultant",
    academic_operations: "academicOperations",
    teacher: "teacher",
  } as const;
  return map[role];
}

export function StaffLifecycleActions({
  member,
  staffSeatsUsed,
  staffLimit,
  variant,
  includeTestIds = true,
}: Props) {
  const t = useTranslations("users.lifecycle");
  const tRoles = useTranslations("roles");
  const [action, setAction] = useState<ActionKind>(null);
  const [nextRole, setNextRole] = useState<StaffCanonicalRole>(
    member.canonicalRole ?? "teacher",
  );
  const [result, setResult] = useState<StaffLifecycleResult | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [, startTransition] = useTransition();

  if (variant === "current" && member.accessStatus === "locked") {
    return null;
  }

  const testId = includeTestIds ? `staff-actions-${member.email}` : undefined;
  const errorMessage =
    result && !result.ok
      ? t(`errors.${lifecycleErrorMessageKey(result.error)}`)
      : null;

  const run = (task: () => Promise<StaffLifecycleResult>) => {
    if (submitting) return;
    setSubmitting(true);
    startTransition(async () => {
      try {
        const next = await task();
        setResult(next);
        if (next.ok) {
          setAction(null);
        }
      } finally {
        setSubmitting(false);
      }
    });
  };

  return (
    <div className="space-y-2" data-testid={testId}>
      {variant === "current" ? (
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            data-testid={includeTestIds ? `action-change-role-${member.email}` : undefined}
            className="rounded border border-slate-300 px-2.5 py-1 text-xs font-medium text-slate-800 hover:bg-slate-50"
            onClick={() => {
              setResult(null);
              setAction("changeRole");
              setNextRole(member.canonicalRole ?? "teacher");
            }}
          >
            {t("changeRole")}
          </button>
          {member.accessStatus === "active" ? (
            <button
              type="button"
              data-testid={includeTestIds ? `action-suspend-${member.email}` : undefined}
              className="rounded border border-slate-300 px-2.5 py-1 text-xs font-medium text-slate-800 hover:bg-slate-50"
              onClick={() => {
                setResult(null);
                setAction("suspend");
              }}
            >
              {t("suspend")}
            </button>
          ) : null}
          {member.accessStatus === "inactive" ? (
            <button
              type="button"
              data-testid={includeTestIds ? `action-reactivate-${member.email}` : undefined}
              className="rounded border border-slate-300 px-2.5 py-1 text-xs font-medium text-slate-800 hover:bg-slate-50"
              onClick={() => {
                setResult(null);
                setAction("reactivate");
              }}
            >
              {t("reactivate")}
            </button>
          ) : null}
          <button
            type="button"
            data-testid={includeTestIds ? `action-remove-${member.email}` : undefined}
            className="rounded border border-red-200 px-2.5 py-1 text-xs font-medium text-red-800 hover:bg-red-50"
            onClick={() => {
              setResult(null);
              setAction("remove");
            }}
          >
            {t("remove")}
          </button>
        </div>
      ) : (
        <button
          type="button"
          data-testid={includeTestIds ? `action-restore-${member.email}` : undefined}
          className="rounded border border-slate-300 px-2.5 py-1 text-xs font-medium text-slate-800 hover:bg-slate-50"
          onClick={() => {
            setResult(null);
            setAction("restore");
            setNextRole(member.canonicalRole ?? "teacher");
          }}
        >
          {t("restore")}
        </button>
      )}

      {action === "changeRole" ? (
        <div
          className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm"
          data-testid={includeTestIds ? "confirm-change-role" : undefined}
        >
          <p className="font-medium text-slate-900">{t("changeRoleTitle")}</p>
          <p className="mt-1 text-slate-600">
            {t("changeRoleSummary", {
              current: member.canonicalRole
                ? tRoles(roleLabelKey(member.canonicalRole))
                : t("roleUnknown"),
              next: tRoles(roleLabelKey(nextRole)),
            })}
          </p>
          <label className="mt-2 block text-xs font-medium text-slate-700" htmlFor={`role-${member.appUserId}`}>
            {t("newRoleLabel")}
          </label>
          <select
            id={`role-${member.appUserId}`}
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
            value={nextRole}
            onChange={(event) => setNextRole(event.target.value as StaffCanonicalRole)}
          >
            {STAFF_CANONICAL_ROLES.map((role) => (
              <option key={role} value={role}>
                {tRoles(roleLabelKey(role))}
              </option>
            ))}
          </select>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              disabled={submitting}
              className="rounded bg-slate-900 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-60"
              onClick={() =>
                run(() =>
                  changeStaffRole({ appUserId: member.appUserId, canonicalRole: nextRole }),
                )
              }
            >
              {submitting ? t("working") : t("confirmChangeRole")}
            </button>
            <button
              type="button"
              className="rounded border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-800"
              onClick={() => setAction(null)}
            >
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : null}

      {action === "suspend" ? (
        <div
          className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm"
          data-testid={includeTestIds ? "confirm-suspend" : undefined}
        >
          <p className="font-medium text-amber-950">{t("suspendTitle")}</p>
          <p className="mt-1 text-amber-900">{t("suspendBody")}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              disabled={submitting}
              className="rounded bg-slate-900 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-60"
              onClick={() => run(() => suspendStaff({ appUserId: member.appUserId }))}
            >
              {submitting ? t("working") : t("confirmSuspend")}
            </button>
            <button
              type="button"
              className="rounded border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-800"
              onClick={() => setAction(null)}
            >
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : null}

      {action === "reactivate" ? (
        <div
          className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm"
          data-testid={includeTestIds ? "confirm-reactivate" : undefined}
        >
          <p className="font-medium text-slate-900">{t("reactivateTitle")}</p>
          <p className="mt-1 text-slate-600">{t("reactivateBody")}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              disabled={submitting}
              className="rounded bg-slate-900 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-60"
              onClick={() => run(() => reactivateStaff({ appUserId: member.appUserId }))}
            >
              {submitting ? t("working") : t("confirmReactivate")}
            </button>
            <button
              type="button"
              className="rounded border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-800"
              onClick={() => setAction(null)}
            >
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : null}

      {action === "remove" ? (
        <div
          className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm"
          data-testid={includeTestIds ? "confirm-remove" : undefined}
        >
          <p className="font-medium text-red-950">{t("removeTitle")}</p>
          <p className="mt-1 text-red-900">{t("removeBody")}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              disabled={submitting}
              className="rounded bg-red-800 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-60"
              onClick={() => run(() => removeStaff({ appUserId: member.appUserId }))}
            >
              {submitting ? t("working") : t("confirmRemove")}
            </button>
            <button
              type="button"
              className="rounded border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-800"
              onClick={() => setAction(null)}
            >
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : null}

      {action === "restore" ? (
        <div
          className="rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm"
          data-testid={includeTestIds ? "confirm-restore" : undefined}
        >
          <p className="font-medium text-slate-900">{t("restoreTitle")}</p>
          <p className="mt-1 text-slate-600">
            {t("restoreBody", { used: staffSeatsUsed, limit: staffLimit })}
          </p>
          <label className="mt-2 block text-xs font-medium text-slate-700" htmlFor={`restore-role-${member.appUserId}`}>
            {t("restoreRoleLabel")}
          </label>
          <select
            id={`restore-role-${member.appUserId}`}
            data-testid={includeTestIds ? `restore-role-${member.email}` : undefined}
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
            value={nextRole}
            onChange={(event) => setNextRole(event.target.value as StaffCanonicalRole)}
          >
            {STAFF_CANONICAL_ROLES.map((role) => (
              <option key={role} value={role}>
                {tRoles(roleLabelKey(role))}
              </option>
            ))}
          </select>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              disabled={submitting}
              className="rounded bg-slate-900 px-3 py-1.5 text-xs font-medium text-white disabled:opacity-60"
              onClick={() =>
                run(() =>
                  restoreRemovedStaff({
                    appUserId: member.appUserId,
                    canonicalRole: nextRole,
                  }),
                )
              }
            >
              {submitting ? t("working") : t("confirmRestore")}
            </button>
            <button
              type="button"
              className="rounded border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-800"
              onClick={() => setAction(null)}
            >
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : null}

      {errorMessage ? (
        <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-800" role="alert">
          {errorMessage}
        </p>
      ) : null}
      {result?.ok ? (
        <p className="text-xs text-emerald-800" data-testid="lifecycle-success">
          {t("success")}
        </p>
      ) : null}
    </div>
  );
}
