import Link from "next/link";
import { getTranslations } from "next-intl/server";
import type { ClassListItem } from "@/lib/academic/query-class-list";

type Props = {
  items: ClassListItem[];
  canUpdate: boolean;
  canViewRoster: boolean;
  canViewTeaching: boolean;
  canViewAssessments: boolean;
};

export async function ClassListCards({
  items,
  canUpdate,
  canViewRoster,
  canViewTeaching,
  canViewAssessments,
}: Props) {
  const t = await getTranslations("classes");
  const tEnroll = await getTranslations("enrollments");
  const tTeach = await getTranslations("teaching");
  const tAssess = await getTranslations("assessments");
  const tStatus = await getTranslations("status.class");
  const placeholder = t("emptyValue");

  return (
    <ul className="space-y-3 lg:hidden">
      {items.map((item) => (
        <li
          key={item.id}
          className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
        >
          <div className="flex items-start justify-between gap-3">
            <p className="font-medium text-slate-900">{item.name}</p>
            <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
              {tStatus(item.status)}
            </span>
          </div>
          <dl className="mt-3 space-y-1 text-sm">
            <div className="flex gap-2">
              <dt className="text-slate-500">{t("courseColumn")}:</dt>
              <dd className="text-slate-800">
                {item.courseCode} — {item.courseName}
              </dd>
            </div>
            <div className="flex gap-2">
              <dt className="text-slate-500">{t("termStartColumn")}:</dt>
              <dd className="text-slate-800">{item.termStartDate ?? placeholder}</dd>
            </div>
            <div className="flex gap-2">
              <dt className="text-slate-500">{t("termEndColumn")}:</dt>
              <dd className="text-slate-800">{item.termEndDate ?? placeholder}</dd>
            </div>
          </dl>
          {canUpdate || canViewRoster || canViewTeaching || canViewAssessments ? (
            <div className="mt-3 flex flex-wrap gap-3">
              {canViewRoster ? (
                <Link
                  href={`/classes/${item.id}/roster`}
                  className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                >
                  {tEnroll("classRoster")}
                </Link>
              ) : null}
              {canViewTeaching ? (
                <Link
                  href={`/classes/${item.id}/teaching`}
                  className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                >
                  {tTeach("title")}
                </Link>
              ) : null}
              {canViewAssessments ? (
                <Link
                  href={`/classes/${item.id}/assessments`}
                  className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
                >
                  {tAssess("title")}
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
          ) : null}
        </li>
      ))}
    </ul>
  );
}
