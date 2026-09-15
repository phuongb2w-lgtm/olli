"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import {
  createClass,
  updateClass,
  type ClassActionState,
  type ClassFormValues,
} from "@/app/actions/classes";
import { CLASS_STATUSES } from "@/lib/academic/constants";

type CourseOption = {
  id: string;
  code: string;
  name: string;
};

type Props = {
  mode: "create" | "edit";
  initialValues: ClassFormValues;
  courses: CourseOption[];
  classId?: string;
};

const initialActionState: ClassActionState = {};

function fieldErrorKey(code: string | undefined): string | null {
  if (!code) return null;
  const map: Record<string, string> = {
    required: "requiredField",
    invalid: "invalidDate",
    tooLong: "nameTooLong",
    beforeStart: "endBeforeStart",
  };
  return map[code] ?? null;
}

export function ClassForm({ mode, initialValues, courses, classId }: Props) {
  const t = useTranslations("classes");
  const tStatus = useTranslations("status.class");
  const action = mode === "create" ? createClass : updateClass;
  const [state, formAction, pending] = useActionState(action, initialActionState);

  const values = state.values ?? initialValues;
  const originalStatus = initialValues.status;
  const formKey = state.values
    ? `${Boolean(state.statusChangeRequired)}-${state.statusChangeRequired?.to ?? ""}-${values.name}`
    : "initial";

  const globalError =
    state.error === "permission_denied"
      ? t("permissionDenied")
      : state.error === "invalid_course"
        ? t("invalidCourse")
        : state.error === "save_error"
          ? t("saveError")
          : state.error === "not_found"
            ? t("notFound")
            : null;

  const closingClass =
    state.statusChangeRequired?.to === "closed" ||
    (values.status === "closed" && state.statusChangeRequired);

  return (
    <form key={formKey} action={formAction} className="space-y-6">
      {mode === "edit" && classId ? (
        <input type="hidden" name="classId" value={classId} />
      ) : null}
      <input type="hidden" name="originalStatus" value={originalStatus} />

      <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-slate-900">{t("profileSection")}</h2>

        <div>
          <label htmlFor="name" className="mb-1 block text-sm font-medium">
            {t("nameColumn")}
          </label>
          <input
            id="name"
            name="name"
            type="text"
            required
            defaultValue={values.name}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          />
          {state.fieldErrors?.name ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t(fieldErrorKey(state.fieldErrors.name) ?? "requiredField")}
            </p>
          ) : null}
        </div>

        <div>
          <label htmlFor="courseId" className="mb-1 block text-sm font-medium">
            {t("courseColumn")}
          </label>
          <select
            id="courseId"
            name="courseId"
            required
            defaultValue={values.courseId}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">{t("selectCourse")}</option>
            {courses.map((course) => (
              <option key={course.id} value={course.id}>
                {course.code} — {course.name}
              </option>
            ))}
          </select>
          {state.fieldErrors?.courseId ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("requiredField")}
            </p>
          ) : null}
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="termStartDate" className="mb-1 block text-sm font-medium">
              {t("termStartColumn")}
            </label>
            <input
              id="termStartDate"
              name="termStartDate"
              type="date"
              defaultValue={values.termStartDate}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            {state.fieldErrors?.termStartDate ? (
              <p className="mt-1 text-sm text-red-600" role="alert">
                {t("invalidDate")}
              </p>
            ) : null}
          </div>

          <div>
            <label htmlFor="termEndDate" className="mb-1 block text-sm font-medium">
              {t("termEndColumn")}
            </label>
            <input
              id="termEndDate"
              name="termEndDate"
              type="date"
              defaultValue={values.termEndDate}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            {state.fieldErrors?.termEndDate ? (
              <p className="mt-1 text-sm text-red-600" role="alert">
                {t(
                  state.fieldErrors.termEndDate === "beforeStart"
                    ? "endBeforeStart"
                    : "invalidDate",
                )}
              </p>
            ) : null}
          </div>
        </div>

        <div>
          <label htmlFor="capacity" className="mb-1 block text-sm font-medium">
            {t("capacity")}
          </label>
          <input
            id="capacity"
            name="capacity"
            type="number"
            min={1}
            defaultValue={values.capacity}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm sm:max-w-xs"
          />
          {state.fieldErrors?.capacity ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("invalidCapacity")}
            </p>
          ) : null}
        </div>
      </section>

      <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-slate-900">{t("lifecycleSection")}</h2>

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
            {CLASS_STATUSES.map((status) => (
              <option key={status} value={status}>
                {tStatus(status)}
              </option>
            ))}
          </select>
          {state.fieldErrors?.status ? (
            <p className="mt-1 text-sm text-red-600" role="alert">
              {t("invalidStatus")}
            </p>
          ) : null}
        </div>

        {state.statusChangeRequired ? (
          <div
            className="rounded border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900"
            role="alert"
          >
            <p className="font-medium">{t("statusChangeConfirmTitle")}</p>
            <p className="mt-1">
              {t("statusChangeConfirmMessage", {
                from: tStatus(state.statusChangeRequired.from),
                to: tStatus(state.statusChangeRequired.to),
              })}
            </p>
            {closingClass || state.statusChangeRequired.to === "closed" ? (
              <p className="mt-2">{t("closeClassHint")}</p>
            ) : null}
            <label className="mt-3 flex items-start gap-2">
              <input
                type="checkbox"
                name="confirmStatusChange"
                value="true"
                className="mt-0.5"
              />
              <span>{t("confirmStatusChange")}</span>
            </label>
          </div>
        ) : null}
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
          {pending ? t("saving") : t("save")}
        </button>
        <Link
          href="/classes"
          className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
        >
          {t("cancel")}
        </Link>
      </div>
    </form>
  );
}
