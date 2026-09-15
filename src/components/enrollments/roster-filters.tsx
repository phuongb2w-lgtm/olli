import { getTranslations } from "next-intl/server";
import { ENROLLMENT_STATUSES, PAGE_SIZES } from "@/lib/enrollments/constants";
import type { RosterListParams } from "@/lib/enrollments/parse-roster-params";

type Props = {
  params: RosterListParams;
  classId: string;
};

export async function RosterFilters({ params }: Props) {
  const t = await getTranslations("enrollments");
  const tStatus = await getTranslations("status.enrollment");

  return (
    <form method="get" className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
      <div className="min-w-0 flex-1">
        <label htmlFor="roster-search" className="mb-1 block text-sm font-medium text-slate-700">
          {t("search")}
        </label>
        <input
          id="roster-search"
          name="q"
          type="search"
          defaultValue={params.q}
          placeholder={t("searchPlaceholder")}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          autoComplete="off"
        />
      </div>

      <div>
        <label htmlFor="roster-status" className="mb-1 block text-sm font-medium text-slate-700">
          {t("statusColumn")}
        </label>
        <select
          id="roster-status"
          name="status"
          defaultValue={params.status}
          className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm sm:w-44"
        >
          <option value="operational">{t("filterOperational")}</option>
          <option value="all">{t("filterAll")}</option>
          {ENROLLMENT_STATUSES.map((status) => (
            <option key={status} value={status}>
              {tStatus(status)}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="roster-page-size" className="mb-1 block text-sm font-medium text-slate-700">
          {t("pageSize")}
        </label>
        <select
          id="roster-page-size"
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
