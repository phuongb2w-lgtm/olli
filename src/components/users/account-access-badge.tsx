import { getTranslations } from "next-intl/server";
import type { CenterAccountPerson } from "@/lib/center-accounts/types";

type Props = {
  accessStatus: CenterAccountPerson["accessStatus"];
};

export async function AccountAccessBadge({ accessStatus }: Props) {
  const t = await getTranslations("users.accessStatus");
  return (
    <span className="inline-flex rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
      {t(accessStatus)}
    </span>
  );
}
