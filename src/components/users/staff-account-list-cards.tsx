import { getTranslations } from "next-intl/server";
import { AccountAccessBadge } from "@/components/users/account-access-badge";
import { StaffLifecycleActions } from "@/components/users/staff-lifecycle-actions";
import type { CenterAccountStaffMember } from "@/lib/center-accounts/types";

type Props = {
  staff: CenterAccountStaffMember[];
  staffSeatsUsed: number;
  staffLimit: number;
};

export async function StaffAccountListCards({ staff, staffSeatsUsed, staffLimit }: Props) {
  const t = await getTranslations("users");
  const tRoles = await getTranslations("roles");

  if (staff.length === 0) {
    return (
      <p className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600 lg:hidden">
        {t("staffEmpty")}
      </p>
    );
  }

  return (
    <ul className="space-y-3 lg:hidden">
      {staff.map((member) => (
        <li
          key={member.appUserId}
          data-testid={`staff-card-${member.email}`}
          className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
        >
          <div className="flex items-start justify-between gap-3">
            <p className="font-medium text-slate-900">{member.displayName}</p>
            <AccountAccessBadge accessStatus={member.accessStatus} />
          </div>
          <dl className="mt-3 space-y-1 text-sm">
            <div className="flex gap-2">
              <dt className="text-slate-500">{t("emailColumn")}</dt>
              <dd className="text-slate-900">{member.email}</dd>
            </div>
            <div className="flex gap-2">
              <dt className="text-slate-500">{t("roleColumn")}</dt>
              <dd className="text-slate-900">
                {member.canonicalRole
                  ? tRoles(`${roleLabelKey(member.canonicalRole)}`)
                  : t("roleUnknown")}
              </dd>
            </div>
          </dl>
          <div className="mt-3">
            <StaffLifecycleActions
              member={member}
              staffSeatsUsed={staffSeatsUsed}
              staffLimit={staffLimit}
              variant="current"
              includeTestIds={false}
            />
          </div>
        </li>
      ))}
    </ul>
  );
}

function roleLabelKey(role: NonNullable<CenterAccountStaffMember["canonicalRole"]>): string {
  const map = {
    accountant: "accountant",
    consultant: "consultant",
    academic_operations: "academicOperations",
    teacher: "teacher",
  } as const;
  return map[role];
}
