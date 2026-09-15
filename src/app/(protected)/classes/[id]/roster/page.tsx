import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { RosterCards } from "@/components/enrollments/roster-cards";
import { RosterFilters } from "@/components/enrollments/roster-filters";
import { RosterPagination } from "@/components/enrollments/roster-pagination";
import { RosterTable } from "@/components/enrollments/roster-table";
import { isRosterSearchActive } from "@/lib/enrollments/parse-roster-params";
import { queryClassRoster } from "@/lib/enrollments/query-class-roster";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ClassRosterPage({ params, searchParams }: Props) {
  const t = await getTranslations("enrollments");
  const { id: classId } = await params;
  const rawParams = await searchParams;
  const hasRead = await can("enrollment.read");

  if (!hasRead) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("classRoster")}</h1>
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
    successParam === "created" ||
    successParam === "withdrawn" ||
    successParam === "completed" ||
    successParam === "transferred"
      ? successParam
      : null;

  const supabase = await createClient();
  const { data: classRow, error: classError } = await supabase
    .from("class")
    .select("id, name, status, course_id")
    .eq("id", classId)
    .maybeSingle();

  if (classError || !classRow) notFound();

  const { data: course } = await supabase
    .from("course")
    .select("code, name")
    .eq("id", classRow.course_id)
    .maybeSingle();

  const { result, error } = await queryClassRoster(supabase, classId, rawParams);

  const { data: allClasses } = await supabase
    .from("class")
    .select("id, name, course_id")
    .neq("status", "closed")
    .order("name", { ascending: true });

  const courseIds = [...new Set((allClasses ?? []).map((c) => c.course_id))];
  const courseCodeById = new Map<string, string>();
  if (courseIds.length > 0) {
    const { data: courses } = await supabase.from("course").select("id, code").in("id", courseIds);
    for (const c of courses ?? []) courseCodeById.set(c.id, c.code);
  }

  if (error || !result) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("classRoster")}</h1>
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      </div>
    );
  }

  const classOptions = (allClasses ?? []).map((row) => ({
    id: row.id,
    name: row.name,
    courseCode: courseCodeById.get(row.course_id) ?? "",
  }));

  const { items, totalCount, params: listParams } = result;
  const hasFilters =
    isRosterSearchActive(listParams.q) || listParams.status !== "operational";
  const isEmptyClass = totalCount === 0 && !hasFilters;
  const isNoResults = totalCount === 0 && hasFilters;

  return (
    <div className="space-y-6">
      <div>
        <Link href="/classes" className="text-sm text-slate-600 hover:text-slate-900">
          ← {t("backToClasses")}
        </Link>
        <h1 className="mt-2 text-xl font-semibold">{t("classRoster")}</h1>
        <p className="mt-1 text-sm text-slate-600">
          {classRow.name}
          {course ? ` · ${course.code} — ${course.name}` : null}
        </p>
      </div>

      <div className="flex flex-wrap gap-3">
        {hasCreate && classRow.status !== "closed" ? (
          <Link
            href={`/classes/${classId}/roster/enroll`}
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
          >
            {t("enrollStudent")}
          </Link>
        ) : null}
      </div>

      {success === "created" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("createdSuccess")}
        </p>
      ) : null}
      {success === "withdrawn" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("withdrawnSuccess")}
        </p>
      ) : null}
      {success === "completed" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("completedSuccess")}
        </p>
      ) : null}
      {success === "transferred" ? (
        <p className="rounded-lg border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800" role="status">
          {t("transferredSuccess")}
        </p>
      ) : null}

      <RosterFilters params={listParams} classId={classId} />

      {isEmptyClass ? (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("noStudentsInClass")}</p>
        </section>
      ) : null}

      {isNoResults ? (
        <section className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600">
          <p>{t("noResults")}</p>
        </section>
      ) : null}

      {items.length > 0 ? (
        <>
          <RosterTable
            items={items}
            canUpdate={hasUpdate}
            classId={classId}
            classOptions={classOptions}
          />
          <RosterCards
            items={items}
            canUpdate={hasUpdate}
            classId={classId}
            classOptions={classOptions}
          />
          <RosterPagination classId={classId} params={listParams} totalCount={totalCount} />
        </>
      ) : null}
    </div>
  );
}
