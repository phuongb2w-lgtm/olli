import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { LeadListFilters } from "@/components/leads/lead-list-filters";
import { LeadListTable } from "@/components/leads/lead-list-table";
import { can } from "@/lib/permissions/can";
import { isLeadSearchActive } from "@/lib/leads/parse-list-params";
import { queryLeadList } from "@/lib/leads/query-lead-list";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function LeadsPage({ searchParams }: Props) {
  const t = await getTranslations("crm.leads");
  const hasRead = await can("lead.read");

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

  const rawParams = await searchParams;
  const supabase = await createClient();
  const { result, error } = await queryLeadList(supabase, rawParams);

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
  const isEmpty = totalCount === 0 && !isLeadSearchActive(params.q) && params.status === "all";
  const isNoResults = totalCount === 0 && !isEmpty;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <Link href="/crm/leads" className="text-sm text-slate-600 hover:text-slate-900">
          {t("refreshHint")}
        </Link>
      </div>

      <LeadListFilters params={params} />

      {isEmpty ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("emptyOrganization")}</p>
        </section>
      ) : null}

      {isNoResults ? (
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("noResults")}</p>
        </section>
      ) : null}

      {!isEmpty && !isNoResults ? <LeadListTable items={items} /> : null}
    </div>
  );
}
