import { getTranslations } from "next-intl/server";
import { CLASS_STATUSES, PAGE_SIZES } from "@/lib/academic/constants";
import type { ClassListParams } from "@/lib/academic/parse-list-params";

type CourseOption = {
  id: string;
  code: string;
  name: string;
};

type Props = {
  params: ClassListParams;
  courses: CourseOption[];
};

export async function ClassListFilters({ params, courses }: Props) {
  const t = await getTranslations("classes");
  const tStatus = await getTranslations("status.class");

  return (
    <form method="get" className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
      <div className="min-w-0 flex-1">
        <label htmlFor="class-search" className="mb-1 block text-sm font-medium text-slate-700">
          {t("search")}
        </label>
        <input
          id="class-search"
          name="q"
          type="search"
          defaultValue={params.q}
          placeholder={t("searchPlaceholder")}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          autoComplete="off"
        />
      </div>

      <div>
        <label htmlFor="class-course" className="mb-1 block text-sm font-medium text-slate-700">
          {t("courseFilter")}
        </label>
        <select
          id="class-course"
          name="course"
          defaultValue={params.course}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm sm:w-48"
        >
          <option value="">{t("filterAll")}</option>
          {courses.map((course) => (
            <option key={course.id} value={course.id}>
              {course.code} — {course.name}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="class-status" className="mb-1 block text-sm font-medium text-slate-700">
          {t("statusColumn")}
        </label>
        <select
          id="class-status"
          name="status"
          defaultValue={params.status}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm sm:w-40"
        >
          <option value="all">{t("filterAll")}</option>
          {CLASS_STATUSES.map((status) => (
            <option key={status} value={status}>
              {tStatus(status)}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="class-page-size" className="mb-1 block text-sm font-medium text-slate-700">
          {t("pageSize")}
        </label>
        <select
          id="class-page-size"
          name="pageSize"
          defaultValue={String(params.pageSize)}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm sm:w-28"
        >
          {PAGE_SIZES.map((size) => (
            <option key={size} value={size}>
              {size}
            </option>
          ))}
        </select>
      </div>

      <button
        type="submit"
        className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800"
      >
        {t("applyFilters")}
      </button>
    </form>
  );
}
