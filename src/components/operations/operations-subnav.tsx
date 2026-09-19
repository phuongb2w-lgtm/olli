"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";

const items = [
  { key: "today", href: "/operations", exact: true },
  { key: "calendar", href: "/operations/calendar", exact: false },
  { key: "workload", href: "/operations/workload", exact: false },
  { key: "intelligence", href: "/operations/intelligence", exact: false },
  { key: "myTeaching", href: "/operations/my-teaching", exact: false },
] as const;

export function OperationsSubnav() {
  const t = useTranslations("operations");
  const pathname = usePathname();

  return (
    <nav className="flex gap-2 border-b border-slate-200 pb-2" aria-label={t("subnavLabel")}>
      {items.map((item) => {
        const isActive = item.exact
          ? pathname === item.href
          : pathname.startsWith(item.href);
        return (
          <Link
            key={item.key}
            href={item.href}
            className={`rounded-md px-3 py-1.5 text-sm font-medium ${
              isActive
                ? "bg-slate-900 text-white"
                : "text-slate-600 hover:bg-slate-100 hover:text-slate-900"
            }`}
            aria-current={isActive ? "page" : undefined}
          >
            {t(`subnav.${item.key}`)}
          </Link>
        );
      })}
    </nav>
  );
}
