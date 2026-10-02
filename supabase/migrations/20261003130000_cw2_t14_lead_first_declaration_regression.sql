-- CW2-T14 (migration 90): lead-first tuition declaration save regression.
--
-- Since CW2-T12 the portfolio read model exposes primary_guardian_id as the
-- primary lead_contact id for lead-only rows. The drawer forwards that id as
-- p_guardian_id, which violates consultant_revenue_declaration_org_guardian_fk.
-- First declarations without a proposed course total also sent
-- p_total_obligation_amount = 0, violating consultant_revenue_declaration_obligation_nonneg.
--
-- save_consultant_payment_declaration_draft now only accepts a guardian id that
-- is an organization guardian (otherwise the lead contact is resolved as in
-- CW2-T11 hotfix), and treats a non-positive obligation as "not proposed".
--
-- Accounting confirmation of a consultant-intake lead also failed: intake leads
-- have no identity resolution (identity_not_ready), and convert_lead's duplicate
-- check requires lead.read, which Accounting lacks. Inside a scoped CW2
-- confirmation, unresolved identities without a strong duplicate are now
-- resolved (candidate create_new; primary contact linked to the declaration
-- guardian), and the duplicate checks may run. Strong duplicates still block.

CREATE OR REPLACE FUNCTION public._cw2_t14_valid_declaration_guardian(
  p_org uuid,
  p_guardian_id uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT g.id
  FROM public.guardian g
  WHERE p_guardian_id IS NOT NULL
    AND p_org = public.current_organization_id()
    AND g.organization_id = p_org
    AND g.id = p_guardian_id;
$$;

REVOKE ALL ON FUNCTION public._cw2_t14_valid_declaration_guardian(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_t14_valid_declaration_guardian(uuid, uuid) TO authenticated;

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
  v_guardian uuid;
  v_obligation numeric := CASE WHEN p_total_obligation_amount > 0 THEN p_total_obligation_amount END;
  v_lead_intake boolean := p_enrollment_id IS NULL AND p_lead_id IS NOT NULL;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  v_org := public.current_organization_id();
  v_user := public.current_app_user_id();
  v_guardian := public._cw2_t14_valid_declaration_guardian(v_org, p_guardian_id);

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
      COALESCE(v_obligation, p_proposed_net_tuition_amount, v_initial_pending.proposed_net_tuition_amount),
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
    guardian_id = COALESCE(v_guardian, d.guardian_id),
    total_obligation_amount = COALESCE(v_obligation, d.total_obligation_amount),
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

CREATE OR REPLACE FUNCTION public._cw2_t14_lead_in_confirm_scope(p_lead_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_lead_id IS NOT NULL
    AND NULLIF(current_setting('cw2.declaration_confirm', true), '') IS NOT NULL
    AND public.has_permission('payment.record')
    AND public.has_permission('consultant_revenue.review')
    AND EXISTS (
      SELECT 1 FROM public.consultant_revenue_declaration d
      WHERE d.id = NULLIF(current_setting('cw2.declaration_confirm', true), '')::uuid
        AND d.organization_id = public.current_organization_id()
        AND d.lead_id = p_lead_id
        AND d.workflow_kind = 'cw2_payment'
        AND d.status = 'pending'
        AND d.submitted_at IS NOT NULL
    );
$$;

REVOKE ALL ON FUNCTION public._cw2_t14_lead_in_confirm_scope(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_t14_lead_in_confirm_scope(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.find_student_matches_for_lead_candidate(
  p_lead_candidate_id uuid
)
RETURNS TABLE (
  student_id uuid,
  given_name text,
  family_name text,
  date_of_birth date,
  student_code text,
  status text,
  match_confidence text,
  match_reasons text[],
  sort_rank integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_candidate lead_candidate%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT * INTO v_candidate
  FROM lead_candidate
  WHERE id = p_lead_candidate_id AND organization_id = v_org_id;

  IF NOT public.has_permission('lead.read')
     AND NOT public._cw2_t14_lead_in_confirm_scope(v_candidate.lead_id) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF v_candidate.id IS NULL THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  WITH direct_matches AS (
    SELECT
      s.id AS student_id,
      s.given_name,
      s.family_name,
      s.date_of_birth,
      s.student_code,
      s.status,
      CASE
        WHEN v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth IS NOT NULL
             AND s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 'strong'
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
          THEN 'possible'
        ELSE NULL
      END AS confidence,
      CASE
        WHEN v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth IS NOT NULL
             AND s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN ARRAY['same_name_and_dob']::text[]
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
          THEN ARRAY['same_name']::text[]
        ELSE ARRAY[]::text[]
      END AS match_reasons,
      CASE
        WHEN v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth IS NOT NULL
             AND s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 2
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
          THEN 1
        ELSE 0
      END AS sort_rank
    FROM student s
    WHERE s.organization_id = v_org_id
      AND (
        (s.given_name = v_candidate.given_name AND s.family_name = v_candidate.family_name)
      )
  ),
  guardian_link_matches AS (
    SELECT
      s.id AS student_id,
      s.given_name,
      s.family_name,
      s.date_of_birth,
      s.student_code,
      s.status,
      CASE
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 'strong'
        ELSE 'possible'
      END AS confidence,
      ARRAY['linked_via_guardian_contact']::text[] AS match_reasons,
      CASE
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 2
        ELSE 1
      END AS sort_rank
    FROM lead_contact lc
    JOIN guardian g
      ON g.organization_id = lc.organization_id
     AND (
       (lc.phone_normalized IS NOT NULL
         AND public.normalize_phone_digits(g.phone) = lc.phone_normalized
         AND length(lc.phone_normalized) >= 4)
       OR (lc.email_normalized IS NOT NULL
         AND public.normalize_email_key(g.email) = lc.email_normalized)
     )
    JOIN student_guardian sg
      ON sg.organization_id = g.organization_id
     AND sg.guardian_id = g.id
     AND sg.status = 'active'
    JOIN student s
      ON s.organization_id = sg.organization_id
     AND s.id = sg.student_id
    WHERE lc.organization_id = v_org_id
      AND lc.lead_id = v_candidate.lead_id
      AND lc.status = 'active'
      AND (
        s.given_name = v_candidate.given_name
        OR s.family_name = v_candidate.family_name
      )
  ),
  combined AS (
    SELECT * FROM direct_matches dm WHERE dm.confidence IS NOT NULL
    UNION ALL
    SELECT * FROM guardian_link_matches
  ),
  ranked AS (
    SELECT
      c.student_id,
      c.given_name,
      c.family_name,
      c.date_of_birth,
      c.student_code,
      c.status,
      c.confidence,
      c.match_reasons,
      c.sort_rank,
      ROW_NUMBER() OVER (
        PARTITION BY c.student_id
        ORDER BY c.sort_rank DESC,
          CASE c.confidence WHEN 'strong' THEN 2 ELSE 1 END DESC
      ) AS rn
    FROM combined c
  )
  SELECT
    r.student_id,
    r.given_name,
    r.family_name,
    r.date_of_birth,
    r.student_code,
    r.status,
    r.confidence AS match_confidence,
    r.match_reasons,
    r.sort_rank
  FROM ranked r
  WHERE r.rn = 1
  ORDER BY r.sort_rank DESC, r.family_name, r.given_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.find_guardian_matches_for_lead_contact(
  p_lead_contact_id uuid
)
RETURNS TABLE (
  guardian_id uuid,
  given_name text,
  family_name text,
  phone text,
  email text,
  status text,
  match_confidence text,
  match_reasons text[],
  sort_rank integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_contact lead_contact%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT * INTO v_contact
  FROM lead_contact
  WHERE id = p_lead_contact_id AND organization_id = v_org_id;

  IF NOT public.has_permission('lead.read')
     AND NOT public._cw2_t14_lead_in_confirm_scope(v_contact.lead_id) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF v_contact.id IS NULL THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  WITH matches AS (
    SELECT
      g.id AS guardian_id,
      g.given_name,
      g.family_name,
      g.phone,
      g.email,
      g.status,
      CASE
        WHEN v_contact.phone_normalized IS NOT NULL
             AND length(v_contact.phone_normalized) >= 4
             AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized
          THEN 'strong'
        WHEN v_contact.email_normalized IS NOT NULL
             AND public.normalize_email_key(g.email) = v_contact.email_normalized
          THEN 'strong'
        WHEN g.given_name = v_contact.given_name
             AND g.family_name = v_contact.family_name
          THEN 'possible'
        ELSE NULL
      END AS confidence,
      CASE
        WHEN v_contact.phone_normalized IS NOT NULL
             AND length(v_contact.phone_normalized) >= 4
             AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized
          THEN ARRAY['same_phone']::text[]
        WHEN v_contact.email_normalized IS NOT NULL
             AND public.normalize_email_key(g.email) = v_contact.email_normalized
          THEN ARRAY['same_email']::text[]
        WHEN g.given_name = v_contact.given_name
             AND g.family_name = v_contact.family_name
          THEN ARRAY['same_name']::text[]
        ELSE ARRAY[]::text[]
      END AS match_reasons,
      CASE
        WHEN v_contact.phone_normalized IS NOT NULL
             AND length(v_contact.phone_normalized) >= 4
             AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized
          THEN 3
        WHEN v_contact.email_normalized IS NOT NULL
             AND public.normalize_email_key(g.email) = v_contact.email_normalized
          THEN 3
        WHEN g.given_name = v_contact.given_name
             AND g.family_name = v_contact.family_name
          THEN 1
        ELSE 0
      END AS sort_rank
    FROM guardian g
    WHERE g.organization_id = v_org_id
      AND (
        (v_contact.phone_normalized IS NOT NULL
          AND length(v_contact.phone_normalized) >= 4
          AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized)
        OR (v_contact.email_normalized IS NOT NULL
          AND public.normalize_email_key(g.email) = v_contact.email_normalized)
        OR (g.given_name = v_contact.given_name AND g.family_name = v_contact.family_name)
      )
  )
  SELECT
    m.guardian_id,
    m.given_name,
    m.family_name,
    m.phone,
    m.email,
    m.status,
    m.confidence AS match_confidence,
    m.match_reasons,
    m.sort_rank
  FROM matches m
  WHERE m.confidence IS NOT NULL
  ORDER BY m.sort_rank DESC, m.family_name, m.given_name;
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_t14_prepare_confirm_lead_identity(
  p_declaration public.consultant_revenue_declaration
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_actor uuid := public.current_app_user_id();
  v_candidate public.lead_candidate%ROWTYPE;
  v_contact public.lead_contact%ROWTYPE;
  v_note constant text := 'CW2 accounting confirmation';
BEGIN
  IF p_declaration.lead_id IS NULL
     OR p_declaration.organization_id IS DISTINCT FROM v_org
     OR NOT public._cw2_t14_lead_in_confirm_scope(p_declaration.lead_id) THEN
    RETURN;
  END IF;

  PERFORM set_config('olli.lead_identity_mutation', 'true', true);
  BEGIN
    FOR v_candidate IN
      SELECT lc.*
      FROM public.lead_candidate lc
      WHERE lc.organization_id = v_org
        AND lc.lead_id = p_declaration.lead_id
        AND lc.status = 'active'
        AND NOT EXISTS (
          SELECT 1 FROM public.lead_candidate_identity_resolution r
          WHERE r.organization_id = lc.organization_id AND r.lead_candidate_id = lc.id
        )
    LOOP
      CONTINUE WHEN EXISTS (
        SELECT 1 FROM public.find_student_matches_for_lead_candidate(v_candidate.id) m
        WHERE m.match_confidence = 'strong'
      );
      PERFORM public.append_lead_identity_resolution_event(
        'candidate', v_candidate.id, NULL, 'create_new', NULL, NULL, v_note
      );
      INSERT INTO public.lead_candidate_identity_resolution (
        organization_id, lead_candidate_id, resolution_mode, student_id,
        is_stale, strong_match_acknowledged, identity_snapshot, resolved_by
      ) VALUES (
        v_org, v_candidate.id, 'create_new', NULL, false, false,
        public.build_lead_candidate_identity_snapshot(
          v_candidate.given_name, v_candidate.family_name, v_candidate.date_of_birth
        ),
        v_actor
      );
    END LOOP;

    FOR v_contact IN
      SELECT lc.*
      FROM public.lead_contact lc
      WHERE lc.organization_id = v_org
        AND lc.lead_id = p_declaration.lead_id
        AND lc.status = 'active'
        AND NOT EXISTS (
          SELECT 1 FROM public.lead_contact_identity_resolution r
          WHERE r.organization_id = lc.organization_id AND r.lead_contact_id = lc.id
        )
    LOOP
      IF v_contact.is_primary_contact
         AND p_declaration.guardian_id IS NOT NULL
         AND public.is_eligible_identity_guardian(p_declaration.guardian_id) THEN
        PERFORM public.append_lead_identity_resolution_event(
          'contact', v_contact.id, NULL, 'use_existing', NULL, p_declaration.guardian_id, v_note
        );
        INSERT INTO public.lead_contact_identity_resolution (
          organization_id, lead_contact_id, resolution_mode, guardian_id,
          is_stale, strong_match_acknowledged, identity_snapshot, resolved_by
        ) VALUES (
          v_org, v_contact.id, 'use_existing', p_declaration.guardian_id, false, false,
          public.build_lead_contact_identity_snapshot(
            v_contact.given_name, v_contact.family_name, v_contact.phone, v_contact.email
          ),
          v_actor
        );
      ELSIF NOT EXISTS (
        SELECT 1 FROM public.find_guardian_matches_for_lead_contact(v_contact.id) m
        WHERE m.match_confidence = 'strong'
      ) THEN
        PERFORM public.append_lead_identity_resolution_event(
          'contact', v_contact.id, NULL, 'create_new', NULL, NULL, v_note
        );
        INSERT INTO public.lead_contact_identity_resolution (
          organization_id, lead_contact_id, resolution_mode, guardian_id,
          is_stale, strong_match_acknowledged, identity_snapshot, resolved_by
        ) VALUES (
          v_org, v_contact.id, 'create_new', NULL, false, false,
          public.build_lead_contact_identity_snapshot(
            v_contact.given_name, v_contact.family_name, v_contact.phone, v_contact.email
          ),
          v_actor
        );
      END IF;
    END LOOP;
    PERFORM set_config('olli.lead_identity_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_identity_mutation', 'false', true);
    RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_t14_prepare_confirm_lead_identity(public.consultant_revenue_declaration) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_t14_prepare_confirm_lead_identity(public.consultant_revenue_declaration) TO authenticated;

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
    PERFORM public._cw2_t14_prepare_confirm_lead_identity(v_row);
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
