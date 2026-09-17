"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import {
  createTeacherAssignmentAction,
  type TeachingActionState,
} from "@/app/actions/teaching";
import type { TeacherOption } from "@/lib/teaching/query-class-teaching";
import { TEACHER_ASSIGNMENT_ROLES } from "@/lib/teaching/constants";

type Props = {
  classId: string;
  teachers: TeacherOption[];
};

const initialState: TeachingActionState = {};

export function TeacherAssignmentForm({ classId, teachers }: Props) {
  const t = useTranslations("teaching");
  const [state, formAction, pending] = useActionState(createTeacherAssignmentAction, initialState);

  return (
    <form action={formAction} className="space-y-4 rounded-lg border border-slate-200 bg-white p-4">
      <h3 className="text-sm font-semibold text-slate-900">{t("addTeacher")}</h3>
      <input type="hidden" name="classId" value={classId} />

      {state.error === "permission_denied" ? (
        <p className="text-sm text-red-700">{t("permissionDenied")}</p>
      ) : null}
      {state.error === "invalid_teacher" ? (
        <p className="text-sm text-red-700">{t("invalidTeacher")}</p>
      ) : null}
      {state.error === "class_closed" ? (
        <p className="text-sm text-red-700">{t("classClosedAssignment")}</p>
      ) : null}
      {state.error === "invalid_assignment_range" ? (
        <p className="text-sm text-red-700">{t("invalidAssignmentRange")}</p>
      ) : null}
      {state.error === "duplicate_assignment" ? (
        <p className="text-sm text-red-700">{t("duplicateAssignment")}</p>
      ) : null}
      {state.error === "save_error" && !state.fieldErrors ? (
        <p className="text-sm text-red-700">{t("saveError")}</p>
      ) : null}

      <div>
        <label htmlFor="teacherId" className="block text-sm font-medium text-slate-700">
          {t("teacher")}
        </label>
        <select
          id="teacherId"
          name="teacherId"
          required
          defaultValue={state.values?.teacherId ?? ""}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          <option value="">{t("selectTeacher")}</option>
          {teachers.map((teacher) => (
            <option key={teacher.id} value={teacher.id}>
              {teacher.label}
            </option>
          ))}
        </select>
        {state.fieldErrors?.teacherId ? (
          <p className="mt-1 text-xs text-red-700">{t("requiredField")}</p>
        ) : null}
      </div>

      <div>
        <label htmlFor="roleCode" className="block text-sm font-medium text-slate-700">
          {t("roleLabel")}
        </label>
        <select
          id="roleCode"
          name="roleCode"
          defaultValue={state.values?.roleCode ?? "primary"}
          className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
        >
          {TEACHER_ASSIGNMENT_ROLES.map((role) => (
            <option key={role} value={role}>
              {t(`role.${role}`)}
            </option>
          ))}
        </select>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label htmlFor="effectiveFrom" className="block text-sm font-medium text-slate-700">
            {t("effectiveFrom")}
          </label>
          <input
            id="effectiveFrom"
            name="effectiveFrom"
            type="date"
            required
            defaultValue={state.values?.effectiveFrom ?? ""}
            className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
        <div>
          <label htmlFor="effectiveTo" className="block text-sm font-medium text-slate-700">
            {t("effectiveUntil")}
          </label>
          <input
            id="effectiveTo"
            name="effectiveTo"
            type="date"
            defaultValue={state.values?.effectiveTo ?? ""}
            className="mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
        </div>
      </div>

      <button
        type="submit"
        disabled={pending}
        className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {pending ? t("saving") : t("addTeacher")}
      </button>
    </form>
  );
}
