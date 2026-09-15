import type { ClassStatus } from "@/lib/academic/constants";
import type { CreateEnrollmentStatus } from "@/lib/enrollments/constants";

export function canEnrollInClass(classStatus: ClassStatus): boolean {
  return classStatus !== "closed";
}

export function isCreateStatusAllowedForClass(
  classStatus: ClassStatus,
  enrollmentStatus: CreateEnrollmentStatus,
): boolean {
  if (classStatus === "closed") return false;
  if (classStatus === "planned") return enrollmentStatus === "pending";
  if (classStatus === "trial" || classStatus === "active") {
    return enrollmentStatus === "pending" || enrollmentStatus === "active";
  }
  return false;
}
