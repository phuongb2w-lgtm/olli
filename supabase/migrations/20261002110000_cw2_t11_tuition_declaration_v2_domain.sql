-- CW2-T11: Tuition declaration V2 domain — course state machine, initial setup, periodic ledger, confirm path.

CREATE OR REPLACE FUNCTION public._cw2_portfolio_pick_enrollment(p_org uuid, p_student_id uuid)
RETURNS TABLE (
  enrollment_id uuid,
  enrollment_financial_terms_id uuid,
  course_id uuid,
  course_name text,
  class_id uuid,
  class_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id,
    t.id,
    cl.course_id,
    co.name,
    e.class_id,
    cl.name
  FROM public.enrollment e
  JOIN public.class cl ON cl.id = e.class_id AND cl.organization_id = e.organization_id
  JOIN public.course co ON co.id = cl.course_id AND co.organization_id = e.organization_id
  LEFT JOIN public.enrollment_financial_terms t
    ON t.enrollment_id = e.id
   AND t.organization_id = e.organization_id
   AND t.status = 'active'
  WHERE e.organization_id = p_org
    AND e.student_id = p_student_id
    AND e.status IN ('active', 'pending')
  ORDER BY
    CASE e.status WHEN 'active' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
    e.start_date DESC NULLS LAST,
    e.created_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._cw2_enrollment_tuition_established(p_org uuid, p_enrollment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.enrollment_financial_terms t
    WHERE t.organization_id = p_org
      AND t.enrollment_id = p_enrollment_id
      AND t.status = 'active'
      AND t.tuition_plan_established_at IS NOT NULL
  );
$$;

CREATE OR REPLACE FUNCTION public._cw2_enrollment_billing_mode(p_org uuid, p_enrollment_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT b.billing_mode
  FROM public.enrollment_tuition_billing b
  WHERE b.organization_id = p_org
    AND b.enrollment_id = p_enrollment_id
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._cw2_has_pending_initial_tuition_setup(p_org uuid, p_enrollment_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.consultant_revenue_declaration d
    WHERE d.organization_id = p_org
      AND d.enrollment_id = p_enrollment_id
      AND d.workflow_kind = 'cw2_payment'
      AND d.status = 'pending'
      AND d.declaration_kind = 'initial_tuition_setup'
  );
$$;

CREATE OR REPLACE FUNCTION public._cw2_confirmed_cw2_payment_count(p_org uuid, p_enrollment_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::integer
  FROM public.consultant_revenue_declaration d
  WHERE d.organization_id = p_org
    AND d.enrollment_id = p_enrollment_id
    AND d.workflow_kind = 'cw2_payment'
    AND d.status = 'approved'
    AND d.approved_payment_id IS NOT NULL;
$$;

DROP FUNCTION IF EXISTS public._cw2_derive_tuition_payment_state(bigint, bigint, text, boolean);

CREATE OR REPLACE FUNCTION public._cw2_derive_periodic_tuition_status(
  p_org uuid,
  p_enrollment_id uuid,
  p_pending_declaration bigint
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bal public.enrollment_periodic_tuition_balance%ROWTYPE;
  v_billing public.enrollment_tuition_billing%ROWTYPE;
  v_upcoming integer := 0;
  v_obligation bigint;
  v_satisfied bigint;
BEGIN
  IF NOT public._cw2_enrollment_tuition_established(p_org, p_enrollment_id) THEN
    IF public._cw2_has_pending_initial_tuition_setup(p_org, p_enrollment_id) THEN
      RETURN 'cho_xac_nhan';
    END IF;
    RETURN 'chua_coc';
  END IF;

  IF COALESCE(p_pending_declaration, 0) > 0 THEN
    RETURN 'cho_xac_nhan';
  END IF;

  SELECT * INTO v_billing
  FROM public.enrollment_tuition_billing b
  WHERE b.organization_id = p_org AND b.enrollment_id = p_enrollment_id;

  SELECT * INTO v_bal
  FROM public.enrollment_periodic_tuition_balance b
  WHERE b.organization_id = p_org AND b.enrollment_id = p_enrollment_id;

  IF v_billing.period_unit = 'lesson' THEN
    SELECT count(*)::integer INTO v_upcoming
    FROM public.teaching_session ts
    JOIN public.enrollment e ON e.class_id = ts.class_id AND e.organization_id = ts.organization_id
    WHERE e.id = p_enrollment_id
      AND ts.organization_id = p_org
      AND ts.status = 'scheduled'
      AND ts.scheduled_start_at > now();
  END IF;

  IF v_billing.period_unit = 'lesson'
     AND v_bal.lessons_remaining_in_block IS NOT NULL
     AND v_bal.lessons_remaining_in_block > 0
     AND v_upcoming >= v_bal.lessons_remaining_in_block THEN
    RETURN 'sap_het_hoc_phi';
  END IF;

  IF v_billing.period_unit = 'lesson'
     AND COALESCE(v_bal.lessons_remaining_in_block, 0) = 0 THEN
    RETURN 'het_hoc_phi';
  END IF;

  IF COALESCE(v_bal.carry_forward_credit, 0) > 0 THEN
    RETURN 'co_so_du';
  END IF;

  SELECT o.obligation_amount, o.satisfied_amount
  INTO v_obligation, v_satisfied
  FROM public.enrollment_periodic_period_obligation o
  WHERE o.organization_id = p_org
    AND o.enrollment_id = p_enrollment_id
    AND o.status IN ('open', 'underpaid', 'satisfied')
  ORDER BY o.created_at DESC
  LIMIT 1;

  IF v_obligation IS NOT NULL AND v_satisfied >= v_obligation THEN
    RETURN 'da_du_ky';
  END IF;

  IF v_obligation IS NOT NULL AND v_satisfied < v_obligation THEN
    RETURN 'con_thieu';
  END IF;

  RETURN 'con_hoc_phi';
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_derive_tuition_payment_state(
  p_org uuid,
  p_enrollment_id uuid,
  p_net_tuition bigint,
  p_outstanding bigint,
  p_allocated bigint,
  p_pending_declaration bigint
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_established boolean;
  v_mode text;
  v_confirmed integer;
BEGIN
  IF p_enrollment_id IS NULL THEN
    RETURN 'chua_coc';
  END IF;

  v_established := public._cw2_enrollment_tuition_established(p_org, p_enrollment_id);
  v_mode := public._cw2_enrollment_billing_mode(p_org, p_enrollment_id);

  IF v_mode = 'periodic' THEN
    RETURN public._cw2_derive_periodic_tuition_status(p_org, p_enrollment_id, p_pending_declaration);
  END IF;

  IF NOT v_established THEN
    IF public._cw2_has_pending_initial_tuition_setup(p_org, p_enrollment_id) THEN
      RETURN 'coc_cho_xac_nhan';
    END IF;
    RETURN 'chua_coc';
  END IF;

  IF COALESCE(p_net_tuition, 0) > 0
     AND COALESCE(p_allocated, 0) >= p_net_tuition
     AND COALESCE(p_outstanding, 0) <= 0 THEN
    RETURN 'full_phi';
  END IF;

  v_confirmed := public._cw2_confirmed_cw2_payment_count(p_org, p_enrollment_id);

  IF v_confirmed <= 1 AND COALESCE(p_allocated, 0) > 0 AND COALESCE(p_outstanding, 0) > 0 THEN
    RETURN 'da_coc';
  END IF;

  IF COALESCE(p_allocated, 0) > 0 AND COALESCE(p_outstanding, 0) > 0 THEN
    RETURN 'nop_phi';
  END IF;

  IF COALESCE(p_outstanding, 0) > 0 THEN
    RETURN 'nop_phi';
  END IF;

  RETURN 'chua_coc';
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_tuition_payment_state_label(p_state text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE p_state
    WHEN 'chua_coc' THEN 'Chưa cọc'
    WHEN 'coc_cho_xac_nhan' THEN 'Cọc chờ xác nhận'
    WHEN 'da_coc' THEN 'Đã cọc'
    WHEN 'nop_phi' THEN 'Nộp phí'
    WHEN 'full_phi' THEN 'Full phí'
    WHEN 'cho_xac_nhan' THEN 'Chờ xác nhận'
    WHEN 'con_hoc_phi' THEN 'Còn học phí'
    WHEN 'sap_het_hoc_phi' THEN 'Sắp hết học phí'
    WHEN 'het_hoc_phi' THEN 'Hết học phí'
    WHEN 'con_thieu' THEN 'Còn thiếu'
    WHEN 'da_du_ky' THEN 'Đã đủ kỳ'
    WHEN 'co_so_du' THEN 'Có số dư'
    ELSE p_state
  END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_portfolio_finance_snapshot(p_org uuid, p_enrollment_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'net_tuition', CASE
      WHEN public._cw2_enrollment_tuition_established(p_org, p_enrollment_id) THEN COALESCE(t.net_tuition_amount, 0)
      ELSE 0
    END,
    'canonical_net_tuition', COALESCE(t.net_tuition_amount, 0),
    'allocated_amount', COALESCE(alloc.total, 0),
    'outstanding_amount', CASE
      WHEN public._cw2_enrollment_billing_mode(p_org, p_enrollment_id) = 'periodic' THEN 0
      WHEN public._cw2_enrollment_tuition_established(p_org, p_enrollment_id) THEN
        GREATEST(COALESCE(t.net_tuition_amount, 0) - COALESCE(alloc.total, 0), 0)
      ELSE 0
    END,
    'course_outstanding_amount', CASE
      WHEN public._cw2_enrollment_billing_mode(p_org, p_enrollment_id) = 'periodic' THEN 0
      WHEN public._cw2_enrollment_tuition_established(p_org, p_enrollment_id) THEN
        GREATEST(COALESCE(t.net_tuition_amount, 0) - COALESCE(alloc.total, 0), 0)
      ELSE 0
    END,
    'has_deposit_structure', COALESCE(t.payment_plan_mode = 'deposit_remainder', false),
    'pending_declaration_amount', COALESCE(pending.total, 0),
    'tuition_established', public._cw2_enrollment_tuition_established(p_org, p_enrollment_id),
    'billing_mode', public._cw2_enrollment_billing_mode(p_org, p_enrollment_id),
    'periodic_carry_forward_credit', COALESCE(pb.carry_forward_credit, 0),
    'periodic_lessons_remaining', pb.lessons_remaining_in_block
  )
  FROM public.enrollment e
  LEFT JOIN public.enrollment_financial_terms t
    ON t.enrollment_id = e.id
   AND t.organization_id = e.organization_id
   AND t.status = 'active'
  LEFT JOIN public.enrollment_periodic_tuition_balance pb
    ON pb.enrollment_id = e.id AND pb.organization_id = e.organization_id
  LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(pa.amount), 0) AS total
    FROM public.payment_allocation pa
    JOIN public.charge c ON c.id = pa.charge_id
    WHERE c.enrollment_id = e.id
      AND c.organization_id = e.organization_id
      AND c.status <> 'void'
      AND pa.status = 'posted'
  ) alloc ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(cb.outstanding_balance), 0) AS total
    FROM public.charge c
    JOIN public.charge_balance cb ON cb.charge_id = c.id
    WHERE c.enrollment_id = e.id
      AND c.organization_id = e.organization_id
      AND c.status IN ('open', 'partially_paid')
  ) outstanding ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(SUM(d.declared_amount), 0)::bigint AS total
    FROM public.consultant_revenue_declaration d
    WHERE d.organization_id = p_org
      AND d.enrollment_id = e.id
      AND d.workflow_kind = 'cw2_payment'
      AND d.status = 'pending'
  ) pending ON true
  WHERE e.id = p_enrollment_id
    AND e.organization_id = p_org
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._cw2_ensure_placeholder_financial_terms(p_org uuid, p_enrollment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_terms uuid;
BEGIN
  SELECT t.id INTO v_terms
  FROM public.enrollment_financial_terms t
  WHERE t.organization_id = p_org
    AND t.enrollment_id = p_enrollment_id
    AND t.status = 'active';

  IF v_terms IS NOT NULL THEN
    RETURN v_terms;
  END IF;

  SELECT t.id INTO v_terms
  FROM public.enrollment_financial_terms t
  WHERE t.organization_id = p_org
    AND t.enrollment_id = p_enrollment_id
    AND t.status = 'draft';

  IF v_terms IS NOT NULL THEN
    UPDATE public.enrollment_financial_terms
    SET status = 'active', updated_at = now()
    WHERE id = v_terms;
    RETURN v_terms;
  END IF;

  INSERT INTO public.enrollment_financial_terms (
    organization_id, enrollment_id, agreed_tuition_amount, discount_amount,
    net_tuition_amount, agreement_date, status
  )
  SELECT p_org, p_enrollment_id, 0, 0, 0, CURRENT_DATE, 'active'
  RETURNING id INTO v_terms;

  RETURN v_terms;
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_ensure_placeholder_financial_terms(uuid, uuid) FROM PUBLIC;

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
  v_enrollment_id uuid;
  v_outstanding bigint := 0;
  v_allocations jsonb := '[]'::jsonb;
  v_remaining bigint;
  v_charge record;
  v_net bigint;
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

  SELECT t.enrollment_id, t.net_tuition_amount
  INTO v_enrollment_id, v_net
  FROM public.enrollment_financial_terms t
  WHERE t.id = p_terms_id
    AND t.organization_id = v_org
    AND t.status = 'active';

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'invalid_financial_terms' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public._cw2_enrollment_tuition_established(v_org, v_enrollment_id) THEN
    RETURN jsonb_build_object('outstanding_before', p_amount, 'allocations', '[]'::jsonb);
  END IF;

  IF public._cw2_enrollment_billing_mode(v_org, v_enrollment_id) = 'periodic' THEN
    RETURN jsonb_build_object('outstanding_before', p_amount, 'allocations', '[]'::jsonb);
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

CREATE OR REPLACE FUNCTION public._cw2_accounting_establish_course_tuition(
  p_org uuid,
  p_declaration public.consultant_revenue_declaration
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_terms_id uuid;
  v_net bigint;
  v_deposit bigint;
  v_remainder bigint;
  v_guardian_id uuid;
  r record;
BEGIN
  v_net := COALESCE(p_declaration.proposed_net_tuition_amount, 0);
  v_deposit := p_declaration.declared_amount::bigint;
  IF v_net <= 0 OR v_deposit <= 0 OR v_deposit >= v_net THEN
    RAISE EXCEPTION 'invalid_course_tuition_proposal' USING ERRCODE = 'P0001';
  END IF;

  v_terms_id := COALESCE(
    p_declaration.enrollment_financial_terms_id,
    public._cw2_ensure_placeholder_financial_terms(p_org, p_declaration.enrollment_id)
  );

  PERFORM set_config('cw2.authoritative_tuition_establishment', 'on', true);

  UPDATE public.enrollment_financial_terms
  SET
    agreed_tuition_amount = v_net,
    discount_amount = 0,
    net_tuition_amount = v_net,
    payment_plan_mode = 'deposit_remainder',
    tuition_plan_established_at = now(),
    updated_at = now()
  WHERE id = v_terms_id AND organization_id = p_org;

  DELETE FROM public.enrollment_payment_schedule_item
  WHERE enrollment_financial_terms_id = v_terms_id;

  v_remainder := v_net - v_deposit;
  INSERT INTO public.enrollment_payment_schedule_item (
    organization_id, enrollment_financial_terms_id, sequence_number, due_date, amount, label
  ) VALUES
    (p_org, v_terms_id, 1, COALESCE(p_declaration.declaration_date, CURRENT_DATE), v_deposit, 'Deposit'),
    (p_org, v_terms_id, 2, COALESCE(p_declaration.declaration_date, CURRENT_DATE) + 30, v_remainder, 'Remainder');

  v_guardian_id := p_declaration.guardian_id;
  IF v_guardian_id IS NULL THEN
    v_guardian_id := public.resolve_enrollment_billing_guardian_id(p_declaration.enrollment_id);
  END IF;
  IF v_guardian_id IS NULL THEN
    RAISE EXCEPTION 'billing_guardian_required' USING ERRCODE = 'P0001';
  END IF;

  FOR r IN
    SELECT si.*
    FROM public.enrollment_payment_schedule_item si
    WHERE si.enrollment_financial_terms_id = v_terms_id
      AND si.status = 'scheduled'
    ORDER BY si.sequence_number
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.charge c WHERE c.enrollment_payment_schedule_item_id = r.id
    ) THEN
      INSERT INTO public.charge (
        organization_id, student_id, enrollment_id, guardian_id,
        amount, currency_code, charged_at, due_date, description, status,
        enrollment_financial_terms_id, enrollment_payment_schedule_item_id,
        charge_source_code, agreed_tuition_snapshot, net_tuition_snapshot
      )
      SELECT
        p_org,
        e.student_id,
        e.id,
        v_guardian_id,
        r.amount,
        t.currency_code,
        CURRENT_DATE,
        r.due_date,
        COALESCE(r.label, 'Tuition'),
        'open',
        v_terms_id,
        r.id,
        'tuition',
        t.agreed_tuition_amount,
        t.net_tuition_amount
      FROM public.enrollment e
      JOIN public.enrollment_financial_terms t ON t.id = v_terms_id
      WHERE e.id = p_declaration.enrollment_id AND e.organization_id = p_org;
    END IF;
  END LOOP;

  INSERT INTO public.enrollment_tuition_billing (
    organization_id, enrollment_id, enrollment_financial_terms_id,
    billing_mode, established_at, established_by
  ) VALUES (
    p_org, p_declaration.enrollment_id, v_terms_id,
    'course_lump_sum', now(), public.current_app_user_id()
  )
  ON CONFLICT (organization_id, enrollment_id) DO UPDATE
  SET
    enrollment_financial_terms_id = EXCLUDED.enrollment_financial_terms_id,
    billing_mode = EXCLUDED.billing_mode,
    established_at = EXCLUDED.established_at,
    established_by = EXCLUDED.established_by,
    updated_at = now();

  RETURN v_terms_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_periodic_period_key(
  p_unit text,
  p_session_date date,
  p_academic_year_id uuid DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_year record;
BEGIN
  IF p_unit = 'lesson' THEN
    RETURN 'lesson-block';
  ELSIF p_unit = 'week' THEN
    RETURN to_char(p_session_date, 'IYYY-"W"IW');
  ELSIF p_unit = 'month' THEN
    RETURN to_char(p_session_date, 'YYYY-MM');
  ELSIF p_unit = 'school_year' THEN
    IF p_academic_year_id IS NULL THEN
      RAISE EXCEPTION 'academic_year_required' USING ERRCODE = 'P0001';
    END IF;
    RETURN 'sy:' || p_academic_year_id::text;
  END IF;
  RAISE EXCEPTION 'invalid_period_unit' USING ERRCODE = 'P0001';
END;
$$;

-- Internal periodic writes use SECURITY DEFINER (postgres owner) with explicit p_org checks.
-- RLS for authenticated users is org + permission only (see migration 83); no session GUC bypass.

CREATE OR REPLACE FUNCTION public._cw2_periodic_ensure_obligation(
  p_org uuid,
  p_enrollment_id uuid,
  p_period_key text,
  p_obligation_amount bigint
)
RETURNS public.enrollment_periodic_period_obligation
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.enrollment_periodic_period_obligation%ROWTYPE;
BEGIN
  SELECT * INTO v_row
  FROM public.enrollment_periodic_period_obligation o
  WHERE o.organization_id = p_org
    AND o.enrollment_id = p_enrollment_id
    AND o.period_key = p_period_key
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.enrollment_periodic_period_obligation (
      organization_id, enrollment_id, period_key, obligation_amount, satisfied_amount, status
    ) VALUES (
      p_org, p_enrollment_id, p_period_key, p_obligation_amount, 0, 'open'
    )
    RETURNING * INTO v_row;
  END IF;
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_periodic_apply_confirmed_payment(
  p_org uuid,
  p_enrollment_id uuid,
  p_amount bigint,
  p_payment_date date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_billing public.enrollment_tuition_billing%ROWTYPE;
  v_key text;
  v_row public.enrollment_periodic_period_obligation%ROWTYPE;
  v_credit bigint;
  v_need bigint;
  v_from_credit bigint;
  v_from_cash bigint;
  v_new_satisfied bigint;
  v_leftover_cash bigint;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_payment_amount' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_billing
  FROM public.enrollment_tuition_billing b
  WHERE b.organization_id = p_org AND b.enrollment_id = p_enrollment_id AND b.billing_mode = 'periodic';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'periodic_billing_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_key := public._cw2_periodic_period_key(
    v_billing.period_unit,
    COALESCE(p_payment_date, CURRENT_DATE),
    v_billing.organization_academic_year_id
  );

  INSERT INTO public.enrollment_periodic_tuition_balance (organization_id, enrollment_id)
  VALUES (p_org, p_enrollment_id)
  ON CONFLICT (organization_id, enrollment_id) DO NOTHING;

  v_row := public._cw2_periodic_ensure_obligation(
    p_org, p_enrollment_id, v_key, v_billing.amount_per_period
  );

  SELECT carry_forward_credit INTO v_credit
  FROM public.enrollment_periodic_tuition_balance
  WHERE organization_id = p_org AND enrollment_id = p_enrollment_id
  FOR UPDATE;

  v_credit := COALESCE(v_credit, 0);
  v_need := GREATEST(v_row.obligation_amount - v_row.satisfied_amount, 0);
  v_from_credit := LEAST(v_credit, v_need);
  v_need := v_need - v_from_credit;
  v_from_cash := LEAST(p_amount, v_need);
  v_new_satisfied := v_row.satisfied_amount + v_from_credit + v_from_cash;
  v_leftover_cash := p_amount - v_from_cash;

  UPDATE public.enrollment_periodic_period_obligation
  SET
    satisfied_amount = v_new_satisfied,
    status = CASE
      WHEN v_new_satisfied >= obligation_amount THEN 'satisfied'
      WHEN v_new_satisfied > 0 THEN 'underpaid'
      ELSE 'open'
    END,
    updated_at = now()
  WHERE id = v_row.id;

  UPDATE public.enrollment_periodic_tuition_balance
  SET
    carry_forward_credit = (v_credit - v_from_credit) + v_leftover_cash,
    lessons_remaining_in_block = CASE
      WHEN v_billing.period_unit = 'lesson' AND v_new_satisfied >= v_row.obligation_amount
        THEN COALESCE(lessons_remaining_in_block, 0) + v_billing.period_quantity
      ELSE lessons_remaining_in_block
    END,
    lessons_per_block = COALESCE(lessons_per_block, v_billing.period_quantity),
    amount_per_block = COALESCE(amount_per_block, v_billing.amount_per_period),
    updated_at = now()
  WHERE organization_id = p_org AND enrollment_id = p_enrollment_id;

  RETURN jsonb_build_object(
    'period_key', v_key,
    'obligation_amount', v_row.obligation_amount,
    'satisfied_amount', v_new_satisfied,
    'outstanding_amount', GREATEST(v_row.obligation_amount - v_new_satisfied, 0),
    'carry_forward_credit', (SELECT carry_forward_credit FROM public.enrollment_periodic_tuition_balance
      WHERE organization_id = p_org AND enrollment_id = p_enrollment_id),
    'applied_from_credit', v_from_credit,
    'applied_from_cash', v_from_cash
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_periodic_preview_payment(
  p_org uuid,
  p_enrollment_id uuid,
  p_amount bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_billing public.enrollment_tuition_billing%ROWTYPE;
  v_key text;
  v_row public.enrollment_periodic_period_obligation%ROWTYPE;
  v_credit bigint;
  v_need bigint;
  v_from_credit bigint;
  v_from_cash bigint;
  v_new_satisfied bigint;
BEGIN
  SELECT * INTO v_billing
  FROM public.enrollment_tuition_billing b
  WHERE b.organization_id = p_org AND b.enrollment_id = p_enrollment_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_key := public._cw2_periodic_period_key(
    v_billing.period_unit, CURRENT_DATE, v_billing.organization_academic_year_id
  );

  SELECT * INTO v_row
  FROM public.enrollment_periodic_period_obligation o
  WHERE o.organization_id = p_org AND o.enrollment_id = p_enrollment_id AND o.period_key = v_key;

  IF NOT FOUND THEN
    v_row.obligation_amount := v_billing.amount_per_period;
    v_row.satisfied_amount := 0;
  END IF;

  SELECT COALESCE(carry_forward_credit, 0) INTO v_credit
  FROM public.enrollment_periodic_tuition_balance
  WHERE organization_id = p_org AND enrollment_id = p_enrollment_id;

  v_need := GREATEST(v_row.obligation_amount - COALESCE(v_row.satisfied_amount, 0), 0);
  v_from_credit := LEAST(v_credit, v_need);
  v_need := v_need - v_from_credit;
  v_from_cash := LEAST(COALESCE(p_amount, 0), v_need);
  v_new_satisfied := COALESCE(v_row.satisfied_amount, 0) + v_from_credit + v_from_cash;

  RETURN jsonb_build_object(
    'obligation_amount', v_row.obligation_amount,
    'satisfied_after', v_new_satisfied,
    'outstanding_after', GREATEST(v_row.obligation_amount - v_new_satisfied, 0),
    'carry_forward_after', (v_credit - v_from_credit) + GREATEST(COALESCE(p_amount, 0) - v_from_cash, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_accounting_establish_periodic_tuition(
  p_org uuid,
  p_declaration public.consultant_revenue_declaration
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_terms_id uuid;
  v_qty integer;
  v_amt bigint;
BEGIN
  v_qty := COALESCE(p_declaration.periodic_period_quantity, 0);
  v_amt := COALESCE(p_declaration.periodic_amount_per_period, 0);
  IF v_qty <= 0 OR v_amt <= 0 THEN
    RAISE EXCEPTION 'invalid_periodic_proposal' USING ERRCODE = 'P0001';
  END IF;
  IF p_declaration.periodic_period_unit = 'school_year'
     AND p_declaration.periodic_academic_year_id IS NULL THEN
    RAISE EXCEPTION 'academic_year_required' USING ERRCODE = 'P0001';
  END IF;

  v_terms_id := COALESCE(
    p_declaration.enrollment_financial_terms_id,
    public._cw2_ensure_placeholder_financial_terms(p_org, p_declaration.enrollment_id)
  );

  PERFORM set_config('cw2.authoritative_tuition_establishment', 'on', true);

  UPDATE public.enrollment_financial_terms
  SET
    agreed_tuition_amount = 0,
    discount_amount = 0,
    net_tuition_amount = 0,
    payment_plan_mode = 'custom',
    recognition_basis_code = 'per_lesson',
    tuition_plan_established_at = now(),
    updated_at = now()
  WHERE id = v_terms_id AND organization_id = p_org;

  INSERT INTO public.enrollment_tuition_billing (
    organization_id, enrollment_id, enrollment_financial_terms_id,
    billing_mode, period_unit, period_quantity, amount_per_period,
    organization_academic_year_id, established_at, established_by
  ) VALUES (
    p_org, p_declaration.enrollment_id, v_terms_id,
    'periodic', p_declaration.periodic_period_unit, v_qty, v_amt,
    p_declaration.periodic_academic_year_id, now(), public.current_app_user_id()
  )
  ON CONFLICT (organization_id, enrollment_id) DO UPDATE
  SET
    enrollment_financial_terms_id = EXCLUDED.enrollment_financial_terms_id,
    billing_mode = EXCLUDED.billing_mode,
    period_unit = EXCLUDED.period_unit,
    period_quantity = EXCLUDED.period_quantity,
    amount_per_period = EXCLUDED.amount_per_period,
    organization_academic_year_id = EXCLUDED.organization_academic_year_id,
    established_at = EXCLUDED.established_at,
    established_by = EXCLUDED.established_by,
    updated_at = now();

  RETURN v_terms_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_periodic_activate_period_from_session(
  p_org uuid,
  p_enrollment_id uuid,
  p_session_date date,
  p_billing public.enrollment_tuition_billing
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
BEGIN
  IF p_billing.period_unit = 'lesson' THEN
    RETURN;
  END IF;
  v_key := public._cw2_periodic_period_key(
    p_billing.period_unit, p_session_date, p_billing.organization_academic_year_id
  );
  PERFORM public._cw2_periodic_ensure_obligation(
    p_org, p_enrollment_id, v_key, p_billing.amount_per_period
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_periodic_reverse_session_consumption(
  p_org uuid,
  p_enrollment_id uuid,
  p_teaching_session_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cons public.enrollment_periodic_session_consumption%ROWTYPE;
  v_billing public.enrollment_tuition_billing%ROWTYPE;
BEGIN
  SELECT * INTO v_cons
  FROM public.enrollment_periodic_session_consumption c
  WHERE c.organization_id = p_org
    AND c.enrollment_id = p_enrollment_id
    AND c.teaching_session_id = p_teaching_session_id
    AND c.reversed_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO v_billing
  FROM public.enrollment_tuition_billing b
  WHERE b.id = v_cons.enrollment_tuition_billing_id;

  IF v_billing.period_unit = 'lesson' AND COALESCE(v_cons.lesson_units_consumed, 0) > 0 THEN
    UPDATE public.enrollment_periodic_tuition_balance
    SET lessons_remaining_in_block = COALESCE(lessons_remaining_in_block, 0) + v_cons.lesson_units_consumed,
        updated_at = now()
    WHERE organization_id = p_org AND enrollment_id = p_enrollment_id;
  END IF;

  UPDATE public.enrollment_periodic_session_consumption
  SET reversed_at = now()
  WHERE id = v_cons.id;

  INSERT INTO public.enrollment_periodic_consumption_audit (
    organization_id, enrollment_id, teaching_session_id, action, reason, actor_user_id
  ) VALUES (
    p_org, p_enrollment_id, p_teaching_session_id, 'reverse', p_reason, public.current_app_user_id()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_periodic_try_consume_session(
  p_org uuid,
  p_enrollment_id uuid,
  p_teaching_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sess public.teaching_session%ROWTYPE;
  v_att public.attendance%ROWTYPE;
  v_billing public.enrollment_tuition_billing%ROWTYPE;
  v_session_date date;
  v_key text;
BEGIN
  SELECT * INTO v_sess
  FROM public.teaching_session ts
  WHERE ts.id = p_teaching_session_id AND ts.organization_id = p_org;

  IF NOT FOUND OR v_sess.status <> 'completed' THEN
    PERFORM public._cw2_periodic_reverse_session_consumption(
      p_org, p_enrollment_id, p_teaching_session_id, 'session_not_completed'
    );
    RETURN;
  END IF;

  SELECT * INTO v_att
  FROM public.attendance a
  WHERE a.teaching_session_id = p_teaching_session_id
    AND a.enrollment_id = p_enrollment_id
    AND a.organization_id = p_org;

  IF NOT FOUND OR v_att.status <> 'present' THEN
    PERFORM public._cw2_periodic_reverse_session_consumption(
      p_org, p_enrollment_id, p_teaching_session_id, 'attendance_not_present'
    );
    RETURN;
  END IF;

  SELECT * INTO v_billing
  FROM public.enrollment_tuition_billing b
  WHERE b.organization_id = p_org AND b.enrollment_id = p_enrollment_id AND b.billing_mode = 'periodic';

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.enrollment_periodic_session_consumption c
    WHERE c.organization_id = p_org
      AND c.enrollment_id = p_enrollment_id
      AND c.teaching_session_id = p_teaching_session_id
      AND c.reversed_at IS NULL
  ) THEN
    RETURN;
  END IF;

  SELECT public.teaching_session_operational_date(
    v_sess.scheduled_start_at,
    (SELECT o.timezone FROM public.organization o WHERE o.id = p_org)
  ) INTO v_session_date;

  PERFORM public._cw2_periodic_activate_period_from_session(
    p_org, p_enrollment_id, v_session_date, v_billing
  );

  v_key := public._cw2_periodic_period_key(
    v_billing.period_unit, v_session_date, v_billing.organization_academic_year_id
  );

  IF EXISTS (
    SELECT 1 FROM public.enrollment_periodic_session_consumption c
    WHERE c.organization_id = p_org
      AND c.enrollment_id = p_enrollment_id
      AND c.teaching_session_id = p_teaching_session_id
      AND c.reversed_at IS NOT NULL
  ) THEN
    IF v_billing.period_unit = 'lesson' THEN
      UPDATE public.enrollment_periodic_tuition_balance
      SET lessons_remaining_in_block = GREATEST(COALESCE(lessons_remaining_in_block, 0) - 1, 0),
          updated_at = now()
      WHERE organization_id = p_org AND enrollment_id = p_enrollment_id
        AND COALESCE(lessons_remaining_in_block, 0) > 0;
      IF NOT FOUND THEN
        RETURN;
      END IF;
    END IF;
    UPDATE public.enrollment_periodic_session_consumption
    SET
      reversed_at = NULL,
      consumed_at = now(),
      enrollment_tuition_billing_id = v_billing.id,
      lesson_units_consumed = CASE WHEN v_billing.period_unit = 'lesson' THEN 1 ELSE 0 END,
      period_key = v_key
    WHERE organization_id = p_org
      AND enrollment_id = p_enrollment_id
      AND teaching_session_id = p_teaching_session_id;
  ELSE
    IF v_billing.period_unit = 'lesson' THEN
      UPDATE public.enrollment_periodic_tuition_balance
      SET lessons_remaining_in_block = GREATEST(COALESCE(lessons_remaining_in_block, 0) - 1, 0),
          updated_at = now()
      WHERE organization_id = p_org AND enrollment_id = p_enrollment_id
        AND COALESCE(lessons_remaining_in_block, 0) > 0;

      IF NOT FOUND THEN
        RETURN;
      END IF;
    END IF;

    INSERT INTO public.enrollment_periodic_session_consumption (
      organization_id, enrollment_id, teaching_session_id, enrollment_tuition_billing_id,
      lesson_units_consumed, period_key
    ) VALUES (
      p_org, p_enrollment_id, p_teaching_session_id, v_billing.id,
      CASE WHEN v_billing.period_unit = 'lesson' THEN 1 ELSE 0 END,
      v_key
    );
  END IF;

  INSERT INTO public.enrollment_periodic_consumption_audit (
    organization_id, enrollment_id, teaching_session_id, action, reason, actor_user_id
  ) VALUES (
    p_org, p_enrollment_id, p_teaching_session_id, 'consume', 'present_completed_session',
    public.current_app_user_id()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cw2_periodic_attendance_consumption_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status = 'present' AND NEW.status IS DISTINCT FROM 'present' THEN
    PERFORM public._cw2_periodic_reverse_session_consumption(
      NEW.organization_id, NEW.enrollment_id, NEW.teaching_session_id, 'attendance_corrected'
    );
  END IF;
  PERFORM public._cw2_periodic_try_consume_session(
    NEW.organization_id,
    NEW.enrollment_id,
    NEW.teaching_session_id
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.cw2_periodic_session_status_consumption_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status = 'completed' AND NEW.status IS DISTINCT FROM 'completed' THEN
    FOR r IN
      SELECT a.enrollment_id
      FROM public.attendance a
      WHERE a.teaching_session_id = NEW.id AND a.organization_id = NEW.organization_id
    LOOP
      PERFORM public._cw2_periodic_reverse_session_consumption(
        NEW.organization_id, r.enrollment_id, NEW.id, 'session_invalidated'
      );
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS cw2_periodic_attendance_consumption ON public.attendance;
CREATE TRIGGER cw2_periodic_attendance_consumption
  AFTER INSERT OR UPDATE OF status ON public.attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.cw2_periodic_attendance_consumption_trigger();

DROP TRIGGER IF EXISTS cw2_periodic_session_status ON public.teaching_session;
CREATE TRIGGER cw2_periodic_session_status
  AFTER UPDATE OF status ON public.teaching_session
  FOR EACH ROW
  EXECUTE FUNCTION public.cw2_periodic_session_status_consumption_trigger();

-- Allow payment schedule rewrite while establishing course tuition on active placeholder terms.
CREATE OR REPLACE FUNCTION public.protect_enrollment_payment_schedule_draft_only()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_terms_id uuid;
  v_status text;
BEGIN
  v_terms_id := COALESCE(NEW.enrollment_financial_terms_id, OLD.enrollment_financial_terms_id);

  IF current_setting('cw2.authoritative_tuition_establishment', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT status INTO v_status
  FROM enrollment_financial_terms
  WHERE id = v_terms_id;

  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Payment schedule can only be modified while financial terms are draft';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Allow first-time tuition plan establishment from zero-net active placeholder terms (CW2-T11).
CREATE OR REPLACE FUNCTION public.protect_enrollment_financial_terms_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status = 'active' THEN
    IF OLD.tuition_plan_established_at IS NULL
       AND NEW.tuition_plan_established_at IS NOT NULL
       AND COALESCE(OLD.net_tuition_amount, 0) = 0
    THEN
      RETURN NEW;
    END IF;
    IF NEW.agreed_tuition_amount IS DISTINCT FROM OLD.agreed_tuition_amount
       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.net_tuition_amount IS DISTINCT FROM OLD.net_tuition_amount
       OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
       OR NEW.payment_plan_mode IS DISTINCT FROM OLD.payment_plan_mode
       OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id
    THEN
      RAISE EXCEPTION 'Active enrollment financial terms cannot be silently rewritten; use financial_adjustment for corrections';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status IN ('superseded', 'cancelled') THEN
    IF NEW.agreed_tuition_amount IS DISTINCT FROM OLD.agreed_tuition_amount
       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.net_tuition_amount IS DISTINCT FROM OLD.net_tuition_amount
       OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
       OR NEW.payment_plan_mode IS DISTINCT FROM OLD.payment_plan_mode
       OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id
       OR NEW.status IS DISTINCT FROM OLD.status
    THEN
      RAISE EXCEPTION 'Historical enrollment financial terms are immutable';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Legacy 4-arg overload kept for immutable migration call sites until portfolio detail is patched.
CREATE OR REPLACE FUNCTION public._cw2_derive_tuition_payment_state(
  p_outstanding bigint,
  p_allocated bigint,
  p_declaration_status text,
  p_has_deposit_structure boolean
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN COALESCE(p_outstanding, 0) <= 0 AND COALESCE(p_allocated, 0) <= 0 THEN 'chua_coc'
    WHEN COALESCE(p_outstanding, 0) <= 0 THEN 'full_phi'
    WHEN p_has_deposit_structure AND COALESCE(p_allocated, 0) > 0 AND COALESCE(p_outstanding, 0) > 0 THEN 'da_coc'
    WHEN COALESCE(p_allocated, 0) > 0 AND COALESCE(p_outstanding, 0) > 0 THEN 'nop_phi'
    WHEN COALESCE(p_outstanding, 0) > 0 AND COALESCE(p_allocated, 0) = 0 THEN 'chua_coc'
    ELSE 'chua_coc'
  END;
$$;

CREATE OR REPLACE FUNCTION public.get_enrollment_operational_tuition_status(p_enrollment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_snap jsonb;
  v_state text;
  v_billing public.enrollment_tuition_billing%ROWTYPE;
  v_bal public.enrollment_periodic_tuition_balance%ROWTYPE;
  v_obligation bigint;
  v_satisfied bigint;
  v_outstanding bigint;
  v_label text;
  v_need_payment boolean := false;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.user_role ur
    JOIN public.role r ON r.id = ur.role_id AND r.organization_id = ur.organization_id
    WHERE ur.organization_id = v_org
      AND ur.user_id = public.current_app_user_id()
      AND ur.status = 'active'
      AND r.canonical_code = 'teacher'
  ) AND NOT EXISTS (
    SELECT 1
    FROM public.user_role ur
    JOIN public.role r ON r.id = ur.role_id AND r.organization_id = ur.organization_id
    WHERE ur.organization_id = v_org
      AND ur.user_id = public.current_app_user_id()
      AND ur.status = 'active'
      AND r.canonical_code IN (
        'academic_operations', 'accountant', 'consultant', 'center_manager', 'owner'
      )
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.enrollment e
    WHERE e.id = p_enrollment_id AND e.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'enrollment_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_snap := public._cw2_portfolio_finance_snapshot(v_org, p_enrollment_id);
  v_state := public._cw2_derive_tuition_payment_state(
    v_org,
    p_enrollment_id,
    COALESCE((v_snap->>'net_tuition')::bigint, 0),
    COALESCE((v_snap->>'course_outstanding_amount')::bigint, 0),
    COALESCE((v_snap->>'allocated_amount')::bigint, 0),
    COALESCE((v_snap->>'pending_declaration_amount')::bigint, 0)
  );

  SELECT * INTO v_billing
  FROM public.enrollment_tuition_billing b
  WHERE b.organization_id = v_org AND b.enrollment_id = p_enrollment_id;

  SELECT * INTO v_bal
  FROM public.enrollment_periodic_tuition_balance b
  WHERE b.organization_id = v_org AND b.enrollment_id = p_enrollment_id;

  SELECT o.obligation_amount, o.satisfied_amount
  INTO v_obligation, v_satisfied
  FROM public.enrollment_periodic_period_obligation o
  WHERE o.organization_id = v_org
    AND o.enrollment_id = p_enrollment_id
    AND o.status IN ('open', 'underpaid')
  ORDER BY o.created_at DESC
  LIMIT 1;

  v_outstanding := GREATEST(COALESCE(v_obligation, 0) - COALESCE(v_satisfied, 0), 0);
  v_label := public._cw2_tuition_payment_state_label(v_state);
  v_need_payment := v_state IN ('chua_coc', 'con_thieu', 'het_hoc_phi', 'coc_cho_xac_nhan', 'cho_xac_nhan')
    OR v_outstanding > 0;

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'tuition_mode', COALESCE(v_billing.billing_mode, 'unset'),
    'operational_status', v_state,
    'operational_status_label', v_label,
    'lessons_remaining', v_bal.lessons_remaining_in_block,
    'period_outstanding_amount', v_outstanding,
    'carry_forward_credit', COALESCE(v_bal.carry_forward_credit, 0),
    'need_payment', v_need_payment
  );
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_periodic_try_consume_session(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_reverse_session_consumption(uuid, uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_ensure_obligation(uuid, uuid, text, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_apply_confirmed_payment(uuid, uuid, bigint, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_activate_period_from_session(uuid, uuid, date, public.enrollment_tuition_billing) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_enrollment_operational_tuition_status(uuid) TO authenticated;
