-- CW2-T12: Consultant intake profile corrective (guardian list read model, DOB/PIN on intake).

ALTER TABLE public.student
  ADD COLUMN IF NOT EXISTS personal_identification_number text;

ALTER TABLE public.lead_candidate
  ADD COLUMN IF NOT EXISTS personal_identification_number text;

COMMENT ON COLUMN public.student.personal_identification_number IS
  'Optional citizen/personal ID (text, leading zeros preserved). Consultant intake + official profile.';
COMMENT ON COLUMN public.lead_candidate.personal_identification_number IS
  'Optional citizen/personal ID on prospective candidate; copied to student on conversion.';

CREATE OR REPLACE FUNCTION public._cw2_normalize_personal_identification_number(p_raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(btrim(p_raw), '');
$$;

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
          trim(both FROM COALESCE(p_guardian_given_name, '') || ' ' || COALESCE(p_guardian_family_name, ''))
        ELSE
          trim(both FROM COALESCE(p_lead_contact_given_name, '') || ' ' || COALESCE(p_lead_contact_family_name, ''))
      END
    ), ''),
    'primary_guardian_phone', COALESCE(p_guardian_phone, p_lead_contact_phone)
  );
$$;

CREATE OR REPLACE FUNCTION public._cw2_propagate_candidate_personal_id_on_convert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'converted'
     AND NEW.converted_student_id IS NOT NULL
     AND NEW.personal_identification_number IS NOT NULL THEN
    UPDATE public.student s
    SET
      personal_identification_number = COALESCE(
        s.personal_identification_number,
        NEW.personal_identification_number
      ),
      updated_at = now()
    WHERE s.id = NEW.converted_student_id
      AND s.organization_id = NEW.organization_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS lead_candidate_propagate_personal_id_on_convert ON public.lead_candidate;
CREATE TRIGGER lead_candidate_propagate_personal_id_on_convert
  AFTER UPDATE OF status, converted_student_id, personal_identification_number ON public.lead_candidate
  FOR EACH ROW
  EXECUTE FUNCTION public._cw2_propagate_candidate_personal_id_on_convert();

DROP FUNCTION IF EXISTS public.create_consultant_workspace_portfolio_intake(text, text, date, text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.create_consultant_workspace_portfolio_intake(
  p_family_name text,
  p_given_name text,
  p_date_of_birth date DEFAULT NULL,
  p_guardian_family_name text DEFAULT NULL,
  p_guardian_given_name text DEFAULT NULL,
  p_guardian_phone text DEFAULT NULL,
  p_personal_identification_number text DEFAULT NULL,
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
  v_pin text;
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

  v_pin := public._cw2_normalize_personal_identification_number(p_personal_identification_number);

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
    personal_identification_number,
    is_primary_candidate, status, created_by, updated_by
  ) VALUES (
    v_org, v_lead_id, v_fn, v_gn, p_date_of_birth,
    v_pin,
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

REVOKE ALL ON FUNCTION public.create_consultant_workspace_portfolio_intake(text, text, date, text, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_consultant_workspace_portfolio_intake(text, text, date, text, text, text, text, jsonb) TO authenticated;

DROP FUNCTION IF EXISTS public.save_consultant_portfolio_profile(uuid, text, text, date, text, text, text, timestamptz);

CREATE OR REPLACE FUNCTION public.save_consultant_portfolio_profile(
  p_portfolio_entry_id uuid,
  p_family_name text,
  p_given_name text,
  p_date_of_birth date DEFAULT NULL,
  p_guardian_family_name text DEFAULT NULL,
  p_guardian_given_name text DEFAULT NULL,
  p_guardian_phone text DEFAULT NULL,
  p_personal_identification_number text DEFAULT NULL,
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
  v_pin text;
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

  v_pin := public._cw2_normalize_personal_identification_number(p_personal_identification_number);

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
      personal_identification_number = COALESCE(v_pin, s.personal_identification_number),
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
      personal_identification_number = COALESCE(v_pin, c.personal_identification_number),
      updated_at = now()
    WHERE c.id = v_lc_id;

    SELECT lc.id INTO v_lc_contact_id
    FROM public.lead_contact lc
    WHERE lc.lead_id = v_entry.lead_id AND lc.organization_id = v_org AND lc.is_primary_contact = true
    ORDER BY lc.created_at
    LIMIT 1;

    IF v_lc_contact_id IS NOT NULL AND (
      p_guardian_family_name IS NOT NULL OR p_guardian_given_name IS NOT NULL OR p_guardian_phone IS NOT NULL
    ) THEN
      UPDATE public.lead_contact lc
      SET
        family_name = COALESCE(NULLIF(btrim(p_guardian_family_name), ''), lc.family_name),
        given_name = COALESCE(NULLIF(btrim(p_guardian_given_name), ''), lc.given_name),
        phone = COALESCE(NULLIF(btrim(p_guardian_phone), ''), lc.phone),
        updated_at = now()
      WHERE lc.id = v_lc_contact_id;
    END IF;
  END IF;

  RETURN public.get_consultant_portfolio_entry_detail(p_portfolio_entry_id);
END;
$$;

REVOKE ALL ON FUNCTION public.save_consultant_portfolio_profile(uuid, text, text, date, text, text, text, text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_consultant_portfolio_profile(uuid, text, text, date, text, text, text, text, timestamptz) TO authenticated;
