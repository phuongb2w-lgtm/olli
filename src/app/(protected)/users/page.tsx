import { getTranslations } from "next-intl/server";
import { CenterAccountSummary } from "@/components/users/center-account-summary";
import { ProvisionStaffForm } from "@/components/users/provision-staff-form";
import { RemovedStaffList } from "@/components/users/removed-staff-list";
import { StaffAccountListCards } from "@/components/users/staff-account-list-cards";
import { StaffAccountListTable } from "@/components/users/staff-account-list-table";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { fetchCenterAccountAdministration } from "@/lib/center-accounts/fetch-center-account-administration";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const t = await getTranslations("users");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);

  if (!(await can("center_account.manage"))) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const supabase = await createClient();
  const { data, error } = await fetchCenterAccountAdministration(supabase);

  if (error || !data) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  const seatsFull = data.staffSeatsUsed >= data.staffLimit;

  return (
    <div className="space-y-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <p className="text-sm text-slate-600">{t("description")}</p>

      <CenterAccountSummary data={data} />

      <section className="space-y-3">
        <h2 className="text-sm font-semibold text-slate-900">{t("staffSectionTitle")}</h2>
        <StaffAccountListTable
          staff={data.staff}
          staffSeatsUsed={data.staffSeatsUsed}
          staffLimit={data.staffLimit}
        />
        <StaffAccountListCards
          staff={data.staff}
          staffSeatsUsed={data.staffSeatsUsed}
          staffLimit={data.staffLimit}
        />
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold text-slate-900">{t("removedSectionTitle")}</h2>
        <RemovedStaffList
          staff={data.removedStaff}
          staffSeatsUsed={data.staffSeatsUsed}
          staffLimit={data.staffLimit}
        />
      </section>

      <ProvisionStaffForm seatsFull={seatsFull} defaultLocale={locale} />
    </div>
  );
}
