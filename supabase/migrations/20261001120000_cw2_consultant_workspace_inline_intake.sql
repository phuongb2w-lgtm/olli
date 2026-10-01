-- CW2 corrective: consultant portfolio inline intake + official-student edit lock.

CREATE OR REPLACE FUNCTION public._cw2_next_consultant_workspace_sequence(
  p_organization_id uuid,
  p_consultant_user_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seq bigint;
BEGIN
  INSERT INTO public.consultant_portfolio_sequence (organization_id, consultant_user_id, last_workspace_sequence)
  VALUES (p_organization_id, p_consultant_user_id, 0)
  ON CONFLICT (organization_id, consultant_user_id) DO NOTHING;

  UPDATE public.consultant_portfolio_sequence
  SET
    last_workspace_sequence = last_workspace_sequence + 1,
    updated_at = now()
  WHERE organization_id = p_organization_id
    AND consultant_user_id = p_consultant_user_id
  RETURNING last_workspace_sequence INTO v_seq;

  RETURN v_seq;
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_next_consultant_workspace_sequence(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_next_consultant_workspace_sequence(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public._cw2_portfolio_can_edit_contact(p_student_code_raw text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT public.has_permission('consultant_workspace.update')
    AND NOT COALESCE(public._cw2_is_official_student_code(p_student_code_raw), false);
$$;

DROP FUNCTION IF EXISTS public._cw2_portfolio_declaration_capabilities(uuid, bigint, text, boolean);

CREATE OR REPLACE FUNCTION public._cw2_portfolio_declaration_capabilities(
  p_enrollment_financial_terms_id uuid,
  p_outstanding bigint,
  p_declaration_status text,
  p_has_student boolean,
  p_student_code_raw text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'can_edit_contact', public._cw2_portfolio_can_edit_contact(p_student_code_raw),
    'can_open_payment_declaration', public.has_permission('consultant_revenue.declare')
      AND p_enrollment_financial_terms_id IS NOT NULL
      AND (
        p_declaration_status IN ('draft', 'returned', 'pending')
        OR (COALESCE(p_outstanding, 0) > 0 AND COALESCE(p_declaration_status, '') NOT IN ('pending'))
      ),
    'can_create_payment_declaration', public.has_permission('consultant_revenue.declare')
      AND p_enrollment_financial_terms_id IS NOT NULL
      AND COALESCE(p_outstanding, 0) > 0
      AND COALESCE(p_declaration_status, '') NOT IN ('pending', 'draft', 'returned'),
    'can_edit_payment_declaration', public.has_permission('consultant_revenue.declare')
      AND p_declaration_status IN ('draft', 'returned'),
    'can_submit_declaration', public.has_permission('consultant_revenue.declare')
      AND p_declaration_status IN ('draft', 'returned'),
    'can_add_payment', false,
    'can_open_student_details', p_has_student
  );
$$;

GRANT EXECUTE ON FUNCTION public._cw2_portfolio_declaration_capabilities(uuid, bigint, text, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_consultant_workspace_portfolio_intake(
  p_family_name text,
  p_given_name text,
  p_date_of_birth date DEFAULT NULL,
  p_guardian_family_name text DEFAULT NULL,
  p_guardian_given_name text DEFAULT NULL,
  p_guardian_phone text DEFAULT NULL,
  p_custom_field_values jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_actor uuid;
  v_lead_id uuid;
  v_entry_id uuid;
  v_seq bigint;
  v_fn text;
  v_gn text;
  v_gf text;
  v_gg text;
  v_item jsonb;
  v_key text;
  v_val text;
  v_def_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('consultant_workspace.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();
  v_actor := public.current_app_user_id();
  v_fn := NULLIF(btrim(p_family_name), '');
  v_gn := NULLIF(btrim(p_given_name), '');
  IF v_fn IS NULL OR v_gn IS NULL THEN
    RAISE EXCEPTION 'invalid_profile_name' USING ERRCODE = 'P0001';
  END IF;

  v_gf := NULLIF(btrim(p_guardian_family_name), '');
  v_gg := NULLIF(btrim(p_guardian_given_name), '');
  IF v_gf IS NULL AND v_gg IS NULL THEN
    v_gf := v_fn;
    v_gg := v_gn;
  ELSIF v_gf IS NULL THEN
    v_gf := v_gg;
  ELSIF v_gg IS NULL THEN
    v_gg := v_gf;
  END IF;

  INSERT INTO public.lead (
    organization_id, status, assigned_user_id, created_by, updated_by
  ) VALUES (
    v_org, 'new', NULL, v_actor, v_actor
  )
  RETURNING id INTO v_lead_id;

  PERFORM set_config('olli.lead_assignment_mutation', 'true', true);
  UPDATE public.lead
  SET assigned_user_id = v_actor, updated_by = v_actor
  WHERE id = v_lead_id AND organization_id = v_org;
  INSERT INTO public.lead_assignment (
    organization_id, lead_id, previous_assigned_user_id, new_assigned_user_id, changed_by
  ) VALUES (
    v_org, v_lead_id, NULL, v_actor, v_actor
  );
  PERFORM set_config('olli.lead_assignment_mutation', 'false', true);

  INSERT INTO public.lead_candidate (
    organization_id, lead_id, family_name, given_name, date_of_birth,
    is_primary_candidate, status, created_by, updated_by
  ) VALUES (
    v_org, v_lead_id, v_fn, v_gn, p_date_of_birth,
    true, 'active', v_actor, v_actor
  );

  INSERT INTO public.lead_contact (
    organization_id, lead_id, family_name, given_name, phone,
    relationship_type, is_primary_contact, is_billing_contact,
    created_by, updated_by
  ) VALUES (
    v_org, v_lead_id, v_gf, v_gg, NULLIF(btrim(p_guardian_phone), ''),
    'guardian', true, true, v_actor, v_actor
  );

  v_seq := public._cw2_next_consultant_workspace_sequence(v_org, v_actor);

  INSERT INTO public.consultant_portfolio_entry (
    organization_id, consultant_user_id, workspace_sequence, lead_id
  ) VALUES (
    v_org, v_actor, v_seq, v_lead_id
  )
  RETURNING id INTO v_entry_id;

  IF p_custom_field_values IS NOT NULL AND jsonb_typeof(p_custom_field_values) = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_custom_field_values)
    LOOP
      v_key := NULLIF(btrim(v_item->>'field_key'), '');
      v_val := COALESCE(v_item->>'value', '');
      IF v_key IS NULL OR public._cw2_custom_field_key_reserved(v_key) THEN
        CONTINUE;
      END IF;
      SELECT d.id INTO v_def_id
      FROM public.consultant_custom_field_definition d
      WHERE d.organization_id = v_org
        AND d.owner_app_user_id = v_actor
        AND d.field_key = v_key
        AND d.status = 'active';
      IF v_def_id IS NOT NULL THEN
        INSERT INTO public.consultant_custom_field_value (
          organization_id, field_definition_id, subject_type, subject_id, value_text
        ) VALUES (v_org, v_def_id, 'lead', v_lead_id, v_val)
        ON CONFLICT (organization_id, field_definition_id, subject_type, subject_id)
        DO UPDATE SET value_text = EXCLUDED.value_text, updated_at = now();
      END IF;
    END LOOP;
  END IF;

  RETURN public.get_consultant_portfolio_entry_detail(v_entry_id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_consultant_workspace_portfolio_intake(text, text, date, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_consultant_workspace_portfolio_intake(text, text, date, text, text, text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.create_consultant_workspace_portfolio_intake(text, text, date, text, text, text, jsonb) IS
  'CW2: Atomic consultant inline intake â€” lead + primary people + self-assigned portfolio row + STT. No official student code allocation.';

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
          fin.outstanding_amount,
          fin.allocated_amount,
          d.status::text,
          fin.has_deposit_structure
        ) = p_filters->>'tuition_payment_state'
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
        'tuition_total_net', COALESCE(p.net_tuition, 0),
        'tuition_paid', COALESCE(p.allocated_amount, 0),
        'tuition_outstanding', COALESCE(p.outstanding_amount, 0),
        'tuition_payment_state', public._cw2_derive_tuition_payment_state(
          p.outstanding_amount, p.allocated_amount, p.declaration_status::text, p.has_deposit_structure
        ),
        'tuition_payment_state_label', CASE public._cw2_derive_tuition_payment_state(
          p.outstanding_amount, p.allocated_amount, p.declaration_status::text, p.has_deposit_structure
        )
          WHEN 'cho_xac_nhan' THEN 'Chá» xÃ¡c nháº­n'
          WHEN 'full_phi' THEN 'Full phÃ­'
          WHEN 'coc_phi' THEN 'Cá»c phÃ­'
          WHEN 'mot_phan' THEN 'Má»™t pháº§n'
          ELSE 'ÄÃ³ng phÃ­'
        END,
        'declaration_id', p.declaration_id,
        'declaration_status', p.declaration_status,
        'declaration_workflow_kind', p.declaration_workflow_kind,
        'portfolio_entered_at', p.portfolio_entered_at,
        'student_details_subject_id', p.student_id,
        'is_hidden', p.is_hidden,
        'custom_fields', COALESCE(cf.custom_fields, '[]'::jsonb),
        'capabilities', public._cw2_portfolio_declaration_capabilities(
          p.enrollment_financial_terms_id,
          COALESCE(p.outstanding_amount, 0),
          p.declaration_status::text,
          p.student_id IS NOT NULL,
          p.student_code_raw
        )
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
  v_student_code text;
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
    SELECT s.student_code INTO v_student_code FROM public.student s WHERE s.id = v_entry.student_id AND s.organization_id = v_org;
    IF public._cw2_is_official_student_code(v_student_code) THEN
      RAISE EXCEPTION 'profile_locked' USING ERRCODE = '42501';
    END IF;
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
