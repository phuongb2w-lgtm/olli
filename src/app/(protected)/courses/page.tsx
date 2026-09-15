import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { CourseListCards } from "@/components/courses/course-list-cards";
import { CourseListPagination } from "@/components/courses/course-list-pagination";
import { CourseListTable } from "@/components/courses/course-list-table";
import { queryCourseList } from "@/lib/academic/query-course-list";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function CoursesPage({ searchParams }: Props) {
  const t = await getTranslations("courses");
  const rawParams = await searchParams;
  const hasRead = await can("enrollment.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const hasCreate = await can("enrollment.create");
  const hasUpdate = await can("enrollment.update");
  const successParam = rawParams.success;
  const success =
    successParam === "created" || successParam === "updated" ? successParam : null;

  const supabase = await createClient();
  const { result, error } = await queryCourseList(supabase, rawParams);

  if (error || !result) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  const { items, totalCount, params } = result;
  const isEmptyOrg = totalCount === 0;
  const isNoResults = false;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <div className="flex flex-wrap gap-3">
          <Link
            href="/classes"
            className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
          >
            {t("backToClasses")}
          </Link>
          {hasCreate ? (
            <Link
              href="/courses/new"
              className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
            >
              {t("createCourse")}
            </Link>
          ) : null}
        </div>
      </div>

      {success === "created" ? (
        <p
          className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800"
          role="status"
        >
          {t("createdSuccess")}
        </p>
      ) : null}
      {success === "updated" ? (
        <p
          className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800"
          role="status"
        >
          {t("updatedSuccess")}
        </p>
      ) : null}

      {isEmptyOrg ? (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("emptyOrganization")}</p>
        </section>
      ) : null}

      {isNoResults ? (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("noResults")}</p>
        </section>
      ) : null}

      {items.length > 0 ? (
        <>
          <CourseListTable items={items} canUpdate={hasUpdate} />
          <CourseListCards items={items} canUpdate={hasUpdate} />
          <CourseListPagination params={params} totalCount={totalCount} />
        </>
      ) : null}
    </div>
  );
}
