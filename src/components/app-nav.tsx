"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import type { NavItemKey } from "@/lib/navigation/app-navigation";

export type VisibleNavItem = {
  key: NavItemKey;
  href: string;
};

type Props = {
  items: VisibleNavItem[];
};

export function AppNav({ items }: Props) {
  const t = useTranslations("shell");
  const pathname = usePathname();

  return (
    <nav className="space-y-1">
      {items.map((item) => {
        const isActive =
          item.href === "/"
            ? pathname === "/"
            : pathname.startsWith(item.href);

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
      })}
    </nav>
  );
}
