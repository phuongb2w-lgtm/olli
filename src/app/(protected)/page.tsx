import { getTranslations } from "next-intl/server";
import { StudentProof } from "@/components/student-proof";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const t = await getTranslations("shell");

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">{t("overview")}</h1>
      <p className="text-sm text-slate-600">{t("foundationProof")}</p>
      <StudentProof />
    </div>
  );
}
