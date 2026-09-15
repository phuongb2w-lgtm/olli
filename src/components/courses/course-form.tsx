"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import {
  createCourse,
  updateCourse,
  type CourseActionState,
  type CourseFormValues,
} from "@/app/actions/courses";
import { COURSE_STATUSES } from "@/lib/academic/constants";

type Props = {
  mode: "create" | "edit";
  initialValues: CourseFormValues;
  courseId?: string;
};

const initialActionState: CourseActionState = {};

function fieldErrorKey(code: string | undefined): string | null {
  if (!code) return null;
  const map: Record<string, string> = {
    required: "requiredField",
    tooLong: "codeTooLong",
    invalid: "invalidStatus",
  };
  return map[code] ?? null;
}

export function CourseForm({ mode, initialValues, courseId }: Props) {
  const t = useTranslations("courses");
  const tStatus = useTranslations("status.course");
  const action = mode === "create" ? createCourse : updateCourse;
  const [state, formAction, pending] = useActionState(action, initialActionState);

  const values = state.values ?? initialValues;

  const globalError =
    state.error === "permission_denied"
      ? t("permissionDenied")
      : state.error === "course_code_conflict"
        ? t("codeExists")
        : state.error === "save_error"
          ? t("saveError")
          : state.error === "not_found"
            ? t("notFound")
            : null;

  return (
    <form action={formAction} className="space-y-6">
      {mode === "edit" && courseId ? (
        <input type="hidden" name="courseId" value={courseId} />
      ) : null}

      <section className="space-y-4 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
        <h2 className="text-sm font-semibold text-slate-900">{t("profileSection")}</h2>

        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="code" className="mb-1 block text-sm font-medium">
              {t("codeColumn")}
            </label>
            <input
              id="code"
              name="code"
              type="text"
              required
              defaultValue={values.code}
              className="w-full rounded border border-slate-300 px-3 py-2 text-sm"
            />
            {state.fieldErrors?.code ? (
              <p className="mt-1 text-sm text-red-600" role="alert">
                {t(fieldErrorKey(state.fieldErrors.code) ?? "requiredField")}
              </p>
            ) : null}
          </div>

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
                {t("requiredField")}
              </p>
            ) : null}
          </div>
        </div>

        <div>
          <label htmlFor="levelCode" className="mb-1 block text-sm font-medium">
            {t("levelColumn")}
          </label>
          <input
            id="levelCode"
            name="levelCode"
            type="text"
            defaultValue={values.levelCode}
            className="w-full rounded border border-slate-300 px-3 py-2 text-sm sm:max-w-xs"
          />
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
            {COURSE_STATUSES.map((status) => (
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
          href="/courses"
          className="rounded border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50"
        >
          {t("cancel")}
        </Link>
      </div>
    </form>
  );
}
