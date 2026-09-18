-- M5-T02: Financial & class economics intelligence read layer.
-- Canonical M2/M5 semantics only — no second financial source of truth.

-- =============================================================================
-- PERMISSION GATE
-- =============================================================================

CREATE OR REPLACE FUNCTION public._assert_finance_intelligence_access()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('payment.read')
    OR public.has_permission('revenue.read')
    OR public.has_permission('charge.read')
    OR public.has_permission('expense.read')
    OR public.has_permission('class_economics.read')
    OR public.has_permission('consultant_revenue.review')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

COMMENT ON FUNCTION public._assert_finance_intelligence_access() IS
  'Center-wide finance intelligence gate. Consultant declare-only and teacher/academic roles are excluded.';

-- =============================================================================
-- PERIOD COMPARISON
-- =============================================================================

CREATE OR REPLACE FUNCTION public.resolve_finance_comparison_period(
  p_start_date date,
  p_end_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_span integer;
  v_prev_end date;
  v_prev_start date;
BEGIN
  PERFORM public._assert_finance_intelligence_access();

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RAISE EXCEPTION 'invalid_reporting_period' USING ERRCODE = 'P0001';
  END IF;

  v_span := (p_end_date - p_start_date) + 1;
  v_prev_end := p_start_date - 1;
  v_prev_start := v_prev_end - (v_span - 1);

  RETURN jsonb_build_object(
    'start_date', v_prev_start,
    'end_date', v_prev_end,
    'span_days', v_span
  );
END;
$$;

COMMENT ON FUNCTION public.resolve_finance_comparison_period(date, date) IS
  'Previous equivalent inclusive local-date window immediately before the selected period.';

-- =============================================================================
-- RECEIVABLES (POINT IN TIME — charge_balance)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sum_canonical_receivables()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  RETURN (
    SELECT jsonb_build_object(
      'total_outstanding', COALESCE(SUM(cb.outstanding_balance) FILTER (WHERE cb.outstanding_balance > 0), 0),
      'obligation_count', COALESCE(COUNT(*) FILTER (WHERE cb.outstanding_balance > 0), 0),
      'overdue_amount', COALESCE(SUM(cb.outstanding_balance) FILTER (
        WHERE cb.outstanding_balance > 0
          AND c.due_date IS NOT NULL
          AND c.due_date < CURRENT_DATE
      ), 0),
      'overdue_count', COALESCE(COUNT(*) FILTER (
        WHERE cb.outstanding_balance > 0
          AND c.due_date IS NOT NULL
          AND c.due_date < CURRENT_DATE
      ), 0)
    )
    FROM charge_balance cb
    JOIN charge c ON c.id = cb.charge_id
    WHERE cb.organization_id = v_org
  );
END;
$$;

COMMENT ON FUNCTION public.sum_canonical_receivables() IS
  'Outstanding tuition from canonical charge_balance. Not inferred from declarations or enrollment amounts.';

-- =============================================================================
-- PERIOD COSTS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_finance_period_costs(
  p_start_date date,
  p_end_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_period_from date;
  v_period_to date;
  v_operating bigint := 0;
  v_marketing bigint := 0;
  v_personnel bigint := 0;
  v_depreciation bigint := 0;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT (
    public.has_permission('expense.read')
    OR public.has_permission('class_economics.read')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();
  v_period_from := public.normalize_accounting_period(p_start_date);
  v_period_to := public.normalize_accounting_period(p_end_date);

  SELECT COALESCE(SUM(e.amount), 0) INTO v_operating
  FROM expense e
  JOIN cost_group cg ON cg.id = e.cost_group_id
  WHERE e.organization_id = v_org
    AND e.status = 'posted'
    AND cg.cost_domain_code = 'operating_overhead'
    AND e.incurred_date BETWEEN p_start_date AND p_end_date;

  SELECT COALESCE(SUM(e.amount), 0) INTO v_marketing
  FROM expense e
  JOIN cost_group cg ON cg.id = e.cost_group_id
  WHERE e.organization_id = v_org
    AND e.status = 'posted'
    AND cg.cost_domain_code = 'marketing_sales'
    AND e.incurred_date BETWEEN p_start_date AND p_end_date;

  SELECT COALESCE(SUM(p.amount), 0) INTO v_personnel
  FROM personnel_cost_entry p
  WHERE p.organization_id = v_org
    AND p.status = 'posted'
    AND p.accounting_period BETWEEN v_period_from AND v_period_to;

  SELECT COALESCE(SUM(d.amount), 0) INTO v_depreciation
  FROM depreciation_entry d
  WHERE d.organization_id = v_org
    AND d.status = 'posted'
    AND d.period_month BETWEEN v_period_from AND v_period_to;

  RETURN jsonb_build_object(
    'operating_overhead', v_operating,
    'marketing_sales', v_marketing,
    'personnel', v_personnel,
    'depreciation', v_depreciation,
    'total_operating', v_operating + v_marketing + v_personnel + v_depreciation
  );
END;
$$;

COMMENT ON FUNCTION public.get_finance_period_costs(date, date) IS
  'Operating cost categories for inclusive local period. Depreciation reflects Cost A monthly burden only.';

-- =============================================================================
-- SERVICE OBLIGATION AGGREGATE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sum_organization_service_obligation()
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_total numeric := 0;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  SELECT COALESCE(SUM(
    GREATEST(
      COALESCE(
        public.enrollment_recognition_entitlement(t.id),
        t.net_tuition_amount,
        0
      ) - public.enrollment_recognized_revenue(e.id),
      0
    )
  ), 0) INTO v_total
  FROM enrollment e
  LEFT JOIN enrollment_financial_terms t
    ON t.enrollment_id = e.id
   AND t.organization_id = e.organization_id
   AND t.status = 'active'
  WHERE e.organization_id = v_org
    AND e.status IN ('active', 'completed');

  RETURN v_total;
END;
$$;

-- =============================================================================
-- CONSULTANT DECLARATION SUMMARY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_consultant_declaration_summary(
  p_start_date date,
  p_end_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('consultant_revenue.review')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  RETURN (
    SELECT jsonb_build_object(
      'pending_amount', COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'pending'), 0),
      'pending_count', COALESCE(COUNT(*) FILTER (WHERE crd.status = 'pending'), 0),
      'returned_amount', COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'returned'), 0),
      'returned_count', COALESCE(COUNT(*) FILTER (WHERE crd.status = 'returned'), 0),
      'approved_amount', COALESCE(SUM(crd.declared_amount) FILTER (WHERE crd.status = 'approved'), 0),
      'approved_count', COALESCE(COUNT(*) FILTER (WHERE crd.status = 'approved'), 0),
      'approved_linked_count', COALESCE(COUNT(*) FILTER (
        WHERE crd.status = 'approved'
          AND public.declaration_has_canonical_payment(crd.id)
      ), 0),
      'approved_unlinked_count', COALESCE(COUNT(*) FILTER (
        WHERE crd.status = 'approved'
          AND NOT public.declaration_has_canonical_payment(crd.id)
      ), 0)
    )
    FROM consultant_revenue_declaration crd
    WHERE crd.organization_id = v_org
      AND crd.declaration_date BETWEEN p_start_date AND p_end_date
  );
END;
$$;

COMMENT ON FUNCTION public.get_consultant_declaration_summary(date, date) IS
  'Consultant declaration lifecycle in period. Approved amounts are NOT cash or recognized revenue.';

-- =============================================================================
-- OVERVIEW KPI COMPOSITE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_finance_intelligence_overview(
  p_start_date date,
  p_end_date date,
  p_compare_previous boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_prev jsonb;
  v_prev_start date;
  v_prev_end date;
  v_org uuid;
  v_cash numeric;
  v_cash_prev numeric;
  v_cash_count bigint;
  v_cash_count_prev bigint;
  v_cash_allocated bigint;
  v_revenue numeric;
  v_revenue_prev numeric;
  v_revenue_count bigint;
  v_revenue_count_prev bigint;
  v_receivables jsonb;
  v_costs jsonb;
  v_costs_prev jsonb;
  v_service_obligation numeric;
  v_unallocated bigint := 0;
  v_reconciliation jsonb;
  v_declarations jsonb;
  v_contribution numeric;
  v_contribution_prev numeric;
  v_period_month date;
BEGIN
  PERFORM public._assert_finance_intelligence_access();

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  v_period_month := public.normalize_accounting_period(p_end_date);

  IF p_compare_previous THEN
    v_prev := public.resolve_finance_comparison_period(p_start_date, p_end_date);
    v_prev_start := (v_prev->>'start_date')::date;
    v_prev_end := (v_prev->>'end_date')::date;
  END IF;

  v_cash := public.sum_canonical_cash_collected(p_start_date, p_end_date);
  IF p_compare_previous THEN
    v_cash_prev := public.sum_canonical_cash_collected(v_prev_start, v_prev_end);
  END IF;

  SELECT count(*)::bigint INTO v_cash_count
  FROM payment p
  WHERE p.organization_id = v_org
    AND p.status = 'posted'
    AND p.paid_at >= v_bounds.start_at_utc
    AND p.paid_at < v_bounds.end_at_exclusive;

  IF p_compare_previous THEN
    SELECT count(*)::bigint INTO v_cash_count_prev
    FROM payment p
    WHERE p.organization_id = v_org
      AND p.status = 'posted'
      AND p.paid_at >= (public.resolve_reporting_period(v_prev_start, v_prev_end)).start_at_utc
      AND p.paid_at < (public.resolve_reporting_period(v_prev_start, v_prev_end)).end_at_exclusive;
  END IF;

  SELECT COALESCE(SUM(pa.amount), 0) INTO v_cash_allocated
  FROM payment_allocation pa
  JOIN payment p ON p.id = pa.payment_id
  WHERE p.organization_id = v_org
    AND p.status = 'posted'
    AND pa.status = 'posted'
    AND p.paid_at >= v_bounds.start_at_utc
    AND p.paid_at < v_bounds.end_at_exclusive;

  v_revenue := public.count_canonical_financial_revenue(p_start_date, p_end_date);
  IF p_compare_previous THEN
    v_revenue_prev := public.count_canonical_financial_revenue(v_prev_start, v_prev_end);
  END IF;

  SELECT count(*)::bigint INTO v_revenue_count
  FROM revenue_recognition_event rre
  WHERE rre.organization_id = v_org
    AND rre.status = 'posted'
    AND rre.recognized_at >= v_bounds.start_at_utc
    AND rre.recognized_at < v_bounds.end_at_exclusive;

  IF p_compare_previous THEN
    SELECT count(*)::bigint INTO v_revenue_count_prev
    FROM revenue_recognition_event rre
    WHERE rre.organization_id = v_org
      AND rre.status = 'posted'
      AND rre.recognized_at >= (public.resolve_reporting_period(v_prev_start, v_prev_end)).start_at_utc
      AND rre.recognized_at < (public.resolve_reporting_period(v_prev_start, v_prev_end)).end_at_exclusive;
  END IF;

  v_receivables := public.sum_canonical_receivables();
  v_costs := public.get_finance_period_costs(p_start_date, p_end_date);
  IF p_compare_previous THEN
    v_costs_prev := public.get_finance_period_costs(v_prev_start, v_prev_end);
  END IF;

  v_service_obligation := public.sum_organization_service_obligation();

  IF public.has_permission('class_economics.read') THEN
    v_reconciliation := public.get_organization_cost_reconciliation(v_period_month);
    v_unallocated := COALESCE((v_reconciliation->>'unallocated_total')::bigint, 0);
  END IF;

  IF public.has_permission('consultant_revenue.review')
     OR public.has_permission('report.executive.read') THEN
    v_declarations := public.get_consultant_declaration_summary(p_start_date, p_end_date);
  ELSE
    v_declarations := NULL;
  END IF;

  v_contribution := v_revenue - COALESCE((v_costs->>'total_operating')::numeric, 0);
  IF p_compare_previous THEN
    v_contribution_prev := v_revenue_prev - COALESCE((v_costs_prev->>'total_operating')::numeric, 0);
  END IF;

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'organization_id', v_bounds.organization_id,
      'timezone', v_bounds.timezone,
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'start_at_utc', v_bounds.start_at_utc,
      'end_at_exclusive', v_bounds.end_at_exclusive
    ),
    'comparison_period', CASE
      WHEN p_compare_previous THEN jsonb_build_object(
        'start_date', v_prev_start,
        'end_date', v_prev_end
      )
      ELSE NULL
    END,
    'cash_collected', jsonb_build_object(
      'current', v_cash,
      'previous', v_cash_prev,
      'change', CASE WHEN p_compare_previous THEN v_cash - v_cash_prev ELSE NULL END,
      'payment_count', v_cash_count,
      'payment_count_previous', v_cash_count_prev,
      'cash_allocated', v_cash_allocated
    ),
    'recognized_revenue', jsonb_build_object(
      'current', v_revenue,
      'previous', v_revenue_prev,
      'change', CASE WHEN p_compare_previous THEN v_revenue - v_revenue_prev ELSE NULL END,
      'event_count', v_revenue_count,
      'event_count_previous', v_revenue_count_prev
    ),
    'receivables', v_receivables,
    'service_obligation', v_service_obligation,
    'costs', jsonb_build_object(
      'current', v_costs,
      'previous', v_costs_prev,
      'change', CASE
        WHEN p_compare_previous THEN
          jsonb_build_object(
            'operating_overhead',
              COALESCE((v_costs->>'operating_overhead')::numeric, 0)
              - COALESCE((v_costs_prev->>'operating_overhead')::numeric, 0),
            'marketing_sales',
              COALESCE((v_costs->>'marketing_sales')::numeric, 0)
              - COALESCE((v_costs_prev->>'marketing_sales')::numeric, 0),
            'personnel',
              COALESCE((v_costs->>'personnel')::numeric, 0)
              - COALESCE((v_costs_prev->>'personnel')::numeric, 0),
            'depreciation',
              COALESCE((v_costs->>'depreciation')::numeric, 0)
              - COALESCE((v_costs_prev->>'depreciation')::numeric, 0),
            'total_operating',
              COALESCE((v_costs->>'total_operating')::numeric, 0)
              - COALESCE((v_costs_prev->>'total_operating')::numeric, 0)
          )
        ELSE NULL
      END,
      'unallocated_shared', v_unallocated
    ),
    'operating_result', jsonb_build_object(
      'current', v_contribution,
      'previous', v_contribution_prev,
      'change', CASE WHEN p_compare_previous THEN v_contribution - v_contribution_prev ELSE NULL END
    ),
    'consultant_declarations', v_declarations
  );
END;
$$;

COMMENT ON FUNCTION public.get_finance_intelligence_overview(date, date, boolean) IS
  'Canonical finance intelligence summary for Manager/Accountant. Cash, revenue, receivables remain separate.';

-- =============================================================================
-- DRILL-DOWN READ MODELS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_finance_cash_payments(
  p_start_date date,
  p_end_date date,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('payment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  RETURN QUERY
  SELECT jsonb_build_object(
    'payment_id', p.id,
    'paid_at', p.paid_at,
    'amount', p.amount,
    'method_code', p.method_code,
    'payer_name', p.payer_name_snapshot,
    'student_id', p.student_id,
    'allocated_amount', public.payment_allocated_amount(p.id),
    'status', p.status
  )
  FROM payment p
  WHERE p.organization_id = v_bounds.organization_id
    AND p.status = 'posted'
    AND p.paid_at >= v_bounds.start_at_utc
    AND p.paid_at < v_bounds.end_at_exclusive
  ORDER BY p.paid_at DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_finance_recognition_events(
  p_start_date date,
  p_end_date date,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('revenue.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  RETURN QUERY
  SELECT jsonb_build_object(
    'event_id', rre.id,
    'recognized_at', rre.recognized_at,
    'amount', rre.amount,
    'enrollment_id', rre.enrollment_id,
    'class_id', e.class_id,
    'class_name', cl.name,
    'teaching_session_id', rre.teaching_session_id,
    'status', rre.status
  )
  FROM revenue_recognition_event rre
  JOIN enrollment e ON e.id = rre.enrollment_id
  LEFT JOIN class cl ON cl.id = e.class_id
  WHERE rre.organization_id = v_bounds.organization_id
    AND rre.status = 'posted'
    AND rre.recognized_at >= v_bounds.start_at_utc
    AND rre.recognized_at < v_bounds.end_at_exclusive
  ORDER BY rre.recognized_at DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_finance_receivables(
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  RETURN QUERY
  SELECT jsonb_build_object(
    'charge_id', c.id,
    'enrollment_id', c.enrollment_id,
    'student_id', e.student_id,
    'student_name', s.given_name || ' ' || s.family_name,
    'due_date', c.due_date,
    'outstanding_balance', cb.outstanding_balance,
    'collection_status', public._charge_collection_status(c.id)
  )
  FROM charge_balance cb
  JOIN charge c ON c.id = cb.charge_id
  LEFT JOIN enrollment e ON e.id = c.enrollment_id
  LEFT JOIN student s ON s.id = e.student_id
  WHERE cb.organization_id = v_org
    AND cb.outstanding_balance > 0
  ORDER BY c.due_date NULLS LAST, cb.outstanding_balance DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_finance_consultant_declarations(
  p_start_date date,
  p_end_date date,
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('consultant_revenue.review')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  RETURN QUERY
  SELECT jsonb_build_object(
    'declaration_id', crd.id,
    'declaration_date', crd.declaration_date,
    'declared_amount', crd.declared_amount,
    'status', crd.status,
    'consultant_user_id', crd.consultant_user_id,
    'consultant_name', au.display_name,
    'approved_payment_id', crd.approved_payment_id,
    'has_canonical_payment', public.declaration_has_canonical_payment(crd.id),
    'description', crd.description
  )
  FROM consultant_revenue_declaration crd
  JOIN app_user au ON au.id = crd.consultant_user_id
  WHERE crd.organization_id = v_org
    AND crd.declaration_date BETWEEN p_start_date AND p_end_date
    AND (p_status IS NULL OR crd.status::text = p_status)
  ORDER BY crd.declaration_date DESC, crd.declared_at DESC
  LIMIT GREATEST(p_limit, 1)
  OFFSET GREATEST(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_finance_class_economics_summary(
  p_start_date date,
  p_end_date date
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_class record;
  v_economics jsonb;
  v_delivered bigint;
  v_enrolled bigint;
  v_period_month date;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('class_economics.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();
  v_period_month := public.normalize_accounting_period(p_end_date);

  FOR v_class IN
    SELECT c.id, c.name, c.status
    FROM class c
    WHERE c.organization_id = v_org
      AND c.status IN ('planned', 'trial', 'active', 'closed')
    ORDER BY c.name
  LOOP
    v_economics := public.get_class_economics(v_class.id, p_start_date, p_end_date);
    v_delivered := public.class_delivered_session_count(v_class.id, v_period_month);
    v_enrolled := public.class_active_enrollment_count(v_class.id, v_period_month);

    RETURN NEXT jsonb_build_object(
      'class_id', v_class.id,
      'class_name', v_class.name,
      'class_status', v_class.status,
      'recognized_revenue', v_economics->'recognized_revenue',
      'total_cost', v_economics->'total_cost',
      'contribution', v_economics->'contribution',
      'margin_percentage', v_economics->'margin_percentage',
      'delivered_session_count', v_delivered,
      'enrolled_student_count', v_enrolled
    );
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.list_finance_class_economics_summary(date, date) IS
  'Class-level economics from canonical M2 get_class_economics. Delivered sessions use status=completed.';

-- =============================================================================
-- FINANCIAL MANAGEMENT EXCEPTIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_finance_exceptions(
  p_start_date date,
  p_end_date date
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_class record;
  v_economics jsonb;
  v_contribution numeric;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  v_org := public.current_organization_id();

  IF public.has_permission('charge.read') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'exception_code', 'receivable_overdue',
      'reason', 'Outstanding tuition past due date',
      'metric_value', cb.outstanding_balance,
      'entity_type', 'charge',
      'entity_id', c.id,
      'drill_down_path', '/finance/receivables',
      'context', jsonb_build_object(
        'due_date', c.due_date,
        'enrollment_id', c.enrollment_id
      )
    )
    FROM charge_balance cb
    JOIN charge c ON c.id = cb.charge_id
    WHERE cb.organization_id = v_org
      AND cb.outstanding_balance > 0
      AND c.due_date IS NOT NULL
      AND c.due_date < CURRENT_DATE;
  END IF;

  IF public.has_permission('class_economics.read') THEN
    FOR v_class IN
      SELECT c.id, c.name
      FROM class c
      WHERE c.organization_id = v_org
        AND c.status IN ('active', 'closed')
    LOOP
      v_economics := public.get_class_economics(v_class.id, p_start_date, p_end_date);
      v_contribution := COALESCE((v_economics->>'contribution')::numeric, 0);
      IF v_contribution < 0 THEN
        RETURN NEXT jsonb_build_object(
          'exception_code', 'class_negative_contribution',
          'reason', 'Class contribution is negative for the selected period',
          'metric_value', v_contribution,
          'entity_type', 'class',
          'entity_id', v_class.id,
          'drill_down_path', '/finance/class-economics/' || v_class.id::text,
          'context', jsonb_build_object('class_name', v_class.name)
        );
      END IF;
    END LOOP;
  END IF;

  IF public.has_permission('consultant_revenue.review')
     OR public.has_permission('report.executive.read') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'exception_code', 'consultant_declaration_pending_review',
      'reason', 'Consultant revenue declaration awaiting accounting review',
      'metric_value', crd.declared_amount,
      'entity_type', 'consultant_revenue_declaration',
      'entity_id', crd.id,
      'drill_down_path', '/finance/consultant-revenue',
      'context', jsonb_build_object('status', crd.status, 'declaration_date', crd.declaration_date)
    )
    FROM consultant_revenue_declaration crd
    WHERE crd.organization_id = v_org
      AND crd.status IN ('pending', 'returned')
      AND crd.declaration_date BETWEEN p_start_date AND p_end_date;

    RETURN QUERY
    SELECT jsonb_build_object(
      'exception_code', 'approved_declaration_without_payment',
      'reason', 'Approved consultant declaration has no linked canonical payment',
      'metric_value', crd.declared_amount,
      'entity_type', 'consultant_revenue_declaration',
      'entity_id', crd.id,
      'drill_down_path', '/finance/consultant-revenue',
      'context', jsonb_build_object('declaration_date', crd.declaration_date)
    )
    FROM consultant_revenue_declaration crd
    WHERE crd.organization_id = v_org
      AND crd.status = 'approved'
      AND NOT public.declaration_has_canonical_payment(crd.id)
      AND crd.declaration_date BETWEEN p_start_date AND p_end_date;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.list_finance_exceptions(date, date) IS
  'Deterministic finance exceptions with drill-down paths. No opaque scoring.';

CREATE OR REPLACE FUNCTION public.get_finance_cash_by_method(
  p_start_date date,
  p_end_date date
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('payment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  RETURN QUERY
  SELECT jsonb_build_object(
    'method_code', p.method_code,
    'amount', COALESCE(SUM(p.amount), 0),
    'payment_count', COUNT(*)::bigint
  )
  FROM payment p
  WHERE p.organization_id = v_bounds.organization_id
    AND p.status = 'posted'
    AND p.paid_at >= v_bounds.start_at_utc
    AND p.paid_at < v_bounds.end_at_exclusive
  GROUP BY p.method_code
  ORDER BY SUM(p.amount) DESC;
END;
$$;

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT EXECUTE ON FUNCTION public._assert_finance_intelligence_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_finance_comparison_period(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sum_canonical_receivables() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_finance_period_costs(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sum_organization_service_obligation() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_consultant_declaration_summary(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_finance_intelligence_overview(date, date, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_finance_cash_payments(date, date, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_finance_recognition_events(date, date, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_finance_receivables(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_finance_consultant_declarations(date, date, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_finance_class_economics_summary(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_finance_exceptions(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_finance_cash_by_method(date, date) TO authenticated;
