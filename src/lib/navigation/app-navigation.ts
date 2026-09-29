import type { PermissionCode } from "@/lib/permissions/codes";

export type NavItemKey =
  | "overview"
  | "executive"
  | "consultantPortfolio"
  | "admissions"
  | "students"
  | "classes"
  | "operations"
  | "academicReview"
  | "mySchedule"
  | "finance"
  | "users"
  | "subscription"
  | "settings";

export type NavItemDefinition = {
  key: NavItemKey;
  href: string;
  /** User must hold at least one listed permission. Empty = always visible when authenticated. */
  anyOf: PermissionCode[];
};

/**
 * Primary sidebar navigation contract.
 * Items not matching the user's permissions are omitted entirely (not disabled).
 */
export const APP_NAV_ITEMS: NavItemDefinition[] = [
  { key: "overview", href: "/", anyOf: ["organization.read"] },
  { key: "executive", href: "/executive", anyOf: ["report.executive.read"] },
  {
    key: "consultantPortfolio",
    href: "/consultant",
    anyOf: ["consultant_workspace.read"],
  },
  { key: "admissions", href: "/crm/leads", anyOf: ["lead.read"] },
  { key: "students", href: "/students", anyOf: ["student.read"] },
  { key: "classes", href: "/classes", anyOf: ["enrollment.read"] },
  {
    key: "operations",
    href: "/operations",
    anyOf: ["enrollment.update", "enrollment.create"],
  },
  {
    key: "academicReview",
    href: "/academic/review",
    anyOf: ["attendance.review", "assessment_result.review", "observation.review"],
  },
  {
    key: "mySchedule",
    href: "/operations",
    anyOf: ["attendance.record", "attendance.read", "enrollment.read"],
  },
  {
    key: "finance",
    href: "/finance",
    anyOf: [
      "charge.read",
      "payment.read",
      "expense.read",
      "asset.read",
      "revenue.read",
      "class_economics.read",
      "class_simulation.read",
      "consultant_revenue.review",
    ],
  },
  { key: "users", href: "/users", anyOf: ["center_account.manage"] },
  { key: "subscription", href: "/subscription", anyOf: ["center_account.manage"] },
  {
    key: "settings",
    href: "/settings",
    anyOf: ["organization.update", "role.read", "lead.manage_sources"],
  },
];

const ACADEMIC_OPERATIONS_PERMISSIONS: PermissionCode[] = [
  "enrollment.update",
  "enrollment.create",
];

export function filterNavItemsByPermissions(
  items: NavItemDefinition[],
  granted: ReadonlySet<string>,
): NavItemDefinition[] {
  const hasAcademicOperations = ACADEMIC_OPERATIONS_PERMISSIONS.some((code) =>
    granted.has(code),
  );

  return items.filter((item) => {
    if (item.key === "operations") {
      return (
        hasAcademicOperations &&
        item.anyOf.some((code) => granted.has(code))
      );
    }
    if (item.key === "mySchedule") {
      return (
        !hasAcademicOperations &&
        item.anyOf.some((code) => granted.has(code))
      );
    }
    return item.anyOf.length === 0 || item.anyOf.some((code) => granted.has(code));
  });
}
