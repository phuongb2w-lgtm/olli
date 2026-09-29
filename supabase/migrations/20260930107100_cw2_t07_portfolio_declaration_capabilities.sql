-- CW2-T07: Portfolio declaration capabilities (T05 read model patch).

CREATE OR REPLACE FUNCTION public._cw2_portfolio_declaration_capabilities(
  p_enrollment_financial_terms_id uuid,
  p_outstanding bigint,
  p_declaration_status text,
  p_has_student boolean
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'can_edit_contact', public.has_permission('consultant_workspace.update'),
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

GRANT EXECUTE ON FUNCTION public._cw2_portfolio_declaration_capabilities(uuid, bigint, text, boolean) TO authenticated;
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
        OR g.phone ILIKE '%' || btrim(p_filters->>'guardian_phone') || '%'
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
          p.student_id IS NOT NULL
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

