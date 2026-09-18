import type { PermissionCode } from "@/lib/permissions/codes";

/** Canonical Olli operating roles (product presentation). Authorization uses permissions. */
export type CanonicalRole =
  | "center_manager"
  | "accountant"
  | "consultant"
  | "academic_operations"
  | "teacher";

export type WorkspaceArea =
  | "executive_overview"
  | "finance"
  | "crm_admissions"
  | "students"
  | "classes"
  | "teaching_operations"
  | "users_permissions"
  | "settings";

export type RoleWorkspaceContract = {
  role: CanonicalRole;
  labelKey: string;
  areas: WorkspaceArea[];
  /** Minimum permission set representing this role when configured in isolation. */
  permissions: PermissionCode[];
  notes?: string;
};

/**
 * Permission bundles for the five canonical roles.
 * Centers may assign multiple bundles to one user; there is no separate HR role.
 */
export const ROLE_WORKSPACE_CONTRACTS: RoleWorkspaceContract[] = [
  {
    role: "center_manager",
    labelKey: "roles.centerManager",
    areas: [
      "executive_overview",
      "finance",
      "crm_admissions",
      "students",
      "classes",
      "teaching_operations",
      "users_permissions",
      "settings",
    ],
    permissions: [
      "report.executive.read",
      "user.manage",
      "role.manage",
      "organization.update",
    ],
    notes: "Full system access via permission composition; only role with executive_overview.",
  },
  {
    role: "accountant",
    labelKey: "roles.accountant",
    areas: ["finance"],
    permissions: [
      "charge.read",
      "charge.create",
      "payment.read",
      "payment.record",
      "payment.reverse",
      "expense.read",
      "expense.create",
      "asset.read",
      "asset.create",
      "asset.update",
      "revenue.read",
      "revenue.recognize",
      "personnel_cost.read",
      "personnel_cost.manage",
      "class_economics.read",
      "consultant_revenue.review",
    ],
    notes: "Finance operational workspace; not automatic executive reporting.",
  },
  {
    role: "consultant",
    labelKey: "roles.consultant",
    areas: ["crm_admissions"],
    permissions: [
      "lead.read",
      "lead.create",
      "lead.update",
      "lead.assign",
      "lead.convert",
      "consultant_revenue.declare",
    ],
    notes: "Personal pipeline and revenue declarations; no center-wide executive finance.",
  },
  {
    role: "academic_operations",
    labelKey: "roles.academicOperations",
    areas: ["students", "classes", "teaching_operations"],
    permissions: [
      "student.read",
      "student.create",
      "student.update",
      "guardian.read",
      "guardian.create",
      "guardian.update",
      "teacher.read",
      "enrollment.read",
      "enrollment.create",
      "enrollment.update",
      "attendance.read",
      "assessment.read",
      "observation.read",
    ],
    notes: "Academic administration and review layer; confirms teacher-entered data.",
  },
  {
    role: "teacher",
    labelKey: "roles.teacher",
    areas: ["teaching_operations"],
    permissions: [
      "attendance.record",
      "attendance.read",
      "assessment.read",
      "assessment_result.record",
      "observation.record",
      "observation.read",
      "enrollment.read",
    ],
    notes: "Simplest workspace: schedule, attendance, scores, comments only.",
  },
];

/** Maps existing dev seed role codes to nearest canonical role for audit documentation. */
export const SEED_ROLE_CANONICAL_MAP: Record<string, CanonicalRole | "mixed"> = {
  admin: "center_manager",
  staff: "mixed",
  student_reader: "mixed",
  no_student: "mixed",
};
