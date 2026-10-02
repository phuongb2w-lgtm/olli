-- CW2-T11: Portfolio read model + finance refresh for tuition V2 states.

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
    'tuition_outstanding', COALESCE((v_snap->>'course_outstanding_amount')::bigint, 0),
    'tuition_pending_declaration', COALESCE((v_snap->>'pending_declaration_amount')::bigint, 0),
    'has_deposit_structure', COALESCE((v_snap->>'has_deposit_structure')::boolean, false),
    'tuition_established', COALESCE((v_snap->>'tuition_established')::boolean, false),
    'billing_mode', v_snap->>'billing_mode',
    'periodic_carry_forward_credit', COALESCE((v_snap->>'periodic_carry_forward_credit')::bigint, 0),
    'periodic_lessons_remaining', (v_snap->>'periodic_lessons_remaining')::integer
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
  p_carry_forward_credit bigint
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
  v_state := public._cw2_derive_tuition_payment_state(
    p_org, p_enrollment_id, COALESCE(p_net_tuition, 0)::bigint, p_outstanding, p_allocated, p_pending
  );
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
      p_student_code_raw
    )
  );
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
    'primary_guardian_id', COALESCE(g.id, lcg.id),
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
    SELECT lc2.id, lc2.given_name, lc2.family_name, lc2.phone
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
      COALESCE((v_snap->>'periodic_carry_forward_credit')::bigint, 0)
    );
    v_row := v_row || v_tuif || jsonb_build_object('capabilities', v_tuif->'capabilities');
  ELSE
    v_row := v_row || jsonb_build_object(
      'tuition_payment_state', 'chua_coc',
      'tuition_payment_state_label', public._cw2_tuition_payment_state_label('chua_coc'),
      'capabilities', public._cw2_portfolio_declaration_capabilities(
        NULL, 0, NULL, (v_row->>'student_id') IS NOT NULL
      )
    );
  END IF;

  RETURN v_row;
END;
$$;
