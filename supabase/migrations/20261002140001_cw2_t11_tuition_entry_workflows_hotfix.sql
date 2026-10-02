-- CW2-T11 hotfix (migration 85): lead-first declaration workflows.

CREATE OR REPLACE FUNCTION public.get_cw2_tuition_declaration_context_for_portfolio(
  p_portfolio_entry_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry public.consultant_portfolio_entry;
  v_org uuid;
  v_enrollment_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_entry := public._cw2_assert_portfolio_entry_access(p_portfolio_entry_id);
  v_org := v_entry.organization_id;
  v_enrollment_id := NULL;

  IF v_entry.student_id IS NOT NULL THEN
    SELECT pe.enrollment_id INTO v_enrollment_id
    FROM public._cw2_portfolio_pick_enrollment(v_org, v_entry.student_id) pe
    LIMIT 1;
  END IF;

  IF v_enrollment_id IS NOT NULL THEN
    RETURN public.get_cw2_tuition_declaration_context(v_enrollment_id);
  END IF;

  RETURN jsonb_build_object(
    'portfolio_entry_id', v_entry.id,
    'lead_id', v_entry.lead_id,
    'student_id', v_entry.student_id,
    'enrollment_id', NULL,
    'enrollment_financial_terms_id', NULL,
    'tuition_established', false,
    'billing_mode', NULL,
    'finance', jsonb_build_object(
      'tuition_total_net', 0,
      'tuition_paid', 0,
      'tuition_outstanding', 0,
      'tuition_pending_declaration', 0,
      'tuition_established', false
    ),
    'billing', NULL,
    'can_change_billing_mode', true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cw2_tuition_declaration_context_for_portfolio(uuid) TO authenticated;

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
  p_promotion_context text DEFAULT NULL,
  p_tuition_billing_mode text DEFAULT NULL,
  p_proposed_net_tuition_amount numeric DEFAULT NULL,
  p_periodic_period_unit text DEFAULT NULL,
  p_periodic_period_quantity integer DEFAULT NULL,
  p_periodic_amount_per_period numeric DEFAULT NULL,
  p_periodic_academic_year_id uuid DEFAULT NULL,
  p_payment_method_code text DEFAULT NULL,
  p_declaration_kind text DEFAULT 'payment_only'
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
  v_terms uuid;
  v_amount numeric;
  v_kind text := COALESCE(NULLIF(btrim(p_declaration_kind), ''), 'payment_only');
  v_depends_on uuid;
  v_initial_pending public.consultant_revenue_declaration%ROWTYPE;
  v_guardian uuid := p_guardian_id;
  v_lead_intake boolean := p_enrollment_id IS NULL AND p_lead_id IS NOT NULL;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  v_org := public.current_organization_id();
  v_user := public.current_app_user_id();

  SELECT consultant_operational_code INTO v_code
  FROM public.app_user WHERE id = v_user AND organization_id = v_org;

  IF p_enrollment_id IS NOT NULL THEN
    v_terms := COALESCE(
      p_enrollment_financial_terms_id,
      public._cw2_ensure_placeholder_financial_terms(v_org, p_enrollment_id)
    );
  ELSE
    v_terms := p_enrollment_financial_terms_id;
  END IF;

  IF p_declaration_id IS NULL THEN
    IF v_lead_intake THEN
      IF v_kind <> 'initial_tuition_setup' THEN
        RAISE EXCEPTION 'initial_tuition_setup_required' USING ERRCODE = 'P0001';
      END IF;
      v_guardian := COALESCE(v_guardian, public._cw2_resolve_lead_declaration_guardian(v_org, p_lead_id));
      IF v_guardian IS NULL THEN
        RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
      END IF;
    ELSIF v_terms IS NULL OR p_enrollment_id IS NULL THEN
      RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
    END IF;
    IF p_declaration_date IS NULL OR p_declared_amount IS NULL OR p_declared_amount <= 0 THEN
      RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
    END IF;

    IF v_kind = 'initial_tuition_setup' THEN
      IF p_tuition_billing_mode IS NULL THEN
        RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
      END IF;
      IF p_tuition_billing_mode = 'course_lump_sum'
         AND (p_proposed_net_tuition_amount IS NULL OR p_proposed_net_tuition_amount <= 0) THEN
        RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
      END IF;
      IF p_tuition_billing_mode = 'periodic' THEN
        IF p_periodic_period_unit IS NULL
           OR COALESCE(p_periodic_period_quantity, 0) <= 0
           OR COALESCE(p_periodic_amount_per_period, 0) <= 0 THEN
          RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
        END IF;
        IF p_periodic_period_unit = 'school_year' AND p_periodic_academic_year_id IS NULL THEN
          RAISE EXCEPTION 'academic_year_required' USING ERRCODE = 'P0001';
        END IF;
      END IF;
      IF NOT v_lead_intake AND public._cw2_enrollment_tuition_established(v_org, p_enrollment_id) THEN
        RAISE EXCEPTION 'tuition_plan_already_established' USING ERRCODE = 'P0001';
      END IF;
      IF v_lead_intake THEN
        IF EXISTS (
          SELECT 1 FROM public.consultant_revenue_declaration d
          WHERE d.organization_id = v_org
            AND d.lead_id = p_lead_id
            AND d.enrollment_id IS NULL
            AND d.workflow_kind = 'cw2_payment'
            AND d.status IN ('pending', 'draft', 'returned')
            AND d.declaration_kind = 'initial_tuition_setup'
        ) THEN
          RAISE EXCEPTION 'initial_tuition_plan_already_pending' USING ERRCODE = 'P0001';
        END IF;
      ELSE
        IF EXISTS (
          SELECT 1 FROM public.consultant_revenue_declaration d
          WHERE d.organization_id = v_org
            AND d.enrollment_id = p_enrollment_id
            AND d.workflow_kind = 'cw2_payment'
            AND d.status = 'pending'
            AND d.declaration_kind = 'initial_tuition_setup'
        ) THEN
          RAISE EXCEPTION 'initial_tuition_plan_already_pending' USING ERRCODE = 'P0001';
        END IF;
        IF EXISTS (
          SELECT 1 FROM public.consultant_revenue_declaration d
          WHERE d.organization_id = v_org
            AND d.enrollment_id = p_enrollment_id
            AND d.workflow_kind = 'cw2_payment'
            AND d.status IN ('draft', 'returned')
            AND d.declaration_kind = 'initial_tuition_setup'
        ) THEN
          RAISE EXCEPTION 'initial_tuition_plan_already_pending' USING ERRCODE = 'P0001';
        END IF;
      END IF;
    ELSE
      IF NOT public._cw2_enrollment_tuition_established(v_org, p_enrollment_id) THEN
        SELECT * INTO v_initial_pending
        FROM public.consultant_revenue_declaration d
        WHERE d.organization_id = v_org
          AND d.enrollment_id = p_enrollment_id
          AND d.workflow_kind = 'cw2_payment'
          AND d.status = 'pending'
          AND d.declaration_kind = 'initial_tuition_setup'
        ORDER BY d.submitted_at NULLS LAST, d.created_at
        LIMIT 1;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'initial_tuition_setup_required' USING ERRCODE = 'P0001';
        END IF;
        v_depends_on := v_initial_pending.id;
        IF p_proposed_net_tuition_amount IS NOT NULL
           AND p_proposed_net_tuition_amount::bigint IS DISTINCT FROM v_initial_pending.proposed_net_tuition_amount THEN
          RAISE EXCEPTION 'conflicting_tuition_proposal' USING ERRCODE = 'P0001';
        END IF;
      ELSE
        PERFORM public._cw2_validate_declaration_finance_state(v_terms, p_declared_amount::bigint);
      END IF;
    END IF;

    INSERT INTO public.consultant_revenue_declaration (
      organization_id, consultant_user_id, declaration_date, declared_amount, description,
      status, workflow_kind, lead_id, student_id, course_id, class_id,
      enrollment_id, enrollment_financial_terms_id, guardian_id,
      total_obligation_amount, idempotency_key, promotion_context,
      tuition_billing_mode, proposed_net_tuition_amount,
      periodic_period_unit, periodic_period_quantity, periodic_amount_per_period,
      periodic_academic_year_id, payment_method_code, declaration_kind,
      consultant_operational_code_snapshot, depends_on_declaration_id
    ) VALUES (
      v_org, v_user, p_declaration_date, p_declared_amount, NULLIF(btrim(p_description), ''),
      'draft', 'cw2_payment', p_lead_id, p_student_id, p_course_id, p_class_id,
      p_enrollment_id, v_terms, v_guardian,
      COALESCE(p_total_obligation_amount, p_proposed_net_tuition_amount, v_initial_pending.proposed_net_tuition_amount),
      NULLIF(btrim(p_idempotency_key), ''),
      NULLIF(btrim(p_promotion_context), ''),
      NULLIF(btrim(p_tuition_billing_mode), ''),
      COALESCE(p_proposed_net_tuition_amount::bigint, v_initial_pending.proposed_net_tuition_amount),
      NULLIF(btrim(p_periodic_period_unit), ''),
      p_periodic_period_quantity,
      p_periodic_amount_per_period::bigint,
      p_periodic_academic_year_id,
      NULLIF(btrim(p_payment_method_code), ''),
      v_kind,
      v_code,
      v_depends_on
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
    enrollment_financial_terms_id = COALESCE(v_terms, d.enrollment_financial_terms_id),
    guardian_id = COALESCE(p_guardian_id, d.guardian_id),
    total_obligation_amount = COALESCE(p_total_obligation_amount, d.total_obligation_amount),
    tuition_billing_mode = COALESCE(NULLIF(btrim(p_tuition_billing_mode), ''), d.tuition_billing_mode),
    proposed_net_tuition_amount = COALESCE(p_proposed_net_tuition_amount::bigint, d.proposed_net_tuition_amount),
    periodic_period_unit = COALESCE(NULLIF(btrim(p_periodic_period_unit), ''), d.periodic_period_unit),
    periodic_period_quantity = COALESCE(p_periodic_period_quantity, d.periodic_period_quantity),
    periodic_amount_per_period = COALESCE(p_periodic_amount_per_period::bigint, d.periodic_amount_per_period),
    periodic_academic_year_id = COALESCE(p_periodic_academic_year_id, d.periodic_academic_year_id),
    payment_method_code = COALESCE(NULLIF(btrim(p_payment_method_code), ''), d.payment_method_code),
    declaration_kind = COALESCE(NULLIF(btrim(p_declaration_kind), ''), d.declaration_kind),
    updated_at = now()
  WHERE d.id = p_declaration_id
    AND d.organization_id = v_org
    AND d.consultant_user_id = v_user
    AND d.workflow_kind = 'cw2_payment'
    AND d.status IN ('draft', 'returned')
  RETURNING d.id, d.enrollment_financial_terms_id, d.declared_amount, d.declaration_kind
  INTO v_id, v_terms, v_amount, v_kind;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'declaration_not_editable' USING ERRCODE = 'P0001';
  END IF;

  IF v_kind <> 'initial_tuition_setup' AND v_terms IS NOT NULL AND v_amount IS NOT NULL THEN
    PERFORM public._cw2_validate_declaration_finance_state(v_terms, v_amount::bigint);
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
  IF v_row.guardian_id IS NULL THEN
    RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
  END IF;
  IF v_row.enrollment_id IS NULL THEN
    IF NOT (v_row.declaration_kind = 'initial_tuition_setup' AND v_row.lead_id IS NOT NULL) THEN
      RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  IF v_row.student_id IS NULL AND v_row.lead_id IS NULL THEN
    RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
  END IF;
  IF v_row.declared_amount IS NULL OR v_row.declared_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.declaration_kind <> 'initial_tuition_setup' THEN
    PERFORM public._cw2_validate_declaration_finance_state(
      v_row.enrollment_financial_terms_id,
      v_row.declared_amount::bigint
    );
  END IF;

  UPDATE public.consultant_revenue_declaration
  SET status = 'pending', submitted_at = now(), updated_at = now()
  WHERE id = p_declaration_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_consultant_payment_declaration(
  p_declaration_id uuid,
  p_paid_at timestamptz DEFAULT now(),
  p_method_code text DEFAULT 'cash',
  p_idempotency_key text DEFAULT NULL
)
RETURNS public.consultant_payment_confirmation_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_row public.consultant_revenue_declaration;
  v_amount bigint;
  v_fin jsonb;
  v_allocations jsonb;
  v_pay jsonb;
  v_payment_id uuid;
  v_student_id uuid;
  v_conv jsonb;
  v_code_result public.official_student_code_allocation_result;
  v_result public.consultant_payment_confirmation_result;
  v_idem text;
  v_attribution_amount bigint;
  v_cc char(2);
  v_terms_id uuid;
  v_method text;
BEGIN
  IF NOT public.is_active_app_user()
     OR NOT public.has_permission('payment.record')
     OR NOT public.has_permission('consultant_revenue.review') THEN
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

  v_method := COALESCE(NULLIF(btrim(p_method_code), ''), NULLIF(btrim(v_row.payment_method_code), ''), 'cash');

  IF v_row.workflow_kind <> 'cw2_payment' THEN
    RAISE EXCEPTION 'declaration_not_cw2_workflow' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status = 'approved' AND v_row.approved_payment_id IS NOT NULL THEN
    v_result.declaration_id := v_row.id;
    v_result.payment_id := v_row.approved_payment_id;
    v_result.student_id := v_row.student_id;
    v_result.enrollment_id := v_row.enrollment_id;
    SELECT student_code INTO v_result.official_student_code FROM student WHERE id = v_row.student_id;
    v_result.idempotent_replay := true;
    RETURN v_result;
  END IF;

  IF v_row.status <> 'pending' OR v_row.submitted_at IS NULL THEN
    RAISE EXCEPTION 'declaration_not_confirmable' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.depends_on_declaration_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.consultant_revenue_declaration parent
      WHERE parent.id = v_row.depends_on_declaration_id
        AND parent.organization_id = v_org
        AND parent.status = 'approved'
        AND parent.approved_payment_id IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'depends_on_declaration_not_confirmed' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  v_amount := v_row.declared_amount::bigint;
  v_student_id := v_row.student_id;

  IF v_student_id IS NULL AND v_row.lead_id IS NOT NULL THEN
    PERFORM set_config('cw2.declaration_confirm', v_row.id::text, true);
    v_conv := public.convert_lead(
      v_row.lead_id,
      '[]'::jsonb,
      CASE WHEN v_row.class_id IS NOT NULL THEN
        jsonb_build_array(jsonb_build_object('class_id', v_row.class_id))
      ELSE '[]'::jsonb END
    );
    SELECT (elem->>'student_id')::uuid INTO v_student_id
    FROM jsonb_array_elements(v_conv->'candidates') elem
    LIMIT 1;
    IF v_student_id IS NULL THEN
      RAISE EXCEPTION 'lead_conversion_failed' USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.consultant_revenue_declaration
    SET student_id = v_student_id,
        enrollment_id = COALESCE(enrollment_id, (v_conv->'enrollments'->0->>'enrollment_id')::uuid)
    WHERE id = v_row.id
    RETURNING * INTO v_row;

    UPDATE public.consultant_portfolio_entry
    SET student_id = v_student_id, updated_at = now()
    WHERE organization_id = v_org
      AND lead_id = v_row.lead_id
      AND consultant_user_id = v_row.consultant_user_id
      AND student_id IS NULL;
  END IF;

  IF v_row.enrollment_id IS NULL AND v_row.student_id IS NOT NULL THEN
    v_row := public._cw2_ensure_declaration_enrollment_for_confirm(v_org, v_row);
  END IF;

  IF v_row.declaration_kind = 'initial_tuition_setup' THEN
    IF v_row.tuition_billing_mode = 'course_lump_sum' THEN
      v_terms_id := public._cw2_accounting_establish_course_tuition(v_org, v_row);
      UPDATE public.consultant_revenue_declaration
      SET enrollment_financial_terms_id = v_terms_id
      WHERE id = v_row.id
      RETURNING * INTO v_row;
      v_fin := public._cw2_validate_declaration_finance_state(v_terms_id, v_amount);
      v_allocations := v_fin->'allocations';
    ELSIF v_row.tuition_billing_mode = 'periodic' THEN
      v_terms_id := public._cw2_accounting_establish_periodic_tuition(v_org, v_row);
      UPDATE public.consultant_revenue_declaration
      SET enrollment_financial_terms_id = v_terms_id
      WHERE id = v_row.id
      RETURNING * INTO v_row;
      v_allocations := '[]'::jsonb;
    ELSE
      RAISE EXCEPTION 'invalid_tuition_billing_mode' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    v_fin := public._cw2_validate_declaration_finance_state(v_row.enrollment_financial_terms_id, v_amount);
    v_allocations := v_fin->'allocations';
  END IF;

  v_idem := COALESCE(NULLIF(btrim(p_idempotency_key), ''), 'cw2-decl-confirm:' || v_row.id::text);
  v_student_id := v_row.student_id;

  v_pay := public.record_payment(
    v_row.guardian_id,
    v_amount,
    COALESCE(p_paid_at, now()),
    v_method,
    NULL,
    'CW2 declaration ' || v_row.id::text,
    v_student_id,
    NULL,
    v_idem,
    v_allocations
  );

  v_payment_id := (v_pay->>'payment_id')::uuid;

  IF public._cw2_enrollment_billing_mode(v_org, v_row.enrollment_id) = 'periodic' THEN
    PERFORM public._cw2_periodic_apply_confirmed_payment(
      v_org, v_row.enrollment_id, v_amount, v_row.declaration_date
    );
  END IF;

  v_cc := COALESCE(
    v_row.consultant_operational_code_snapshot,
    (SELECT consultant_operational_code FROM app_user WHERE id = v_row.consultant_user_id)
  );

  v_attribution_amount := v_amount;

  INSERT INTO public.payment_consultant_attribution (
    organization_id, payment_id, consultant_user_id, consultant_operational_code,
    attributed_amount, currency_code, consultant_revenue_declaration_id, attribution_recorded_at
  )
  SELECT
    v_org, v_payment_id, v_row.consultant_user_id, v_cc,
    v_attribution_amount, p.currency_code, v_row.id, p.paid_at
  FROM public.payment p
  WHERE p.id = v_payment_id AND p.organization_id = v_org
  ON CONFLICT (organization_id, payment_id) DO NOTHING;

  BEGIN
    v_code_result := public.allocate_official_student_code(v_student_id, v_row.consultant_user_id);
    v_result.official_student_code := v_code_result.official_student_code;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%student_code_already_set%' THEN
        SELECT student_code INTO v_result.official_student_code FROM student WHERE id = v_student_id;
      ELSE
        RAISE;
      END IF;
  END;

  UPDATE public.consultant_revenue_declaration
  SET
    status = 'approved',
    approved_payment_id = v_payment_id,
    reviewed_by = public.current_app_user_id(),
    reviewed_at = now(),
    confirmation_idempotency_key = v_idem,
    student_id = v_student_id,
    updated_at = now()
  WHERE id = v_row.id;

  v_result.declaration_id := v_row.id;
  v_result.payment_id := v_payment_id;
  v_result.student_id := v_student_id;
  v_result.enrollment_id := v_row.enrollment_id;
  v_result.idempotent_replay := false;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_consultant_portfolio_entry_detail(p_portfolio_entry_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry public.consultant_portfolio_entry;
  v_org uuid;
  v_consultant uuid;
  v_row jsonb;
  v_tuif jsonb;
  v_enrollment_id uuid;
  v_lead_id uuid;
  v_snap jsonb;
BEGIN
  v_entry := public._cw2_assert_portfolio_entry_access(p_portfolio_entry_id);
  v_org := v_entry.organization_id;
  v_consultant := v_entry.consultant_user_id;

  SELECT jsonb_build_object(
    'portfolio_entry_id', e.id,
    'workspace_sequence', e.workspace_sequence,
    'portfolio_entered_at', e.portfolio_entered_at,
    'lead_id', e.lead_id,
    'student_id', e.student_id,
    'subject_type', CASE WHEN e.student_id IS NOT NULL THEN 'student' ELSE 'lead' END,
    'display_subject_id', COALESCE(e.student_id, e.lead_id),
    'is_hidden', (h.subject_id IS NOT NULL),
    'family_name', COALESCE(s.family_name, lc.family_name),
    'given_name', COALESCE(s.given_name, lc.given_name),
    'date_of_birth', COALESCE(s.date_of_birth, lc.date_of_birth),
    'subject_updated_at', COALESCE(s.updated_at, lc.updated_at),
    'student_code_official', CASE WHEN public._cw2_is_official_student_code(s.student_code) THEN btrim(s.student_code) END,
    'student_code_display', COALESCE(
      CASE WHEN public._cw2_is_official_student_code(s.student_code) THEN btrim(s.student_code) END,
      public._cw2_provisional_student_code_display(au.consultant_operational_code, COALESCE(s.date_of_birth, lc.date_of_birth))
    ),
    'student_code_is_provisional', NOT public._cw2_is_official_student_code(s.student_code),
    'lifecycle_status', public._cw2_derive_workspace_lifecycle_status(
      e.student_id, s.status,
      public._cw2_is_official_student_code(s.student_code),
      EXISTS (SELECT 1 FROM public.enrollment en WHERE en.student_id = e.student_id AND en.organization_id = v_org AND en.status = 'active')
    ),
    'enrollment_id', pe.enrollment_id,
    'enrollment_status', en.status,
    'enrollment_start_date', en.start_date,
    'enrollment_financial_terms_id', pe.enrollment_financial_terms_id,
    'course_id', pe.course_id,
    'course_name', pe.course_name,
    'class_id', pe.class_id,
    'class_name', pe.class_name,
    'tuition_total_net', fin.net_tuition,
    'tuition_paid', fin.allocated_amount,
    'tuition_outstanding', fin.outstanding_amount,
    'tuition_pending_declaration', fin.pending_declaration_amount,
    'declaration_id', d.id,
    'declaration_status', d.status,
    'declaration_workflow_kind', d.workflow_kind,
    'primary_guardian_id', g.id,
    'primary_guardian_family_name', COALESCE(g.family_name, lcg.family_name),
    'primary_guardian_given_name', COALESCE(g.given_name, lcg.given_name),
    'primary_guardian_phone', COALESCE(g.phone, lcg.phone),
    'custom_fields', COALESCE(cf.fields, '[]'::jsonb),
    'editable', jsonb_build_object(
      'can_edit_profile', public._cw2_portfolio_can_edit_contact(s.student_code),
      'can_edit_date_of_birth', public._cw2_portfolio_can_edit_contact(s.student_code),
      'can_edit_custom_fields', public.has_permission('consultant_custom_field.manage'),
      'official_student_code_locked', public._cw2_is_official_student_code(s.student_code)
    )
  ) INTO v_row
  FROM public.consultant_portfolio_entry e
  LEFT JOIN public.consultant_grid_hidden_row h
    ON h.organization_id = e.organization_id
   AND h.app_user_id = public.current_app_user_id()
   AND h.subject_type = CASE WHEN e.student_id IS NOT NULL THEN 'student' ELSE 'lead' END
   AND h.subject_id = COALESCE(e.student_id, e.lead_id)
  LEFT JOIN public.student s ON s.id = e.student_id AND s.organization_id = e.organization_id
  LEFT JOIN LATERAL (
    SELECT c.*
    FROM public.lead_candidate c
    WHERE c.lead_id = e.lead_id AND c.organization_id = e.organization_id AND c.status = 'active'
    ORDER BY c.is_primary_candidate DESC, c.created_at
    LIMIT 1
  ) lc ON e.lead_id IS NOT NULL
  LEFT JOIN LATERAL public._cw2_portfolio_pick_enrollment(v_org, e.student_id) pe ON e.student_id IS NOT NULL
  LEFT JOIN public.enrollment en ON en.id = pe.enrollment_id AND en.organization_id = v_org
  LEFT JOIN LATERAL (
    SELECT
      (snap->>'net_tuition')::numeric AS net_tuition,
      (snap->>'allocated_amount')::bigint AS allocated_amount,
      (snap->>'course_outstanding_amount')::bigint AS outstanding_amount,
      COALESCE((snap->>'pending_declaration_amount')::bigint, 0) AS pending_declaration_amount,
      snap->>'billing_mode' AS billing_mode,
      (snap->>'periodic_lessons_remaining')::integer AS periodic_lessons_remaining,
      COALESCE((snap->>'periodic_carry_forward_credit')::bigint, 0) AS carry_forward_credit
    FROM public._cw2_portfolio_finance_snapshot(v_org, pe.enrollment_id) snap
    WHERE pe.enrollment_id IS NOT NULL
  ) fin ON true
  LEFT JOIN LATERAL public._cw2_portfolio_pick_declaration(
    v_org, v_consultant, e.student_id, e.lead_id, pe.enrollment_id, pe.enrollment_financial_terms_id
  ) d ON true
  LEFT JOIN LATERAL (
    SELECT sg.guardian_id
    FROM public.student_guardian sg
    WHERE sg.student_id = e.student_id AND sg.organization_id = v_org AND sg.is_primary_contact = true
    ORDER BY sg.created_at
    LIMIT 1
  ) sg ON e.student_id IS NOT NULL
  LEFT JOIN public.guardian g ON g.id = sg.guardian_id AND g.organization_id = v_org
  LEFT JOIN LATERAL (
    SELECT lc2.given_name, lc2.family_name, lc2.phone
    FROM public.lead_contact lc2
    WHERE lc2.lead_id = e.lead_id AND lc2.organization_id = v_org AND lc2.is_primary_contact = true
    ORDER BY lc2.created_at
    LIMIT 1
  ) lcg ON e.student_id IS NULL
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'definition_id', d2.id,
        'field_key', d2.field_key,
        'label', d2.label,
        'data_type', d2.data_type,
        'value', v.value_text
      )
      ORDER BY d2.sort_order, d2.field_key
    ) AS fields
    FROM public.consultant_custom_field_definition d2
    LEFT JOIN public.consultant_custom_field_value v
      ON v.field_definition_id = d2.id
     AND v.organization_id = d2.organization_id
     AND v.subject_type = CASE WHEN e.student_id IS NOT NULL THEN 'student' ELSE 'lead' END
     AND v.subject_id = COALESCE(e.student_id, e.lead_id)
    WHERE d2.organization_id = v_org
      AND d2.owner_app_user_id = public.current_app_user_id()
      AND d2.status = 'active'
  ) cf ON true
  JOIN public.app_user au ON au.id = e.consultant_user_id AND au.organization_id = e.organization_id
  WHERE e.id = p_portfolio_entry_id;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'portfolio_entry_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_enrollment_id := NULLIF(v_row->>'enrollment_id', '')::uuid;
  v_lead_id := NULLIF(v_row->>'lead_id', '')::uuid;

  IF v_enrollment_id IS NOT NULL THEN
    v_snap := public._cw2_portfolio_finance_snapshot(v_org, v_enrollment_id);
    v_tuif := public._cw2_portfolio_row_tuition_fields(
      v_org,
      v_enrollment_id,
      NULLIF(v_row->>'enrollment_financial_terms_id', '')::uuid,
      (v_row->>'tuition_total_net')::numeric,
      (v_row->>'tuition_outstanding')::bigint,
      (v_row->>'tuition_paid')::bigint,
      (v_row->>'tuition_pending_declaration')::bigint,
      v_row->>'declaration_status',
      (v_row->>'student_id') IS NOT NULL,
      NULL,
      v_snap->>'billing_mode',
      (v_snap->>'periodic_lessons_remaining')::integer,
      COALESCE((v_snap->>'periodic_carry_forward_credit')::bigint, 0),
      v_lead_id,
      v_consultant
    );
    v_row := v_row || v_tuif || jsonb_build_object('capabilities', v_tuif->'capabilities');
  ELSE
    v_tuif := public._cw2_portfolio_row_tuition_fields(
      v_org,
      NULL,
      NULL,
      0,
      0,
      0,
      0,
      v_row->>'declaration_status',
      (v_row->>'student_id') IS NOT NULL,
      NULL,
      NULL,
      NULL,
      0,
      v_lead_id,
      v_consultant
    );
    v_row := v_row || v_tuif || jsonb_build_object('capabilities', v_tuif->'capabilities');
  END IF;

  RETURN v_row;
END;
$$;
