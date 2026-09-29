-- CW2-T07: Payment declaration drawer — submit validation, promotion context, finance refresh, capabilities.

DROP FUNCTION IF EXISTS public.save_consultant_payment_declaration_draft(
  uuid, date, numeric, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text
);

-- Align outstanding calculation with T05 portfolio finance snapshot (open + partially_paid).
CREATE OR REPLACE FUNCTION public._cw2_validate_declaration_finance_state(
  p_terms_id uuid,
  p_amount bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_outstanding bigint := 0;
  v_allocations jsonb := '[]'::jsonb;
  v_remaining bigint;
  v_charge record;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (
    public.has_permission('consultant_revenue.declare')
    OR public.has_permission('consultant_revenue.review')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_payment_amount' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.enrollment_financial_terms t
    WHERE t.id = p_terms_id
      AND t.organization_id = v_org
      AND t.status = 'active'
  ) THEN
    RAISE EXCEPTION 'invalid_financial_terms' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(sum(cb.outstanding_balance), 0) INTO v_outstanding
  FROM public.charge c
  JOIN public.charge_balance cb ON cb.charge_id = c.id
  WHERE c.organization_id = v_org
    AND c.enrollment_financial_terms_id = p_terms_id
    AND c.status IN ('open', 'partially_paid')
    AND cb.outstanding_balance > 0;

  IF v_outstanding <= 0 THEN
    RAISE EXCEPTION 'no_outstanding_obligation' USING ERRCODE = 'P0001';
  END IF;

  IF p_amount > v_outstanding THEN
    RAISE EXCEPTION 'payment_exceeds_outstanding' USING ERRCODE = 'P0001';
  END IF;

  v_remaining := p_amount;
  FOR v_charge IN
    SELECT c.id AS charge_id, cb.outstanding_balance AS outstanding
    FROM public.charge c
    JOIN public.charge_balance cb ON cb.charge_id = c.id
    WHERE c.organization_id = v_org
      AND c.enrollment_financial_terms_id = p_terms_id
      AND c.status IN ('open', 'partially_paid')
      AND cb.outstanding_balance > 0
    ORDER BY c.due_date, c.id
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_allocations := v_allocations || jsonb_build_array(jsonb_build_object(
      'charge_id', v_charge.charge_id,
      'amount', LEAST(v_remaining, v_charge.outstanding)
    ));
    v_remaining := v_remaining - LEAST(v_remaining, v_charge.outstanding);
  END LOOP;

  RETURN jsonb_build_object(
    'outstanding_before', v_outstanding,
    'allocations', v_allocations
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_cw2_payment_declaration_finance(
  p_enrollment_financial_terms_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_enrollment_id uuid;
  v_snap jsonb;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT t.enrollment_id INTO v_enrollment_id
  FROM public.enrollment_financial_terms t
  WHERE t.id = p_enrollment_financial_terms_id
    AND t.organization_id = v_org
    AND t.status = 'active';

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'invalid_financial_terms' USING ERRCODE = 'P0001';
  END IF;

  v_snap := public._cw2_portfolio_finance_snapshot(v_org, v_enrollment_id);
  IF v_snap IS NULL THEN
    RAISE EXCEPTION 'invalid_financial_terms' USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object(
    'enrollment_id', v_enrollment_id,
    'enrollment_financial_terms_id', p_enrollment_financial_terms_id,
    'tuition_total_net', COALESCE((v_snap->>'net_tuition')::numeric, 0),
    'tuition_paid', COALESCE((v_snap->>'allocated_amount')::bigint, 0),
    'tuition_outstanding', COALESCE((v_snap->>'outstanding_amount')::bigint, 0),
    'has_deposit_structure', COALESCE((v_snap->>'has_deposit_structure')::boolean, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_cw2_payment_declaration_finance(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_cw2_payment_declaration_finance(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_cw2_payment_declaration_drawer(
  p_declaration_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_row public.consultant_revenue_declaration;
  v_fin jsonb;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.consultant_revenue_declaration
  WHERE id = p_declaration_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'declaration_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_row.consultant_user_id IS DISTINCT FROM public.current_app_user_id()
     AND NOT public.has_permission('consultant_revenue.review') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_row.workflow_kind <> 'cw2_payment' THEN
    RAISE EXCEPTION 'declaration_not_cw2_workflow' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.enrollment_financial_terms_id IS NOT NULL THEN
    v_fin := public.refresh_cw2_payment_declaration_finance(v_row.enrollment_financial_terms_id);
  END IF;

  RETURN jsonb_build_object(
    'declaration', jsonb_build_object(
      'id', v_row.id,
      'status', v_row.status,
      'declared_amount', v_row.declared_amount,
      'description', v_row.description,
      'promotion_context', v_row.promotion_context,
      'declaration_date', v_row.declaration_date,
      'lead_id', v_row.lead_id,
      'student_id', v_row.student_id,
      'course_id', v_row.course_id,
      'class_id', v_row.class_id,
      'enrollment_id', v_row.enrollment_id,
      'enrollment_financial_terms_id', v_row.enrollment_financial_terms_id,
      'guardian_id', v_row.guardian_id,
      'review_notes', v_row.review_notes
    ),
    'finance', v_fin
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cw2_payment_declaration_drawer(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_consultant_payment_declaration_draft(
  p_declaration_id uuid DEFAULT NULL,
  p_declaration_date date DEFAULT NULL,
  p_declared_amount numeric DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_lead_id uuid DEFAULT NULL,
  p_student_id uuid DEFAULT NULL,
  p_course_id uuid DEFAULT NULL,
  p_class_id uuid DEFAULT NULL,
  p_enrollment_id uuid DEFAULT NULL,
  p_enrollment_financial_terms_id uuid DEFAULT NULL,
  p_guardian_id uuid DEFAULT NULL,
  p_total_obligation_amount numeric DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL,
  p_promotion_context text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_user uuid;
  v_code char(2);
  v_id uuid;
  v_pending uuid;
  v_terms uuid;
  v_amount numeric;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  v_org := public.current_organization_id();
  v_user := public.current_app_user_id();

  SELECT consultant_operational_code INTO v_code
  FROM public.app_user WHERE id = v_user AND organization_id = v_org;

  IF p_declaration_id IS NULL THEN
    IF p_enrollment_financial_terms_id IS NULL THEN
      RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
    END IF;
    IF p_declaration_date IS NULL OR p_declared_amount IS NULL OR p_declared_amount <= 0 THEN
      RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
    END IF;

    SELECT d.id INTO v_pending
    FROM public.consultant_revenue_declaration d
    WHERE d.organization_id = v_org
      AND d.consultant_user_id = v_user
      AND d.workflow_kind = 'cw2_payment'
      AND d.enrollment_financial_terms_id = p_enrollment_financial_terms_id
      AND d.status = 'pending'
    LIMIT 1;
    IF v_pending IS NOT NULL THEN
      RAISE EXCEPTION 'declaration_already_pending' USING ERRCODE = 'P0001';
    END IF;

    PERFORM public._cw2_validate_declaration_finance_state(
      p_enrollment_financial_terms_id,
      p_declared_amount::bigint
    );

    INSERT INTO public.consultant_revenue_declaration (
      organization_id, consultant_user_id, declaration_date, declared_amount, description,
      status, workflow_kind, lead_id, student_id, course_id, class_id,
      enrollment_id, enrollment_financial_terms_id, guardian_id,
      total_obligation_amount, idempotency_key, promotion_context,
      consultant_operational_code_snapshot
    ) VALUES (
      v_org, v_user, p_declaration_date, p_declared_amount, NULLIF(btrim(p_description), ''),
      'draft', 'cw2_payment', p_lead_id, p_student_id, p_course_id, p_class_id,
      p_enrollment_id, p_enrollment_financial_terms_id, p_guardian_id,
      p_total_obligation_amount, NULLIF(btrim(p_idempotency_key), ''),
      NULLIF(btrim(p_promotion_context), ''),
      v_code
    )
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;

  IF p_declared_amount IS NOT NULL AND p_declared_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.consultant_revenue_declaration d
  SET
    declaration_date = COALESCE(p_declaration_date, d.declaration_date),
    declared_amount = COALESCE(p_declared_amount, d.declared_amount),
    description = CASE WHEN p_description IS NOT NULL THEN NULLIF(btrim(p_description), '') ELSE d.description END,
    promotion_context = CASE WHEN p_promotion_context IS NOT NULL THEN NULLIF(btrim(p_promotion_context), '') ELSE d.promotion_context END,
    lead_id = COALESCE(p_lead_id, d.lead_id),
    student_id = COALESCE(p_student_id, d.student_id),
    course_id = COALESCE(p_course_id, d.course_id),
    class_id = COALESCE(p_class_id, d.class_id),
    enrollment_id = COALESCE(p_enrollment_id, d.enrollment_id),
    enrollment_financial_terms_id = COALESCE(p_enrollment_financial_terms_id, d.enrollment_financial_terms_id),
    guardian_id = COALESCE(p_guardian_id, d.guardian_id),
    total_obligation_amount = COALESCE(p_total_obligation_amount, d.total_obligation_amount),
    updated_at = now()
  WHERE d.id = p_declaration_id
    AND d.organization_id = v_org
    AND d.consultant_user_id = v_user
    AND d.workflow_kind = 'cw2_payment'
    AND d.status IN ('draft', 'returned')
  RETURNING d.id, d.enrollment_financial_terms_id, d.declared_amount
  INTO v_id, v_terms, v_amount;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'declaration_not_editable' USING ERRCODE = 'P0001';
  END IF;

  IF v_terms IS NOT NULL AND v_amount IS NOT NULL THEN
    PERFORM public._cw2_validate_declaration_finance_state(
      v_terms,
      v_amount::bigint
    );
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_consultant_payment_declaration(p_declaration_id uuid)
RETURNS public.consultant_revenue_declaration
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_row public.consultant_revenue_declaration;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  v_org := public.current_organization_id();

  SELECT * INTO v_row
  FROM public.consultant_revenue_declaration
  WHERE id = p_declaration_id AND organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'declaration_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF v_row.consultant_user_id IS DISTINCT FROM public.current_app_user_id() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_row.workflow_kind <> 'cw2_payment' OR v_row.status NOT IN ('draft', 'returned') THEN
    RAISE EXCEPTION 'declaration_not_submittable' USING ERRCODE = 'P0001';
  END IF;
  IF v_row.enrollment_financial_terms_id IS NULL OR v_row.guardian_id IS NULL THEN
    RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
  END IF;
  IF v_row.student_id IS NULL AND v_row.lead_id IS NULL THEN
    RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
  END IF;
  IF v_row.declared_amount IS NULL OR v_row.declared_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public._cw2_validate_declaration_finance_state(
    v_row.enrollment_financial_terms_id,
    v_row.declared_amount::bigint
  );

  UPDATE public.consultant_revenue_declaration
  SET status = 'pending', submitted_at = now(), updated_at = now()
  WHERE id = p_declaration_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.save_consultant_payment_declaration_draft(uuid, date, numeric, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_consultant_payment_declaration_draft(uuid, date, numeric, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text, text) TO authenticated;

-- Portfolio capability patch: see 20260930107100_cw2_t07_portfolio_declaration_capabilities.sql
