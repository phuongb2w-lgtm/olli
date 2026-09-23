"use client";

import { useTranslations } from "next-intl";
import type { OwnerCommercialStatusPayload } from "@/lib/auth/session-commercial-access";

type Props = {
  status: OwnerCommercialStatusPayload | null;
};

function statusMessageKey(status: string | undefined): string {
  switch (status) {
    case "provisioning":
      return "commercial.statusProvisioning";
    case "suspended":
      return "commercial.statusSuspended";
    case "cancelled":
      return "commercial.statusCancelled";
    case "missing":
      return "commercial.statusMissing";
    default:
      return "commercial.statusRestricted";
  }
}

export function OwnerSubscriptionStatusPanel({ status }: Props) {
  const t = useTranslations();
  const subscriptionStatus = status?.subscription_status ?? "missing";

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold text-slate-900">{t("commercial.ownerTitle")}</h2>
        <p className="mt-2 text-sm text-slate-700">{t(statusMessageKey(subscriptionStatus))}</p>
      </div>
      <dl className="grid gap-3 rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm">
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.plan")}</dt>
          <dd className="font-medium text-slate-900">
            {status?.plan_name ?? "—"} ({status?.plan_code ?? "—"})
          </dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.subscriptionStatus")}</dt>
          <dd className="font-medium text-slate-900">{subscriptionStatus}</dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.seats")}</dt>
          <dd className="font-medium text-slate-900">
            {status?.staff_seats_used ?? "—"} / {status?.staff_limit ?? "—"}
          </dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt className="text-slate-600">{t("commercial.organizationStatus")}</dt>
          <dd className="font-medium text-slate-900">{status?.organization_status ?? "—"}</dd>
        </div>
      </dl>
      <p className="text-sm text-slate-600">{t("commercial.ownerContact")}</p>
    </div>
  );
}
