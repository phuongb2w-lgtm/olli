import { getTranslations } from "next-intl/server";
import { AccountAccessBadge } from "@/components/users/account-access-badge";
import type { CenterAccountStaffMember } from "@/lib/center-accounts/types";

type Props = {
  staff: CenterAccountStaffMember[];
};

export async function StaffAccountListTable({ staff }: Props) {
  const t = await getTranslations("users");
  const tRoles = await getTranslations("roles");

  if (staff.length === 0) {
    return (
      <p className="hidden rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600 lg:block">
        {t("staffEmpty")}
      </p>
    );
  }

  return (
    <div className="hidden overflow-x-auto lg:block">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-50">
          <tr>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("nameColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("emailColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("roleColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("accessColumn")}
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-200 bg-white">
          {staff.map((member) => (
            <tr key={member.appUserId}>
              <td className="px-4 py-3 font-medium text-slate-900">{member.displayName}</td>
              <td className="px-4 py-3 text-slate-700">{member.email}</td>
              <td className="px-4 py-3 text-slate-700">
                {member.canonicalRole ? tRoles(`${roleLabelKey(member.canonicalRole)}`) : t("roleUnknown")}
              </td>
              <td className="px-4 py-3">
                <AccountAccessBadge accessStatus={member.accessStatus} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
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
