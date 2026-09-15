import { getTranslations } from "next-intl/server";
import { RosterLifecycleActions } from "@/components/enrollments/roster-lifecycle-actions";
import type { RosterListItem } from "@/lib/enrollments/query-class-roster";
import { OPERATIONAL_ENROLLMENT_STATUSES } from "@/lib/enrollments/constants";

type ClassOption = {
  id: string;
  name: string;
  courseCode: string;
};

type Props = {
  items: RosterListItem[];
  canUpdate: boolean;
  classId: string;
  classOptions: ClassOption[];
};

export async function RosterCards({ items, canUpdate, classId, classOptions }: Props) {
  const t = await getTranslations("enrollments");
  const tStatus = await getTranslations("status.enrollment");
  const placeholder = t("emptyValue");

  return (
    <ul className="space-y-3 lg:hidden">
      {items.map((item) => {
        const isOperational = OPERATIONAL_ENROLLMENT_STATUSES.includes(
          item.status as (typeof OPERATIONAL_ENROLLMENT_STATUSES)[number],
        );
        return (
          <li
            key={item.enrollmentId}
            className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
          >
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="font-medium text-slate-900">{item.studentName}</p>
                <p className="text-sm text-slate-600">{item.studentCode ?? placeholder}</p>
              </div>
              <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
                {tStatus(item.status)}
              </span>
            </div>
            <dl className="mt-3 space-y-1 text-sm">
              <div className="flex gap-2">
                <dt className="text-slate-500">{t("startDate")}:</dt>
                <dd className="text-slate-800">{item.startDate}</dd>
              </div>
              <div className="flex gap-2">
                <dt className="text-slate-500">{t("endDate")}:</dt>
                <dd className="text-slate-800">{item.endDate ?? placeholder}</dd>
              </div>
            </dl>
            {canUpdate && isOperational ? (
              <div className="mt-3">
                <RosterLifecycleActions
                  enrollmentId={item.enrollmentId}
                  canUpdate={canUpdate}
                  classOptions={classOptions}
                  currentClassId={classId}
                />
              </div>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}
