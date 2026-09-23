"use client";

import { useTranslations } from "next-intl";
import type { OrganizationSubscriptionStatus } from "@/types/app-user";

type Props = {
  subscriptionStatus: OrganizationSubscriptionStatus | "missing";
};

function statusMessageKey(
  status: OrganizationSubscriptionStatus | "missing",
): string {
  switch (status) {
    case "provisioning":
      return "commercial.staffProvisioning";
    case "suspended":
      return "commercial.staffSuspended";
    case "cancelled":
      return "commercial.staffCancelled";
    case "missing":
      return "commercial.staffMissing";
    default:
      return "commercial.staffRestricted";
  }
}

export function StaffCommercialAccessPanel({ subscriptionStatus }: Props) {
  const t = useTranslations();

  return (
    <div className="rounded-lg border border-amber-200 bg-amber-50 p-6 text-sm text-amber-950">
      <h2 className="text-lg font-semibold">{t("commercial.staffTitle")}</h2>
      <p className="mt-3">{t(statusMessageKey(subscriptionStatus))}</p>
      <p className="mt-2 text-amber-800">{t("commercial.staffContactOwner")}</p>
    </div>
  );
}
