"use client";

import { useLocale, useTranslations } from "next-intl";
import type { OwnerCommercialStatusPayload } from "@/lib/auth/session-commercial-access";

type Props = {
  status: OwnerCommercialStatusPayload;
  /** Page title uses h1 in workspace; restricted shell uses h2. */
  titleAs: "h1" | "h2";
};

function statusExplanationKey(subscriptionStatus: string): string {
  switch (subscriptionStatus) {
    case "active":
      return "commercial.statusActive";
    case "provisioning":
      return "commercial.statusProvisioning";
    case "suspended":
      return "commercial.statusSuspended";
    case "cancelled":
      return "commercial.statusCancelled";
    default:
      return "commercial.statusRestricted";
  }
}

function statusLabelKey(subscriptionStatus: string): string {
  switch (subscriptionStatus) {
    case "active":
    case "provisioning":
    case "suspended":
    case "cancelled":
      return `commercial.subscriptionStatusValue.${subscriptionStatus}`;
    default:
      return "commercial.subscriptionStatusValue.unknown";
  }
}

function formatTimestamp(value: string | undefined, locale: string): string | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" }).format(
    date,
  );
}

export function OwnerCommercialStatusView({ status, titleAs }: Props) {
  const t = useTranslations();
  const locale = useLocale();
  const subscriptionStatus = status.subscription_status ?? "unknown";
  const used = status.staff_seats_used;
  const limit = status.staff_limit;
  const remaining =
    typeof used === "number" && typeof limit === "number"
      ? Math.max(0, limit - used)
      : null;

  const activatedAt = formatTimestamp(status.activated_at as string | undefined, locale);
  const suspendedAt = formatTimestamp(status.suspended_at as string | undefined, locale);
  const cancelledAt = formatTimestamp(status.cancelled_at as string | undefined, locale);

  const TitleTag = titleAs;
  const isRestricted = subscriptionStatus !== "active";

  return (
    <div className="space-y-6">
      <div>
        <TitleTag className="text-xl font-semibold text-slate-900">{t("commercial.pageTitle")}</TitleTag>
        <p className="mt-2 text-sm text-slate-700">{t(statusExplanationKey(subscriptionStatus))}</p>
      </div>

      {isRestricted ? (
        <div
          className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950"
          role="status"
        >
          {t("commercial.restrictedWorkspaceNotice")}
        </div>
      ) : null}

      <dl className="grid gap-3 rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm">
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.plan")}</dt>
          <dd className="font-medium text-slate-900">
            {status.plan_name ?? "—"} ({status.plan_code ?? "—"})
          </dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.subscriptionStatus")}</dt>
          <dd className="font-medium text-slate-900">{t(statusLabelKey(subscriptionStatus))}</dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.seatsUsed")}</dt>
          <dd className="font-medium text-slate-900">{used ?? "—"}</dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.seatsLimit")}</dt>
          <dd className="font-medium text-slate-900">{limit ?? "—"}</dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.seatsRemaining")}</dt>
          <dd className="font-medium text-slate-900">{remaining ?? "—"}</dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.organizationStatus")}</dt>
          <dd className="font-medium text-slate-900">{status.organization_status ?? "—"}</dd>
        </div>
        {activatedAt ? (
          <div className="flex justify-between gap-4">
            <dt className="text-slate-600">{t("commercial.activatedAt")}</dt>
            <dd className="font-medium text-slate-900">{activatedAt}</dd>
          </div>
        ) : null}
        {suspendedAt ? (
          <div className="flex justify-between gap-4">
            <dt className="text-slate-600">{t("commercial.suspendedAt")}</dt>
            <dd className="font-medium text-slate-900">{suspendedAt}</dd>
          </div>
        ) : null}
        {cancelledAt ? (
          <div className="flex justify-between gap-4">
            <dt className="text-slate-600">{t("commercial.cancelledAt")}</dt>
            <dd className="font-medium text-slate-900">{cancelledAt}</dd>
          </div>
        ) : null}
      </dl>

      <p className="text-sm text-slate-600">{t("commercial.ownerContact")}</p>
      <p className="text-xs text-slate-500">{t("commercial.operatorMutationsNotice")}</p>
    </div>
  );
}
