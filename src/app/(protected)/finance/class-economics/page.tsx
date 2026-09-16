import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ClassEconomicsIndexPage() {
  const t = await getTranslations("finance.classEconomics");

  if (!(await can("class_economics.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { data: classes } = await supabase
    .from("class")
    .select("id, name, course:course_id(code)")
    .order("name");

  return (
    <div className="space-y-4">
      <h2 className="text-lg font-semibold">{t("selectClass")}</h2>
      {(classes ?? []).length === 0 ? (
        <p className="text-sm text-slate-600">{t("noClasses")}</p>
      ) : (
        <ul className="space-y-2">
          {(classes ?? []).map((cls) => {
            const course = cls.course as { code?: string } | null;
            return (
              <li key={cls.id}>
                <Link href={`/finance/class-economics/${cls.id}`} className="text-sm underline">
                  {cls.name} {course?.code ? `(${course.code})` : ""}
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
