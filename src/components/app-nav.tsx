"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";

const navItems = [
  { key: "overview", href: "/" },
  { key: "admissions", href: "/crm/leads" },
  { key: "students", href: "/students" },
  { key: "classes", href: "/classes" },
  { key: "teachers", href: null },
  { key: "finance", href: "/finance" },
  { key: "reports", href: null },
  { key: "settings", href: null },
] as const;

export function AppNav() {
  const t = useTranslations("shell");
  const pathname = usePathname();

  return (
    <nav className="space-y-1">
      {navItems.map((item) => {
        const isActive =
          item.href !== null &&
          (item.href === "/" ? pathname === "/" : pathname.startsWith(item.href));

        if (item.href) {
          return (
            <Link
              key={item.key}
              href={item.href}
              className={`flex items-center justify-between rounded px-3 py-2 text-sm ${
                isActive
                  ? "bg-slate-900 font-medium text-white"
                  : "text-slate-700 hover:bg-slate-100"
              }`}
              aria-current={isActive ? "page" : undefined}
            >
              <span>{t(item.key)}</span>
            </Link>
          );
        }

        return (
          <div
            key={item.key}
            className="flex items-center justify-between rounded px-3 py-2 text-sm text-slate-500"
            aria-disabled="true"
          >
            <span>{t(item.key)}</span>
            <span className="text-xs text-slate-400">{t("comingSoon")}</span>
          </div>
        );
      })}
    </nav>
  );
}
