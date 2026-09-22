import { getTranslations } from "next-intl/server";
import { StaffLifecycleActions } from "@/components/users/staff-lifecycle-actions";
import type { CenterAccountStaffMember } from "@/lib/center-accounts/types";

type Props = {
  staff: CenterAccountStaffMember[];
  staffSeatsUsed: number;
  staffLimit: number;
};

export async function RemovedStaffList({ staff, staffSeatsUsed, staffLimit }: Props) {
  const t = await getTranslations("users");
  const tRoles = await getTranslations("roles");

  if (staff.length === 0) {
    return (
      <p className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        {t("removedEmpty")}
      </p>
    );
  }

  return (
    <ul className="space-y-3" data-testid="removed-staff-section">
      {staff.map((member) => (
        <li
          key={member.appUserId}
          data-testid={`removed-staff-${member.email}`}
          className="rounded-lg border border-slate-200 bg-white p-4"
        >
          <p className="font-medium text-slate-900">{member.displayName}</p>
          <p className="text-sm text-slate-600">{member.email}</p>
          <p className="mt-1 text-sm text-slate-700">
            {t("lastRoleLabel")}:{" "}
            {member.canonicalRole ? tRoles(roleLabelKey(member.canonicalRole)) : t("roleUnknown")}
          </p>
          <div className="mt-3">
            <StaffLifecycleActions
              member={member}
              staffSeatsUsed={staffSeatsUsed}
              staffLimit={staffLimit}
              variant="removed"
            />
          </div>
        </li>
      ))}
    </ul>
  );
}

function roleLabelKey(
  role: NonNullable<CenterAccountStaffMember["canonicalRole"]>,
): string {
  const map = {
    accountant: "accountant",
    consultant: "consultant",
    academic_operations: "academicOperations",
    teacher: "teacher",
  } as const;
  return map[role];
}
