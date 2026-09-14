import { getTranslations } from "next-intl/server";
import { STUDENT_PAGE_SIZES, STUDENT_STATUSES } from "@/lib/students/types";
import type { StudentListParams } from "@/lib/students/types";

type Props = {
  params: StudentListParams;
};

export async function StudentListFilters({ params }: Props) {
  const t = await getTranslations("students");
  const tStatus = await getTranslations("status.student");

  return (
    <form method="get" className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
      <div className="min-w-0 flex-1">
        <label htmlFor="student-search" className="mb-1 block text-sm font-medium text-slate-700">
          {t("search")}
        </label>
        <input
          id="student-search"
          name="q"
          type="search"
          defaultValue={params.q}
          placeholder={t("searchPlaceholder")}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          autoComplete="off"
        />
      </div>

      <div>
        <label htmlFor="student-status" className="mb-1 block text-sm font-medium text-slate-700">
          {t("statusColumn")}
        </label>
        <select
          id="student-status"
          name="status"
          defaultValue={params.status}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm sm:w-40"
        >
          <option value="all">{t("filterAll")}</option>
          {STUDENT_STATUSES.map((status) => (
            <option key={status} value={status}>
              {tStatus(status)}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="student-page-size" className="mb-1 block text-sm font-medium text-slate-700">
          {t("pageSize")}
        </label>
        <select
          id="student-page-size"
          name="pageSize"
          defaultValue={String(params.pageSize)}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm sm:w-28"
        >
          {STUDENT_PAGE_SIZES.map((size) => (
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
