-- CW2-T13: personal custom-field RPCs, extended types, PIN access permissions (migration 89+)

INSERT INTO public.permission (code)
VALUES
  ('student_personal_field.manage'),
  ('student.personal_id.read')
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.consultant_custom_field_definition
  DROP CONSTRAINT IF EXISTS consultant_custom_field_definition_data_type_check;

ALTER TABLE public.consultant_custom_field_definition
  ADD CONSTRAINT consultant_custom_field_definition_data_type_check
  CHECK (data_type IN ('text', 'date', 'phone', 'url', 'number', 'boolean'));

CREATE OR REPLACE FUNCTION public._cw2_slug_custom_field_key(p_label text, p_attempt integer DEFAULT 0)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_base text;
  v_key text;
BEGIN
  v_base := lower(regexp_replace(translate(btrim(p_label), 'àÀáÁạẠảẢãÃâÂầẦấẤậẬẩẨẫẪăĂằẰắẮặẶẳẲẵẴèÈéÉẹẸẻẺẽẼêÊềỀếẾệỆểỂễỄìÌíÍịỊỉỈĩĨòÒóÓọỌỏỎõÕôÔồỒốỐộỘổỔỗỖơƠờỜớỚợỢởỞỡỠùÙúÚụỤủỦũŨưƯừỪứỨựỰửỬữỮỳỲýÝỵỴỷỶỹỸđĐ', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaeeeeeeeeeeeeeeeeeeeeeeiiiiiiiiiioooooooooooooooooooooooooooooooooouuuuuuuuuuuuuuuuuuuuuuyyyyyyyyyydd'), '[^a-zA-Z0-9]+', '_', 'g'));
  v_base := regexp_replace(v_base, '^_+|_+$', '', 'g');
  IF v_base = '' OR v_base !~ '^[a-z]' THEN
    v_base := 'f_' || coalesce(v_base, 'note');
  END IF;
  v_key := left(v_base, 40);
  IF p_attempt > 0 THEN
    v_key := left(v_base, 40 - length(p_attempt::text) - 1) || '_' || p_attempt::text;
  END IF;
  RETURN v_key;
END;
$$;

-- Core student/grid identities can never be reused as personal field keys.
CREATE OR REPLACE FUNCTION public._cw2_custom_field_key_reserved(p_key text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT lower(btrim(p_key)) = ANY (ARRAY[
    'student_code', 'status', 'given_name', 'family_name', 'student_id', 'lead_id',
    'consultant', 'course', 'enrollment', 'payment', 'charge', 'id', 'organization_id',
    'date_of_birth', 'personal_identification_number', 'guardian_name', 'guardian_phone',
    'primary_guardian_name', 'primary_guardian_phone', 'lifecycle_status',
    'student_code_display', 'student_code_official'
  ]::text[]);
$$;

CREATE OR REPLACE FUNCTION public._cw2_can_manage_personal_custom_fields()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.has_permission('consultant_custom_field.manage')
      OR public.has_permission('student_personal_field.manage');
$$;

DROP POLICY IF EXISTS consultant_custom_field_definition_owner ON public.consultant_custom_field_definition;
CREATE POLICY consultant_custom_field_definition_owner ON public.consultant_custom_field_definition
  FOR ALL TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND owner_app_user_id = public.current_app_user_id()
    AND public._cw2_can_manage_personal_custom_fields()
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND owner_app_user_id = public.current_app_user_id()
    AND public._cw2_can_manage_personal_custom_fields()
  );

DROP POLICY IF EXISTS consultant_custom_field_value_owner ON public.consultant_custom_field_value;
CREATE POLICY consultant_custom_field_value_owner ON public.consultant_custom_field_value
  FOR ALL TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public._cw2_can_manage_personal_custom_fields()
    AND EXISTS (
      SELECT 1 FROM public.consultant_custom_field_definition d
      WHERE d.id = field_definition_id
        AND d.organization_id = consultant_custom_field_value.organization_id
        AND d.owner_app_user_id = public.current_app_user_id()
    )
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public._cw2_can_manage_personal_custom_fields()
    AND EXISTS (
      SELECT 1 FROM public.consultant_custom_field_definition d
      WHERE d.id = field_definition_id
        AND d.organization_id = consultant_custom_field_value.organization_id
        AND d.owner_app_user_id = public.current_app_user_id()
    )
  );

CREATE OR REPLACE FUNCTION public.create_personal_custom_field_definition(
  p_label text,
  p_data_type text DEFAULT 'text',
  p_field_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_owner uuid := public.current_app_user_id();
  v_label text := btrim(p_label);
  v_type text := lower(btrim(coalesce(p_data_type, 'text')));
  v_key text;
  v_attempt integer := 0;
  v_row public.consultant_custom_field_definition%ROWTYPE;
BEGIN
  IF NOT public._cw2_can_manage_personal_custom_fields() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_label = '' THEN
    RAISE EXCEPTION 'invalid_label' USING ERRCODE = 'P0001';
  END IF;
  IF v_type NOT IN ('text', 'date', 'phone', 'url', 'number', 'boolean') THEN
    RAISE EXCEPTION 'invalid_data_type' USING ERRCODE = 'P0001';
  END IF;
  IF length(v_label) > 80 THEN
    RAISE EXCEPTION 'invalid_label' USING ERRCODE = 'P0001';
  END IF;
  IF p_field_key IS NOT NULL AND btrim(p_field_key) <> '' THEN
    v_key := lower(btrim(p_field_key));
    IF public._cw2_custom_field_key_reserved(v_key) THEN
      RAISE EXCEPTION 'custom_field_key_reserved' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    LOOP
      v_key := public._cw2_slug_custom_field_key(v_label, v_attempt);
      IF public._cw2_custom_field_key_reserved(v_key) THEN
        v_key := public._cw2_slug_custom_field_key('cf_' || v_key, v_attempt);
      END IF;
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.consultant_custom_field_definition d
        WHERE d.organization_id = v_org AND d.owner_app_user_id = v_owner AND d.field_key = v_key
      );
      v_attempt := v_attempt + 1;
      IF v_attempt > 50 THEN
        RAISE EXCEPTION 'field_key_generation_failed' USING ERRCODE = 'P0001';
      END IF;
    END LOOP;
  END IF;
  INSERT INTO public.consultant_custom_field_definition (
    organization_id, owner_app_user_id, field_key, label, data_type, sort_order, status
  ) VALUES (
    v_org, v_owner, v_key, v_label, v_type,
    coalesce((SELECT max(sort_order) + 1 FROM public.consultant_custom_field_definition d
              WHERE d.organization_id = v_org AND d.owner_app_user_id = v_owner), 0),
    'active'
  )
  RETURNING * INTO v_row;
  RETURN jsonb_build_object(
    'id', v_row.id,
    'field_key', v_row.field_key,
    'label', v_row.label,
    'data_type', v_row.data_type,
    'sort_order', v_row.sort_order,
    'status', v_row.status
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.update_personal_custom_field_definition(
  p_field_definition_id uuid,
  p_label text DEFAULT NULL,
  p_status text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.consultant_custom_field_definition%ROWTYPE;
  v_status text := nullif(lower(btrim(coalesce(p_status, ''))), '');
  v_label text := nullif(btrim(coalesce(p_label, '')), '');
BEGIN
  IF NOT public._cw2_can_manage_personal_custom_fields() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF v_status IS NOT NULL AND v_status NOT IN ('active', 'archived') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;
  IF v_label IS NOT NULL AND length(v_label) > 80 THEN
    RAISE EXCEPTION 'invalid_label' USING ERRCODE = 'P0001';
  END IF;
  UPDATE public.consultant_custom_field_definition d
  SET
    label = coalesce(v_label, d.label),
    status = coalesce(v_status, d.status),
    updated_at = now()
  WHERE d.id = p_field_definition_id
    AND d.organization_id = public.current_organization_id()
    AND d.owner_app_user_id = public.current_app_user_id()
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'field_not_found' USING ERRCODE = 'P0001';
  END IF;
  RETURN jsonb_build_object(
    'id', v_row.id,
    'field_key', v_row.field_key,
    'label', v_row.label,
    'data_type', v_row.data_type,
    'sort_order', v_row.sort_order,
    'status', v_row.status
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.save_personal_custom_field_values(
  p_subject_type text,
  p_subject_id uuid,
  p_values jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_owner uuid := public.current_app_user_id();
  v_item jsonb;
  v_key text;
  v_val text;
  v_def_id uuid;
BEGIN
  IF NOT public._cw2_can_manage_personal_custom_fields() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_subject_type NOT IN ('lead', 'student') THEN
    RAISE EXCEPTION 'invalid_subject_type' USING ERRCODE = 'P0001';
  END IF;
  IF p_subject_type = 'student' AND NOT EXISTS (
    SELECT 1 FROM public.student s WHERE s.id = p_subject_id AND s.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'subject_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF p_subject_type = 'lead' AND NOT EXISTS (
    SELECT 1 FROM public.lead l WHERE l.id = p_subject_id AND l.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'subject_not_found' USING ERRCODE = 'P0002';
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(coalesce(p_values, '[]'::jsonb))
  LOOP
    v_key := btrim(v_item->>'field_key');
    v_val := coalesce(v_item->>'value', '');
    IF v_key = '' THEN CONTINUE; END IF;
    SELECT d.id INTO v_def_id
    FROM public.consultant_custom_field_definition d
    WHERE d.organization_id = v_org
      AND d.owner_app_user_id = v_owner
      AND d.field_key = v_key
      AND d.status = 'active';
    IF v_def_id IS NULL THEN
      RAISE EXCEPTION 'invalid_custom_field' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.consultant_custom_field_value (
      organization_id, field_definition_id, subject_type, subject_id, value_text
    ) VALUES (v_org, v_def_id, p_subject_type, p_subject_id, v_val)
    ON CONFLICT (organization_id, field_definition_id, subject_type, subject_id)
    DO UPDATE SET value_text = excluded.value_text, updated_at = now();
  END LOOP;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_personal_custom_field_values(
  p_subject_type text,
  p_subject_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'field_key', d.field_key,
    'label', d.label,
    'data_type', d.data_type,
    'value', coalesce(v.value_text, '')
  ) ORDER BY d.sort_order, d.label), '[]'::jsonb)
  FROM public.consultant_custom_field_definition d
  LEFT JOIN public.consultant_custom_field_value v
    ON v.field_definition_id = d.id
   AND v.organization_id = d.organization_id
   AND v.subject_type = p_subject_type
   AND v.subject_id = p_subject_id
  WHERE d.organization_id = public.current_organization_id()
    AND d.owner_app_user_id = public.current_app_user_id()
    AND d.status = 'active';
$$;

GRANT EXECUTE ON FUNCTION public.create_personal_custom_field_definition(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_personal_custom_field_definition(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_personal_custom_field_values(text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_personal_custom_field_values(text, uuid) TO authenticated;

-- Bulk read for list surfaces (one round-trip per page instead of one per row).
CREATE OR REPLACE FUNCTION public.list_personal_custom_field_values_bulk(
  p_subject_type text,
  p_subject_ids uuid[]
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'subject_id', v.subject_id,
    'field_key', d.field_key,
    'value', coalesce(v.value_text, '')
  )), '[]'::jsonb)
  FROM public.consultant_custom_field_value v
  JOIN public.consultant_custom_field_definition d
    ON d.id = v.field_definition_id
   AND d.organization_id = v.organization_id
  WHERE public._cw2_can_manage_personal_custom_fields()
    AND v.organization_id = public.current_organization_id()
    AND d.owner_app_user_id = public.current_app_user_id()
    AND d.status = 'active'
    AND v.subject_type = p_subject_type
    AND v.subject_id = ANY (coalesce(p_subject_ids, ARRAY[]::uuid[]));
$$;

REVOKE ALL ON FUNCTION public.list_personal_custom_field_values_bulk(text, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_personal_custom_field_values_bulk(text, uuid[]) TO authenticated;

-- Per-user grid layout (visibility / width / order / filters) for non-consultant list surfaces.
CREATE TABLE IF NOT EXISTS public.personal_grid_preference (
  organization_id uuid NOT NULL REFERENCES public.organization (id) ON DELETE CASCADE,
  app_user_id uuid NOT NULL,
  surface_key text NOT NULL,
  preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, app_user_id, surface_key),
  FOREIGN KEY (organization_id, app_user_id) REFERENCES public.app_user (organization_id, id) ON DELETE CASCADE,
  CONSTRAINT personal_grid_preference_surface_check CHECK (surface_key IN ('students', 'finance_students')),
  CONSTRAINT personal_grid_preference_object_check CHECK (jsonb_typeof(preferences) = 'object')
);

ALTER TABLE public.personal_grid_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.personal_grid_preference FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS personal_grid_preference_owner ON public.personal_grid_preference;
CREATE POLICY personal_grid_preference_owner ON public.personal_grid_preference
  FOR ALL TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND app_user_id = public.current_app_user_id()
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND app_user_id = public.current_app_user_id()
  );

REVOKE ALL ON TABLE public.personal_grid_preference FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.personal_grid_preference TO authenticated;

-- Accounting student-level list: every student with a financial relationship
-- (enrollment or non-void charge), including fully paid students that
-- list_finance_receivables (outstanding > 0 only) excludes.
CREATE OR REPLACE FUNCTION public.list_finance_student_accounts(
  p_limit integer DEFAULT 200,
  p_offset integer DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  PERFORM public._assert_finance_intelligence_access();
  IF NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  RETURN QUERY
  WITH student_charges AS (
    SELECT
      coalesce(c.student_id, e.student_id) AS student_id,
      cb.effective_obligation,
      cb.allocated_total,
      cb.outstanding_balance
    FROM public.charge c
    JOIN public.charge_balance cb ON cb.charge_id = c.id
    LEFT JOIN public.enrollment e ON e.id = c.enrollment_id AND e.organization_id = c.organization_id
    WHERE c.organization_id = v_org
      AND c.status <> 'void'
  ),
  population AS (
    SELECT DISTINCT en.student_id
    FROM public.enrollment en
    WHERE en.organization_id = v_org
    UNION
    SELECT sc.student_id FROM student_charges sc WHERE sc.student_id IS NOT NULL
  ),
  totals AS (
    SELECT
      sc.student_id,
      sum(sc.effective_obligation)::bigint AS total_charged,
      sum(sc.allocated_total)::bigint AS total_paid,
      sum(greatest(sc.outstanding_balance, 0))::bigint AS outstanding_balance
    FROM student_charges sc
    WHERE sc.student_id IS NOT NULL
    GROUP BY sc.student_id
  )
  SELECT jsonb_build_object(
    'student_id', s.id,
    'family_name', s.family_name,
    'given_name', s.given_name,
    'student_code', CASE WHEN public._cw2_is_official_student_code(s.student_code) THEN btrim(s.student_code) ELSE s.student_code END,
    'student_status', s.status,
    'total_charged', coalesce(t.total_charged, 0),
    'total_paid', coalesce(t.total_paid, 0),
    'outstanding_balance', coalesce(t.outstanding_balance, 0)
  )
  FROM population p
  JOIN public.student s ON s.id = p.student_id AND s.organization_id = v_org
  LEFT JOIN totals t ON t.student_id = s.id
  ORDER BY coalesce(t.outstanding_balance, 0) DESC, s.family_name, s.given_name, s.id
  LIMIT least(greatest(coalesce(p_limit, 200), 1), 500)
  OFFSET greatest(coalesce(p_offset, 0), 0);
END;
$$;

REVOKE ALL ON FUNCTION public.list_finance_student_accounts(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_finance_student_accounts(integer, integer) TO authenticated;

-- Canonical role grants for T13 permissions; also applied to every future organization.
CREATE OR REPLACE FUNCTION public._cw2_t13_apply_personal_field_permissions(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.role_permission (role_id, permission_id)
  SELECT r.id, p.id
  FROM public.role r
  JOIN public.permission p ON p.code = 'student_personal_field.manage'
  WHERE r.organization_id = p_organization_id
    AND r.is_canonical_template
    AND r.canonical_code IN ('academic_operations', 'accountant', 'consultant', 'center_manager')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.role_permission (role_id, permission_id)
  SELECT r.id, p.id
  FROM public.role r
  JOIN public.permission p ON p.code = 'student.personal_id.read'
  WHERE r.organization_id = p_organization_id
    AND r.is_canonical_template
    AND r.canonical_code IN ('academic_operations', 'center_manager')
  ON CONFLICT DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public._cw2_t13_apply_personal_field_permissions(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.initialize_organization_cw2_foundation(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_primary uuid;
  v_role_id uuid;
BEGIN
  PERFORM public._cw2_refresh_organization_student_sequence_floor(p_organization_id);

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = p_organization_id;

  IF v_primary IS NOT NULL THEN
    UPDATE public.app_user
    SET consultant_operational_code = '01'
    WHERE id = v_primary
      AND organization_id = p_organization_id
      AND consultant_operational_code IS NULL;
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.role r
  WHERE r.organization_id = p_organization_id
    AND r.is_canonical_template
    AND r.canonical_code = 'consultant';

  IF v_role_id IS NOT NULL THEN
    PERFORM public._cw2_apply_consultant_workspace_permissions(v_role_id);
  END IF;

  PERFORM public._cw2_t13_apply_personal_field_permissions(p_organization_id);
END;
$$;

REVOKE ALL ON FUNCTION public.initialize_organization_cw2_foundation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.initialize_organization_cw2_foundation(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_organization_cw2_foundation(uuid) TO service_role;
-- PIN access control at RPC boundary + column-level SELECT hardening

CREATE OR REPLACE FUNCTION public._cw2_can_read_personal_identification(
  p_organization_id uuid,
  p_portfolio_consultant_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RETURN false;
  END IF;
  IF p_organization_id IS DISTINCT FROM public.current_organization_id() THEN
    RETURN false;
  END IF;
  IF public._cw2_is_teacher_only_app_user() THEN
    RETURN false;
  END IF;
  IF public.is_primary_owner() THEN
    RETURN true;
  END IF;
  IF public.has_permission('student.personal_id.read') THEN
    RETURN true;
  END IF;
  IF public.has_permission('consultant_workspace.read')
     AND p_portfolio_consultant_user_id = public.current_app_user_id() THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_can_read_student_personal_id()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public._cw2_can_read_personal_identification(
    public.current_organization_id(),
    public.current_app_user_id()
  );
$$;

GRANT EXECUTE ON FUNCTION public._cw2_can_read_personal_identification(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public._cw2_can_read_student_personal_id() TO authenticated;

REVOKE SELECT (personal_identification_number) ON public.student FROM authenticated, anon;
REVOKE SELECT (personal_identification_number) ON public.lead_candidate FROM authenticated, anon;


-- CW2-T12: list portfolio guardian + DOB/PIN read model fix.

-- Guardian display in Vietnamese order (family name, then given name).
CREATE OR REPLACE FUNCTION public._cw2_portfolio_primary_contact_display(
  p_guardian_id uuid,
  p_guardian_given_name text,
  p_guardian_family_name text,
  p_guardian_phone text,
  p_lead_contact_id uuid,
  p_lead_contact_given_name text,
  p_lead_contact_family_name text,
  p_lead_contact_phone text
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'primary_guardian_id', COALESCE(p_guardian_id, p_lead_contact_id),
    'primary_guardian_name', NULLIF(btrim(
      CASE
        WHEN p_guardian_id IS NOT NULL THEN
          trim(both FROM COALESCE(p_guardian_family_name, '') || ' ' || COALESCE(p_guardian_given_name, ''))
        ELSE
          trim(both FROM COALESCE(p_lead_contact_family_name, '') || ' ' || COALESCE(p_lead_contact_given_name, ''))
      END
    ), ''),
    'primary_guardian_phone', COALESCE(p_guardian_phone, p_lead_contact_phone)
  );
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
      CASE WHEN public._cw2_can_read_personal_identification(e.organization_id, e.consultant_user_id) THEN COALESCE(s.personal_identification_number, lc.personal_identification_number) ELSE NULL END AS personal_identification_number,
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
      (public._cw2_portfolio_primary_contact_display(
        g.id, g.given_name, g.family_name, g.phone,
        lcg.id, lcg.given_name, lcg.family_name, lcg.phone
      )->>'primary_guardian_id')::uuid AS primary_guardian_id,
      public._cw2_portfolio_primary_contact_display(
        g.id, g.given_name, g.family_name, g.phone,
        lcg.id, lcg.given_name, lcg.family_name, lcg.phone
      )->>'primary_guardian_name' AS primary_guardian_name,
      public._cw2_portfolio_primary_contact_display(
        g.id, g.given_name, g.family_name, g.phone,
        lcg.id, lcg.given_name, lcg.family_name, lcg.phone
      )->>'primary_guardian_phone' AS primary_guardian_phone,
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
      SELECT lc2.id, lc2.given_name, lc2.family_name, lc2.phone
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
        'date_of_birth', p.date_of_birth,
        'personal_identification_number', p.personal_identification_number,
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
          WHEN 'tot_nghiep' THEN 'Tốt nghiệp'
          WHEN 'dang_hoc' THEN 'Đang học'
          WHEN 'ghi_danh' THEN 'Ghi danh'
          ELSE 'Tiềm năng'
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
    'personal_identification_number', CASE WHEN public._cw2_can_read_personal_identification(v_org, v_consultant) THEN COALESCE(s.personal_identification_number, lc.personal_identification_number) ELSE NULL END,
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

-- Backfill canonical role permissions for personal fields (existing orgs at migrate time)
INSERT INTO public.role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM public.role r
JOIN public.permission p ON p.code = 'student_personal_field.manage'
WHERE r.is_canonical_template
  AND r.canonical_code IN ('academic_operations', 'accountant', 'consultant', 'center_manager')
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permission (role_id, permission_id)
SELECT r.id, p.id
FROM public.role r
JOIN public.permission p ON p.code = 'student.personal_id.read'
WHERE r.is_canonical_template
  AND r.canonical_code IN ('academic_operations', 'center_manager')
ON CONFLICT DO NOTHING;

