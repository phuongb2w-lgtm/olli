export const STUDENT_STATUSES = [
  "prospect",
  "active",
  "inactive",
  "graduated",
  "withdrawn",
] as const;

export type StudentStatus = (typeof STUDENT_STATUSES)[number];

export type StudentListStatusFilter = "all" | StudentStatus;

export const STUDENT_PAGE_SIZES = [25, 50, 100] as const;

export type StudentPageSize = (typeof STUDENT_PAGE_SIZES)[number];

export type StudentListPrimaryContact = {
  id: string;
  name: string;
  phone: string | null;
};

export type StudentListItem = {
  id: string;
  name: string;
  studentCode: string | null;
  status: StudentStatus;
  primaryContact: StudentListPrimaryContact | null;
};

export type StudentListParams = {
  q: string;
  status: StudentListStatusFilter;
  page: number;
  pageSize: StudentPageSize;
};

export type StudentListResult = {
  items: StudentListItem[];
  totalCount: number;
  params: StudentListParams;
};
