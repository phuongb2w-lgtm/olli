"use client";

import { useActionState, useState, useTransition } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import {
  createEnrollment,
  searchStudentsForEnrollmentAction,
  type EnrollmentActionState,
  type EnrollmentFormValues,
} from "@/app/actions/enrollments";
import { CREATE_ENROLLMENT_STATUSES } from "@/lib/enrollments/constants";
import type { StudentSearchItem } from "@/lib/enrollments/query-student-search";

type ClassOption = {
  id: string;
  name: string;
  courseCode: string;
  status: string;
};

type Props = {
  mode: "fromClass" | "fromStudent";
  classId?: string;
  className?: string;
  studentId?: string;
  studentName?: string;
  classes?: ClassOption[];
  initialValues: EnrollmentFormValues;
  returnTo: "roster" | "student";
  backHref: string;
};

const initialState: EnrollmentActionState = {};

export function EnrollmentForm({
  mode,
  classId,
  className,
  studentId,
  studentName,
  classes = [],
  initialValues,
  returnTo,
  backHref,
}: Props) {
  const t = useTranslations("enrollments");
  const tStatus = useTranslations("status.enrollment");
  const [state, formAction, pending] = useActionState(createEnrollment, initialState);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<StudentSearchItem[]>([]);
  const [selectedStudentId, setSelectedStudentId] = useState(initialValues.studentId);
  const [isSearching, startSearch] = useTransition();

  const values = state.values ?? initialValues;

  const globalError =
    state.error === "permission_denied"
      ? t("permissionDenied")
      : state.error === "overlap_conflict"
        ? t("overlapConflict")
        : state.error === "capacity_reached"
          ? t("capacityReached")
        : state.error === "class_closed"
          ? t("classClosed")
          : state.error === "invalid_class_status"
            ? t("invalidClassStatus")
            : state.error === "invalid_student"
              ? t("invalidStudent")
              : state.error === "invalid_class"
                ? t("invalidClass")
                : state.error === "save_error"
                  ? t("saveError")
                  : null;

  function handleStudentSearch(event: React.FormEvent) {
    event.preventDefault();
    startSearch(async () => {
      const { items } = await searchStudentsForEnrollmentAction(searchQuery);
      setSearchResults(items);
    });
  }

  return (
    <form action={formAction} className="space-y-6">
      <input type="hidden" name="returnTo" value={returnTo} />

      {mode === "fromClass" && classId ? (
        <>
          <input type="hidden" name="classId" value={classId} />
          <input type="hidden" name="studentId" value={selectedStudentId || values.studentId} />
        </>
      ) : null}

      {mode === "fromStudent" && studentId ? (
        <input type="hidden" name="studentId" value={studentId} />
      ) : null}

      <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-slate-900">{t("enrollSection")}</h2>

        {mode === "fromClass" ? (
          <>
            <p className="text-sm text-slate-600">
              {t("enrollingIntoClass")}: <strong>{className}</strong>
            </p>
            <div>
              <label htmlFor="student-search" className="mb-1 block text-sm font-medium">
                {t("selectStudent")}
              </label>
              <div className="flex flex-wrap gap-2">
                <input
                  id="student-search"
                  type="search"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder={t("searchPlaceholder")}
                  className="min-w-0 flex-1 rounded border border-slate-300 px-3 py-2 text-sm"
                />
                <button
                  type="button"
                  onClick={(e) => handleStudentSearch(e as unknown as React.FormEvent)}
                  disabled={isSearching || searchQuery.trim().length < 2}
                  className="rounded border border-slate-300 px-4 py-2 text-sm disabled:opacity-50"
                >
                  {isSearching ? t("searching") : t("search")}
                </button>
              </div>
              {searchResults.length > 0 ? (
                <ul className="mt-3 max-h-48 space-y-1 overflow-y-auto rounded border border-slate-200 p-2">
                  {searchResults.map((student) => (
                    <li key={student.id}>
                      <label className="flex cursor-pointer items-center gap-2 rounded px-2 py-1 hover:bg-slate-50">
                        <input
                          type="radio"
                          name="studentPicker"
                          value={student.id}
                          checked={selectedStudentId === student.id}
                          onChange={() => setSelectedStudentId(student.id)}
                        />
                        <span>
                          {student.name}
                          {student.studentCode ? (
                            <span className="ml-2 text-xs text-slate-500">{student.studentCode}</span>
                          ) : null}
                        </span>
                      </label>
                    </li>
                  ))}
                </ul>
              ) : null}
              {state.fieldErrors?.studentId ? (
                <p className="mt-1 text-sm text-red-600" role="alert">
                  {t("requiredField")}
                </p>
              ) : null}
            </div>
          </>
        ) : (
          <>
            <p className="text-sm text-slate-600">
              {t("enrollingStudent")}: <strong>{studentName}</strong>
            </p>
            <div>
              <label htmlFor="classId" className="mb-1 block text-sm font-medium">
                {t("selectClass")}
              </label>
              <select
                id="classId"
                name="classId"
                required
                defaultValue={values.classId}
                className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
              >
                <option value="">{t("selectClass")}</option>
                {classes.map((cls) => (
                  <option key={cls.id} value={cls.id}>
                    {cls.courseCode} — {cls.name}
                  </option>
                ))}
              </select>
              {state.fieldErrors?.classId ? (
                <p className="mt-1 text-sm text-red-600" role="alert">
                  {t("requiredField")}
                </p>
              ) : null}
            </div>
          </>
        )}

        <div>
          <label htmlFor="startDate" className="mb-1 block text-sm font-medium">
            {t("startDate")}
          </label>
          <input
            id="startDate"
            name="startDate"
            type="date"
            required
            defaultValue={values.startDate}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm sm:max-w-xs"
          />
          {state.fieldErrors?.startDate ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("invalidDate")}
            </p>
          ) : null}
        </div>

        <div>
          <label htmlFor="status" className="mb-1 block text-sm font-medium">
            {t("statusColumn")}
          </label>
          <select
            id="status"
            name="status"
            defaultValue={values.status}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm sm:max-w-xs"
          >
            {CREATE_ENROLLMENT_STATUSES.map((status) => (
              <option key={status} value={status}>
                {tStatus(status)}
              </option>
            ))}
          </select>
        </div>
      </section>

      {globalError ? (
        <p className="text-sm text-red-600" role="alert">
          {globalError}
        </p>
      ) : null}

      <div className="flex flex-wrap gap-3">
        <button
          type="submit"
          disabled={pending}
          className="rounded bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
        >
          {pending ? t("saving") : t("enrollStudent")}
        </button>
        <Link
          href={backHref}
          className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
        >
          {t("cancel")}
        </Link>
      </div>
    </form>
  );
}
