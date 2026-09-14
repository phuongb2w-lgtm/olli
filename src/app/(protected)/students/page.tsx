import { getTranslations } from "next-intl/server";
import { StudentListCards } from "@/components/students/student-list-cards";
import { StudentListFilters } from "@/components/students/student-list-filters";
import { StudentListPagination } from "@/components/students/student-list-pagination";
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
      <h1 className="text-xl font-semibold">{t("title")}</h1>

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
          <StudentListTable items={items} showPrimaryContact={hasGuardianRead} />
          <StudentListCards items={items} showPrimaryContact={hasGuardianRead} />
          <StudentListPagination params={params} totalCount={totalCount} />
        </>
      ) : null}
    </div>
  );
}
