import { getTranslations } from "next-intl/server";
import { can } from "@/lib/permissions/can";

export const dynamic = "force-dynamic";

export default async function UsersPage() {
  const t = await getTranslations("users");

  const hasRead = await can("user.read");
  const hasManage = await can("user.manage");

  if (!hasRead && !hasManage) {
    return (
      <div className="space-y-4">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <section className="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
          <p>{t("denied")}</p>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <p className="text-sm text-slate-600">{t("foundationDescription")}</p>
      {hasManage ? (
        <p className="text-sm text-slate-700">{t("manageHint")}</p>
      ) : (
        <p className="text-sm text-slate-700">{t("readHint")}</p>
      )}
    </div>
  );
}
