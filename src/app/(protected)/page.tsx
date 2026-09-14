import Link from "next/link";
import { getTranslations } from "next-intl/server";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const t = await getTranslations("shell");
  const tStudents = await getTranslations("students");

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">{t("overview")}</h1>
      <p className="text-sm text-slate-600">{t("foundationProof")}</p>
      <p className="text-sm text-slate-600">
        <Link href="/students" className="font-medium text-slate-900 underline">
          {tStudents("title")}
        </Link>
      </p>
    </div>
  );
}
