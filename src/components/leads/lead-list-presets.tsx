"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";
import { LEAD_WORKLIST_PRESETS, type LeadWorklistPreset } from "@/lib/leads/constants";
import type { LeadListParams } from "@/lib/leads/parse-list-params";

type Props = {
  params: LeadListParams;
};

const PRESET_KEYS = LEAD_WORKLIST_PRESETS.filter((p) => p !== "all") as Exclude<
  LeadWorklistPreset,
  "all"
>[];

function presetHref(preset: LeadWorklistPreset, current: LeadListParams): string {
  const search = new URLSearchParams();
  search.set("preset", preset);
  if (current.q) search.set("q", current.q);
  if (current.pageSize !== 25) search.set("pageSize", String(current.pageSize));
  return `/crm/leads?${search.toString()}`;
}

export function LeadListPresets({ params }: Props) {
  const t = useTranslations("crm.leads.presets");

  return (
    <div className="flex flex-wrap gap-2" role="navigation" aria-label={t("label")}>
      {PRESET_KEYS.map((preset) => {
        const isActive = params.preset === preset;
        return (
          <Link
            key={preset}
            href={presetHref(preset, params)}
            className={`rounded-full px-3 py-1 text-sm ${
              isActive
                ? "bg-slate-900 font-medium text-white"
                : "bg-slate-100 text-slate-700 hover:bg-slate-200"
            }`}
            aria-current={isActive ? "true" : undefined}
          >
            {t(preset)}
          </Link>
        );
      })}
      {params.preset !== "all" ? (
        <Link
          href="/crm/leads"
          className="rounded-full px-3 py-1 text-sm text-slate-600 underline"
        >
          {t("clear")}
        </Link>
      ) : null}
    </div>
  );
}
