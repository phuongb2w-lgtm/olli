-- CW2-T09: Consultant portfolio entry detail read + controlled profile/custom-field writes.

CREATE OR REPLACE FUNCTION public._cw2_assert_portfolio_entry_access(p_portfolio_entry_id uuid)
RETURNS public.consultant_portfolio_entry
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.consultant_portfolio_entry;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('consultant_workspace.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.consultant_portfolio_entry e
  WHERE e.id = p_portfolio_entry_id
    AND e.organization_id = public.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'portfolio_entry_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.consultant_user_id IS DISTINCT FROM public.current_app_user_id()
     AND NOT (
       public.is_primary_owner()
       OR public.has_permission('report.executive.read')
     ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_assert_portfolio_entry_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_assert_portfolio_entry_access(uuid) TO authenticated;

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
    'tuition_payment_state', public._cw2_derive_tuition_payment_state(
      fin.outstanding_amount, fin.allocated_amount, d.status::text, fin.has_deposit_structure
    ),
    'declaration_id', d.id,
    'declaration_status', d.status,
    'declaration_workflow_kind', d.workflow_kind,
    'primary_guardian_id', COALESCE(g.id, lcg.id),
    'primary_guardian_family_name', COALESCE(g.family_name, lcg.family_name),
    'primary_guardian_given_name', COALESCE(g.given_name, lcg.given_name),
    'primary_guardian_phone', COALESCE(g.phone, lcg.phone),
    'custom_fields', COALESCE(cf.fields, '[]'::jsonb),
    'capabilities', public._cw2_portfolio_declaration_capabilities(
      pe.enrollment_financial_terms_id,
      fin.outstanding_amount,
      d.status::text,
      e.student_id IS NOT NULL
    ),
    'editable', jsonb_build_object(
      'can_edit_profile', public.has_permission('consultant_workspace.update'),
      'can_edit_date_of_birth', public.has_permission('consultant_workspace.update'),
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
      (snap->>'outstanding_amount')::bigint AS outstanding_amount,
      COALESCE((snap->>'has_deposit_structure')::boolean, false) AS has_deposit_structure
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
        'definition_id', d.id,
        'field_key', d.field_key,
        'label', d.label,
        'data_type', d.data_type,
        'value', v.value_text
      )
      ORDER BY d.sort_order, d.field_key
    ) AS fields
    FROM public.consultant_custom_field_definition d
    LEFT JOIN public.consultant_custom_field_value v
      ON v.field_definition_id = d.id
     AND v.organization_id = d.organization_id
     AND v.subject_type = CASE WHEN e.student_id IS NOT NULL THEN 'student' ELSE 'lead' END
     AND v.subject_id = COALESCE(e.student_id, e.lead_id)
    WHERE d.organization_id = v_org
      AND d.owner_app_user_id = public.current_app_user_id()
      AND d.status = 'active'
  ) cf ON true
  JOIN public.app_user au ON au.id = e.consultant_user_id AND au.organization_id = e.organization_id
  WHERE e.id = p_portfolio_entry_id;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'portfolio_entry_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.get_consultant_portfolio_entry_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_consultant_portfolio_entry_detail(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_consultant_portfolio_profile(
  p_portfolio_entry_id uuid,
  p_family_name text,
  p_given_name text,
  p_date_of_birth date DEFAULT NULL,
  p_guardian_family_name text DEFAULT NULL,
  p_guardian_given_name text DEFAULT NULL,
  p_guardian_phone text DEFAULT NULL,
  p_expected_subject_updated_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry public.consultant_portfolio_entry;
  v_org uuid;
  v_fn text;
  v_gn text;
  v_lc_id uuid;
  v_lc_contact_id uuid;
  v_guardian_id uuid;
BEGIN
  IF NOT public.has_permission('consultant_workspace.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_entry := public._cw2_assert_portfolio_entry_access(p_portfolio_entry_id);
  v_org := v_entry.organization_id;
  v_fn := NULLIF(btrim(p_family_name), '');
  v_gn := NULLIF(btrim(p_given_name), '');
  IF v_fn IS NULL OR v_gn IS NULL THEN
    RAISE EXCEPTION 'invalid_profile_name' USING ERRCODE = 'P0001';
  END IF;

  IF v_entry.student_id IS NOT NULL THEN
    IF p_expected_subject_updated_at IS NOT NULL THEN
      PERFORM 1 FROM public.student s
      WHERE s.id = v_entry.student_id AND s.organization_id = v_org
        AND s.updated_at = p_expected_subject_updated_at
      FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_conflict' USING ERRCODE = 'P0001';
      END IF;
    END IF;

    UPDATE public.student s
    SET
      family_name = v_fn,
      given_name = v_gn,
      date_of_birth = COALESCE(p_date_of_birth, s.date_of_birth),
      updated_at = now()
    WHERE s.id = v_entry.student_id AND s.organization_id = v_org;

    SELECT sg.guardian_id INTO v_guardian_id
    FROM public.student_guardian sg
    WHERE sg.student_id = v_entry.student_id AND sg.organization_id = v_org AND sg.is_primary_contact = true
    ORDER BY sg.created_at
    LIMIT 1;

    IF v_guardian_id IS NOT NULL AND (
      p_guardian_family_name IS NOT NULL OR p_guardian_given_name IS NOT NULL OR p_guardian_phone IS NOT NULL
    ) THEN
      UPDATE public.guardian g
      SET
        family_name = COALESCE(NULLIF(btrim(p_guardian_family_name), ''), g.family_name),
        given_name = COALESCE(NULLIF(btrim(p_guardian_given_name), ''), g.given_name),
        phone = COALESCE(NULLIF(btrim(p_guardian_phone), ''), g.phone),
        updated_at = now()
      WHERE g.id = v_guardian_id AND g.organization_id = v_org;
    END IF;
  ELSE
    SELECT c.id INTO v_lc_id
    FROM public.lead_candidate c
    WHERE c.lead_id = v_entry.lead_id AND c.organization_id = v_org AND c.status = 'active'
    ORDER BY c.is_primary_candidate DESC, c.created_at
    LIMIT 1;

    IF v_lc_id IS NULL THEN
      RAISE EXCEPTION 'lead_candidate_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF p_expected_subject_updated_at IS NOT NULL THEN
      PERFORM 1 FROM public.lead_candidate c
      WHERE c.id = v_lc_id AND c.updated_at = p_expected_subject_updated_at
      FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_conflict' USING ERRCODE = 'P0001';
      END IF;
    END IF;

    UPDATE public.lead_candidate c
    SET
      family_name = v_fn,
      given_name = v_gn,
      date_of_birth = COALESCE(p_date_of_birth, c.date_of_birth),
      updated_at = now()
    WHERE c.id = v_lc_id;

    SELECT lc.id INTO v_lc_contact_id
    FROM public.lead_contact lc
    WHERE lc.lead_id = v_entry.lead_id AND lc.organization_id = v_org AND lc.is_primary_contact = true
    ORDER BY lc.created_at
    LIMIT 1;

    IF v_lc_contact_id IS NOT NULL AND p_guardian_phone IS NOT NULL THEN
      UPDATE public.lead_contact lc
      SET
        family_name = COALESCE(NULLIF(btrim(p_guardian_family_name), ''), lc.family_name),
        given_name = COALESCE(NULLIF(btrim(p_guardian_given_name), ''), lc.given_name),
        phone = NULLIF(btrim(p_guardian_phone), ''),
        updated_at = now()
      WHERE lc.id = v_lc_contact_id;
    END IF;
  END IF;

  RETURN public.get_consultant_portfolio_entry_detail(p_portfolio_entry_id);
END;
$$;

REVOKE ALL ON FUNCTION public.save_consultant_portfolio_profile(uuid, text, text, date, text, text, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_consultant_portfolio_profile(uuid, text, text, date, text, text, text, timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_consultant_portfolio_custom_fields(
  p_portfolio_entry_id uuid,
  p_values jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry public.consultant_portfolio_entry;
  v_org uuid;
  v_subject_type text;
  v_subject_id uuid;
  v_item jsonb;
  v_def_id uuid;
  v_key text;
  v_val text;
BEGIN
  IF NOT public.has_permission('consultant_custom_field.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_entry := public._cw2_assert_portfolio_entry_access(p_portfolio_entry_id);
  v_org := v_entry.organization_id;
  v_subject_type := CASE WHEN v_entry.student_id IS NOT NULL THEN 'student' ELSE 'lead' END;
  v_subject_id := COALESCE(v_entry.student_id, v_entry.lead_id);

  IF p_values IS NULL OR jsonb_typeof(p_values) <> 'array' THEN
    RAISE EXCEPTION 'invalid_custom_fields' USING ERRCODE = 'P0001';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_values)
  LOOP
    v_key := NULLIF(btrim(v_item->>'field_key'), '');
    v_val := COALESCE(v_item->>'value', '');
    IF v_key IS NULL OR public._cw2_custom_field_key_reserved(v_key) THEN
      RAISE EXCEPTION 'invalid_custom_field_key' USING ERRCODE = 'P0001';
    END IF;

    SELECT d.id INTO v_def_id
    FROM public.consultant_custom_field_definition d
    WHERE d.organization_id = v_org
      AND d.owner_app_user_id = public.current_app_user_id()
      AND d.field_key = v_key
      AND d.status = 'active';

    IF v_def_id IS NULL THEN
      RAISE EXCEPTION 'custom_field_not_found' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.consultant_custom_field_value (
      organization_id, field_definition_id, subject_type, subject_id, value_text
    ) VALUES (v_org, v_def_id, v_subject_type, v_subject_id, v_val)
    ON CONFLICT (organization_id, field_definition_id, subject_type, subject_id)
    DO UPDATE SET value_text = EXCLUDED.value_text, updated_at = now();
  END LOOP;

  RETURN public.get_consultant_portfolio_entry_detail(p_portfolio_entry_id);
END;
$$;

REVOKE ALL ON FUNCTION public.save_consultant_portfolio_custom_fields(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_consultant_portfolio_custom_fields(uuid, jsonb) TO authenticated;

COMMENT ON FUNCTION public.get_consultant_portfolio_entry_detail(uuid) IS
  'CW2-T09: Authoritative composed detail for one consultant portfolio entry (read-only finance/status/code).';
