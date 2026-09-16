import { getTranslations } from "next-intl/server";

export const dynamic = "force-dynamic";

export default async function CrmLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const t = await getTranslations("crm");
  return (
    <div className="space-y-2">
      <p className="text-sm text-slate-500">{t("title")}</p>
      {children}
    </div>
  );
}
