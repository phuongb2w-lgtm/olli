# M5-T01 — Reporting Semantics

Reporting data is derived from canonical M1–M4 operational state. Prefer SQL views/RPCs over speculative reporting tables.

## Organization scoping

All M5 read models scope to `current_organization_id()`. Cross-organization access is denied by RLS and RPC guards.

## Timezone & reporting periods

**Authority:** `resolve_reporting_period(start_date, end_date)` RPC and `src/lib/reporting/period-contract.ts`.

| Rule | Definition |
|------|------------|
| Input dates | Inclusive local dates (`YYYY-MM-DD`) in organization timezone |
| `start_at_utc` | `start_date 00:00:00` interpreted in `organization.timezone` |
| `end_at_exclusive` | Instant after `end_date` local day (`end_date + 1` at 00:00:00 local) |
| Timestamptz filter | `instant >= start_at_utc AND instant < end_at_exclusive` |
| DST | Conversion uses PostgreSQL / ICU timezone rules; safe for DST regions |

Each M5 query must use this contract — no ad-hoc period math.

## Financial semantics (do not collapse)

| Concept | Canonical source | Notes |
|---------|------------------|-------|
| Consultant declared revenue | `consultant_revenue_declaration` | Status `pending` / `returned` — **not** booked revenue |
| Approved consultant revenue | Declaration with `status = approved` | May link to `payment` when booked |
| Cash collected | `payment` + `payment_allocation` | Operational cash recording |
| Tuition obligation | `charge`, enrollment financial terms | Obligation, not cash |
| Receivable | `charge_balance` view | Derived outstanding |
| Recognized revenue | `revenue_recognition_event` (`status = posted`) | M2 recognition rules; **≠ cash collected** |
| Cost | `expense`, depreciation, personnel cost entries | By cost group |
| Class economics | Allocation rules + class economics RPCs | Contribution vs revenue/cost |

**Pending consultant declarations must not appear in canonical financial KPIs** unless the KPI namespace explicitly says `finance.pending_consultant_declarations`.

## Teaching / session semantics

| Concept | Rule |
|---------|------|
| Operational session date | `(scheduled_start_at AT TIME ZONE org.timezone)::date` |
| `occurrence_date` | Identity / provenance / dedup key; **not** current operational date after reschedule |
| Current teacher / room | `teaching_session.teacher_id`, `teaching_session.room_id` |
| Cancelled sessions | Suppress schedule projections (M4) |
| Planned vs delivered | Projected calendar entries vs materialized `teaching_session` rows |
| Delivered | Completed (or in-progress/completed per KPI definition in later tasks) materialized sessions |

Helper: `teaching_session_operational_date(timestamptz, timezone)`.

## Academic data

| Stage | Actor | Record |
|-------|-------|--------|
| Create | Teacher | `attendance`, `assessment_result`, `teacher_observation` |
| Review / confirm | Academic Operations | Workflow layer (explicit confirmation state — future task if required) |
| Consume | Reporting | Same canonical records — **no duplicate entry** |

Teacher-entered data is not automatically equivalent to final Manager-facing quality metrics until confirmation workflow exists.

## CRM semantics

| Measure type | Source |
|--------------|--------|
| Current lead state | `lead.status` |
| Historical activity | `lead_activity`, lifecycle history |
| Trial event | Trial workflow tables / events |
| Conversion event | `lead_conversion` and related records |
| Consultant ownership | Assignment / ownership history |
| Personal performance | Scoped to owning consultant user |

Do not reconstruct historical KPIs from current stage alone when event history exists.

## KPI namespaces

Stable identifiers in `src/lib/reporting/kpi-namespaces.ts`:

- **Finance:** cash collected, recognized revenue, receivables, costs, class economics, pending declarations
- **CRM:** intake, follow-ups, trials, conversions, personal declared/approved revenue, productivity
- **Academic:** attendance, scores, observations, fulfillment
- **Teaching ops:** scheduled, delivered, cancelled, rescheduled, workload, room usage, exceptions
- **Management:** executive overview, cross-domain exceptions (require `report.executive.read` for center-wide views)

## Authorization boundaries

| Surface | Permission |
|---------|------------|
| Complete executive reporting | `report.executive.read` |
| Operational class/student reports | Domain reads (`attendance.read`, etc.) |
| CRM attribution report | `lead.read` (+ conditional finance columns) |
| Finance overview | Finance read permissions |
| Personal consultant metrics | `consultant_revenue.declare` + ownership scope |
