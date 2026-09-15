import type { AttendanceStatus } from "@/lib/session-execution/constants";
import type { EnrollmentStatus } from "@/lib/enrollments/constants";

export type ReportPeriod = {
  startDate: string;
  endDate: string;
};

export type OrganizationBranding = {
  name: string;
  hasLogo: boolean;
};

export type ClassReportContext = {
  classId: string;
  className: string;
  classStatus: string;
  courseCode: string | null;
  courseName: string | null;
  termStartDate: string | null;
  termEndDate: string | null;
};

export type AttendanceLearnerRow = {
  enrollmentId: string;
  studentId: string;
  studentName: string;
  studentCode: string | null;
  enrollmentStatus: EnrollmentStatus;
  eligibleSessions: number;
  presentCount: number;
  absentCount: number;
  lateCount: number;
  excusedCount: number;
  notRecordedCount: number;
  recordedSessions: number;
  attendanceRate: number | null;
};

export type ClassAttendanceReport = {
  branding: OrganizationBranding;
  context: ClassReportContext;
  period: ReportPeriod;
  generatedAt: string;
  sessionTotals: {
    materialized: number;
    completed: number;
    cancelled: number;
    inProgress: number;
    scheduled: number;
  };
  learners: AttendanceLearnerRow[];
};

export type AssessmentLearnerCell = {
  assessmentId: string;
  rawScore: number | null;
  maxScore: number | null;
  percentage: number | null;
  hasScore: boolean;
};

export type AssessmentReportItem = {
  id: string;
  title: string;
  assessedOn: string;
  maxScore: number;
};

export type ClassAssessmentReport = {
  branding: OrganizationBranding;
  context: ClassReportContext;
  period: ReportPeriod;
  generatedAt: string;
  assessments: AssessmentReportItem[];
  learners: Array<{
    enrollmentId: string;
    studentName: string;
    studentCode: string | null;
    cells: AssessmentLearnerCell[];
  }>;
  aggregates: {
    scoredCount: number;
    withoutScoreCount: number;
    meanPercentage: number | null;
    minPercentage: number | null;
    maxPercentage: number | null;
  };
};

export type ObservationSummaryRow = {
  indicatorCode: string;
  ratingCode: string;
  count: number;
};

export type ClassEndOfCourseReport = {
  branding: OrganizationBranding;
  context: ClassReportContext;
  period: ReportPeriod;
  generatedAt: string;
  includesObservations: boolean;
  sessions: {
    completed: number;
    cancelled: number;
    total: number;
  };
  enrollments: {
    total: number;
    byStatus: Record<string, number>;
  };
  attendance: {
    learnersWithData: number;
    averageAttendanceRate: number | null;
    totalNotRecorded: number;
  };
  assessments: {
    count: number;
    resultsRecorded: number;
    meanPercentage: number | null;
  };
  observations: {
    sessionCount: number;
    ratingDistribution: ObservationSummaryRow[];
    commentCount: number;
  } | null;
  attendanceReport: ClassAttendanceReport;
  assessmentReport: ClassAssessmentReport;
};

export type StudentProgressReport = {
  branding: OrganizationBranding;
  studentId: string;
  studentName: string;
  studentCode: string | null;
  period: ReportPeriod;
  generatedAt: string;
  includesObservations: boolean;
  enrollmentScope: {
    enrollmentId: string;
    classId: string;
    className: string;
    courseCode: string | null;
    enrollmentStatus: EnrollmentStatus;
    startDate: string;
    endDate: string | null;
  } | null;
  attendance: AttendanceLearnerRow | null;
  assessments: Array<{
    assessmentId: string;
    title: string;
    assessedOn: string;
    rawScore: number | null;
    maxScore: number | null;
    percentage: number | null;
  }>;
  averagePercentage: number | null;
  observations: Array<{
    sessionDate: string;
    className: string;
    ratings: Record<string, string>;
    comment: string | null;
  }> | null;
};

export type SessionRow = {
  id: string;
  occurrenceDate: string;
  status: string;
};

export type EnrollmentRow = {
  id: string;
  studentId: string;
  startDate: string;
  endDate: string | null;
  status: EnrollmentStatus;
  studentName: string;
  studentCode: string | null;
};

export type AttendanceRow = {
  enrollmentId: string;
  teachingSessionId: string;
  status: AttendanceStatus;
};
