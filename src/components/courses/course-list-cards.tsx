import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { CourseListItem } from "@/lib/academic/query-course-list";

type Props = {
  items: CourseListItem[];
  canUpdate: boolean;
};

export async function CourseListCards({ items, canUpdate }: Props) {
  const t = await getTranslations("courses");
  const tStatus = await getTranslations("status.course");
  const placeholder = t("emptyValue");

  return (
    <ul className="space-y-3 lg:hidden">
      {items.map((item) => (
        <li
          key={item.id}
          className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
        >
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="font-medium text-slate-900">{item.name}</p>
              <p className="text-sm text-slate-600">{item.code}</p>
            </div>
            <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
              {tStatus(item.status)}
            </span>
          </div>
          <dl className="mt-3 space-y-1 text-sm">
            <div className="flex gap-2">
              <dt className="text-slate-500">{t("levelColumn")}:</dt>
              <dd className="text-slate-800">{item.levelCode ?? placeholder}</dd>
            </div>
          </dl>
          {canUpdate ? (
            <div className="mt-3">
              <Link
                href={`/courses/${item.id}/edit`}
                className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
              >
                {t("editCourse")}
              </Link>
            </div>
          ) : null}
        </li>
      ))}
    </ul>
  );
}
