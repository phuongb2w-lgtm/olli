# M5-T01 — Role & Workspace Contracts

Authorization is **permission-based** internally. The product presents **five canonical operational roles**. A user may hold multiple permission groups.

## Center Manager

**Workspace areas:** Executive Overview, Finance, CRM/Admissions, Students, Classes, Teaching Operations, Users & Permissions, Settings.

**Exclusive:** `report.executive.read` — complete center-wide executive/management reporting surface.

**Typical permissions:** All operational permissions plus user/role management. Dev seed role `admin` maps here.

## Accountant

**Workspace areas:** Finance overview, Receipts, Expenses, Cost A, permitted Cost B, tuition/payments/receivables, Consultant Revenue Review, bookkeeping records.

**Not granted:** Complete cross-domain executive dashboard, teacher quality management, unrelated CRM tools.

**Key permissions:** `charge.*`, `payment.*`, `expense.*`, `asset.*`, `revenue.*`, `personnel_cost.*`, `class_economics.read`, `consultant_revenue.review`.

## Consultant

**Workspace areas:** Leads, pipeline, follow-ups, trials, conversions, contacts, Declare Revenue, My Revenue / declaration status.

**Not granted:** Cost A, accounting ledger, center-wide P&L, teacher quality, executive reporting.

**Key permissions:** `lead.read`, `lead.create`, `lead.update`, `lead.assign`, `lead.convert`, `consultant_revenue.declare`.

## Academic Operations

**Workspace areas:** Students, enrollments, classes, timetables, teaching sessions, scheduling, attendance/score/comment review.

**Not granted:** Center-wide financial executive reporting.

**Key permissions:** `student.*`, `guardian.*`, `teacher.read`, `enrollment.*`, `attendance.read`, `assessment.read`, `observation.read`.

## Teacher

**Workspace areas:** My Schedule, today's sessions, session roster, Attendance, Scores, Comments.

**Not granted:** Finance, CRM, user management, class economics, executive reports, general administration.

**Key permissions:** `attendance.record`, `attendance.read`, `assessment.read`, `assessment_result.record`, `observation.record`, `observation.read`, `enrollment.read`.

Navigation label **My schedule** (`mySchedule`) appears instead of **Operations** when the user lacks academic scheduling permissions.

## Navigation contract

Implemented in `src/lib/navigation/app-navigation.ts`:

- Items require at least one listed permission (`anyOf`).
- Items without matching permissions are **omitted** (not disabled).
- Routes and actions remain independently protected server-side.

## UX wording (locked)

| Role | Preferred label | Avoid |
|------|-----------------|-------|
| Consultant | Declare Revenue | Create Financial Transaction |
| Accountant | Revenue Awaiting Review | Raw declaration table names |
| Teacher | Attendance, Scores, Comments | Internal entity jargon |
