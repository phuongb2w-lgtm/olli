-- CW2-T08: Consultant monthly sales read RPC (authoritative posted payment + attribution).

CREATE INDEX IF NOT EXISTS idx_payment_org_posted_paid_at
  ON public.payment (organization_id, paid_at)
  WHERE status = 'posted';

CREATE OR REPLACE FUNCTION public.get_consultant_monthly_sales(
  p_period_month date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_consultant uuid;
  v_org uuid;
  v_bounds public.reporting_period_bounds;
  v_month_start date;
  v_month_end date;
  v_prev_start date;
  v_prev_end date;
  v_prev_bounds public.reporting_period_bounds;
  v_sales bigint;
  v_payment_count integer;
  v_prev_sales bigint;
  v_prev_payment_count integer;
  v_delta bigint;
  v_pct numeric;
  v_comparison_kind text;
  v_today_local date;
  v_current_month_start date;
  v_timezone text;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_consultant := public.current_app_user_id();
  IF v_consultant IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('consultant_revenue.review')
    OR public.has_permission('payment.read')
    OR public.has_permission('report.executive.read')
    OR public.has_permission('consultant_workspace.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_month_start := date_trunc(
    'month',
    COALESCE(p_period_month, CURRENT_DATE)
  )::date;
  v_month_end := (v_month_start + interval '1 month - 1 day')::date;

  v_bounds := public.resolve_reporting_period(v_month_start, v_month_end);
  v_org := v_bounds.organization_id;
  v_timezone := v_bounds.timezone;

  SELECT
    COALESCE(sum(pca.attributed_amount), 0)::bigint,
    count(DISTINCT p.id)::integer
  INTO v_sales, v_payment_count
  FROM public.payment_consultant_attribution pca
  JOIN public.payment p
    ON p.id = pca.payment_id
   AND p.organization_id = pca.organization_id
  WHERE pca.organization_id = v_org
    AND pca.consultant_user_id = v_consultant
    AND p.status = 'posted'
    AND p.paid_at >= v_bounds.start_at_utc
    AND p.paid_at < v_bounds.end_at_exclusive;

  v_prev_start := (v_month_start - interval '1 month')::date;
  v_prev_end := (v_month_start - interval '1 day')::date;
  v_prev_bounds := public.resolve_reporting_period(v_prev_start, v_prev_end);

  SELECT
    COALESCE(sum(pca.attributed_amount), 0)::bigint,
    count(DISTINCT p.id)::integer
  INTO v_prev_sales, v_prev_payment_count
  FROM public.payment_consultant_attribution pca
  JOIN public.payment p
    ON p.id = pca.payment_id
   AND p.organization_id = pca.organization_id
  WHERE pca.organization_id = v_org
    AND pca.consultant_user_id = v_consultant
    AND p.status = 'posted'
    AND p.paid_at >= v_prev_bounds.start_at_utc
    AND p.paid_at < v_prev_bounds.end_at_exclusive;

  v_delta := v_sales - v_prev_sales;

  IF v_prev_sales = 0 AND v_sales > 0 THEN
    v_comparison_kind := 'new';
    v_pct := NULL;
  ELSIF v_prev_sales = 0 AND v_sales = 0 THEN
    v_comparison_kind := 'neutral';
    v_pct := NULL;
  ELSIF v_prev_sales > 0 THEN
    v_pct := round((v_delta::numeric / v_prev_sales::numeric) * 100, 1);
    IF v_delta > 0 THEN
      v_comparison_kind := 'increase';
    ELSIF v_delta < 0 THEN
      v_comparison_kind := 'decrease';
    ELSE
      v_comparison_kind := 'neutral';
    END IF;
  ELSE
    v_comparison_kind := 'neutral';
    v_pct := NULL;
  END IF;

  v_today_local := (now() AT TIME ZONE v_timezone)::date;
  v_current_month_start := date_trunc('month', v_today_local)::date;

  RETURN jsonb_build_object(
    'consultant_user_id', v_consultant,
    'organization_id', v_org,
    'currency_code', 'VND',
    'period', jsonb_build_object(
      'month_start', v_month_start,
      'month_end', v_month_end,
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_timezone,
      'start_at_utc', v_bounds.start_at_utc,
      'end_at_exclusive', v_bounds.end_at_exclusive
    ),
    'sales_amount', v_sales,
    'payment_count', v_payment_count,
    'previous_period', jsonb_build_object(
      'month_start', v_prev_start,
      'month_end', v_prev_end,
      'sales_amount', v_prev_sales,
      'payment_count', v_prev_payment_count
    ),
    'comparison', jsonb_build_object(
      'delta_amount', v_delta,
      'percent', v_pct,
      'kind', v_comparison_kind
    ),
    'navigation', jsonb_build_object(
      'is_current_month', v_month_start = v_current_month_start,
      'can_go_next', v_month_start < v_current_month_start,
      'can_go_previous', true,
      'current_month_start', v_current_month_start
    )
  );
END;
$$;

COMMENT ON FUNCTION public.get_consultant_monthly_sales(date) IS
  'CW2-T08: Consultant monthly sales = sum of posted M2 payment attribution (paid_at month). Not declarations; not revenue recognition.';

REVOKE ALL ON FUNCTION public.get_consultant_monthly_sales(date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_consultant_monthly_sales(date) TO authenticated;

-- Consultants have attribution SELECT but not payment.read; aggregate must not rely on payment RLS.
CREATE OR REPLACE FUNCTION public.sum_consultant_attributed_cash(
  p_consultant_user_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_bounds public.reporting_period_bounds;
  v_total bigint;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (
    public.has_permission('consultant_revenue.review')
    OR public.has_permission('payment.read')
    OR public.has_permission('report.executive.read')
    OR (
      public.has_permission('consultant_workspace.read')
      AND p_consultant_user_id = public.current_app_user_id()
    )
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  SELECT COALESCE(sum(pca.attributed_amount), 0) INTO v_total
  FROM public.payment_consultant_attribution pca
  JOIN public.payment p ON p.id = pca.payment_id AND p.organization_id = pca.organization_id
  WHERE pca.organization_id = v_org
    AND pca.consultant_user_id = p_consultant_user_id
    AND p.status = 'posted'
    AND p.paid_at >= v_bounds.start_at_utc
    AND p.paid_at < v_bounds.end_at_exclusive;

  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.sum_consultant_attributed_cash(uuid, date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sum_consultant_attributed_cash(uuid, date, date) TO authenticated;
