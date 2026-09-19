"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";

const baseItems = [
  { key: "myWork", href: "/crm/my-work" },
  { key: "leads", href: "/crm/leads" },
  { key: "reports", href: "/crm/reports" },
] as const;

type Props = {
  showSettings?: boolean;
};

export function CrmNav({ showSettings = false }: Props) {
  const items = showSettings
    ? [...baseItems, { key: "settings" as const, href: "/crm/settings" }]
    : baseItems;
  const t = useTranslations("crm.nav");
  const pathname = usePathname();

  return (
    <nav className="flex flex-wrap gap-2 border-b border-slate-200 pb-3">
      {items.map((item) => {
        const isActive = pathname.startsWith(item.href);
        return (
          <Link
            key={item.key}
            href={item.href}
            className={`rounded px-3 py-1.5 text-sm ${
              isActive
                ? "bg-slate-900 font-medium text-white"
                : "bg-slate-100 text-slate-700 hover:bg-slate-200"
            }`}
            aria-current={isActive ? "page" : undefined}
          >
            {t(item.key)}
          </Link>
        );
      })}
    </nav>
  );
}
