-- CW2-T11: declaration workflows, portfolio read model, accounting confirm composition.

CREATE OR REPLACE FUNCTION public._cw2_portfolio_declaration_capabilities(
  p_org uuid,
  p_enrollment_id uuid,
  p_enrollment_financial_terms_id uuid,
  p_outstanding bigint,
  p_net_tuition bigint,
  p_allocated bigint,
  p_pending_declaration bigint,
  p_declaration_status text,
  p_has_student boolean,
  p_student_code_raw text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_state text;
BEGIN
  v_state := public._cw2_derive_tuition_payment_state(
    p_org, p_enrollment_id, p_net_tuition, p_outstanding, p_allocated, p_pending_declaration
  );

  RETURN jsonb_build_object(
    'can_edit_contact', public._cw2_portfolio_can_edit_contact(p_student_code_raw),
    'can_open_payment_declaration', public.has_permission('consultant_revenue.declare')
      AND p_enrollment_id IS NOT NULL
      AND v_state <> 'full_phi',
    'can_create_payment_declaration', public.has_permission('consultant_revenue.declare')
      AND p_enrollment_id IS NOT NULL
      AND v_state <> 'full_phi'
      AND COALESCE(p_declaration_status, '') NOT IN ('draft', 'returned'),
    'can_edit_payment_declaration', public.has_permission('consultant_revenue.declare')
      AND p_declaration_status IN ('draft', 'returned'),
    'can_submit_declaration', public.has_permission('consultant_revenue.declare')
      AND p_declaration_status IN ('draft', 'returned'),
    'can_add_payment', false,
    'can_open_student_details', p_has_student
  );
END;
$$;

DROP FUNCTION IF EXISTS public.save_consultant_payment_declaration_draft(
  uuid, date, numeric, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text, text
);

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
    IF v_terms IS NULL OR p_enrollment_id IS NULL THEN
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
      IF public._cw2_enrollment_tuition_established(v_org, p_enrollment_id) THEN
        RAISE EXCEPTION 'tuition_plan_already_established' USING ERRCODE = 'P0001';
      END IF;
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
      p_enrollment_id, v_terms, p_guardian_id,
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
  IF v_row.enrollment_id IS NULL OR v_row.guardian_id IS NULL THEN
    RAISE EXCEPTION 'declaration_context_incomplete' USING ERRCODE = 'P0001';
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
  END IF;

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

CREATE OR REPLACE FUNCTION public.get_cw2_tuition_declaration_context(
  p_enrollment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_snap jsonb;
  v_billing public.enrollment_tuition_billing%ROWTYPE;
  v_terms_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_snap := public._cw2_portfolio_finance_snapshot(v_org, p_enrollment_id);
  SELECT * INTO v_billing
  FROM public.enrollment_tuition_billing b
  WHERE b.organization_id = v_org AND b.enrollment_id = p_enrollment_id;

  SELECT t.id INTO v_terms_id
  FROM public.enrollment_financial_terms t
  WHERE t.organization_id = v_org
    AND t.enrollment_id = p_enrollment_id
    AND t.status = 'active'
  LIMIT 1;

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'enrollment_financial_terms_id', v_terms_id,
    'tuition_established', COALESCE((v_snap->>'tuition_established')::boolean, false),
    'billing_mode', v_snap->>'billing_mode',
    'finance', v_snap,
    'billing', CASE WHEN v_billing.id IS NULL THEN NULL ELSE jsonb_build_object(
      'billing_mode', v_billing.billing_mode,
      'period_unit', v_billing.period_unit,
      'period_quantity', v_billing.period_quantity,
      'amount_per_period', v_billing.amount_per_period,
      'organization_academic_year_id', v_billing.organization_academic_year_id
    ) END,
    'can_change_billing_mode', v_billing.id IS NULL
      AND NOT public._cw2_has_pending_initial_tuition_setup(v_org, p_enrollment_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cw2_tuition_declaration_context(uuid) TO authenticated;

-- Backward-compatible wrapper for portfolio detail / inline intake call sites.
CREATE OR REPLACE FUNCTION public._cw2_portfolio_declaration_capabilities(
  p_enrollment_financial_terms_id uuid,
  p_outstanding bigint,
  p_declaration_status text,
  p_has_student boolean,
  p_student_code_raw text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_enrollment_id uuid;
  v_net bigint;
  v_allocated bigint;
  v_pending bigint;
  v_outstanding bigint := p_outstanding;
BEGIN
  IF p_enrollment_financial_terms_id IS NULL THEN
    RETURN jsonb_build_object(
      'can_edit_contact', public._cw2_portfolio_can_edit_contact(p_student_code_raw),
      'can_open_payment_declaration', false,
      'can_create_payment_declaration', false,
      'can_edit_payment_declaration', false,
      'can_submit_declaration', false,
      'can_add_payment', false,
      'can_open_student_details', p_has_student
    );
  END IF;

  SELECT t.enrollment_id, t.net_tuition_amount
  INTO v_enrollment_id, v_net
  FROM public.enrollment_financial_terms t
  WHERE t.id = p_enrollment_financial_terms_id AND t.organization_id = v_org;

  SELECT
    COALESCE((snap->>'allocated_amount')::bigint, 0),
    COALESCE((snap->>'course_outstanding_amount')::bigint, 0),
    COALESCE((snap->>'pending_declaration_amount')::bigint, 0),
    COALESCE((snap->>'net_tuition')::bigint, 0)
  INTO v_allocated, v_outstanding, v_pending, v_net
  FROM public._cw2_portfolio_finance_snapshot(v_org, v_enrollment_id) snap;

  RETURN public._cw2_portfolio_declaration_capabilities(
    v_org,
    v_enrollment_id,
    p_enrollment_financial_terms_id,
    v_outstanding,
    v_net,
    v_allocated,
    v_pending,
    p_declaration_status,
    p_has_student,
    p_student_code_raw
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public._cw2_portfolio_declaration_capabilities(uuid, bigint, text, boolean, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.save_consultant_payment_declaration_draft(
  uuid, date, numeric, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text, text,
  text, numeric, text, integer, numeric, uuid, text, text
) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_cw2_finance_declaration_review_detail(p_declaration_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_row public.consultant_revenue_declaration%ROWTYPE;
  v_snap jsonb;
  v_preview jsonb;
  v_student_name text;
  v_consultant_name text;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.review') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.consultant_revenue_declaration d
  WHERE d.id = p_declaration_id AND d.organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'declaration_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.enrollment_id IS NOT NULL THEN
    v_snap := public._cw2_portfolio_finance_snapshot(v_org, v_row.enrollment_id);
    IF v_row.tuition_billing_mode = 'periodic'
       OR public._cw2_enrollment_billing_mode(v_org, v_row.enrollment_id) = 'periodic' THEN
      v_preview := public._cw2_periodic_preview_payment(v_org, v_row.enrollment_id, v_row.declared_amount::bigint);
    END IF;
  END IF;

  SELECT trim(both FROM COALESCE(s.given_name, '') || ' ' || COALESCE(s.family_name, ''))
  INTO v_student_name
  FROM public.student s
  WHERE s.id = v_row.student_id AND s.organization_id = v_org;

  SELECT au.display_name INTO v_consultant_name
  FROM public.app_user au
  WHERE au.id = v_row.consultant_user_id AND au.organization_id = v_org;

  RETURN jsonb_build_object(
    'declaration', jsonb_build_object(
      'id', v_row.id,
      'declaration_kind', v_row.declaration_kind,
      'status', v_row.status,
      'declaration_date', v_row.declaration_date,
      'declared_amount', v_row.declared_amount,
      'payment_method_code', v_row.payment_method_code,
      'description', v_row.description,
      'tuition_billing_mode', v_row.tuition_billing_mode,
      'proposed_net_tuition_amount', v_row.proposed_net_tuition_amount,
      'periodic_period_unit', v_row.periodic_period_unit,
      'periodic_period_quantity', v_row.periodic_period_quantity,
      'periodic_amount_per_period', v_row.periodic_amount_per_period,
      'depends_on_declaration_id', v_row.depends_on_declaration_id,
      'enrollment_id', v_row.enrollment_id,
      'student_id', v_row.student_id,
      'consultant_user_id', v_row.consultant_user_id
    ),
    'student_name', v_student_name,
    'consultant_name', v_consultant_name,
    'canonical_finance', v_snap,
    'periodic_effect_preview', v_preview
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cw2_finance_declaration_review_detail(uuid) TO authenticated;

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
    'description', crd.description,
    'declaration_kind', crd.declaration_kind,
    'workflow_kind', crd.workflow_kind,
    'tuition_billing_mode', crd.tuition_billing_mode,
    'student_id', crd.student_id,
    'enrollment_id', crd.enrollment_id
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
