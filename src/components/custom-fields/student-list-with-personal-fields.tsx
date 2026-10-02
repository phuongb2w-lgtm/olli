"use client";

import Link from "next/link";
import { useMemo } from "react";
import { useTranslations } from "next-intl";
import { PersonalFieldsGrid, type PersonalGridBaseColumn } from "@/components/custom-fields/personal-fields-grid";
import type { StudentListItem } from "@/lib/students/types";

type Props = {
  items: StudentListItem[];
  showPrimaryContact: boolean;
  canUpdate: boolean;
  canViewGuardians: boolean;
  canViewEnrollments: boolean;
};

export function StudentListWithPersonalFields({
  items,
  showPrimaryContact,
  canUpdate,
  canViewGuardians,
  canViewEnrollments,
}: Props) {
  const t = useTranslations("students");
  const tGuardians = useTranslations("guardians");
  const tEnroll = useTranslations("enrollments");
  const tStatus = useTranslations("status.student");
  const placeholder = t("emptyValue");

  const baseColumns = useMemo(() => {
    const cols: PersonalGridBaseColumn<StudentListItem>[] = [
      {
        id: "name",
        header: t("nameColumn"),
        cell: (item) => (
          <span className="font-medium text-slate-900" data-testid="student-list-name">
            {item.name}
          </span>
        ),
      },
      {
        id: "student_code",
        header: t("codeColumn"),
        cell: (item) => <span data-testid="student-list-code">{item.studentCode ?? placeholder}</span>,
      },
    ];
    if (showPrimaryContact) {
      cols.push({
        id: "primary_contact",
        header: t("primaryContactColumn"),
        cell: (item) =>
          item.primaryContact ? (
            <span>
              {item.primaryContact.name}
              {item.primaryContact.phone ? (
                <span className="block text-xs text-slate-500">{item.primaryContact.phone}</span>
              ) : null}
            </span>
          ) : (
            placeholder
          ),
      });
    }
    cols.push({
      id: "status",
      header: t("statusColumn"),
      cell: (item) => (
        <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
          {tStatus(item.status)}
        </span>
      ),
    });
    return cols;
  }, [placeholder, showPrimaryContact, t, tStatus]);

  return (
    <PersonalFieldsGrid
      surface="students"
      rows={items}
      baseColumns={baseColumns}
      rowTestId="student-list-row"
      actionsHeader={t("actionsColumn")}
      rowActions={(item) => (
        <>
          {canViewEnrollments ? (
            <Link
              href={`/students/${item.id}/enrollments`}
              className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
            >
              {tEnroll("enrollmentHistory")}
            </Link>
          ) : null}
          {canViewGuardians ? (
            <Link
              href={`/students/${item.id}/guardians`}
              className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
            >
              {tGuardians("manageGuardians")}
            </Link>
          ) : null}
          {canUpdate ? (
            <Link
              href={`/students/${item.id}/edit`}
              className="text-sm font-medium text-slate-900 underline hover:text-slate-700"
            >
              {t("editStudent")}
            </Link>
          ) : null}
        </>
      )}
    />
  );
}
