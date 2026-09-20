-- M5-T08: Avoid full list_executive_exceptions scan for overview worklist counts.

CREATE OR REPLACE FUNCTION public.get_executive_exception_worklist_summary(
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
  v_detected integer;
  v_open integer;
  v_ack integer;
BEGIN
  PERFORM public._assert_executive_exception_read_access();
  v_org := public.current_organization_id();

  SELECT (
    (SELECT count(*)::integer FROM public.list_finance_exceptions(p_start_date, p_end_date))
    + (SELECT count(*)::integer FROM public.list_crm_admissions_exceptions(p_start_date, p_end_date))
    + (SELECT count(*)::integer FROM public.list_academic_exceptions(p_start_date, p_end_date))
    + (SELECT count(*)::integer FROM public.list_teaching_ops_exceptions(p_start_date, p_end_date))
  ) INTO v_detected;

  SELECT count(*)::integer INTO v_open
  FROM executive_exception_follow_up
  WHERE organization_id = v_org AND status = 'open';

  SELECT count(*)::integer INTO v_ack
  FROM executive_exception_follow_up
  WHERE organization_id = v_org AND status = 'acknowledged';

  RETURN jsonb_build_object(
    'current_detected_count', v_detected,
    'open_follow_up_count', v_open,
    'acknowledged_follow_up_count', v_ack,
    'worklist_path', '/executive/exceptions'
  );
END;
$$;

COMMENT ON FUNCTION public.get_executive_exception_worklist_summary(date, date) IS
  'Executive overview worklist counts. Detected exceptions counted from canonical domain exception RPCs without follow-up merge.';

-- Authenticated role uses an 8s statement_timeout; executive composition exceeds that under real seed load.
CREATE OR REPLACE FUNCTION public.get_executive_overview(
  p_start_date date,
  p_end_date date,
  p_compare_previous boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
SET statement_timeout TO '120s'
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_compare jsonb;
BEGIN
  PERFORM public._assert_executive_overview_access();

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  IF p_compare_previous THEN
    v_compare := public.resolve_finance_comparison_period(p_start_date, p_end_date);
  END IF;

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'organization_id', v_bounds.organization_id,
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_bounds.timezone,
      'start_at_utc', v_bounds.start_at_utc,
      'end_at_exclusive', v_bounds.end_at_exclusive
    ),
    'comparison_period', CASE WHEN p_compare_previous THEN v_compare ELSE NULL END,
    'finance', public.get_finance_intelligence_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'admissions', public.get_crm_admissions_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'quality', public.get_academic_quality_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'operations', public.get_teaching_ops_intelligence_overview(
      p_start_date, p_end_date, p_compare_previous
    ),
    'attention', COALESCE((
      SELECT jsonb_agg(item ORDER BY item->>'domain', item->>'exception_code')
      FROM public.list_executive_attention_items(p_start_date, p_end_date, 5) AS item
    ), '[]'::jsonb),
    'exception_worklist', public.get_executive_exception_worklist_summary(p_start_date, p_end_date),
    'composition_rule',
      'Each domain object is the verbatim output of the canonical domain overview RPC for the same period inputs.'
  );
END;
$$;

COMMENT ON FUNCTION public.get_executive_overview(date, date, boolean) IS
  'Manager executive landing composition. Uses extended local statement_timeout for multi-domain canonical reads.';
