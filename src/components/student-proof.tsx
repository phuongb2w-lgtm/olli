import { getTranslations } from "next-intl/server";
import { createClient } from "@/lib/supabase/server";
import { can } from "@/lib/permissions/can";

export async function StudentProof() {
  const t = await getTranslations("students");
  const hasRead = await can("student.read");

  if (!hasRead) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <h2 className="mb-2 font-medium">{t("proofTitle")}</h2>
        <p>{t("proofDenied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("student")
    .select("id, given_name, family_name")
    .order("family_name")
    .limit(10);

  if (error) {
    return (
      <section className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
        <h2 className="mb-2 font-medium">{t("proofTitle")}</h2>
        <p>{t("proofError")}</p>
      </section>
    );
  }

  return (
    <section className="rounded-lg border border-slate-200 bg-white p-4">
      <h2 className="mb-3 font-medium">{t("proofTitle")}</h2>
      {data.length === 0 ? (
        <p className="text-sm text-slate-600">{t("proofEmpty")}</p>
      ) : (
        <ul className="space-y-1 text-sm">
          {data.map((student) => (
            <li key={student.id}>
              {student.family_name} {student.given_name}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
