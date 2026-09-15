"use client";

import { useActionState, useState, useTransition } from "react";
import { useTranslations } from "next-intl";
import {
  linkExistingGuardian,
  searchGuardiansAction,
  type GuardianActionState,
} from "@/app/actions/guardians";
import type { GuardianSearchItem } from "@/lib/guardians/query-guardian-search";
import { LinkOptionsFields } from "@/components/guardians/link-options-fields";

type Props = {
  studentId: string;
  canCreate: boolean;
};

const initialState: GuardianActionState = {};

export function GuardianLinkSearch({ studentId, canCreate }: Props) {
  const t = useTranslations("guardians");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<GuardianSearchItem[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [isSearching, startSearch] = useTransition();
  const [state, formAction, pending] = useActionState(linkExistingGuardian, initialState);

  if (!canCreate) return null;

  function handleSearch(event: React.FormEvent) {
    event.preventDefault();
    startSearch(async () => {
      const { items, error } = await searchGuardiansAction(query);
      if (!error) setResults(items);
    });
  }

  const globalError =
    state.error === "permission_denied"
      ? t("permissionDenied")
      : state.error === "already_linked"
        ? t("alreadyLinked")
        : state.error === "primary_conflict"
          ? t("primaryConflict")
          : state.error === "save_error"
            ? t("saveError")
            : null;

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
      <h2 className="text-sm font-semibold text-slate-900">{t("linkExistingGuardian")}</h2>

      {state.success === "linked" ? (
        <p className="mt-3 text-sm text-green-700" role="status">
          {t("linkedSuccess")}
        </p>
      ) : null}

      <form onSubmit={handleSearch} className="mt-4 flex flex-wrap gap-2">
        <label htmlFor="guardian-search" className="sr-only">
          {t("searchGuardian")}
        </label>
        <input
          id="guardian-search"
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={t("searchGuardianPlaceholder")}
          className="min-w-0 flex-1 rounded border border-slate-300 px-3 py-2 text-sm"
        />
        <button
          type="submit"
          disabled={isSearching || query.trim().length < 2}
          className="rounded border border-slate-300 px-4 py-2 text-sm font-medium hover:bg-slate-50 disabled:opacity-50"
        >
          {isSearching ? t("searching") : t("searchGuardian")}
        </button>
      </form>

      {results.length > 0 ? (
        <ul className="mt-4 space-y-2">
          {results.map((item) => (
            <li key={item.id}>
              <button
                type="button"
                onClick={() => setSelectedId(item.id === selectedId ? null : item.id)}
                className={`w-full rounded border px-3 py-2 text-left text-sm ${
                  selectedId === item.id
                    ? "border-slate-900 bg-slate-50"
                    : "border-slate-200 hover:bg-slate-50"
                }`}
              >
                <span className="font-medium">{item.name}</span>
                {item.phone ? (
                  <span className="block text-xs text-slate-500">{item.phone}</span>
                ) : null}
                {item.email ? (
                  <span className="block text-xs text-slate-500">{item.email}</span>
                ) : null}
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      {selectedId ? (
        <form action={formAction} className="mt-4 space-y-4 border-t border-slate-200 pt-4">
          <input type="hidden" name="studentId" value={studentId} />
          <input type="hidden" name="guardianId" value={selectedId} />
          <LinkOptionsFields idPrefix="link-" />
          {globalError ? (
            <p className="text-sm text-red-600" role="alert">
              {globalError}
            </p>
          ) : null}
          <button
            type="submit"
            disabled={pending}
            className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            {pending ? t("saving") : t("linkGuardian")}
          </button>
        </form>
      ) : null}
    </section>
  );
}
