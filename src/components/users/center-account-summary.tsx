import { getTranslations } from "next-intl/server";
import { AccountAccessBadge } from "@/components/users/account-access-badge";
import type { CenterAccountAdministration } from "@/lib/center-accounts/types";

type Props = {
  data: CenterAccountAdministration;
};

export async function CenterAccountSummary({ data }: Props) {
  const t = await getTranslations("users");
  const owner = data.primaryOwner;
  const seatsFull = data.staffSeatsUsed >= data.staffLimit;

  return (
    <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="text-sm font-semibold text-slate-900">{t("summaryTitle")}</h2>

      <div className="rounded-lg border border-slate-100 bg-slate-50 p-4">
        <p className="text-xs font-medium uppercase tracking-wide text-slate-500">
          {t("primaryOwnerLabel")}
        </p>
        <p className="mt-1 text-base font-semibold text-slate-900">{owner.displayName}</p>
        <p className="text-sm text-slate-600">{owner.email}</p>
        <div className="mt-2">
          <AccountAccessBadge accessStatus={owner.accessStatus} />
        </div>
      </div>

      <div>
        <p className="text-sm text-slate-700">
          {t("staffSeatsUsage", {
            used: data.staffSeatsUsed,
            limit: data.staffLimit,
          })}
        </p>
        {seatsFull ? (
          <p className="mt-1 text-sm font-medium text-amber-800" role="status">
            {t("staffSeatsFull")}
          </p>
        ) : null}
      </div>
    </section>
  );
}
