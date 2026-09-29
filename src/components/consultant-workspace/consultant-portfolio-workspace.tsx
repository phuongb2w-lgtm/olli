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
import { useCallback, useEffect, useMemo, useRef, useState, useTransition } from "react";
import { useLocale, useTranslations } from "next-intl";
import {
  hideConsultantGridRowAction,
  restoreConsultantGridRowAction,
  saveConsultantGridPreferencesAction,
} from "@/app/actions/consultant-workspace";
import { fetchConsultantWorkspacePortfolio } from "@/lib/consultant-workspace/fetch-portfolio";
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
import { PaymentDeclarationDrawer } from "@/components/consultant-workspace/payment-declaration-drawer";

type CourseOption = { id: string; name: string };

type Props = {
  initialPreferences: ConsultantGridPreferences | null;
  courseOptions: CourseOption[];
};

type QueryState = {
  nameSearch: string;
  studentCode: string;
  guardianPhone: string;
  lifecycleStatus: string;
  tuitionPaymentState: string;
  declarationStatus: string;
  courseId: string;
  sortField: string;
  sortDirection: "asc" | "desc";
  includeHidden: boolean;
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
  nameSearch: "",
  studentCode: "",
  guardianPhone: "",
  lifecycleStatus: "",
  tuitionPaymentState: "",
  declarationStatus: "",
  courseId: "",
  sortField: "workspace_sequence",
  sortDirection: "desc",
  includeHidden: false,
};

function buildFilters(q: QueryState) {
  const filters: Record<string, string> = {};
  if (q.nameSearch.trim()) filters.name_search = q.nameSearch.trim();
  if (q.studentCode.trim()) filters.student_code = q.studentCode.trim();
  if (q.guardianPhone.trim()) filters.guardian_phone = q.guardianPhone.trim();
  if (q.lifecycleStatus) filters.lifecycle_status = q.lifecycleStatus;
  if (q.tuitionPaymentState) filters.tuition_payment_state = q.tuitionPaymentState;
  if (q.declarationStatus) filters.declaration_status = q.declarationStatus;
  if (q.courseId) filters.course_id = q.courseId;
  return filters;
}

function collectCustomFieldKeys(rows: ConsultantWorkspacePortfolioRow[]): string[] {
  const keys = new Set<string>();
  for (const row of rows) {
    for (const cf of row.custom_fields ?? []) {
      keys.add(cf.field_key);
    }
  }
  return [...keys].sort();
}

export function ConsultantPortfolioWorkspace({ initialPreferences, courseOptions }: Props) {
  const t = useTranslations("consultantWorkspace");
  const locale = useLocale() as Locale;
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
  const declarationTriggerRef = useRef<HTMLButtonElement>(null);

  const scrollRef = useRef<HTMLDivElement>(null);
  const searchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const customFieldKeys = useMemo(() => collectCustomFieldKeys(rows), [rows]);

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

  const onSearchChange = (value: string) => {
    setQuery((prev) => ({ ...prev, nameSearch: value }));
    if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
    searchDebounceRef.current = setTimeout(() => {
      setAppliedQuery((prev) => ({ ...prev, nameSearch: value }));
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
              className={provisional ? "rounded border border-dashed border-amber-400 px-1 text-amber-800" : undefined}
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
          return (
            <div className="space-y-0.5 text-xs" data-testid="portfolio-tuition">
              <p className="font-medium">{r.tuition_payment_state_label}</p>
              <p className="text-slate-600">
                {formatMoneyVnd(r.tuition_total_net, locale)} · {t("tuition.paid")}{" "}
                {formatMoneyVnd(r.tuition_paid, locale)} · {t("tuition.outstanding")}{" "}
                {formatMoneyVnd(r.tuition_outstanding, locale)}
              </p>
              {r.capabilities.can_open_payment_declaration ? (
                <button
                  type="button"
                  ref={declarationRow?.portfolio_entry_id === r.portfolio_entry_id ? declarationTriggerRef : undefined}
                  className="mt-1 text-left text-xs font-medium text-slate-900 underline"
                  data-testid="declare-payment-action"
                  onClick={() => setDeclarationRow(r)}
                >
                  {t("declaration.openAction")}
                </button>
              ) : null}
            </div>
          );
        },
      },
      {
        id: "details",
        header: () => t("columns.details"),
        cell: ({ row }) => {
          const href = detailsHref(row.original);
          if (!href) return "—";
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
            <button
              type="button"
              disabled
              className="rounded border border-slate-200 px-2 py-1 text-xs text-slate-400"
              title={t("edit.deferred")}
            >
              {t("actions.edit")}
            </button>
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
      header: () => key,
      cell: ({ row }) => {
        const cf = row.original.custom_fields?.find((f) => f.field_key === key);
        return cf?.value ?? "—";
      },
    }));

    return [...base, ...customCols];
  }, [t, locale, customFieldKeys, appliedQuery, loadPage, startTransition]);

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

  const tableRows = table.getRowModel().rows;
  const rowVirtualizer = useVirtualizer({
    count: tableRows.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: () => 52,
    overscan: 8,
  });

  const visibleColumnCount = table.getVisibleLeafColumns().length;

  const moveFocus = (rowDelta: number, colDelta: number) => {
    setFocusedCell((prev) => {
      const row = Math.min(Math.max((prev?.row ?? 0) + rowDelta, 0), Math.max(tableRows.length - 1, 0));
      const col = Math.min(Math.max((prev?.col ?? 0) + colDelta, 0), Math.max(visibleColumnCount - 1, 0));
      return { row, col };
    });
  };

  const isFiltered =
    Boolean(appliedQuery.nameSearch.trim()) ||
    Boolean(appliedQuery.studentCode.trim()) ||
    Boolean(appliedQuery.guardianPhone.trim()) ||
    Boolean(appliedQuery.lifecycleStatus) ||
    Boolean(appliedQuery.tuitionPaymentState) ||
    Boolean(appliedQuery.declarationStatus) ||
    Boolean(appliedQuery.courseId);

  const showEmpty = hasLoadedOnce && loadState !== "loading" && rows.length === 0 && !isFiltered;
  const showFilteredEmpty =
    hasLoadedOnce && loadState !== "loading" && rows.length === 0 && isFiltered;

  return (
    <div className="space-y-4" data-testid="consultant-workspace">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold text-slate-900">{t("title")}</h2>
          <p className="text-sm text-slate-600">{t("subtitle")}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            className="rounded border border-slate-300 px-3 py-1.5 text-sm"
            onClick={() =>
              applyFilters({ includeHidden: !appliedQuery.includeHidden })
            }
            data-testid="toggle-hidden-rows"
          >
            {appliedQuery.includeHidden ? t("filters.showActive") : t("filters.showHidden")}
          </button>
        </div>
      </div>

      <div
        className="grid gap-3 rounded-lg border border-slate-200 bg-white p-3 sm:grid-cols-2 lg:grid-cols-4"
        data-testid="portfolio-filters"
      >
        <label className="block text-sm">
          <span className="text-slate-600">{t("filters.search")}</span>
          <input
            type="search"
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
            value={query.nameSearch}
            onChange={(e) => onSearchChange(e.target.value)}
            data-testid="filter-name-search"
          />
        </label>
        <label className="block text-sm">
          <span className="text-slate-600">{t("filters.studentCode")}</span>
          <input
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
            value={query.studentCode}
            onChange={(e) => setQuery((p) => ({ ...p, studentCode: e.target.value }))}
            onBlur={() => applyFilters({ studentCode: query.studentCode })}
            data-testid="filter-student-code"
          />
        </label>
        <label className="block text-sm">
          <span className="text-slate-600">{t("filters.guardianPhone")}</span>
          <input
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
            value={query.guardianPhone}
            onChange={(e) => setQuery((p) => ({ ...p, guardianPhone: e.target.value }))}
            onBlur={() => applyFilters({ guardianPhone: query.guardianPhone })}
          />
        </label>
        <label className="block text-sm">
          <span className="text-slate-600">{t("filters.lifecycleStatus")}</span>
          <select
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
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
        </label>
        <label className="block text-sm">
          <span className="text-slate-600">{t("filters.paymentState")}</span>
          <select
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
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
        </label>
        <label className="block text-sm">
          <span className="text-slate-600">{t("filters.declarationStatus")}</span>
          <select
            className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
            value={query.declarationStatus}
            onChange={(e) => applyFilters({ declarationStatus: e.target.value })}
            data-testid="filter-declaration-status"
          >
            <option value="">{t("filters.all")}</option>
            <option value="draft">{t("declaration.draft")}</option>
            <option value="pending">{t("declaration.pending")}</option>
            <option value="approved">{t("declaration.approved")}</option>
            <option value="rejected">{t("declaration.rejected")}</option>
            <option value="returned">{t("declaration.returned")}</option>
          </select>
        </label>
        {courseOptions.length > 0 ? (
          <label className="block text-sm">
            <span className="text-slate-600">{t("filters.course")}</span>
            <select
              className="mt-1 w-full rounded border border-slate-300 px-2 py-1.5"
              value={query.courseId}
              onChange={(e) => applyFilters({ courseId: e.target.value })}
              data-testid="filter-course"
            >
              <option value="">{t("filters.all")}</option>
              {courseOptions.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </label>
        ) : null}
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
            {key}
          </label>
        ))}
      </div>

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

      {showEmpty ? (
        <p className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600" data-testid="portfolio-empty">
          {t("states.empty")}
        </p>
      ) : null}

      {showFilteredEmpty ? (
        <p
          className="rounded-lg border border-slate-200 bg-white p-6 text-sm text-slate-600"
          data-testid="portfolio-filtered-empty"
        >
          {t("states.filteredEmpty")}
        </p>
      ) : null}

      {rows.length > 0 ? (
        <div
          ref={scrollRef}
          className="max-h-[min(70vh,720px)] overflow-auto rounded-lg border border-slate-200 bg-white"
          data-testid="portfolio-grid-scroll"
        >
          <table className="min-w-full border-collapse text-sm" data-testid="portfolio-grid">
            <thead className="sticky top-0 z-10 bg-slate-50">
              {table.getHeaderGroups().map((headerGroup) => (
                <tr key={headerGroup.id} className="border-b border-slate-200">
                  {headerGroup.headers.map((header) => {
                    const colId = header.column.id;
                    const sortable = [
                      "workspace_sequence",
                      "family_name",
                      "given_name",
                      "student_code",
                      "tuition",
                    ].includes(colId);
                    const sortFieldMap: Record<string, string> = {
                      stt: "workspace_sequence",
                      family_name: "family_name",
                      given_name: "given_name",
                      student_code: "student_code",
                      tuition: "tuition_outstanding",
                    };
                    const sortKey = sortFieldMap[colId];
                    return (
                      <th
                        key={header.id}
                        className="relative px-2 py-2 text-left font-medium text-slate-700"
                        style={{ width: header.getSize() }}
                        aria-sort={
                          sortable && sortKey && appliedQuery.sortField === sortKey
                            ? appliedQuery.sortDirection === "asc"
                              ? "ascending"
                              : "descending"
                            : sortable && sortKey
                              ? "none"
                              : undefined
                        }
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
            </thead>
            <tbody style={{ height: `${rowVirtualizer.getTotalSize()}px`, position: "relative" }}>
              {rowVirtualizer.getVirtualItems().map((virtualRow) => {
                const tableRow = tableRows[virtualRow.index];
                if (!tableRow) return null;
                return (
                  <tr
                    key={tableRow.id}
                    className="border-b border-slate-100"
                    style={{
                      position: "absolute",
                      top: 0,
                      left: 0,
                      width: "100%",
                      transform: `translateY(${virtualRow.start}px)`,
                    }}
                    data-testid="portfolio-row"
                  >
                    {tableRow.getVisibleCells().map((cell, colIndex) => {
                      const focused =
                        focusedCell?.row === virtualRow.index && focusedCell?.col === colIndex;
                      return (
                        <td
                          key={cell.id}
                          tabIndex={focused ? 0 : -1}
                          className={`px-2 py-2 align-top ${focused ? "ring-2 ring-slate-900 ring-inset" : ""} ${
                            cell.column.id === "stt" || cell.column.id === "family_name"
                              ? "sticky left-0 z-[1] bg-white"
                              : ""
                          } ${cell.column.id === "details" || cell.column.id === "edit" ? "sticky right-0 z-[1] bg-white" : ""}`}
                          onClick={() => setFocusedCell({ row: virtualRow.index, col: colIndex })}
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
                          {flexRender(cell.column.columnDef.cell, cell.getContext())}
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
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
