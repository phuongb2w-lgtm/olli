import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { ExecutiveExceptionsWorklist } from "@/components/executive/executive-exceptions-worklist";
import { ReportingPeriodFilterForm } from "@/components/finance/reporting-period-filter-form";
import { resolveLocale } from "@/i18n/resolve-locale";
import { getIdentityState } from "@/lib/auth/get-identity-state";
import { can } from "@/lib/permissions/can";
import {
  fetchExecutiveExceptions,
  type ExecutiveExceptionListFilters,
} from "@/lib/reporting/executive-read-model";
import { buildReportingHref } from "@/lib/reporting/build-reporting-href";
import { parseReportingSearchParams } from "@/lib/reporting/parse-reporting-search-params";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

function firstParam(value: string | string[] | undefined): string | undefined {
  if (Array.isArray(value)) return value[0];
  return value;
}

export default async function ExecutiveExceptionsPage({ searchParams }: Props) {
  const t = await getTranslations("executive.exceptions");
  const identity = await getIdentityState();
  const locale = await resolveLocale(identity.kind === "active" ? identity.appUser : null);
  const rawParams = await searchParams;
  const { period, comparePrevious } = parseReportingSearchParams(rawParams);

  if (!(await can("report.executive.read"))) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  const domainParam = firstParam(rawParams.domain);
  const exceptionCode = firstParam(rawParams.exceptionCode)?.trim() || undefined;
  const followUpStatus = firstParam(rawParams.followUpStatus)?.trim() as
    | ExecutiveExceptionListFilters["followUpStatus"]
    | undefined;
  const search = firstParam(rawParams.q)?.trim() || undefined;

  const filters: ExecutiveExceptionListFilters = {
    domain:
      domainParam === "finance" ||
      domainParam === "admissions" ||
      domainParam === "quality" ||
      domainParam === "operations"
        ? domainParam
        : undefined,
    exceptionCode,
    followUpStatus,
    search,
    includeHistorical: true,
  };

  const supabase = await createClient();
  const { rows, error } = await fetchExecutiveExceptions(supabase, period, filters);
  const canManageFollowUp = await can("report.executive.follow_up.manage");

  const filterQuery = new URLSearchParams();
  filterQuery.set("start", period.startDate);
  filterQuery.set("end", period.endDate);
  if (filters.domain) filterQuery.set("domain", filters.domain);
  if (filters.exceptionCode) filterQuery.set("exceptionCode", filters.exceptionCode);
  if (filters.followUpStatus) filterQuery.set("followUpStatus", filters.followUpStatus);
  if (filters.search) filterQuery.set("q", filters.search);

  const baseFilterPath = `/executive/exceptions?${filterQuery.toString()}`;

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <p className="text-sm">
          <Link
            href={buildReportingHref("/executive", period, { comparePrevious })}
            className="underline"
          >
            {t("backToExecutive")}
          </Link>
        </p>
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <p className="text-sm text-slate-600">{t("description")}</p>
      </div>

      <ReportingPeriodFilterForm
        action="/executive/exceptions"
        startDate={period.startDate}
        endDate={period.endDate}
        comparePrevious={false}
      />

      <form method="get" className="grid gap-3 rounded-lg border border-slate-200 bg-white p-4 sm:grid-cols-2 lg:grid-cols-4">
        <input type="hidden" name="start" value={period.startDate} />
        <input type="hidden" name="end" value={period.endDate} />
        <div>
          <label className="text-xs font-medium text-slate-700" htmlFor="domain">
            {t("filterDomain")}
          </label>
          <select
            id="domain"
            name="domain"
            defaultValue={filters.domain ?? ""}
            className="mt-1 block w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
          >
            <option value="">{t("filterAllDomains")}</option>
            <option value="finance">{t("domainFinance")}</option>
            <option value="admissions">{t("domainAdmissions")}</option>
            <option value="quality">{t("domainQuality")}</option>
            <option value="operations">{t("domainOperations")}</option>
          </select>
        </div>
        <div>
          <label className="text-xs font-medium text-slate-700" htmlFor="followUpStatus">
            {t("filterFollowUpStatus")}
          </label>
          <select
            id="followUpStatus"
            name="followUpStatus"
            defaultValue={filters.followUpStatus ?? ""}
            className="mt-1 block w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
          >
            <option value="">{t("filterAnyFollowUp")}</option>
            <option value="open">{t("statusOpen")}</option>
            <option value="acknowledged">{t("statusAcknowledged")}</option>
            <option value="resolved">{t("statusResolved")}</option>
            <option value="dismissed">{t("statusDismissed")}</option>
          </select>
        </div>
        <div>
          <label className="text-xs font-medium text-slate-700" htmlFor="exceptionCode">
            {t("filterExceptionCode")}
          </label>
          <input
            id="exceptionCode"
            name="exceptionCode"
            defaultValue={filters.exceptionCode ?? ""}
            className="mt-1 block w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
          />
        </div>
        <div>
          <label className="text-xs font-medium text-slate-700" htmlFor="q">
            {t("filterSearch")}
          </label>
          <input
            id="q"
            name="q"
            defaultValue={filters.search ?? ""}
            className="mt-1 block w-full rounded border border-slate-300 px-2 py-1.5 text-sm"
          />
        </div>
        <div className="sm:col-span-2 lg:col-span-4">
          <button
            type="submit"
            className="rounded bg-slate-900 px-3 py-1.5 text-xs font-medium text-white"
          >
            {t("applyFilters")}
          </button>
        </div>
      </form>

      <div className="flex flex-wrap gap-2 text-xs">
        <Link href={`${baseFilterPath}&domain=finance`} className="underline">
          {t("domainFinance")}
        </Link>
        <Link href={`${baseFilterPath}&domain=admissions`} className="underline">
          {t("domainAdmissions")}
        </Link>
        <Link href={`${baseFilterPath}&domain=quality`} className="underline">
          {t("domainQuality")}
        </Link>
        <Link href={`${baseFilterPath}&domain=operations`} className="underline">
          {t("domainOperations")}
        </Link>
      </div>

      {error ? (
        <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          <p>{t("loadError")}</p>
        </section>
      ) : (
        <ExecutiveExceptionsWorklist
          rows={rows}
          locale={locale}
          canManageFollowUp={canManageFollowUp}
          labels={{
            empty: t("empty"),
            viewDrillDown: t("viewDrillDown"),
            viewDomain: t("viewDomain"),
            domainFinance: t("domainFinance"),
            domainAdmissions: t("domainAdmissions"),
            domainQuality: t("domainQuality"),
            domainOperations: t("domainOperations"),
            followUpTitle: t("followUpTitle"),
            statusLabel: t("statusLabel"),
            noteLabel: t("noteLabel"),
            notePlaceholder: t("notePlaceholder"),
            save: t("saveFollowUp"),
            saving: t("savingFollowUp"),
            permissionDenied: t("permissionDenied"),
            saveError: t("saveError"),
            statusOpen: t("statusOpen"),
            statusAcknowledged: t("statusAcknowledged"),
            statusResolved: t("statusResolved"),
            statusDismissed: t("statusDismissed"),
            sourceActive: t("sourceActive"),
            sourceInactive: t("sourceInactive"),
            followUpNone: t("followUpNone"),
            noReasonHistorical: t("noReasonHistorical"),
          }}
        />
      )}
    </div>
  );
}
