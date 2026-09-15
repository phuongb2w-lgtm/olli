import { getTranslations } from "next-intl/server";
import { EndTeacherAssignmentForm } from "@/components/teaching/end-teacher-assignment-form";
import type { TeacherAssignmentItem } from "@/lib/teaching/query-class-teaching";

type Props = {
  classId: string;
  assignments: TeacherAssignmentItem[];
  canUpdate: boolean;
};

export async function TeacherAssignmentList({ classId, assignments, canUpdate }: Props) {
  const t = await getTranslations("teaching");
  const tStatus = await getTranslations("status.teacherAssignment");

  if (assignments.length === 0) {
    return <p className="text-sm text-slate-600">{t("noTeachers")}</p>;
  }

  return (
    <div className="space-y-3">
      {assignments.map((item) => (
        <article
          key={item.id}
          className="rounded-lg border border-slate-200 bg-white p-4 text-sm"
        >
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p className="font-medium text-slate-900">{item.teacherName}</p>
              <p className="text-slate-600">
                {t(`role.${item.roleCode}`)} · {item.effectiveFrom}
                {item.effectiveTo ? ` – ${item.effectiveTo}` : ""}
              </p>
            </div>
            <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
              {tStatus(item.status)}
            </span>
          </div>
          {canUpdate && item.status === "active" ? (
            <div className="mt-3">
              <EndTeacherAssignmentForm classId={classId} assignmentId={item.id} />
            </div>
          ) : null}
        </article>
      ))}
    </div>
  );
}
