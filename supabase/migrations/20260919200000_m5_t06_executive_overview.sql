-- M5-T06: Executive cross-domain overview — composition over M5-T02..T05 domain RPCs.
-- No duplicated KPI formulas; each domain block is the canonical overview RPC output.

CREATE OR REPLACE FUNCTION public._assert_executive_overview_access()
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

  IF NOT public.has_permission('report.executive.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

COMMENT ON FUNCTION public._assert_executive_overview_access() IS
  'Center Manager cross-domain executive overview. Requires report.executive.read only.';

CREATE OR REPLACE FUNCTION public.list_executive_attention_items(
  p_start_date date,
  p_end_date date,
  p_limit_per_domain integer DEFAULT 5
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_limit integer := GREATEST(COALESCE(p_limit_per_domain, 5), 0);
BEGIN
  PERFORM public._assert_executive_overview_access();

  RETURN QUERY
  SELECT jsonb_build_object(
    'domain', 'finance',
    'domain_drill_down_path', '/finance'
  ) || fin
  FROM public.list_finance_exceptions(p_start_date, p_end_date) fin
  LIMIT v_limit;

  RETURN QUERY
  SELECT jsonb_build_object(
    'domain', 'admissions',
    'domain_drill_down_path', '/executive/admissions'
  ) || adm
  FROM public.list_crm_admissions_exceptions(p_start_date, p_end_date) adm
  LIMIT v_limit;

  RETURN QUERY
  SELECT jsonb_build_object(
    'domain', 'quality',
    'domain_drill_down_path', '/executive/quality'
  ) || qual
  FROM public.list_academic_exceptions(p_start_date, p_end_date) qual
  LIMIT v_limit;

  RETURN QUERY
  SELECT jsonb_build_object(
    'domain', 'operations',
    'domain_drill_down_path', '/executive/operations'
  ) || ops
  FROM public.list_teaching_ops_exceptions(p_start_date, p_end_date) ops
  LIMIT v_limit;
END;
$$;

COMMENT ON FUNCTION public.list_executive_attention_items(date, date, integer) IS
  'Deterministic cross-domain exception summary for executive overview. Each item tags its domain and links to the canonical drill-down surface.';

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
    'composition_rule',
      'Each domain object is the verbatim output of the canonical domain overview RPC for the same period inputs.'
  );
END;
$$;

COMMENT ON FUNCTION public.get_executive_overview(date, date, boolean) IS
  'Manager executive landing composition: finance, CRM/admissions, academic quality, and teaching operations over canonical M5 read models.';

GRANT EXECUTE ON FUNCTION public._assert_executive_overview_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_executive_attention_items(date, date, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_executive_overview(date, date, boolean) TO authenticated;
