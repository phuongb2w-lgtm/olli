import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { CourseListItem } from "@/lib/academic/query-course-list";

type Props = {
  items: CourseListItem[];
  canUpdate: boolean;
};

export async function CourseListTable({ items, canUpdate }: Props) {
  const t = await getTranslations("courses");
  const tStatus = await getTranslations("status.course");
  const placeholder = t("emptyValue");

  return (
    <div className="hidden overflow-x-auto lg:block">
      <table className="min-w-full divide-y divide-slate-200 text-sm">
        <thead className="bg-slate-50">
          <tr>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("codeColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("nameColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("levelColumn")}
            </th>
            <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
              {t("statusColumn")}
            </th>
            {canUpdate ? (
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                <span className="sr-only">{t("actionsColumn")}</span>
              </th>
            ) : null}
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-200 bg-white">
          {items.map((item) => (
            <tr key={item.id}>
              <td className="px-4 py-3 font-medium text-slate-900">{item.code}</td>
              <td className="px-4 py-3 text-slate-700">{item.name}</td>
              <td className="px-4 py-3 text-slate-700">{item.levelCode ?? placeholder}</td>
              <td className="px-4 py-3">
                <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                  {tStatus(item.status)}
                </span>
              </td>
              {canUpdate ? (
                <td className="px-4 py-3">
                  <Link
                    href={`/courses/${item.id}/edit`}
                    className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                  >
                    {t("editCourse")}
                  </Link>
                </td>
              ) : null}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
