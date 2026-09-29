"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { ConsultantPortfolioDetailView } from "@/components/consultant-workspace/consultant-portfolio-detail-view";
import { fetchConsultantPortfolioEntryDetail } from "@/lib/consultant-workspace/fetch-portfolio-detail";
import type { ConsultantPortfolioDetail } from "@/lib/consultant-workspace/portfolio-detail-read-model";
import { createClient } from "@/lib/supabase/client";

type Props = {
  portfolioEntryId: string;
  startInEditMode: boolean;
};

export function ConsultantPortfolioDetailLoader({ portfolioEntryId, startInEditMode }: Props) {
  const t = useTranslations("consultantWorkspace.detail");
  const tWs = useTranslations("consultantWorkspace");
  const [state, setState] = useState<
    | { status: "loading" }
    | { status: "denied" }
    | { status: "not_found" }
    | { status: "error" }
    | { status: "ready"; detail: ConsultantPortfolioDetail }
  >({ status: "loading" });

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const supabase = createClient();
      const { data, error } = await fetchConsultantPortfolioEntryDetail(supabase, portfolioEntryId);
      if (cancelled) return;
      if (error?.includes("permission_denied") || error?.includes("42501")) {
        setState({ status: "denied" });
        return;
      }
      if (!data || error?.includes("not_found") || error?.includes("portfolio_entry_not_found")) {
        setState({ status: "not_found" });
        return;
      }
      if (error) {
        setState({ status: "error" });
        return;
      }
      setState({ status: "ready", detail: data });
    })();
    return () => {
      cancelled = true;
    };
  }, [portfolioEntryId]);

  if (state.status === "loading") {
    return (
      <p className="text-sm text-slate-600" data-testid="consultant-portfolio-detail-loading">
        {tWs("states.loadingMore")}
      </p>
    );
  }
  if (state.status === "denied") {
    return (
      <section
        className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600"
        data-testid="consultant-detail-denied"
      >
        <p>{t("denied")}</p>
      </section>
    );
  }
  if (state.status === "not_found") {
    return (
      <section
        className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600"
        data-testid="consultant-detail-not-found"
      >
        <p>{t("notFound")}</p>
      </section>
    );
  }
  if (state.status === "error") {
    return (
      <section
        className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600"
        data-testid="consultant-detail-error"
      >
        <p>{tWs("states.error")}</p>
      </section>
    );
  }

  return (
    <ConsultantPortfolioDetailView initialDetail={state.detail} startInEditMode={startInEditMode} />
  );
}
