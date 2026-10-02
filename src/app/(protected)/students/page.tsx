import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { StudentListCards } from "@/components/students/student-list-cards";
import { StudentListFilters } from "@/components/students/student-list-filters";
import { StudentListPagination } from "@/components/students/student-list-pagination";
import { StudentListWithPersonalFields } from "@/components/custom-fields/student-list-with-personal-fields";
import { StudentListTable } from "@/components/students/student-list-table";
import { can } from "@/lib/permissions/can";
import { isSearchActive } from "@/lib/students/parse-list-params";
import { queryStudentList } from "@/lib/students/query-student-list";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function StudentsPage({ searchParams }: Props) {
  const t = await getTranslations("students");
  const rawParams = await searchParams;
  const hasRead = await can("student.read");

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

  const hasGuardianRead = await can("guardian.read");
  const hasEnrollmentRead = await can("enrollment.read");
  const hasCreate = await can("student.create");
  const hasUpdate = await can("student.update");
  const canPersonalFields =
    (await can("student_personal_field.manage")) || (await can("consultant_custom_field.manage"));
  const successParam = rawParams.success;
  const success =
    successParam === "created" || successParam === "updated" ? successParam : null;
  const supabase = await createClient();
  const { result, error } = await queryStudentList(supabase, rawParams, {
    hasGuardianRead,
  });

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
  const isEmptyOrg = totalCount === 0 && !isSearchActive(params.q) && params.status === "all";
  const isNoResults = totalCount === 0 && !isEmptyOrg;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        {hasCreate ? (
          <Link
            href="/students/new"
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
          >
            {t("createStudent")}
          </Link>
        ) : null}
      </div>

      {success === "created" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("createdSuccess")}
        </p>
      ) : null}
      {success === "updated" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("updatedSuccess")}
        </p>
      ) : null}

      <StudentListFilters params={params} />

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
          {canPersonalFields ? (
            <StudentListWithPersonalFields
              items={items}
              showPrimaryContact={hasGuardianRead}
              canUpdate={hasUpdate}
              canViewGuardians={hasGuardianRead}
              canViewEnrollments={hasEnrollmentRead}
            />
          ) : (
            <StudentListTable
              items={items}
              showPrimaryContact={hasGuardianRead}
              canUpdate={hasUpdate}
              canViewGuardians={hasGuardianRead}
              canViewEnrollments={hasEnrollmentRead}
            />
          )}
          <StudentListCards
            items={items}
            showPrimaryContact={hasGuardianRead}
            canUpdate={hasUpdate}
            canViewGuardians={hasGuardianRead}
            canViewEnrollments={hasEnrollmentRead}
          />
          <StudentListPagination params={params} totalCount={totalCount} />
        </>
      ) : null}
    </div>
  );
}
