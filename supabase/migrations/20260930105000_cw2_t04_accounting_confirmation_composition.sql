-- CW2-T04: declaration draft/submit + Accounting confirmation composition.

ALTER TABLE public.consultant_revenue_declaration
  ADD COLUMN IF NOT EXISTS guardian_id uuid,
  ADD COLUMN IF NOT EXISTS class_id uuid,
  ADD COLUMN IF NOT EXISTS workflow_kind text NOT NULL DEFAULT 'legacy_m5',
  ADD COLUMN IF NOT EXISTS confirmation_idempotency_key text;

ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_workflow_kind_check
    CHECK (workflow_kind IN ('legacy_m5', 'cw2_payment')),
  ADD CONSTRAINT consultant_revenue_declaration_org_guardian_fk
    FOREIGN KEY (organization_id, guardian_id)
    REFERENCES public.guardian (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT consultant_revenue_declaration_org_class_fk
    FOREIGN KEY (organization_id, class_id)
    REFERENCES public.class (organization_id, id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_consultant_revenue_declaration_confirm_idempotency
  ON public.consultant_revenue_declaration (organization_id, confirmation_idempotency_key)
  WHERE confirmation_idempotency_key IS NOT NULL;

COMMENT ON COLUMN public.consultant_revenue_declaration.workflow_kind IS
  'legacy_m5: M5 context-free declare_consultant_revenue rows (not CW2 confirmable). cw2_payment: tuition/payment declaration workflow.';

COMMENT ON COLUMN public.consultant_revenue_declaration.approved_payment_id IS
  'Authoritative M2 payment created by CW2 Accounting confirmation (or legacy manual link).';

-- ---------------------------------------------------------------------------
-- Eligibility + allocation helpers
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._cw2_declaration_is_cw2_payment(p_row public.consultant_revenue_declaration)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_row.workflow_kind = 'cw2_payment';
$$;

CREATE OR REPLACE FUNCTION public._cw2_validate_declaration_finance_state(
  p_terms_id uuid,
  p_amount bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_outstanding bigint := 0;
  v_allocations jsonb := '[]'::jsonb;
  v_remaining bigint;
  v_charge record;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_payment_amount' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(sum(cb.outstanding_balance), 0) INTO v_outstanding
  FROM public.charge c
  JOIN public.charge_balance cb ON cb.charge_id = c.id
  WHERE c.organization_id = v_org
    AND c.enrollment_financial_terms_id = p_terms_id
    AND c.status = 'open'
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
      AND c.status = 'open'
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

REVOKE ALL ON FUNCTION public._cw2_validate_declaration_finance_state(uuid, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_validate_declaration_finance_state(uuid, bigint) TO authenticated;

-- Monthly consultant cash (payment.paid_at), not declaration date.
CREATE OR REPLACE FUNCTION public.sum_consultant_attributed_cash(
  p_consultant_user_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
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

GRANT EXECUTE ON FUNCTION public.sum_consultant_attributed_cash(uuid, date, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- Consultant draft / submit
-- ---------------------------------------------------------------------------

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
  p_idempotency_key text DEFAULT NULL
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
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  v_org := public.current_organization_id();
  v_user := public.current_app_user_id();

  SELECT consultant_operational_code INTO v_code
  FROM public.app_user WHERE id = v_user AND organization_id = v_org;

  IF p_declaration_id IS NULL THEN
    IF p_declaration_date IS NULL OR p_declared_amount IS NULL OR p_declared_amount <= 0 THEN
      RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.consultant_revenue_declaration (
      organization_id, consultant_user_id, declaration_date, declared_amount, description,
      status, workflow_kind, lead_id, student_id, course_id, class_id,
      enrollment_id, enrollment_financial_terms_id, guardian_id,
      total_obligation_amount, idempotency_key,
      consultant_operational_code_snapshot
    ) VALUES (
      v_org, v_user, p_declaration_date, p_declared_amount, NULLIF(btrim(p_description), ''),
      'draft', 'cw2_payment', p_lead_id, p_student_id, p_course_id, p_class_id,
      p_enrollment_id, p_enrollment_financial_terms_id, p_guardian_id,
      p_total_obligation_amount, NULLIF(btrim(p_idempotency_key), ''),
      v_code
    )
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;

  UPDATE public.consultant_revenue_declaration d
  SET
    declaration_date = COALESCE(p_declaration_date, d.declaration_date),
    declared_amount = COALESCE(p_declared_amount, d.declared_amount),
    description = COALESCE(NULLIF(btrim(p_description), ''), d.description),
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
  RETURNING d.id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'declaration_not_editable' USING ERRCODE = 'P0001';
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

  UPDATE public.consultant_revenue_declaration
  SET status = 'pending', submitted_at = now(), updated_at = now()
  WHERE id = p_declaration_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Accounting confirmation (atomic composition)
-- ---------------------------------------------------------------------------

CREATE TYPE public.consultant_payment_confirmation_result AS (
  declaration_id uuid,
  payment_id uuid,
  student_id uuid,
  enrollment_id uuid,
  official_student_code text,
  idempotent_replay boolean
);

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

  v_amount := v_row.declared_amount::bigint;
  v_fin := public._cw2_validate_declaration_finance_state(v_row.enrollment_financial_terms_id, v_amount);
  v_allocations := v_fin->'allocations';

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
    COALESCE(p_method_code, 'cash'),
    NULL,
    'CW2 declaration ' || v_row.id::text,
    v_student_id,
    NULL,
    v_idem,
    v_allocations
  );

  v_payment_id := (v_pay->>'payment_id')::uuid;

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

REVOKE ALL ON FUNCTION public.save_consultant_payment_declaration_draft(uuid, date, numeric, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_consultant_payment_declaration_draft(uuid, date, numeric, text, uuid, uuid, uuid, uuid, uuid, uuid, uuid, numeric, text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.submit_consultant_payment_declaration(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_consultant_payment_declaration(uuid, timestamptz, text, text) TO authenticated;

COMMENT ON FUNCTION public.confirm_consultant_payment_declaration(uuid, timestamptz, text, text) IS
  'CW2-T04: Accounting confirms submitted cw2_payment declaration â€” M2 payment, allocation, optional lead conversion, T03 code, attribution â€” one transaction.';

-- Legacy M5 declare remains context-free (workflow_kind legacy_m5); not confirmable via confirm_consultant_payment_declaration.

COMMENT ON FUNCTION public.declare_consultant_revenue(date, numeric, text) IS
  'Legacy M5 context-free declaration (workflow_kind legacy_m5). CW2 tuition workflow uses save/submit + confirm_consultant_payment_declaration.';

