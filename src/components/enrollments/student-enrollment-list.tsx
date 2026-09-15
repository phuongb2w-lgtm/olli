import { getTranslations } from "next-intl/server";
import type { StudentEnrollmentItem } from "@/lib/enrollments/query-student-enrollments";

type Props = {
  items: StudentEnrollmentItem[];
};

export async function StudentEnrollmentList({ items }: Props) {
  const t = await getTranslations("enrollments");
  const tStatus = await getTranslations("status.enrollment");
  const placeholder = t("emptyValue");

  if (items.length === 0) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
        <p>{t("noEnrollments")}</p>
      </section>
    );
  }

  return (
    <>
      <div className="hidden overflow-x-auto lg:block">
        <table className="min-w-full divide-y divide-slate-200 text-sm">
          <thead className="bg-slate-50">
            <tr>
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                {t("classColumn")}
              </th>
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                {t("courseColumn")}
              </th>
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                {t("statusColumn")}
              </th>
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                {t("startDate")}
              </th>
              <th scope="col" className="px-4 py-3 text-left font-medium text-slate-700">
                {t("endDate")}
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200 bg-white">
            {items.map((item) => (
              <tr key={item.enrollmentId}>
                <td className="px-4 py-3 font-medium text-slate-900">{item.className}</td>
                <td className="px-4 py-3 text-slate-700">
                  <span className="block font-medium">{item.courseCode}</span>
                  <span className="text-xs text-slate-500">{item.courseName}</span>
                </td>
                <td className="px-4 py-3">
                  <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                    {tStatus(item.status)}
                  </span>
                </td>
                <td className="px-4 py-3 text-slate-700">{item.startDate}</td>
                <td className="px-4 py-3 text-slate-700">{item.endDate ?? placeholder}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <ul className="space-y-3 lg:hidden">
        {items.map((item) => (
          <li
            key={item.enrollmentId}
            className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="font-medium text-slate-900">{item.className}</p>
                <p className="text-sm text-slate-600">
                  {item.courseCode} — {item.courseName}
                </p>
              </div>
              <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                {tStatus(item.status)}
              </span>
            </div>
            <dl className="mt-3 space-y-1 text-sm">
              <div className="flex gap-2">
                <dt className="text-slate-500">{t("startDate")}:</dt>
                <dd>{item.startDate}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-slate-500">{t("endDate")}:</dt>
                <dd>{item.endDate ?? placeholder}</dd>
              </div>
            </dl>
          </li>
        ))}
      </ul>
    </>
  );
}
