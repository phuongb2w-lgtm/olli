"use client";

import Link from "next/link";
import {
  flexRender,
  getCoreRowModel,
  useReactTable,
  type ColumnDef,
  type VisibilityState,
} from "@tanstack/react-table";
import { useVirtualizer } from "@tanstack/react-virtual";
import {
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  useTransition,
} from "react";
import { useSearchParams } from "next/navigation";
import { useLocale, useTranslations } from "next-intl";
import {
  hideConsultantGridRowAction,
  restoreConsultantGridRowAction,
  saveConsultantGridPreferencesAction,
} from "@/app/actions/consultant-workspace";
import { fetchConsultantWorkspacePortfolio } from "@/lib/consultant-workspace/fetch-portfolio";
import {
  createConsultantWorkspacePortfolioIntake,
  saveConsultantPortfolioCustomFields,
  saveConsultantPortfolioProfile,
} from "@/lib/consultant-workspace/fetch-portfolio-detail";
import { createClient } from "@/lib/supabase/client";
import { formatPortfolioNamePart, detailsHref } from "@/lib/consultant-workspace/display-format";
import {
  DEFAULT_COLUMN_ORDER,
  mergeGridPreferences,
  PROTECTED_VISIBILITY_COLUMNS,
  type ConsultantGridPreferences,
} from "@/lib/consultant-workspace/grid-preferences";
import type {
  ConsultantWorkspacePortfolioRow,
  ConsultantWorkspacePortfolioCursor,
} from "@/lib/consultant-workspace/portfolio-read-model";
import { formatMoneyVnd } from "@/lib/formatting";
import type { Locale } from "@/i18n/config";
import { ConsultantMonthlySalesHeader } from "@/components/consultant-workspace/consultant-monthly-sales-header";
import { PaymentDeclarationDrawer } from "@/components/consultant-workspace/payment-declaration-drawer";

type CourseOption = { id: string; name: string };

type Props = {
  initialPreferences: ConsultantGridPreferences | null;
  courseOptions: CourseOption[];
};

type QueryState = {
  familyNameFilter: string;
  givenNameFilter: string;
  studentCode: string;
  guardianPhone: string;
  lifecycleStatus: string;
  tuitionPaymentState: string;
  sortField: string;
  sortDirection: "asc" | "desc";
  includeHidden: boolean;
};

type CustomFieldDef = {
  definition_id: string;
  field_key: string;
  label: string;
  data_type: string;
};

type InlineDraft = {
  familyName: string;
  givenName: string;
  guardianName: string;
  guardianPhone: string;
  customFields: Record<string, string>;
};

const COLUMN_LABEL_KEY: Record<string, string> = {
  stt: "columns.stt",
  family_name: "columns.familyName",
  given_name: "columns.givenName",
  student_code: "columns.studentCode",
  lifecycle_status: "columns.status",
  guardian_name: "columns.guardian",
  guardian_phone: "columns.phone",
  tuition: "columns.tuition",
  details: "columns.details",
  edit: "columns.saveEdit",
};

const DEFAULT_QUERY: QueryState = {
  familyNameFilter: "",
  givenNameFilter: "",
  studentCode: "",
  guardianPhone: "",
  lifecycleStatus: "",
  tuitionPaymentState: "",
  sortField: "workspace_sequence",
  sortDirection: "desc",
  includeHidden: false,
};

const EMPTY_DRAFT: InlineDraft = {
  familyName: "",
  givenName: "",
  guardianName: "",
  guardianPhone: "",
  customFields: {},
};

function buildFilters(q: QueryState) {
  const filters: Record<string, string> = {};
  if (q.familyNameFilter.trim()) filters.family_name = q.familyNameFilter.trim();
  if (q.givenNameFilter.trim()) filters.given_name = q.givenNameFilter.trim();
  if (q.studentCode.trim()) filters.student_code = q.studentCode.trim();
  if (q.guardianPhone.trim()) filters.guardian_phone = q.guardianPhone.trim();
  if (q.lifecycleStatus) filters.lifecycle_status = q.lifecycleStatus;
  if (q.tuitionPaymentState) filters.tuition_payment_state = q.tuitionPaymentState;
  return filters;
}

function collectCustomFieldKeys(
  rows: ConsultantWorkspacePortfolioRow[],
  defs: CustomFieldDef[],
): string[] {
  const keys = new Set<string>();
  for (const d of defs) keys.add(d.field_key);
  for (const row of rows) {
    for (const cf of row.custom_fields ?? []) {
      keys.add(cf.field_key);
    }
  }
  return [...keys].sort();
}

function splitGuardianName(full: string): { familyName: string; givenName: string } {
  const trimmed = full.trim();
  if (!trimmed) return { familyName: "", givenName: "" };
  const parts = trimmed.split(/\s+/);
  if (parts.length === 1) return { familyName: parts[0]!, givenName: parts[0]! };
  return { familyName: parts[0]!, givenName: parts.slice(1).join(" ") };
}

function draftFromRow(row: ConsultantWorkspacePortfolioRow, fieldKeys: string[]): InlineDraft {
  const customFields: Record<string, string> = {};
  for (const key of fieldKeys) {
    customFields[key] = row.custom_fields?.find((f) => f.field_key === key)?.value ?? "";
  }
  return {
    familyName: row.family_name ?? "",
    givenName: row.given_name ?? "",
    guardianName: row.primary_guardian_name ?? "",
    guardianPhone: row.primary_guardian_phone ?? "",
    customFields,
  };
}

export function ConsultantPortfolioWorkspace({ initialPreferences }: Props) {
  const t = useTranslations("consultantWorkspace");
  const locale = useLocale() as Locale;
  const searchParams = useSearchParams();
  const consultantReturnQuery = useMemo(() => {
    const q = searchParams.toString();
    return q ? `/consultant?${q}` : "/consultant";
  }, [searchParams]);
  const mergedPrefs = useMemo(() => mergeGridPreferences(initialPreferences), [initialPreferences]);

  const [query, setQuery] = useState<QueryState>(DEFAULT_QUERY);
  const [appliedQuery, setAppliedQuery] = useState<QueryState>(DEFAULT_QUERY);
  const [rows, setRows] = useState<ConsultantWorkspacePortfolioRow[]>([]);
  const [cursor, setCursor] = useState<ConsultantWorkspacePortfolioCursor | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [loadState, setLoadState] = useState<"idle" | "loading" | "error">("idle");
  const [hasLoadedOnce, setHasLoadedOnce] = useState(false);
  const [columnSizing, setColumnSizing] = useState(mergedPrefs.columnSizing ?? {});
  const [columnVisibility, setColumnVisibility] = useState<VisibilityState>(
    mergedPrefs.columnVisibility ?? {},
  );
  const [focusedCell, setFocusedCell] = useState<{ row: number; col: number } | null>(null);
  const [pending, startTransition] = useTransition();
  const [declarationRow, setDeclarationRow] = useState<ConsultantWorkspacePortfolioRow | null>(
    null,
  );
  const [customFieldDefs, setCustomFieldDefs] = useState<CustomFieldDef[]>([]);
  const [newEntryDraft, setNewEntryDraft] = useState<InlineDraft>(EMPTY_DRAFT);
  const [editingEntryId, setEditingEntryId] = useState<string | null>(null);
  const [editDraft, setEditDraft] = useState<InlineDraft>(EMPTY_DRAFT);
  const [inlineError, setInlineError] = useState<string | null>(null);
  const [savingInline, setSavingInline] = useState(false);
  const declarationTriggerRef = useRef<HTMLButtonElement>(null);

  const scrollRef = useRef<HTMLDivElement>(null);
  const filterDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const customFieldKeys = useMemo(
    () => collectCustomFieldKeys(rows, customFieldDefs),
    [rows, customFieldDefs],
  );

  useEffect(() => {
    void (async () => {
      const supabase = createClient();
      const { data } = await supabase
        .from("consultant_custom_field_definition")
        .select("id, field_key, label, data_type")
        .eq("status", "active")
        .order("sort_order");
      if (data) {
        setCustomFieldDefs(
          data.map((row) => ({
            definition_id: row.id,
            field_key: row.field_key,
            label: row.label ?? row.field_key,
            data_type: row.data_type ?? "text",
          })),
        );
      }
    })();
  }, []);

  const loadPage = useCallback(
    async (
      q: QueryState,
      append: boolean,
      nextCursor: ConsultantWorkspacePortfolioCursor | null,
    ) => {
      setLoadState("loading");
      const supabase = createClient();
      const { data, error } = await fetchConsultantWorkspacePortfolio(supabase, {
        filters: buildFilters(q),
        sortField: q.sortField,
        sortDirection: q.sortDirection,
        includeHidden: q.includeHidden,
        limit: 50,
        cursorWorkspaceSequence: append ? nextCursor?.workspace_sequence : null,
        cursorPortfolioEntryId: append ? nextCursor?.portfolio_entry_id : null,
      });

      if (error || !data) {
        setLoadState("error");
        return;
      }

      setRows((prev) => (append ? [...prev, ...data.rows] : data.rows));
      setCursor(data.next_cursor);
      setHasMore(data.has_more);
      setLoadState("idle");
      setHasLoadedOnce(true);
    },
    [],
  );

  useEffect(() => {
    void loadPage(appliedQuery, false, null);
  }, [appliedQuery, loadPage]);

  const applyFilters = useCallback((patch: Partial<QueryState>) => {
    setQuery((prev) => {
      const next = { ...prev, ...patch };
      setAppliedQuery(next);
      return next;
    });
  }, []);

  const debouncedApply = (patch: Partial<QueryState>) => {
    setQuery((prev) => ({ ...prev, ...patch }));
    if (filterDebounceRef.current) clearTimeout(filterDebounceRef.current);
    filterDebounceRef.current = setTimeout(() => {
      setAppliedQuery((prev) => ({ ...prev, ...patch }));
    }, 350);
  };

  const toggleSort = (field: string) => {
    applyFilters({
      sortField: field,
      sortDirection:
        appliedQuery.sortField === field && appliedQuery.sortDirection === "desc" ? "asc" : "desc",
    });
  };

  const persistPreferences = useCallback(
    (visibility: VisibilityState, sizing: Record<string, number>) => {
      void saveConsultantGridPreferencesAction({
        columnVisibility: visibility as Record<string, boolean>,
        columnSizing: sizing,
      });
    },
    [],
  );

  const saveNewEntry = () => {
    setInlineError(null);
    setSavingInline(true);
    startTransition(async () => {
      const supabase = createClient();
      const { familyName, givenName } = newEntryDraft;
      const guardian = splitGuardianName(newEntryDraft.guardianName);
      const customFieldValues = customFieldKeys
        .map((key) => ({
          field_key: key,
          value: newEntryDraft.customFields[key] ?? "",
        }))
        .filter((item) => item.value.trim());

      const result = await createConsultantWorkspacePortfolioIntake(supabase, {
        familyName,
        givenName,
        guardianFamilyName: guardian.familyName || undefined,
        guardianGivenName: guardian.givenName || undefined,
        guardianPhone: newEntryDraft.guardianPhone || undefined,
        customFieldValues,
      });
      setSavingInline(false);
      if (!result.ok) {
        setInlineError(result.errorCode);
        return;
      }
      setNewEntryDraft(EMPTY_DRAFT);
      void loadPage(appliedQuery, false, null);
    });
  };

  const startEditRow = useCallback(
    (row: ConsultantWorkspacePortfolioRow) => {
      setEditingEntryId(row.portfolio_entry_id);
      setEditDraft(draftFromRow(row, customFieldKeys));
      setInlineError(null);
    },
    [customFieldKeys],
  );

  const saveEditRow = (row: ConsultantWorkspacePortfolioRow) => {
    setInlineError(null);
    setSavingInline(true);
    startTransition(async () => {
      const supabase = createClient();
      const guardian = splitGuardianName(editDraft.guardianName);
      const profileResult = await saveConsultantPortfolioProfile(supabase, {
        portfolioEntryId: row.portfolio_entry_id,
        familyName: editDraft.familyName,
        givenName: editDraft.givenName,
        guardianFamilyName: guardian.familyName || undefined,
        guardianGivenName: guardian.givenName || undefined,
        guardianPhone: editDraft.guardianPhone || undefined,
      });
      if (!profileResult.ok) {
        setSavingInline(false);
        setInlineError(profileResult.errorCode);
        return;
      }
      const customFieldValues = customFieldKeys.map((key) => ({
        field_key: key,
        value: editDraft.customFields[key] ?? "",
      }));
      if (customFieldValues.some((v) => v.value.trim())) {
        await saveConsultantPortfolioCustomFields(supabase, {
          portfolioEntryId: row.portfolio_entry_id,
          values: customFieldValues,
        });
      }
      setSavingInline(false);
      setEditingEntryId(null);
      void loadPage(appliedQuery, false, null);
    });
  };

  const columns = useMemo((): ColumnDef<ConsultantWorkspacePortfolioRow>[] => {
    const base: ColumnDef<ConsultantWorkspacePortfolioRow>[] = [
      {
        id: "stt",
        accessorKey: "workspace_sequence",
        header: () => t("columns.stt"),
        cell: ({ row }) => (
          <span data-testid="portfolio-stt">{row.original.workspace_sequence}</span>
        ),
      },
      {
        id: "family_name",
        accessorKey: "family_name",
        header: () => t("columns.familyName"),
        cell: ({ row }) => formatPortfolioNamePart(row.original.family_name, locale),
      },
      {
        id: "given_name",
        accessorKey: "given_name",
        header: () => t("columns.givenName"),
        cell: ({ row }) => formatPortfolioNamePart(row.original.given_name, locale),
      },
      {
        id: "student_code",
        header: () => t("columns.studentCode"),
        cell: ({ row }) => {
          const display = row.original.student_code_display ?? row.original.student_code_official;
          if (!display) return "—";
          const provisional = row.original.student_code_is_provisional;
          return (
            <span
              data-testid="portfolio-student-code"
              className={
                provisional ? "rounded border border-dashed border-amber-400 px-1 text-amber-800" : undefined
              }
              title={provisional ? t("studentCode.provisionalHint") : undefined}
            >
              {display}
            </span>
          );
        },
      },
      {
        id: "lifecycle_status",
        header: () => t("columns.status"),
        cell: ({ row }) => (
          <span
            data-testid="portfolio-lifecycle-status"
            className="inline-flex rounded bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-800"
          >
            {row.original.lifecycle_status_label}
          </span>
        ),
      },
      {
        id: "guardian_name",
        header: () => t("columns.guardian"),
        cell: ({ row }) => row.original.primary_guardian_name ?? "—",
      },
      {
        id: "guardian_phone",
        header: () => t("columns.phone"),
        cell: ({ row }) => row.original.primary_guardian_phone ?? "—",
      },
      {
        id: "tuition",
        header: () => t("columns.tuition"),
        cell: ({ row }) => {
          const r = row.original;
          const tuitionLabel = r.tuition_payment_state
            ? t(`paymentState.${r.tuition_payment_state}` as "paymentState.chua_nop_phi")
            : (r.tuition_payment_state_label ?? "—");
          const isUnpaidInitial =
            r.tuition_payment_state === "chua_nop_phi" || r.tuition_payment_state === "chua_coc";
          const openDeclaration = () => setDeclarationRow(r);
          const displayName = `${formatPortfolioNamePart(r.family_name, locale)} ${formatPortfolioNamePart(r.given_name, locale)}`.trim();
          return (
            <div className="space-y-0.5 text-xs" data-testid="portfolio-tuition">
              {r.capabilities.can_open_payment_declaration ? (
                <button
                  type="button"
                  ref={
                    declarationRow?.portfolio_entry_id === r.portfolio_entry_id
                      ? declarationTriggerRef
                      : undefined
                  }
                  className="font-medium text-left text-slate-900 underline decoration-slate-400 underline-offset-2 hover:decoration-slate-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-800"
                  data-testid="portfolio-tuition-action"
                  aria-label={t("declaration.openTuitionFor", { name: displayName })}
                  onClick={openDeclaration}
                >
                  {tuitionLabel}
                </button>
              ) : (
                <p className="font-medium">{tuitionLabel}</p>
              )}
              {r.tuition_payment_state === "full_phi" && r.tuition_total_net > 0 ? (
                <p className="text-slate-600">
                  {formatMoneyVnd(r.tuition_paid, locale)} / {formatMoneyVnd(r.tuition_total_net, locale)}
                </p>
              ) : isUnpaidInitial ? null : (
                <p className="text-slate-600">
                  {r.tuition_billing_mode === "periodic" ? (
                    <>
                      {typeof r.tuition_periodic_lessons_remaining === "number"
                        ? t("tuition.lessonsRemaining", { count: r.tuition_periodic_lessons_remaining })
                        : null}
                      {(r.tuition_carry_forward_credit ?? 0) > 0 ? (
                        <>
                          {" "}
                          · {t("tuition.carryForward")}{" "}
                          {formatMoneyVnd(r.tuition_carry_forward_credit ?? 0, locale)}
                        </>
                      ) : null}
                    </>
                  ) : (
                    <>
                      {t("tuition.paid")} {formatMoneyVnd(r.tuition_paid, locale)}
                      {(r.tuition_pending_declaration ?? 0) > 0 ? (
                        <>
                          {" "}
                          · {t("tuition.pendingConfirmation")}{" "}
                          {formatMoneyVnd(r.tuition_pending_declaration ?? 0, locale)}
                        </>
                      ) : null}
                      {r.tuition_outstanding > 0 ? (
                        <>
                          {" "}
                          · {t("tuition.outstandingDue")}{" "}
                          {formatMoneyVnd(r.tuition_outstanding, locale)}
                        </>
                      ) : null}
                    </>
                  )}
                </p>
              )}
            </div>
          );
        },
      },
      {
        id: "details",
        header: () => t("columns.details"),
        cell: ({ row }) => {
          const href = detailsHref(row.original, consultantReturnQuery);
          return (
            <Link
              href={href}
              className="text-sm font-medium text-slate-900 underline"
              data-testid="portfolio-details-link"
            >
              {t("actions.details")}
            </Link>
          );
        },
      },
      {
        id: "edit",
        header: () => t("columns.saveEdit"),
        cell: ({ row }) => (
          <div className="flex flex-col gap-1">
            {row.original.capabilities.can_edit_contact ? (
              <button
                type="button"
                className="rounded border border-slate-300 px-2 py-1 text-xs hover:bg-slate-50"
                data-testid="portfolio-edit-row"
                onClick={() => startEditRow(row.original)}
              >
                {t("actions.edit")}
              </button>
            ) : null}
            {!appliedQuery.includeHidden ? (
              <button
                type="button"
                className="rounded border border-slate-300 px-2 py-1 text-xs hover:bg-slate-50"
                data-testid="portfolio-hide-row"
                onClick={() => {
                  startTransition(async () => {
                    await hideConsultantGridRowAction(
                      row.original.subject_type,
                      row.original.display_subject_id,
                    );
                    void loadPage(appliedQuery, false, null);
                  });
                }}
              >
                {t("actions.hide")}
              </button>
            ) : (
              <button
                type="button"
                className="rounded border border-slate-300 px-2 py-1 text-xs hover:bg-slate-50"
                data-testid="portfolio-restore-row"
                onClick={() => {
                  startTransition(async () => {
                    await restoreConsultantGridRowAction(
                      row.original.subject_type,
                      row.original.display_subject_id,
                    );
                    void loadPage(appliedQuery, false, null);
                  });
                }}
              >
                {t("actions.restore")}
              </button>
            )}
          </div>
        ),
      },
    ];

    const customCols: ColumnDef<ConsultantWorkspacePortfolioRow>[] = customFieldKeys.map((key) => ({
      id: `custom_${key}`,
      header: () => customFieldDefs.find((d) => d.field_key === key)?.label ?? key,
      cell: ({ row }) => {
        const cf = row.original.custom_fields?.find((f) => f.field_key === key);
        return cf?.value ?? "—";
      },
    }));

    return [...base, ...customCols];
  }, [
    t,
    locale,
    customFieldKeys,
    customFieldDefs,
    appliedQuery,
    loadPage,
    startTransition,
    consultantReturnQuery,
    declarationRow?.portfolio_entry_id,
    startEditRow,
  ]);

  const table = useReactTable({
    data: rows,
    columns,
    state: { columnVisibility, columnSizing },
    onColumnVisibilityChange: (updater) => {
      setColumnVisibility((prev) => {
        const next = typeof updater === "function" ? updater(prev) : updater;
        for (const key of PROTECTED_VISIBILITY_COLUMNS) {
          next[key] = true;
        }
        persistPreferences(next, columnSizing);
        return next;
      });
    },
    onColumnSizingChange: (updater) => {
      setColumnSizing((prev) => {
        const next = typeof updater === "function" ? updater(prev) : updater;
        persistPreferences(columnVisibility, next);
        return next;
      });
    },
    getCoreRowModel: getCoreRowModel(),
    columnResizeMode: "onChange",
    enableColumnResizing: true,
  });

  const visibleColumns = table.getVisibleLeafColumns();
  const tableRows = table.getRowModel().rows;
  const rowVirtualizer = useVirtualizer({
    count: tableRows.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: () => 52,
    overscan: 8,
  });
  const virtualItems = rowVirtualizer.getVirtualItems();
  const virtualPadTop = virtualItems.length > 0 ? virtualItems[0]!.start : 0;
  const virtualPadBottom =
    virtualItems.length > 0
      ? rowVirtualizer.getTotalSize() - virtualItems[virtualItems.length - 1]!.end
      : 0;

  const isFiltered =
    Boolean(appliedQuery.familyNameFilter.trim()) ||
    Boolean(appliedQuery.givenNameFilter.trim()) ||
    Boolean(appliedQuery.studentCode.trim()) ||
    Boolean(appliedQuery.guardianPhone.trim()) ||
    Boolean(appliedQuery.lifecycleStatus) ||
    Boolean(appliedQuery.tuitionPaymentState);

  const showEmptyBelowGrid =
    hasLoadedOnce && loadState !== "loading" && rows.length === 0 && !isFiltered;
  const showFilteredEmpty =
    hasLoadedOnce && loadState !== "loading" && rows.length === 0 && isFiltered;

  const inputClass = "w-full min-w-0 rounded border border-slate-300 px-1.5 py-1 text-sm";

  const renderFilterCell = (colId: string) => {
    switch (colId) {
      case "family_name":
        return (
          <input
            type="search"
            className={inputClass}
            value={query.familyNameFilter}
            onChange={(e) => debouncedApply({ familyNameFilter: e.target.value })}
            data-testid="filter-family-name"
          />
        );
      case "given_name":
        return (
          <input
            type="search"
            className={inputClass}
            value={query.givenNameFilter}
            onChange={(e) => debouncedApply({ givenNameFilter: e.target.value })}
            data-testid="filter-given-name"
          />
        );
      case "student_code":
        return (
          <input
            className={inputClass}
            value={query.studentCode}
            onChange={(e) => setQuery((p) => ({ ...p, studentCode: e.target.value }))}
            onBlur={(e) => applyFilters({ studentCode: e.currentTarget.value })}
            data-testid="filter-student-code"
          />
        );
      case "lifecycle_status":
        return (
          <select
            className={inputClass}
            value={query.lifecycleStatus}
            onChange={(e) => applyFilters({ lifecycleStatus: e.target.value })}
            data-testid="filter-lifecycle-status"
          >
            <option value="">{t("filters.all")}</option>
            <option value="tiem_nang">{t("lifecycle.tiem_nang")}</option>
            <option value="ghi_danh">{t("lifecycle.ghi_danh")}</option>
            <option value="dang_hoc">{t("lifecycle.dang_hoc")}</option>
            <option value="tot_nghiep">{t("lifecycle.tot_nghiep")}</option>
          </select>
        );
      case "guardian_name":
        return null;
      case "guardian_phone":
        return (
          <input
            className={inputClass}
            value={query.guardianPhone}
            onChange={(e) => setQuery((p) => ({ ...p, guardianPhone: e.target.value }))}
            onBlur={(e) => applyFilters({ guardianPhone: e.currentTarget.value })}
            data-testid="filter-guardian-phone"
          />
        );
      case "tuition":
        return (
          <select
            className={inputClass}
            value={query.tuitionPaymentState}
            onChange={(e) => applyFilters({ tuitionPaymentState: e.target.value })}
            data-testid="filter-payment-state"
          >
            <option value="">{t("filters.all")}</option>
            <option value="dong_phi">{t("paymentState.dong_phi")}</option>
            <option value="cho_xac_nhan">{t("paymentState.cho_xac_nhan")}</option>
            <option value="coc_phi">{t("paymentState.coc_phi")}</option>
            <option value="mot_phan">{t("paymentState.mot_phan")}</option>
            <option value="full_phi">{t("paymentState.full_phi")}</option>
          </select>
        );
      default:
        return null;
    }
  };

  const renderInlineField = (
    colId: string,
    draft: InlineDraft,
    setDraft: (updater: (prev: InlineDraft) => InlineDraft) => void,
    readRow?: ConsultantWorkspacePortfolioRow,
  ) => {
    if (colId === "stt") {
      if (readRow) {
        return <span data-testid="portfolio-stt">{readRow.workspace_sequence}</span>;
      }
      return <span className="text-slate-400">—</span>;
    }
    if (colId === "family_name") {
      if (draft) {
        return (
          <input
            className={`${inputClass} uppercase`}
            value={draft.familyName}
            onChange={(e) => setDraft((p) => ({ ...p, familyName: e.target.value }))}
            data-testid="inline-family-name"
          />
        );
      }
      return formatPortfolioNamePart(readRow?.family_name ?? null, locale);
    }
    if (colId === "given_name") {
      if (draft) {
        return (
          <input
            className={`${inputClass} uppercase`}
            value={draft.givenName}
            onChange={(e) => setDraft((p) => ({ ...p, givenName: e.target.value }))}
            data-testid="inline-given-name"
          />
        );
      }
      return formatPortfolioNamePart(readRow?.given_name ?? null, locale);
    }
    if (colId === "student_code") {
      const display = readRow?.student_code_display ?? readRow?.student_code_official;
      if (!display) return "—";
      const provisional = readRow?.student_code_is_provisional;
      return (
        <span
          data-testid="portfolio-student-code"
          className={
            provisional ? "rounded border border-dashed border-amber-400 px-1 text-amber-800" : undefined
          }
        >
          {display}
        </span>
      );
    }
    if (colId === "lifecycle_status") {
      const label = readRow?.lifecycle_status_label ?? t("lifecycle.tiem_nang");
      return (
        <span
          data-testid="portfolio-lifecycle-status"
          className="inline-flex rounded bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-800"
        >
          {label}
        </span>
      );
    }
    if (colId === "guardian_name") {
      if (draft) {
        return (
          <input
            className={inputClass}
            value={draft.guardianName}
            onChange={(e) => setDraft((p) => ({ ...p, guardianName: e.target.value }))}
            data-testid="inline-guardian-name"
          />
        );
      }
      return readRow?.primary_guardian_name ?? "—";
    }
    if (colId === "guardian_phone") {
      if (draft) {
        return (
          <input
            className={inputClass}
            value={draft.guardianPhone}
            onChange={(e) => setDraft((p) => ({ ...p, guardianPhone: e.target.value }))}
            data-testid="inline-guardian-phone"
          />
        );
      }
      return readRow?.primary_guardian_phone ?? "—";
    }
    if (colId === "tuition" && readRow) {
      const r = readRow;
      const tuitionLabel = r.tuition_payment_state
        ? t(`paymentState.${r.tuition_payment_state}` as "paymentState.chua_nop_phi")
        : (r.tuition_payment_state_label ?? "—");
      return (
        <div className="space-y-0.5 text-xs" data-testid="portfolio-tuition">
          <p className="font-medium">{tuitionLabel}</p>
        </div>
      );
    }
    if (colId === "details" && readRow) {
      return (
        <Link
          href={detailsHref(readRow, consultantReturnQuery)}
          className="text-sm font-medium text-slate-900 underline"
          data-testid="portfolio-details-link"
        >
          {t("actions.details")}
        </Link>
      );
    }
    if (colId.startsWith("custom_")) {
      const key = colId.replace(/^custom_/, "");
      if (draft) {
        return (
          <input
            className={inputClass}
            value={draft.customFields[key] ?? ""}
            onChange={(e) =>
              setDraft((p) => ({
                ...p,
                customFields: { ...p.customFields, [key]: e.target.value },
              }))
            }
            data-testid={`inline-custom-${key}`}
          />
        );
      }
      return readRow?.custom_fields?.find((f) => f.field_key === key)?.value ?? "—";
    }
    return null;
  };

  const moveFocus = (rowDelta: number, colDelta: number) => {
    setFocusedCell((prev) => {
      const maxRow = Math.max(tableRows.length, 0);
      const row = Math.min(Math.max((prev?.row ?? 0) + rowDelta, 0), maxRow);
      const col = Math.min(
        Math.max((prev?.col ?? 0) + colDelta, 0),
        Math.max(visibleColumns.length - 1, 0),
      );
      return { row, col };
    });
  };

  const sortFieldMap: Record<string, string> = {
    stt: "workspace_sequence",
    family_name: "family_name",
    given_name: "given_name",
    student_code: "student_code",
    tuition: "tuition_outstanding",
  };

  const showGrid = hasLoadedOnce && loadState !== "loading";

  return (
    <div className="space-y-4" data-testid="consultant-workspace">
      <Suspense
        fallback={
          <div
            className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600"
            data-testid="consultant-monthly-sales-header-loading"
          >
            {t("monthlySales.loadingAmount")}
          </div>
        }
      >
        <ConsultantMonthlySalesHeader />
      </Suspense>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h3 className="text-lg font-semibold text-slate-900">{t("title")}</h3>
          <p className="text-sm text-slate-600">{t("subtitle")}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            className="rounded border border-slate-300 px-3 py-1.5 text-sm"
            onClick={() => applyFilters({ includeHidden: !appliedQuery.includeHidden })}
            data-testid="toggle-hidden-rows"
          >
            {appliedQuery.includeHidden ? t("filters.showActive") : t("filters.showHidden")}
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="text-slate-600">{t("columns.manage")}</span>
        {DEFAULT_COLUMN_ORDER.map((colId) => (
          <label key={colId} className="inline-flex items-center gap-1">
            <input
              type="checkbox"
              checked={table.getColumn(colId)?.getIsVisible() ?? true}
              disabled={PROTECTED_VISIBILITY_COLUMNS.has(colId)}
              onChange={() => table.getColumn(colId)?.toggleVisibility()}
              data-testid={`column-toggle-${colId}`}
            />
            {t(COLUMN_LABEL_KEY[colId] as "columns.stt")}
          </label>
        ))}
        {customFieldKeys.map((key) => (
          <label key={key} className="inline-flex items-center gap-1">
            <input
              type="checkbox"
              checked={table.getColumn(`custom_${key}`)?.getIsVisible() ?? true}
              onChange={() => table.getColumn(`custom_${key}`)?.toggleVisibility()}
            />
            {customFieldDefs.find((d) => d.field_key === key)?.label ?? key}
          </label>
        ))}
      </div>

      {inlineError ? (
        <p className="text-sm text-red-700" role="alert" data-testid="portfolio-inline-error">
          {inlineError}
        </p>
      ) : null}

      {loadState === "error" ? (
        <div
          className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800"
          data-testid="portfolio-error"
          role="alert"
        >
          <p>{t("states.error")}</p>
          <button
            type="button"
            className="mt-2 underline"
            onClick={() => void loadPage(appliedQuery, false, null)}
          >
            {t("states.retry")}
          </button>
        </div>
      ) : null}

      {loadState === "loading" && !hasLoadedOnce ? (
        <div className="space-y-2" data-testid="portfolio-loading" aria-busy="true">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-10 animate-pulse rounded bg-slate-100" />
          ))}
        </div>
      ) : null}

      {showGrid ? (
        <div
          ref={scrollRef}
          className="max-h-[min(70vh,720px)] overflow-auto rounded-lg border border-slate-200 bg-white"
          data-testid="portfolio-grid-scroll"
        >
          <table className="min-w-full border-collapse text-sm" data-testid="portfolio-grid">
            <thead>
              {table.getHeaderGroups().map((headerGroup) => (
                <tr key={headerGroup.id} className="sticky top-0 z-20 border-b border-slate-200 bg-slate-50">
                  {headerGroup.headers.map((header) => {
                    const colId = header.column.id;
                    const sortKey = sortFieldMap[colId];
                    const sortable = Boolean(sortKey);
                    return (
                      <th
                        key={header.id}
                        className="relative px-2 py-2 text-left font-medium text-slate-700"
                        style={{ width: header.getSize() }}
                      >
                        {sortable && sortKey ? (
                          <button
                            type="button"
                            className="inline-flex items-center gap-1 underline-offset-2 hover:underline"
                            onClick={() => toggleSort(sortKey)}
                          >
                            {flexRender(header.column.columnDef.header, header.getContext())}
                          </button>
                        ) : (
                          flexRender(header.column.columnDef.header, header.getContext())
                        )}
                        {header.column.getCanResize() ? (
                          <div
                            onMouseDown={header.getResizeHandler()}
                            onTouchStart={header.getResizeHandler()}
                            className="absolute right-0 top-0 h-full w-1 cursor-col-resize bg-slate-200 opacity-0 hover:opacity-100"
                            data-testid={`resize-${colId}`}
                          />
                        ) : null}
                      </th>
                    );
                  })}
                </tr>
              ))}
              <tr
                className="sticky top-10 z-20 border-b border-slate-200 bg-slate-50/90"
                data-testid="portfolio-column-filters"
              >
                {visibleColumns.map((col) => (
                  <th key={`filter-${col.id}`} className="px-2 py-1.5 font-normal">
                    {renderFilterCell(col.id)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-slate-200 bg-amber-50/40" data-testid="portfolio-new-row">
                {visibleColumns.map((col, colIndex) => (
                  <td
                    key={`new-${col.id}`}
                    className={`px-2 py-2 align-top ${col.id === "stt" || col.id === "family_name" ? "sticky left-0 z-[1] bg-amber-50/40" : ""}`}
                    tabIndex={colIndex === 0 ? 0 : -1}
                    onKeyDown={(e) => {
                      if (e.key === "Tab") {
                        e.preventDefault();
                        const next = colIndex + (e.shiftKey ? -1 : 1);
                        const row = e.currentTarget.parentElement;
                        const cells = row?.querySelectorAll("td");
                        const target = cells?.[next] as HTMLElement | undefined;
                        target?.focus();
                      }
                    }}
                  >
                    {col.id === "edit" ? (
                      <button
                        type="button"
                        className="rounded border border-slate-900 bg-slate-900 px-2 py-1 text-xs font-medium text-white disabled:opacity-50"
                        disabled={savingInline || pending}
                        data-testid="portfolio-save-new-row"
                        onClick={saveNewEntry}
                      >
                        {t("actions.save")}
                      </button>
                    ) : (
                      renderInlineField(col.id, newEntryDraft, setNewEntryDraft)
                    )}
                  </td>
                ))}
              </tr>

              {showEmptyBelowGrid ? (
                <tr data-testid="portfolio-empty">
                  <td colSpan={visibleColumns.length} className="px-2 py-3 text-sm text-slate-600">
                    {t("states.empty")}
                  </td>
                </tr>
              ) : null}

              {showFilteredEmpty ? (
                <tr data-testid="portfolio-filtered-empty">
                  <td colSpan={visibleColumns.length} className="px-2 py-3 text-sm text-slate-600">
                    {t("states.filteredEmpty")}
                  </td>
                </tr>
              ) : null}

              {virtualPadTop > 0 ? (
                <tr aria-hidden className="pointer-events-none border-0">
                  <td
                    colSpan={visibleColumns.length}
                    className="border-0 p-0"
                    style={{ height: virtualPadTop, lineHeight: 0 }}
                  />
                </tr>
              ) : null}

              {virtualItems.map((virtualRow) => {
                const tableRow = tableRows[virtualRow.index];
                if (!tableRow) return null;
                const isEditing = editingEntryId === tableRow.original.portfolio_entry_id;
                return (
                  <tr
                    key={tableRow.id}
                    className="border-b border-slate-100 bg-white"
                    data-testid="portfolio-row"
                  >
                    {tableRow.getVisibleCells().map((cell, colIndex) => {
                      const colId = cell.column.id;
                      const focused =
                        focusedCell?.row === virtualRow.index + 1 && focusedCell?.col === colIndex;
                      return (
                        <td
                          key={cell.id}
                          tabIndex={focused ? 0 : -1}
                          className={`px-2 py-2 align-top ${focused ? "ring-2 ring-slate-900 ring-inset" : ""} ${
                            colId === "stt" || colId === "family_name"
                              ? "sticky left-0 z-[1] bg-white"
                              : ""
                          }`}
                          onClick={() => setFocusedCell({ row: virtualRow.index + 1, col: colIndex })}
                          onKeyDown={(e) => {
                            if (e.key === "ArrowDown") {
                              e.preventDefault();
                              moveFocus(1, 0);
                            } else if (e.key === "ArrowUp") {
                              e.preventDefault();
                              moveFocus(-1, 0);
                            } else if (e.key === "ArrowRight") {
                              e.preventDefault();
                              moveFocus(0, 1);
                            } else if (e.key === "ArrowLeft") {
                              e.preventDefault();
                              moveFocus(0, -1);
                            } else if (e.key === "Tab") {
                              e.preventDefault();
                              moveFocus(0, e.shiftKey ? -1 : 1);
                            } else if (e.key === "Escape") {
                              e.preventDefault();
                              setFocusedCell(null);
                              (e.target as HTMLElement).blur();
                            } else if (e.key === "Enter") {
                              const link = (e.currentTarget as HTMLElement).querySelector("a");
                              const btn = (e.currentTarget as HTMLElement).querySelector(
                                "button:not([disabled])",
                              );
                              if (link instanceof HTMLAnchorElement) link.click();
                              else if (btn instanceof HTMLButtonElement) btn.click();
                            }
                          }}
                        >
                          {isEditing && colId !== "edit" && colId !== "details" && colId !== "tuition" && colId !== "student_code" && colId !== "lifecycle_status" && colId !== "stt" ? (
                            renderInlineField(colId, editDraft, setEditDraft, tableRow.original)
                          ) : colId === "edit" ? (
                            <div className="flex flex-col gap-1">
                              {isEditing ? (
                                <>
                                  <button
                                    type="button"
                                    className="rounded border border-slate-900 bg-slate-900 px-2 py-1 text-xs text-white disabled:opacity-50"
                                    disabled={savingInline || pending}
                                    data-testid="portfolio-save-edit-row"
                                    onClick={() => saveEditRow(tableRow.original)}
                                  >
                                    {t("actions.save")}
                                  </button>
                                  <button
                                    type="button"
                                    className="rounded border border-slate-300 px-2 py-1 text-xs"
                                    onClick={() => setEditingEntryId(null)}
                                  >
                                    {t("detail.cancel")}
                                  </button>
                                </>
                              ) : tableRow.original.capabilities.can_edit_contact ? (
                                <button
                                  type="button"
                                  className="rounded border border-slate-300 px-2 py-1 text-xs hover:bg-slate-50"
                                  data-testid="portfolio-edit-row"
                                  onClick={() => startEditRow(tableRow.original)}
                                >
                                  {t("actions.edit")}
                                </button>
                              ) : null}
                              {!appliedQuery.includeHidden ? (
                                <button
                                  type="button"
                                  className="rounded border border-slate-300 px-2 py-1 text-xs hover:bg-slate-50"
                                  data-testid="portfolio-hide-row"
                                  onClick={() => {
                                    startTransition(async () => {
                                      await hideConsultantGridRowAction(
                                        tableRow.original.subject_type,
                                        tableRow.original.display_subject_id,
                                      );
                                      void loadPage(appliedQuery, false, null);
                                    });
                                  }}
                                >
                                  {t("actions.hide")}
                                </button>
                              ) : (
                                <button
                                  type="button"
                                  className="rounded border border-slate-300 px-2 py-1 text-xs hover:bg-slate-50"
                                  data-testid="portfolio-restore-row"
                                  onClick={() => {
                                    startTransition(async () => {
                                      await restoreConsultantGridRowAction(
                                        tableRow.original.subject_type,
                                        tableRow.original.display_subject_id,
                                      );
                                      void loadPage(appliedQuery, false, null);
                                    });
                                  }}
                                >
                                  {t("actions.restore")}
                                </button>
                              )}
                            </div>
                          ) : (
                            flexRender(cell.column.columnDef.cell, cell.getContext())
                          )}
                        </td>
                      );
                    })}
                  </tr>
                );
              })}

              {virtualPadBottom > 0 ? (
                <tr aria-hidden className="pointer-events-none border-0">
                  <td
                    colSpan={visibleColumns.length}
                    className="border-0 p-0"
                    style={{ height: virtualPadBottom, lineHeight: 0 }}
                  />
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      ) : null}

      {hasMore ? (
        <button
          type="button"
          disabled={pending || loadState === "loading"}
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
          data-testid="portfolio-load-more"
          onClick={() => void loadPage(appliedQuery, true, cursor)}
        >
          {loadState === "loading" ? t("states.loadingMore") : t("actions.loadMore")}
        </button>
      ) : null}

      {declarationRow ? (
        <PaymentDeclarationDrawer
          key={declarationRow.portfolio_entry_id}
          row={declarationRow}
          triggerRef={declarationTriggerRef}
          onClose={() => setDeclarationRow(null)}
          onSuccess={() => void loadPage(appliedQuery, false, null)}
        />
      ) : null}
    </div>
  );
}
