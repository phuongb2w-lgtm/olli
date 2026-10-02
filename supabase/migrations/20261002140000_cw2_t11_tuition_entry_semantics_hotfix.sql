-- CW2-T11 hotfix (migration 84): consultant tuition entry semantics — Chưa nộp phí, lead-first declaration.

DROP FUNCTION IF EXISTS public._cw2_portfolio_row_tuition_fields(
  uuid, uuid, uuid, numeric, bigint, bigint, bigint, text, boolean, text, text, integer, bigint
);
DROP FUNCTION IF EXISTS public._cw2_portfolio_declaration_capabilities(
  uuid, uuid, uuid, bigint, bigint, bigint, bigint, text, boolean, text
);
DROP FUNCTION IF EXISTS public._cw2_portfolio_declaration_capabilities(
  uuid, bigint, text, boolean, text
);

CREATE OR REPLACE FUNCTION public._cw2_tuition_payment_state_label(p_state text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE p_state
    WHEN 'chua_nop_phi' THEN 'Chưa nộp phí'
    WHEN 'chua_coc' THEN 'Chưa nộp phí'
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

CREATE OR REPLACE FUNCTION public._cw2_derive_lead_only_tuition_state(
  p_org uuid,
  p_lead_id uuid,
  p_consultant uuid,
  p_declaration_status text
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.consultant_revenue_declaration%ROWTYPE;
BEGIN
  IF p_lead_id IS NULL THEN
    RETURN 'chua_nop_phi';
  END IF;

  IF COALESCE(p_declaration_status, '') = 'pending' THEN
    SELECT * INTO v_row
    FROM public.consultant_revenue_declaration d
    WHERE d.organization_id = p_org
      AND d.lead_id = p_lead_id
      AND d.consultant_user_id = p_consultant
      AND d.workflow_kind = 'cw2_payment'
      AND d.status = 'pending'
      AND d.enrollment_id IS NULL
    ORDER BY d.submitted_at DESC NULLS LAST, d.created_at DESC
    LIMIT 1;
    IF FOUND AND v_row.declaration_kind = 'initial_tuition_setup' THEN
      RETURN 'coc_cho_xac_nhan';
    END IF;
    IF FOUND THEN
      RETURN 'cho_xac_nhan';
    END IF;
  END IF;

  RETURN 'chua_nop_phi';
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
    RETURN 'chua_nop_phi';
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
    RETURN 'chua_nop_phi';
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

  RETURN 'chua_nop_phi';
END;
$$;

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
    WHEN COALESCE(p_outstanding, 0) <= 0 AND COALESCE(p_allocated, 0) <= 0 THEN 'chua_nop_phi'
    WHEN COALESCE(p_outstanding, 0) <= 0 THEN 'full_phi'
    WHEN p_has_deposit_structure AND COALESCE(p_allocated, 0) > 0 AND COALESCE(p_outstanding, 0) > 0 THEN 'da_coc'
    WHEN COALESCE(p_allocated, 0) > 0 AND COALESCE(p_outstanding, 0) > 0 THEN 'nop_phi'
    WHEN COALESCE(p_outstanding, 0) > 0 AND COALESCE(p_allocated, 0) = 0 THEN 'chua_nop_phi'
    ELSE 'chua_nop_phi'
  END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_resolve_lead_declaration_guardian(p_org uuid, p_lead_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lc public.lead_contact%ROWTYPE;
  v_guardian uuid;
BEGIN
  IF p_lead_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_lc
  FROM public.lead_contact lc
  WHERE lc.organization_id = p_org
    AND lc.lead_id = p_lead_id
    AND lc.is_primary_contact = true
  ORDER BY lc.created_at
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_lc.converted_guardian_id IS NOT NULL THEN
    RETURN v_lc.converted_guardian_id;
  END IF;

  INSERT INTO public.guardian (
    organization_id, family_name, given_name, phone, email
  ) VALUES (
    p_org, v_lc.family_name, v_lc.given_name, v_lc.phone, v_lc.email
  )
  RETURNING id INTO v_guardian;

  RETURN v_guardian;
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_resolve_lead_declaration_guardian(uuid, uuid) FROM PUBLIC;

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
  p_student_code_raw text DEFAULT NULL,
  p_lead_id uuid DEFAULT NULL,
  p_consultant_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_state text;
  v_can_declare boolean := public.has_permission('consultant_revenue.declare');
  v_has_context boolean;
BEGIN
  IF p_enrollment_id IS NULL AND p_lead_id IS NOT NULL AND p_consultant_user_id IS NOT NULL THEN
    v_state := public._cw2_derive_lead_only_tuition_state(
      p_org, p_lead_id, p_consultant_user_id, p_declaration_status
    );
    v_has_context := true;
  ELSE
    v_state := public._cw2_derive_tuition_payment_state(
      p_org, p_enrollment_id, p_net_tuition, p_outstanding, p_allocated, p_pending_declaration
    );
    v_has_context := p_enrollment_id IS NOT NULL;
  END IF;

  RETURN jsonb_build_object(
    'can_edit_contact', public._cw2_portfolio_can_edit_contact(p_student_code_raw),
    'can_open_payment_declaration', v_can_declare AND v_has_context AND v_state <> 'full_phi',
    'can_create_payment_declaration', v_can_declare AND v_has_context AND v_state <> 'full_phi'
      AND COALESCE(p_declaration_status, '') NOT IN ('draft', 'returned'),
    'can_edit_payment_declaration', v_can_declare
      AND p_declaration_status IN ('draft', 'returned'),
    'can_submit_declaration', v_can_declare
      AND p_declaration_status IN ('draft', 'returned'),
    'can_add_payment', false,
    'can_open_student_details', p_has_student
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_portfolio_declaration_capabilities(
  p_enrollment_financial_terms_id uuid,
  p_outstanding bigint,
  p_declaration_status text,
  p_has_student boolean,
  p_student_code_raw text DEFAULT NULL,
  p_lead_id uuid DEFAULT NULL,
  p_consultant_user_id uuid DEFAULT NULL
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
    IF p_lead_id IS NOT NULL THEN
      RETURN public._cw2_portfolio_declaration_capabilities(
        v_org, NULL, NULL, 0, 0, 0, 0, p_declaration_status, p_has_student, p_student_code_raw,
        p_lead_id, COALESCE(p_consultant_user_id, public.current_app_user_id())
      );
    END IF;
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
    v_org, v_enrollment_id, p_enrollment_financial_terms_id, v_outstanding, v_net,
    v_allocated, v_pending, p_declaration_status, p_has_student, p_student_code_raw,
    NULL, NULL
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_portfolio_row_tuition_fields(
  p_org uuid,
  p_enrollment_id uuid,
  p_enrollment_financial_terms_id uuid,
  p_net_tuition numeric,
  p_outstanding bigint,
  p_allocated bigint,
  p_pending bigint,
  p_declaration_status text,
  p_has_student boolean,
  p_student_code_raw text,
  p_billing_mode text,
  p_periodic_lessons_remaining integer,
  p_carry_forward_credit bigint,
  p_lead_id uuid DEFAULT NULL,
  p_consultant_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_state text;
BEGIN
  IF p_enrollment_id IS NULL AND p_lead_id IS NOT NULL AND p_consultant_user_id IS NOT NULL THEN
    v_state := public._cw2_derive_lead_only_tuition_state(
      p_org, p_lead_id, p_consultant_user_id, p_declaration_status
    );
  ELSE
    v_state := public._cw2_derive_tuition_payment_state(
      p_org, p_enrollment_id, COALESCE(p_net_tuition, 0)::bigint, p_outstanding, p_allocated, p_pending
    );
  END IF;

  RETURN jsonb_build_object(
    'tuition_total_net', COALESCE(p_net_tuition, 0),
    'tuition_paid', COALESCE(p_allocated, 0),
    'tuition_outstanding', COALESCE(p_outstanding, 0),
    'tuition_pending_declaration', COALESCE(p_pending, 0),
    'tuition_payment_state', v_state,
    'tuition_payment_state_label', public._cw2_tuition_payment_state_label(v_state),
    'tuition_billing_mode', p_billing_mode,
    'tuition_periodic_lessons_remaining', p_periodic_lessons_remaining,
    'tuition_carry_forward_credit', COALESCE(p_carry_forward_credit, 0),
    'capabilities', public._cw2_portfolio_declaration_capabilities(
      p_org,
      p_enrollment_id,
      p_enrollment_financial_terms_id,
      p_outstanding,
      COALESCE(p_net_tuition, 0)::bigint,
      p_allocated,
      p_pending,
      p_declaration_status,
      p_has_student,
      p_student_code_raw,
      p_lead_id,
      p_consultant_user_id
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_ensure_declaration_enrollment_for_confirm(
  p_org uuid,
  p_row public.consultant_revenue_declaration
)
RETURNS public.consultant_revenue_declaration
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_class uuid;
  v_enrollment uuid;
  v_row public.consultant_revenue_declaration := p_row;
BEGIN
  IF v_row.enrollment_id IS NOT NULL OR v_row.student_id IS NULL THEN
    RETURN v_row;
  END IF;

  v_class := v_row.class_id;
  IF v_class IS NULL AND v_row.course_id IS NOT NULL THEN
    SELECT c.id INTO v_class
    FROM public.class c
    WHERE c.organization_id = p_org
      AND c.course_id = p_row.course_id
      AND c.status = 'active'
    ORDER BY c.created_at
    LIMIT 1;
  END IF;

  IF v_class IS NULL THEN
    SELECT c.id INTO v_class
    FROM public.class c
    WHERE c.organization_id = p_org
      AND c.status = 'active'
    ORDER BY c.created_at
    LIMIT 1;
  END IF;

  IF v_class IS NULL THEN
    RAISE EXCEPTION 'declaration_enrollment_context_required' USING ERRCODE = 'P0001';
  END IF;

  SELECT e.id INTO v_enrollment
  FROM public.enrollment e
  WHERE e.organization_id = p_org
    AND e.student_id = v_row.student_id
    AND e.class_id = v_class
    AND e.status = 'active'
  LIMIT 1;

  IF v_enrollment IS NULL THEN
    INSERT INTO public.enrollment (
      organization_id, student_id, class_id, start_date, status
    ) VALUES (
      p_org, v_row.student_id, v_class, COALESCE(v_row.declaration_date, CURRENT_DATE), 'active'
    )
    RETURNING id INTO v_enrollment;
  END IF;

  UPDATE public.consultant_revenue_declaration
  SET enrollment_id = v_enrollment,
      class_id = COALESCE(class_id, v_class),
      updated_at = now()
  WHERE id = v_row.id AND organization_id = p_org
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_ensure_declaration_enrollment_for_confirm(uuid, public.consultant_revenue_declaration) FROM PUBLIC;

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
    RETURN 'chua_nop_phi';
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

-- list_consultant_workspace_portfolio patch
CREATE OR REPLACE FUNCTION public.list_consultant_workspace_portfolio(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_sort_field text DEFAULT 'workspace_sequence',
  p_sort_direction text DEFAULT 'desc',
  p_limit integer DEFAULT 50,
  p_cursor_workspace_sequence bigint DEFAULT NULL,
  p_cursor_portfolio_entry_id uuid DEFAULT NULL,
  p_include_hidden boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_consultant uuid;
  v_limit integer;
  v_sort text;
  v_dir text;
  v_rows jsonb;
  v_next_seq bigint;
  v_next_id uuid;
  v_has_more boolean := false;
BEGIN
  v_org := public.current_organization_id();
  v_consultant := COALESCE(
    NULLIF(p_filters->>'consultant_user_id', '')::uuid,
    public.current_app_user_id()
  );
  PERFORM public._cw2_assert_consultant_workspace_list_access(v_consultant);

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_sort := lower(COALESCE(NULLIF(btrim(p_sort_field), ''), 'workspace_sequence'));
  v_dir := lower(COALESCE(NULLIF(btrim(p_sort_direction), ''), 'desc'));
  IF v_sort NOT IN (
    'workspace_sequence', 'family_name', 'given_name', 'lifecycle_status',
    'student_code', 'tuition_outstanding', 'portfolio_entered_at'
  ) THEN
    RAISE EXCEPTION 'invalid_sort_field' USING ERRCODE = 'P0001';
  END IF;
  IF v_dir NOT IN ('asc', 'desc') THEN
    RAISE EXCEPTION 'invalid_sort_direction' USING ERRCODE = 'P0001';
  END IF;

  WITH base AS (
    SELECT
      e.id AS portfolio_entry_id,
      e.workspace_sequence,
      e.portfolio_entered_at,
      e.lead_id,
      e.student_id,
      CASE WHEN e.student_id IS NOT NULL THEN 'student' ELSE 'lead' END AS subject_type,
      COALESCE(e.student_id, e.lead_id) AS display_subject_id,
      s.given_name AS student_given_name,
      s.family_name AS student_family_name,
      s.date_of_birth AS student_dob,
      s.status AS student_status,
      s.student_code AS student_code_raw,
      lc.given_name AS lead_given_name,
      lc.family_name AS lead_family_name,
      lc.date_of_birth AS lead_dob,
      COALESCE(s.family_name, lc.family_name) AS family_name,
      COALESCE(s.given_name, lc.given_name) AS given_name,
      COALESCE(s.date_of_birth, lc.date_of_birth) AS date_of_birth,
      (h.subject_id IS NOT NULL) AS is_hidden,
      pe.enrollment_id,
      pe.enrollment_financial_terms_id,
      pe.course_id,
      pe.course_name,
      pe.class_id,
      pe.class_name,
      fin.net_tuition,
      fin.allocated_amount,
      fin.outstanding_amount,
      fin.has_deposit_structure,
      fin.pending_declaration_amount,
      fin.billing_mode,
      fin.periodic_lessons_remaining,
      fin.carry_forward_credit,
      d.id AS declaration_id,
      d.status AS declaration_status,
      d.workflow_kind AS declaration_workflow_kind,
      EXISTS (
        SELECT 1 FROM public.enrollment en
        WHERE en.student_id = e.student_id
          AND en.organization_id = v_org
          AND en.status = 'active'
      ) AS has_active_enrollment,
      g.id AS primary_guardian_id,
      trim(both FROM COALESCE(g.given_name, '') || ' ' || COALESCE(g.family_name, '')) AS primary_guardian_name,
            g.phone AS primary_guardian_phone,
      lcg.phone AS lead_contact_phone,
      au.consultant_operational_code AS consultant_code
    FROM public.consultant_portfolio_entry e
    LEFT JOIN public.consultant_grid_hidden_row h
      ON h.organization_id = e.organization_id
     AND h.app_user_id = public.current_app_user_id()
     AND h.subject_type = CASE WHEN e.student_id IS NOT NULL THEN 'student' ELSE 'lead' END
     AND h.subject_id = COALESCE(e.student_id, e.lead_id)
    LEFT JOIN public.student s
      ON s.id = e.student_id AND s.organization_id = e.organization_id
    LEFT JOIN LATERAL (
      SELECT c.*
      FROM public.lead_candidate c
      WHERE c.lead_id = e.lead_id
        AND c.organization_id = e.organization_id
        AND c.status = 'active'
      ORDER BY c.is_primary_candidate DESC, c.created_at
      LIMIT 1
    ) lc ON e.lead_id IS NOT NULL
    LEFT JOIN LATERAL public._cw2_portfolio_pick_enrollment(v_org, e.student_id) pe ON e.student_id IS NOT NULL
    LEFT JOIN LATERAL (
      SELECT
        (snap->>'net_tuition')::numeric AS net_tuition,
        (snap->>'allocated_amount')::bigint AS allocated_amount,
        COALESCE((snap->>'course_outstanding_amount')::bigint, 0) AS outstanding_amount,
        COALESCE((snap->>'has_deposit_structure')::boolean, false) AS has_deposit_structure,
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
      WHERE sg.student_id = e.student_id
        AND sg.organization_id = e.organization_id
        AND sg.is_primary_contact = true
      ORDER BY sg.created_at
      LIMIT 1
    ) sg ON e.student_id IS NOT NULL
    LEFT JOIN public.guardian g
      ON g.id = sg.guardian_id AND g.organization_id = e.organization_id
        LEFT JOIN LATERAL (
      SELECT lc2.phone
      FROM public.lead_contact lc2
      WHERE lc2.lead_id = e.lead_id
        AND lc2.organization_id = e.organization_id
        AND lc2.is_primary_contact = true
      ORDER BY lc2.created_at
      LIMIT 1
    ) lcg ON e.student_id IS NULL
    JOIN public.app_user au
      ON au.id = e.consultant_user_id AND au.organization_id = e.organization_id
    WHERE e.organization_id = v_org
      AND e.consultant_user_id = v_consultant
      AND (p_include_hidden OR h.subject_id IS NULL)
      AND (
        v_sort <> 'workspace_sequence'
        OR v_dir <> 'desc'
        OR p_cursor_workspace_sequence IS NULL
        OR e.workspace_sequence < p_cursor_workspace_sequence
        OR (e.workspace_sequence = p_cursor_workspace_sequence AND e.id < p_cursor_portfolio_entry_id)
      )
      AND (
        NULLIF(p_filters->>'lifecycle_status', '') IS NULL
        OR public._cw2_derive_workspace_lifecycle_status(
          e.student_id,
          s.status,
          public._cw2_is_official_student_code(s.student_code),
          EXISTS (
            SELECT 1 FROM public.enrollment en
            WHERE en.student_id = e.student_id AND en.organization_id = v_org AND en.status = 'active'
          )
        ) = p_filters->>'lifecycle_status'
      )
      AND (
        NULLIF(p_filters->>'tuition_payment_state', '') IS NULL
        OR public._cw2_derive_tuition_payment_state(
          v_org,
          pe.enrollment_id,
          COALESCE(fin.net_tuition, 0)::bigint,
          fin.outstanding_amount,
          fin.allocated_amount,
          fin.pending_declaration_amount
        ) = p_filters->>'tuition_payment_state'
        OR (
          p_filters->>'tuition_payment_state' = 'cho_xac_nhan'
          AND COALESCE(fin.pending_declaration_amount, 0) > 0
        )
      )
      AND (
        NULLIF(p_filters->>'declaration_status', '') IS NULL
        OR d.status::text = p_filters->>'declaration_status'
      )
      AND (
        NULLIF(p_filters->>'course_id', '') IS NULL
        OR pe.course_id = (p_filters->>'course_id')::uuid
      )
            AND (
        NULLIF(btrim(p_filters->>'family_name'), '') IS NULL
        OR lower(COALESCE(s.family_name, lc.family_name, ''))
           LIKE '%' || lower(btrim(p_filters->>'family_name')) || '%'
      )
      AND (
        NULLIF(btrim(p_filters->>'given_name'), '') IS NULL
        OR lower(COALESCE(s.given_name, lc.given_name, ''))
           LIKE '%' || lower(btrim(p_filters->>'given_name')) || '%'
      )
      AND (
        NULLIF(btrim(p_filters->>'name_search'), '') IS NULL
        OR lower(COALESCE(s.family_name, lc.family_name, '') || ' ' || COALESCE(s.given_name, lc.given_name, ''))
           LIKE '%' || lower(btrim(p_filters->>'name_search')) || '%'
      )
      AND (
        NULLIF(btrim(p_filters->>'student_code'), '') IS NULL
        OR COALESCE(
          CASE WHEN public._cw2_is_official_student_code(s.student_code) THEN btrim(s.student_code) END,
          public._cw2_provisional_student_code_display(au.consultant_operational_code, COALESCE(s.date_of_birth, lc.date_of_birth))
        ) ILIKE '%' || btrim(p_filters->>'student_code') || '%'
      )
      AND (
        NULLIF(btrim(p_filters->>'guardian_phone'), '') IS NULL
        OR COALESCE(g.phone, lcg.phone) ILIKE '%' || btrim(p_filters->>'guardian_phone') || '%'
      )
  ),
  ordered AS (
    SELECT *
    FROM base
    ORDER BY
      CASE WHEN v_sort = 'workspace_sequence' AND v_dir = 'desc' THEN workspace_sequence END DESC NULLS LAST,
      CASE WHEN v_sort = 'workspace_sequence' AND v_dir = 'asc' THEN workspace_sequence END ASC NULLS LAST,
      CASE WHEN v_sort = 'family_name' AND v_dir = 'desc' THEN family_name END DESC NULLS LAST,
      CASE WHEN v_sort = 'family_name' AND v_dir = 'asc' THEN family_name END ASC NULLS LAST,
      CASE WHEN v_sort = 'given_name' AND v_dir = 'desc' THEN given_name END DESC NULLS LAST,
      CASE WHEN v_sort = 'given_name' AND v_dir = 'asc' THEN given_name END ASC NULLS LAST,
      CASE WHEN v_sort = 'lifecycle_status' AND v_dir = 'desc' THEN public._cw2_derive_workspace_lifecycle_status(student_id, student_status, public._cw2_is_official_student_code(student_code_raw), has_active_enrollment) END DESC,
      CASE WHEN v_sort = 'lifecycle_status' AND v_dir = 'asc' THEN public._cw2_derive_workspace_lifecycle_status(student_id, student_status, public._cw2_is_official_student_code(student_code_raw), has_active_enrollment) END ASC,
      CASE WHEN v_sort = 'student_code' AND v_dir = 'desc' THEN student_code_raw END DESC NULLS LAST,
      CASE WHEN v_sort = 'student_code' AND v_dir = 'asc' THEN student_code_raw END ASC NULLS LAST,
      CASE WHEN v_sort = 'tuition_outstanding' AND v_dir = 'desc' THEN outstanding_amount END DESC NULLS LAST,
      CASE WHEN v_sort = 'tuition_outstanding' AND v_dir = 'asc' THEN outstanding_amount END ASC NULLS LAST,
      CASE WHEN v_sort = 'portfolio_entered_at' AND v_dir = 'desc' THEN portfolio_entered_at END DESC NULLS LAST,
      CASE WHEN v_sort = 'portfolio_entered_at' AND v_dir = 'asc' THEN portfolio_entered_at END ASC NULLS LAST,
      workspace_sequence DESC,
      portfolio_entry_id DESC
    LIMIT v_limit + 1
  ),
  page AS (
    SELECT * FROM ordered
    LIMIT v_limit
  ),
  cf AS (
    SELECT
      p.portfolio_entry_id,
      COALESCE(jsonb_agg(jsonb_build_object(
        'definition_id', d.id,
        'field_key', d.field_key,
        'label', d.label,
        'data_type', d.data_type,
        'value', v.value_text
      ) ORDER BY d.sort_order, d.field_key) FILTER (WHERE d.id IS NOT NULL), '[]'::jsonb) AS custom_fields
    FROM page p
    LEFT JOIN public.consultant_custom_field_value v
      ON v.organization_id = v_org
     AND v.subject_type = p.subject_type
     AND v.subject_id = p.display_subject_id
    LEFT JOIN public.consultant_custom_field_definition d
      ON d.id = v.field_definition_id
     AND d.organization_id = v_org
     AND d.owner_app_user_id = public.current_app_user_id()
     AND d.status = 'active'
    GROUP BY p.portfolio_entry_id
  ),
  built AS (
    SELECT
      jsonb_build_object(
        'portfolio_entry_id', p.portfolio_entry_id,
        'workspace_sequence', p.workspace_sequence,
        'lead_id', p.lead_id,
        'student_id', p.student_id,
        'display_subject_id', p.display_subject_id,
        'subject_type', p.subject_type,
        'family_name', p.family_name,
        'given_name', p.given_name,
        'student_code_official', CASE WHEN public._cw2_is_official_student_code(p.student_code_raw) THEN btrim(p.student_code_raw) END,
        'student_code_display', COALESCE(
          CASE WHEN public._cw2_is_official_student_code(p.student_code_raw) THEN btrim(p.student_code_raw) END,
          public._cw2_provisional_student_code_display(p.consultant_code, p.date_of_birth)
        ),
        'student_code_is_provisional', NOT COALESCE(public._cw2_is_official_student_code(p.student_code_raw), false),
        'lifecycle_status', public._cw2_derive_workspace_lifecycle_status(
          p.student_id, p.student_status,
          public._cw2_is_official_student_code(p.student_code_raw),
          p.has_active_enrollment
        ),
        'lifecycle_status_label', CASE public._cw2_derive_workspace_lifecycle_status(
          p.student_id, p.student_status,
          public._cw2_is_official_student_code(p.student_code_raw),
          p.has_active_enrollment
        )
          WHEN 'tot_nghiep' THEN 'Tá»‘t nghiá»‡p'
          WHEN 'dang_hoc' THEN 'Äang há»c'
          WHEN 'ghi_danh' THEN 'Ghi danh'
          ELSE 'Tiá»m nÄƒng'
        END,
        'primary_guardian_id', p.primary_guardian_id,
        'primary_guardian_name', NULLIF(btrim(p.primary_guardian_name), ''),
        'primary_guardian_phone', p.primary_guardian_phone,
        'course_id', p.course_id,
        'course_name', p.course_name,
        'class_id', p.class_id,
        'class_name', p.class_name,
        'enrollment_id', p.enrollment_id,
        'enrollment_financial_terms_id', p.enrollment_financial_terms_id,
        'declaration_id', p.declaration_id,
        'declaration_status', p.declaration_status,
        'declaration_workflow_kind', p.declaration_workflow_kind,
        'portfolio_entered_at', p.portfolio_entered_at,
        'student_details_subject_id', p.student_id,
        'is_hidden', p.is_hidden,
        'custom_fields', COALESCE(cf.custom_fields, '[]'::jsonb)
      ) || public._cw2_portfolio_row_tuition_fields(
        v_org,
        p.enrollment_id,
        p.enrollment_financial_terms_id,
        p.net_tuition,
        COALESCE(p.outstanding_amount, 0),
        COALESCE(p.allocated_amount, 0),
        COALESCE(p.pending_declaration_amount, 0),
        p.declaration_status::text,
        p.student_id IS NOT NULL,
        p.student_code_raw,
        p.billing_mode,
        p.periodic_lessons_remaining,
        p.carry_forward_credit,
        p.lead_id,
        v_consultant
      ) AS row_json,
      p.workspace_sequence AS ws,
      p.portfolio_entry_id AS pe_id
    FROM page p
    LEFT JOIN cf ON cf.portfolio_entry_id = p.portfolio_entry_id
  )
  SELECT
    COALESCE((SELECT jsonb_agg(b.row_json ORDER BY b.ws DESC, b.pe_id DESC) FROM built b), '[]'::jsonb),
    (SELECT o.workspace_sequence FROM ordered o OFFSET v_limit LIMIT 1),
    (SELECT o.portfolio_entry_id FROM ordered o OFFSET v_limit LIMIT 1),
    (SELECT count(*) > v_limit FROM ordered)
  INTO v_rows, v_next_seq, v_next_id, v_has_more;

  RETURN jsonb_build_object(
    'rows', v_rows,
    'next_cursor', CASE WHEN v_has_more THEN jsonb_build_object(
      'workspace_sequence', v_next_seq,
      'portfolio_entry_id', v_next_id
    ) ELSE NULL END,
    'has_more', v_has_more
  );
END;
$$;
