import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { ClassListItem } from "@/lib/academic/query-class-list";

type Props = {
  items: ClassListItem[];
  canUpdate: boolean;
  canViewRoster: boolean;
};

export async function ClassListTable({ items, canUpdate, canViewRoster }: Props) {
  const t = await getTranslations("classes");
  const tEnroll = await getTranslations("enrollments");
  const tStatus = await getTranslations("status.class");
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
              {t("courseColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("statusColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("termStartColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("termEndColumn")}
            </th>
            {canUpdate || canViewRoster ? (
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
              <td className="px-4 py-3 text-slate-700">
                <span className="block font-medium">{item.courseCode}</span>
                <span className="text-xs text-slate-500">{item.courseName}</span>
              </td>
              <td className="px-4 py-3">
                <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                  {tStatus(item.status)}
                </span>
              </td>
              <td className="px-4 py-3 text-slate-700">{item.termStartDate ?? placeholder}</td>
              <td className="px-4 py-3 text-slate-700">{item.termEndDate ?? placeholder}</td>
              {canUpdate || canViewRoster ? (
                <td className="px-4 py-3">
                  <div className="flex flex-col gap-1">
                    {canViewRoster ? (
                      <Link
                        href={`/classes/${item.id}/roster`}
                        className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                      >
                        {tEnroll("classRoster")}
                      </Link>
                    ) : null}
                    {canUpdate ? (
                      <Link
                        href={`/classes/${item.id}/edit`}
                        className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                      >
                        {t("editClass")}
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
