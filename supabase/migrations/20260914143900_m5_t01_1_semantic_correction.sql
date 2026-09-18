-- M5-T01.1: Reporting semantic boundary correction.
-- Materialized teaching_session != delivered service.
-- Approved consultant declaration != canonical booked revenue unless linked M2 evidence exists.

COMMENT ON TYPE consultant_revenue_declaration_status IS
  'Consultant declaration lifecycle. approved = accountant validated the declaration; it is NOT cash collected, booked payment, or recognized revenue unless approved_payment_id links canonical M2 payment evidence.';

COMMENT ON COLUMN consultant_revenue_declaration.approved_payment_id IS
  'Optional link to canonical payment after separate bookkeeping. Approval alone does not populate this column.';

COMMENT ON FUNCTION public.review_consultant_revenue_declaration(uuid, text, text) IS
  'Accountant validates declaration (approve/reject/return). Approve sets status=approved only; does not create payment or recognition events.';

COMMENT ON FUNCTION public.count_canonical_financial_revenue(date, date) IS
  'Posted revenue_recognition_event amounts in period. Recognized revenue only — not consultant declarations, not cash collected.';

-- =============================================================================
-- TEACHING SERVICE STATE (M5 reporting contract)
-- =============================================================================

COMMENT ON COLUMN teaching_session.status IS
  'Operational lifecycle: scheduled | in_progress | completed | cancelled. Only completed = delivered teaching service for M5 reporting. Existence of a row = materialized session.';

CREATE OR REPLACE FUNCTION public.teaching_session_is_delivered(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_status = 'completed';
$$;

CREATE OR REPLACE FUNCTION public.teaching_session_is_materialized_cancelled(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_status = 'cancelled';
$$;

CREATE OR REPLACE FUNCTION public.teaching_session_is_materialized_non_delivered(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_status IN ('scheduled', 'in_progress');
$$;

COMMENT ON FUNCTION public.teaching_session_is_delivered(text) IS
  'Delivered teaching service requires teaching_session.status = completed (M1 session execution). Materialized scheduled/in_progress rows are not delivered.';

-- Count helpers for M5 read models (distinct semantics).
CREATE OR REPLACE FUNCTION public.count_materialized_teaching_sessions(
  p_date_from date,
  p_date_to date,
  p_class_id uuid DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  SELECT o.timezone INTO v_timezone FROM organization o WHERE o.id = v_org_id;

  RETURN (
    SELECT count(*)::bigint
    FROM teaching_session ts
    WHERE ts.organization_id = v_org_id
      AND ts.status <> 'cancelled'
      AND public.teaching_session_operational_date(ts.scheduled_start_at, v_timezone)
          BETWEEN p_date_from AND p_date_to
      AND (p_class_id IS NULL OR ts.class_id = p_class_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.count_delivered_teaching_sessions(
  p_date_from date,
  p_date_to date,
  p_class_id uuid DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  SELECT o.timezone INTO v_timezone FROM organization o WHERE o.id = v_org_id;

  RETURN (
    SELECT count(*)::bigint
    FROM teaching_session ts
    WHERE ts.organization_id = v_org_id
      AND public.teaching_session_is_delivered(ts.status)
      AND public.teaching_session_operational_date(ts.scheduled_start_at, v_timezone)
          BETWEEN p_date_from AND p_date_to
      AND (p_class_id IS NULL OR ts.class_id = p_class_id)
  );
END;
$$;

COMMENT ON FUNCTION public.count_materialized_teaching_sessions(date, date, uuid) IS
  'Non-cancelled materialized teaching_session rows in operational date range. Includes scheduled and in_progress — not delivered.';

COMMENT ON FUNCTION public.count_delivered_teaching_sessions(date, date, uuid) IS
  'Materialized sessions with status=completed only. Aligns with M2 class_delivered_session_count and M4 workload delivered metrics.';

-- =============================================================================
-- CONSULTANT REVENUE SEMANTIC BOUNDARIES
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sum_approved_consultant_declarations(
  p_start_date date,
  p_end_date date
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('consultant_revenue.declare')
    OR public.has_permission('consultant_revenue.review')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  RETURN COALESCE((
    SELECT sum(crd.declared_amount)
    FROM consultant_revenue_declaration crd
    WHERE crd.organization_id = v_org_id
      AND crd.status = 'approved'
      AND crd.declaration_date BETWEEN p_start_date AND p_end_date
  ), 0);
END;
$$;

COMMENT ON FUNCTION public.sum_approved_consultant_declarations(date, date) IS
  'Sum of accountant-approved consultant revenue declarations. NOT cash collected, NOT recognized revenue, NOT ledger revenue unless approved_payment_id is set separately.';

CREATE OR REPLACE FUNCTION public.sum_canonical_cash_collected(
  p_start_date date,
  p_end_date date
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('payment.read')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  RETURN COALESCE((
    SELECT sum(p.amount)
    FROM payment p
    WHERE p.organization_id = v_bounds.organization_id
      AND p.status = 'posted'
      AND p.paid_at >= v_bounds.start_at_utc
      AND p.paid_at < v_bounds.end_at_exclusive
  ), 0);
END;
$$;

COMMENT ON FUNCTION public.sum_canonical_cash_collected(date, date) IS
  'Canonical M2 posted payments in period. Consultant declarations never count here unless recorded as payment.';

CREATE OR REPLACE FUNCTION public.declaration_has_canonical_payment(p_declaration_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM consultant_revenue_declaration crd
    JOIN payment p
      ON p.id = crd.approved_payment_id
     AND p.organization_id = crd.organization_id
    WHERE crd.id = p_declaration_id
      AND crd.organization_id = public.current_organization_id()
      AND crd.status = 'approved'
      AND p.status = 'posted'
  );
$$;

GRANT EXECUTE ON FUNCTION public.teaching_session_is_delivered(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.teaching_session_is_materialized_cancelled(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.teaching_session_is_materialized_non_delivered(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_materialized_teaching_sessions(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_delivered_teaching_sessions(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sum_approved_consultant_declarations(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sum_canonical_cash_collected(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.declaration_has_canonical_payment(uuid) TO authenticated;
