import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { StudentListItem } from "@/lib/students/types";

type Props = {
  items: StudentListItem[];
  showPrimaryContact: boolean;
  canUpdate: boolean;
  canViewGuardians: boolean;
};

export async function StudentListTable({
  items,
  showPrimaryContact,
  canUpdate,
  canViewGuardians,
}: Props) {
  const t = await getTranslations("students");
  const tGuardians = await getTranslations("guardians");
  const tStatus = await getTranslations("status.student");
  const placeholder = t("emptyValue");

  return (
    <div className="hidden overflow-x-auto lg:block">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-50">
          <tr>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("nameColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("codeColumn")}
            </th>
            {showPrimaryContact ? (
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                {t("primaryContactColumn")}
              </th>
            ) : null}
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("statusColumn")}
            </th>
            {canUpdate || canViewGuardians ? (
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                <span className="sr-only">{t("actionsColumn")}</span>
              </th>
            ) : null}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-200 bg-white">
          {items.map((item) => (
            <tr key={item.id}>
              <td className="px-4 py-3 font-medium text-slate-900">{item.name}</td>
              <td className="px-4 py-3 text-slate-700">{item.studentCode ?? placeholder}</td>
              {showPrimaryContact ? (
                <td className="px-4 py-3 text-slate-700">
                  {item.primaryContact ? (
                    <span>
                      {item.primaryContact.name}
                      {item.primaryContact.phone ? (
                        <span className="block text-xs text-slate-500">
                          {item.primaryContact.phone}
                        </span>
                      ) : null}
                    </span>
                  ) : (
                    placeholder
                  )}
                </td>
              ) : null}
              <td className="px-4 py-3">
                <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                  {tStatus(item.status)}
                </span>
              </td>
              {canUpdate || canViewGuardians ? (
                <td className="px-4 py-3">
                  <div className="flex flex-col gap-1">
                    {canViewGuardians ? (
                      <Link
                        href={`/students/${item.id}/guardians`}
                        className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                      >
                        {tGuardians("manageGuardians")}
                      </Link>
                    ) : null}
                    {canUpdate ? (
                      <Link
                        href={`/students/${item.id}/edit`}
                        className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                      >
                        {t("editStudent")}
                      </Link>
                    ) : null}
                  </div>
                </td>
              ) : null}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
