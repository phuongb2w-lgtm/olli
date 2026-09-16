import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { ClassEconomicsPanel } from "@/components/finance/class-economics-panel";
import { can } from "@/lib/permissions/can";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Props = {
  params: Promise<{ classId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function ClassEconomicsDetailPage({ params, searchParams }: Props) {
  const t = await getTranslations("finance.classEconomics");
  const { classId } = await params;
  const rawParams = await searchParams;

  if (!(await can("class_economics.read"))) {
    return (
      <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
        <p>{t("denied")}</p>
      </section>
    );
  }

  const supabase = await createClient();
  const { data: cls } = await supabase.from("class").select("id, name").eq("id", classId).maybeSingle();
  if (!cls) notFound();

  const periodMode = typeof rawParams.mode === "string" ? rawParams.mode : "month";
  const period = typeof rawParams.period === "string" ? rawParams.period : undefined;
  const from = typeof rawParams.from === "string" ? rawParams.from : undefined;
  const to = typeof rawParams.to === "string" ? rawParams.to : undefined;

  return (
    <div className="space-y-6">
      <Link href="/finance/class-economics" className="text-sm text-slate-600 underline">
        ← {t("backToList")}
      </Link>
      <h2 className="text-lg font-semibold">
        {t("title")} — {cls.name}
      </h2>
      <ClassEconomicsPanel classId={classId} periodMode={periodMode} period={period} from={from} to={to} />
    </div>
  );
}
