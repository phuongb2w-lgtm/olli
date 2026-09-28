-- CW2-T02.1: center-wide student sequence bootstrap from existing CW2-shaped codes only.

CREATE OR REPLACE FUNCTION public._cw2_extract_official_sequence_nnnn(p_student_code text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_student_code IS NULL OR btrim(p_student_code) = '' THEN NULL
    WHEN btrim(p_student_code) ~ '^[0-9]{8}$'
      AND substring(btrim(p_student_code) from 5 for 4)::integer BETWEEN 1 AND 9999
    THEN substring(btrim(p_student_code) from 5 for 4)::integer
    ELSE NULL
  END;
$$;

COMMENT ON FUNCTION public._cw2_extract_official_sequence_nnnn(text) IS
  'CW2 bootstrap: infer center NNNN from stored CCYYNNNN-shaped student_code. Legacy/manual codes (e.g. HV001) return NULL. 0000 is never official.';

CREATE OR REPLACE FUNCTION public._cw2_compute_organization_student_sequence_floor(p_organization_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT max(public._cw2_extract_official_sequence_nnnn(s.student_code))
      FROM public.student s
      WHERE s.organization_id = p_organization_id
    ),
    0
  );
$$;

COMMENT ON FUNCTION public._cw2_compute_organization_student_sequence_floor(uuid) IS
  'Highest NNNN already present in CW2-shaped student_code values for the org. Does not use COUNT(student) or portfolio STT.';

CREATE OR REPLACE FUNCTION public._cw2_refresh_organization_student_sequence_floor(p_organization_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_floor integer;
  v_new integer;
BEGIN
  v_floor := public._cw2_compute_organization_student_sequence_floor(p_organization_id);

  INSERT INTO public.organization_student_sequence (organization_id, last_allocated_sequence)
  VALUES (p_organization_id, v_floor)
  ON CONFLICT (organization_id) DO UPDATE
  SET last_allocated_sequence = GREATEST(
    public.organization_student_sequence.last_allocated_sequence,
    EXCLUDED.last_allocated_sequence
  )
  RETURNING last_allocated_sequence INTO v_new;

  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_student_code_refresh_org_sequence_floor()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._cw2_refresh_organization_student_sequence_floor(NEW.organization_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS student_code_refresh_org_sequence_floor ON public.student;
CREATE TRIGGER student_code_refresh_org_sequence_floor
  AFTER INSERT OR UPDATE OF student_code ON public.student
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_student_code_refresh_org_sequence_floor();

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
END;
$$;

COMMENT ON COLUMN public.organization_student_sequence.last_allocated_sequence IS
  'Highest center-wide NNNN already issued via official CW2-shaped student_code (or future T03 allocator). Legacy non-shaped codes do not advance this counter. Next allocation uses last + 1 under row lock in T03.';

DO $$
DECLARE
  org_record record;
BEGIN
  FOR org_record IN SELECT id FROM public.organization LOOP
    PERFORM public._cw2_refresh_organization_student_sequence_floor(org_record.id);
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public._cw2_extract_official_sequence_nnnn(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_compute_organization_student_sequence_floor(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_refresh_organization_student_sequence_floor(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_refresh_organization_student_sequence_floor(uuid) TO service_role;
