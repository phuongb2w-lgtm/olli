import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { buildRosterUrl } from "@/lib/enrollments/build-roster-url";
import type { RosterListParams } from "@/lib/enrollments/parse-roster-params";

type Props = {
  classId: string;
  params: RosterListParams;
  totalCount: number;
};

export async function RosterPagination({ classId, params, totalCount }: Props) {
  const t = await getTranslations("enrollments");
  const totalPages = Math.max(1, Math.ceil(totalCount / params.pageSize));
  const page = params.page;

  if (totalCount === 0) return null;

  const prevHref = page > 1 ? buildRosterUrl(classId, { ...params, page: page - 1 }) : null;
  const nextHref =
    page < totalPages ? buildRosterUrl(classId, { ...params, page: page + 1 }) : null;

  return (
    <nav
      className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
      aria-label={t("paginationLabel")}
    >
      <p className="text-sm text-slate-600">
        {t("paginationSummary", {
          from: (page - 1) * params.pageSize + 1,
          to: Math.min(page * params.pageSize, totalCount),
          total: totalCount,
        })}
      </p>
      <div className="flex items-center gap-2">
        {prevHref ? (
          <Link
            href={prevHref}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50"
          >
            {t("previous")}
          </Link>
        ) : (
          <span className="rounded-md border border-slate-200 px-3 py-1.5 text-sm text-slate-400">
            {t("previous")}
          </span>
        )}
        <span className="text-sm text-slate-600">
          {t("pageIndicator", { page, totalPages })}
        </span>
        {nextHref ? (
          <Link
            href={nextHref}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50"
          >
            {t("next")}
          </Link>
        ) : (
          <span className="rounded-md border border-slate-200 px-3 py-1.5 text-sm text-slate-400">
            {t("next")}
          </span>
        )}
      </div>
    </nav>
  );
}
