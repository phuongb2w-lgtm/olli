import { getTranslations } from "next-intl/server";
import type { StudentListItem } from "@/lib/students/types";

type Props = {
  items: StudentListItem[];
  showPrimaryContact: boolean;
};

export async function StudentListCards({ items, showPrimaryContact }: Props) {
  const t = await getTranslations("students");
  const tStatus = await getTranslations("status.student");
  const placeholder = t("emptyValue");

  return (
    <ul className="space-y-3 lg:hidden">
      {items.map((item) => (
        <li
          key={item.id}
          className="rounded-lg border border-slate-200 bg-white p-4 shadow-sm"
        >
          <div className="flex items-start justify-between gap-3">
            <p className="font-medium text-slate-900">{item.name}</p>
            <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
              {tStatus(item.status)}
            </span>
          </div>
          <dl className="mt-3 space-y-1 text-sm">
            <div className="flex gap-2">
              <dt className="text-slate-500">{t("codeColumn")}:</dt>
              <dd className="text-slate-800">{item.studentCode ?? placeholder}</dd>
            </div>
            {showPrimaryContact ? (
              <div className="flex gap-2">
                <dt className="text-slate-500">{t("primaryContactColumn")}:</dt>
                <dd className="text-slate-800">
                  {item.primaryContact ? (
                    <>
                      {item.primaryContact.name}
                      {item.primaryContact.phone ? (
                        <span className="block text-xs text-slate-500">
                          {item.primaryContact.phone}
                        </span>
                      ) : null}
                    </>
                  ) : (
                    placeholder
                  )}
                </dd>
              </div>
            ) : null}
          </dl>
        </li>
      ))}
    </ul>
  );
}
