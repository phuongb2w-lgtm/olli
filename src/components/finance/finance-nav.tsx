"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";

const items = [
  { key: "overview", href: "/finance" },
  { key: "payments", href: "/finance/payments" },
  { key: "costs", href: "/finance/costs" },
  { key: "classEconomics", href: "/finance/class-economics" },
  { key: "simulator", href: "/finance/simulator" },
] as const;

export function FinanceNav() {
  const t = useTranslations("finance.nav");
  const pathname = usePathname();

  return (
    <nav className="flex flex-wrap gap-2 border-b border-slate-200 pb-3">
      {items.map((item) => {
        const isActive =
          item.href === "/finance"
            ? pathname === "/finance"
            : pathname.startsWith(item.href);
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
