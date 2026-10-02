"use client";

import { useMemo } from "react";
import { useTranslations } from "next-intl";
import { PersonalFieldsGrid, type PersonalGridBaseColumn } from "@/components/custom-fields/personal-fields-grid";
import { formatFinanceMoney } from "@/lib/finance/format-finance-value";
import type { FinanceStudentAccountRow } from "@/lib/reporting/finance-read-model";
import type { Locale } from "@/i18n/config";

type Props = {
  rows: FinanceStudentAccountRow[];
  locale: Locale;
};

export function FinanceStudentAccountsWithPersonalFields({ rows, locale }: Props) {
  const t = useTranslations("finance.intelligence");

  const baseColumns = useMemo<PersonalGridBaseColumn<FinanceStudentAccountRow>[]>(
    () => [
      {
        id: "name",
        header: t("student"),
        cell: (row) => (
          <span className="font-medium text-slate-900" data-testid="finance-student-name">
            {`${row.familyName} ${row.givenName}`.trim() || "—"}
          </span>
        ),
      },
      {
        id: "student_code",
        header: t("studentCode"),
        cell: (row) => row.studentCode ?? "—",
      },
      {
        id: "total_charged",
        header: t("totalCharged"),
        cell: (row) => formatFinanceMoney(row.totalCharged, locale),
      },
      {
        id: "total_paid",
        header: t("totalPaid"),
        cell: (row) => formatFinanceMoney(row.totalPaid, locale),
      },
      {
        id: "outstanding_balance",
        header: t("outstanding"),
        cell: (row) => (
          <span data-testid="finance-student-outstanding">{formatFinanceMoney(row.outstandingBalance, locale)}</span>
        ),
      },
    ],
    [locale, t],
  );

  return (
    <PersonalFieldsGrid
      surface="finance_students"
      rows={rows}
      baseColumns={baseColumns}
      rowTestId="finance-student-row"
      actionsHeader={t("studentAccountsActions")}
    />
  );
}
