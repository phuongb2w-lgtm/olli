# M1 — Student & Guardian Product Contract

**Task:** M1-T01  
**Status:** Design lock (pre-implementation)

---

## 1. Product Objective

M1 creates the **operational master record** for people served by the center. Authorized staff must eventually be able to:

| Capability | In M1 scope? |
|------------|--------------|
| Find students quickly | Yes (list + search contract) |
| Create a student | Yes (workflow defined; implementation M1-T03) |
| Maintain student information | Yes |
| Manage lifecycle/status | Yes |
| Associate one or more guardians | Yes |
| Reuse one guardian across multiple students | Yes |
| Identify primary/contact guardians | Yes |
| Preserve history instead of duplicating people | Yes |
| Operate bilingually (vi/en) | Yes |
| Remain organization-isolated through RLS | Yes — mandatory |

---

## 2. Explicit Non-Goals

| Out of scope | Reason |
|--------------|--------|
| Admissions CRM / lead pipeline | M1 is operational master data, not marketing |
| LMS / learning content | Separate domain |
| Class enrollment workflows | Academic operation; Enrollment entity handles this |
| Guardian/student portal or Auth identity linking | `guardian.email` ≠ `auth.users.email` |
| Hard DELETE of people records | M0 archive/lifecycle pattern |
| Weakening RLS or elevated bypass in Server Actions | Security invariant from M0 |
| Schema migrations in M1-T01 | Audit and contract only |

---

## 3. Canonical Responsibilities

### Student

One real learner/person within one Organization. Primarily **personal/master data plus lifecycle state**.

Student must **not** store canonical:

- Current class → derived from active `enrollment`
- Attendance percentage → derived from `attendance`
- Current tuition balance → derived from `charge` / `charge_balance`
- Latest test score → derived from `assessment_result`
- Progress score → derived from `progress_evaluation`

See [03-student-field-contract.md](./03-student-field-contract.md).

### Guardian

One real parent/guardian/contact person, independent of any single Student. Exists so siblings can share one Guardian record.

Guardian contact data must **not** be duplicated as canonical columns on Student.

### StudentGuardian

The many-to-many link carrying relationship metadata (`relationship_type`, contact flags, link lifecycle).

See [04-guardian-relationship-contract.md](./04-guardian-relationship-contract.md).

---

## 4. Organization Isolation

All Student/Guardian data is organization-owned:

```text
auth user → app_user → organization
```

Rules (unchanged from M0):

- Client code must not choose another Organization to create/read Student data.
- Server Actions derive `organization_id` from trusted identity (`current_organization_id()` / resolved `app_user`).
- Normal mutations use the authenticated user's Supabase session and remain subject to RLS.
- No second REST backend; no service-role bypass for normal CRUD.

Reference: [M0 auth application flow](../m0/24-auth-application-flow.md).

---

## 5. Authorization (Existing Permissions)

M1 uses the existing permission registry — **no new permissions in M1-T01**.

| Operation | Permission | RLS table(s) |
|-----------|------------|--------------|
| Read students | `student.read` | `student` |
| Create students | `student.create` | `student` |
| Update students | `student.update` | `student` |
| Read guardians | `guardian.read` | `guardian`, `student_guardian` |
| Create guardians / links | `guardian.create` | `guardian`, `student_guardian` |
| Update guardians / links | `guardian.update` | `guardian`, `student_guardian` |

There is no separate `student_guardian.*` permission; guardian permissions govern the relationship table. No permission gap identified for M1 V1.

Reference: [M0 permission model](../m0/19-permission-model.md).

---

## 6. Bilingual Terminology

Machine codes and database column names are **never renamed** for locale. UI labels use i18n namespaces below.

| English (en) | Vietnamese (vi) | i18n key (proposed) | Notes |
|--------------|-----------------|---------------------|-------|
| Student | Học viên | `students.title` | Standard center term |
| Guardian / Parent-Guardian | Phụ huynh / Người giám hộ | `guardians.title` | UI may use "Phụ huynh" as primary vi label; "Người giám hộ" when relationship is non-parent |
| Status | Trạng thái | `common.status` | |
| Active | Đang hoạt động | `status.student.active` | Student master lifecycle — see §7 |
| Inactive | Ngừng hoạt động | `status.student.inactive` | |
| Prospect | Tiềm năng | `status.student.prospect` | Pre-operational lead |
| Graduated | Đã tốt nghiệp | `status.student.graduated` | |
| Withdrawn | Đã rút lui | `status.student.withdrawn` | |
| Student code | Mã học viên | `students.studentCode` | |
| Date of birth | Ngày sinh | `students.dateOfBirth` | |
| Phone | Số điện thoại | `common.phone` | |
| Email | Email | `common.email` | |
| Address | Địa chỉ | `common.address` | Not in schema V1; reserved |
| Notes | Ghi chú | `common.notes` | |
| Relationship | Mối quan hệ | `studentGuardian.relationship` | |
| Primary contact | Liên hệ chính | `studentGuardian.primaryContact` | |
| Billing contact | Liên hệ thanh toán | `studentGuardian.billingContact` | Finance-facing |
| Add | Thêm | `common.add` | |
| Edit | Sửa | `common.edit` | |
| Save | Lưu | `common.save` | |
| Cancel | Hủy | `common.cancel` | |
| Search | Tìm kiếm | `common.search` | |
| No results | Không có kết quả | `common.noResults` | |

**Relationship type labels** (machine codes unchanged):

| Code | en | vi |
|------|----|----|
| `mother` | Mother | Mẹ |
| `father` | Father | Bố / Cha |
| `guardian` | Guardian | Người giám hộ |
| `other` | Other | Khác |

**Ambiguity note:** Vietnamese "Phụ huynh" implies parent; use relationship-type label when precision matters (e.g. billing contact who is an aunt → show "Người giám hộ" + relationship `other`).

Status translations follow [M0 status registry](../m0/31-status-code-registry.md) namespaces (`status.student.*`, `status.guardian.*`, `relationship.studentGuardian.*`).

---

## 7. Student Lifecycle vs Enrollment (Critical Distinction)

M0 status registry describes student `active` as "Currently enrolled participant." **M1 corrects the product semantics without changing machine codes:**

| Code | M1 master-record meaning | Not equivalent to |
|------|--------------------------|-------------------|
| `prospect` | Known person; not yet an operational student | CRM deal stage |
| `active` | Center currently serves / maintains this person | `enrollment.status = 'active'` |
| `inactive` | Temporarily not attending; record preserved | Leaving one class |
| `graduated` | Completed intended program pathway | Single class completion |
| `withdrawn` | Left center before completion | Enrollment withdrawal only |

A student leaving one class does **not** automatically change Student status. Enrollment carries class-level lifecycle.

Allowed transitions: see [03-student-field-contract.md](./03-student-field-contract.md).

Deactivating a Student does **not** delete enrollment history, attendance, assessments, observations, charges, or payments.

---

## 8. Archive / Inactive UI Terminology

| Entity | Mechanism | UI action label (en) | UI action label (vi) |
|--------|-----------|----------------------|----------------------|
| Student | `status` → `inactive`, `withdrawn`, or `graduated` | Deactivate / Mark withdrawn / Mark graduated | Ngừng hoạt động / Đánh dấu rút lui / … |
| Guardian | `status` → `inactive` | Deactivate contact | Ngừng liên hệ |
| StudentGuardian link | `status` → `ended` | Remove link | Gỡ liên kết |

No destructive **Delete** in UI. Guardian deactivation does not remove historical charges/payments.

Guardian does **not** need a separate `archived` status; `active` / `inactive` matches M0 schema.

---

## 9. Accessibility & Usability Foundation

M1 forms and lists (implemented in later tasks) must:

- Use explicit `<label>` / `htmlFor` for every input
- Support keyboard navigation and visible focus rings
- Associate validation errors with fields (`aria-describedby`, `role="alert"`)
- Provide touch targets ≥ 44×44 px on mobile
- Use semantic headings and landmarks in list/detail layouts
- Localize all user-visible strings including errors

No pixel-perfect designs in M1-T01; these are reusable standards for M1-T02+.

---

## 10. Responsive Layout

Primary target: administrative desktop. Must remain usable on tablet and mobile.

| Breakpoint | List behavior | Form behavior |
|------------|---------------|---------------|
| ≥ 1024px (desktop) | Full table: name, code, guardian, status | Two-column where helpful |
| 768–1023px (tablet) | Condensed table; hide secondary columns | Single column |
| < 768px (mobile) | Card/condensed rows; primary info first | Single column, stacked actions |

Student list may omit class column until Enrollment integration is intentionally introduced.

---

## 11. Success Feedback Pattern

After create/update (later tasks):

- Concise non-blocking confirmation (toast or inline banner, auto-dismiss)
- Deterministic navigation: return to list or stay on detail with refetched data
- No modal whose only purpose is "Success"

Pattern should be reusable for Teachers, Classes, etc.
