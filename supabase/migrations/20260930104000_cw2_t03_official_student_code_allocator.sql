-- CW2-T03: authoritative official student code allocator (CCYYNNNN).

-- ---------------------------------------------------------------------------
-- Helpers (IMMUTABLE for indexing)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._cw2_extract_official_sequence_nnnn(p_student_code text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN p_student_code IS NULL OR btrim(p_student_code) = '' THEN NULL
    WHEN btrim(p_student_code) ~ '^[0-9]{8}$'
      AND substring(btrim(p_student_code) from 5 for 4)::integer BETWEEN 1 AND 9999
    THEN substring(btrim(p_student_code) from 5 for 4)::integer
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_is_official_student_code(p_student_code text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT public._cw2_extract_official_sequence_nnnn(p_student_code) IS NOT NULL;
$$;

COMMENT ON FUNCTION public._cw2_is_official_student_code(text) IS
  'True when student_code is an official CW2 CCYYNNNN (8 digits, NNNN 0001-9999).';

CREATE OR REPLACE FUNCTION public._cw2_official_student_code_write_allowed()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(current_setting('cw2.official_student_code_write', true), '') = '1'
    OR current_user IN ('postgres', 'supabase_admin', 'service_role');
$$;

-- Center-wide NNNN uniqueness within an organization (legacy codes excluded).
CREATE UNIQUE INDEX IF NOT EXISTS idx_student_org_cw2_nnnn_unique
  ON public.student (
    organization_id,
    (public._cw2_extract_official_sequence_nnnn(student_code))
  )
  WHERE public._cw2_extract_official_sequence_nnnn(student_code) IS NOT NULL;

COMMENT ON INDEX public.idx_student_org_cw2_nnnn_unique IS
  'CW2: each center NNNN may be consumed at most once per organization for official codes.';

-- ---------------------------------------------------------------------------
-- Student code protection (manual CW2 bypass + official immutability)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protect_student_official_code()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_old_code text := NULLIF(btrim(OLD.student_code), '');
  v_new_code text := NULLIF(btrim(NEW.student_code), '');
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF public._cw2_is_official_student_code(v_old_code) THEN
      IF v_new_code IS DISTINCT FROM v_old_code THEN
        RAISE EXCEPTION 'official_student_code_immutable' USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END IF;

  IF v_new_code IS NOT NULL AND public._cw2_is_official_student_code(v_new_code) THEN
    IF NOT public._cw2_official_student_code_write_allowed() THEN
      RAISE EXCEPTION 'official_student_code_trusted_path_only' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS student_protect_official_code ON public.student;
CREATE TRIGGER student_protect_official_code
  BEFORE INSERT OR UPDATE OF student_code ON public.student
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_student_official_code();

-- ---------------------------------------------------------------------------
-- Allocator result type + RPC
-- ---------------------------------------------------------------------------

CREATE TYPE public.official_student_code_allocation_result AS (
  student_id uuid,
  organization_id uuid,
  official_student_code text,
  consultant_operational_code char(2),
  birth_year_suffix char(2),
  center_sequence_nnnn integer,
  idempotent_replay boolean
);

COMMENT ON TYPE public.official_student_code_allocation_result IS
  'CW2-T03: result of allocate_official_student_code.';

CREATE OR REPLACE FUNCTION public._cw2_student_organization_id(p_student_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT s.organization_id FROM public.student s WHERE s.id = p_student_id;
$$;

REVOKE ALL ON FUNCTION public._cw2_student_organization_id(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public._cw2_advance_organization_student_sequence(p_organization_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next integer;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('payment.record') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF public.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.organization_student_sequence (organization_id, last_allocated_sequence)
  VALUES (p_organization_id, 0)
  ON CONFLICT (organization_id) DO NOTHING;

  SELECT last_allocated_sequence + 1 INTO v_next
  FROM public.organization_student_sequence
  WHERE organization_id = p_organization_id
  FOR UPDATE;

  IF v_next IS NULL OR v_next > 9999 THEN
    RAISE EXCEPTION 'official_student_code_sequence_exhausted' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.organization_student_sequence
  SET last_allocated_sequence = v_next,
      updated_at = now()
  WHERE organization_id = p_organization_id;

  RETURN v_next;
END;
$$;

COMMENT ON FUNCTION public._cw2_advance_organization_student_sequence(uuid) IS
  'CW2-T03 internal: row-lock and advance center NNNN counter (payment.record, same org).';

REVOKE ALL ON FUNCTION public._cw2_advance_organization_student_sequence(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_advance_organization_student_sequence(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.allocate_official_student_code(
  p_student_id uuid,
  p_consultant_app_user_id uuid
)
RETURNS public.official_student_code_allocation_result
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_actor_org uuid;
  v_student public.student%ROWTYPE;
  v_consultant public.app_user%ROWTYPE;
  v_next integer;
  v_yy char(2);
  v_code text;
  v_existing_nnnn integer;
  v_result public.official_student_code_allocation_result;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('payment.record') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_actor_org := public.current_organization_id();
  IF v_actor_org IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF public._cw2_student_organization_id(p_student_id) IS NULL THEN
    RAISE EXCEPTION 'student_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF public._cw2_student_organization_id(p_student_id) IS DISTINCT FROM v_actor_org THEN
    RAISE EXCEPTION 'invalid_student' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_student
  FROM public.student s
  WHERE s.id = p_student_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'student_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_existing_nnnn := public._cw2_extract_official_sequence_nnnn(v_student.student_code);
  IF v_existing_nnnn IS NOT NULL THEN
    SELECT u.consultant_operational_code INTO v_consultant.consultant_operational_code
    FROM public.app_user u
    WHERE u.id = p_consultant_app_user_id
      AND u.organization_id = v_actor_org;

    v_result.student_id := v_student.id;
    v_result.organization_id := v_student.organization_id;
    v_result.official_student_code := btrim(v_student.student_code);
    v_result.consultant_operational_code := substring(v_result.official_student_code from 1 for 2)::char(2);
    v_result.birth_year_suffix := substring(v_result.official_student_code from 3 for 2)::char(2);
    v_result.center_sequence_nnnn := v_existing_nnnn;
    v_result.idempotent_replay := true;
    RETURN v_result;
  END IF;

  IF v_student.student_code IS NOT NULL AND btrim(v_student.student_code) <> '' THEN
    RAISE EXCEPTION 'student_code_already_set' USING ERRCODE = 'P0001';
  END IF;

  IF v_student.date_of_birth IS NULL THEN
    RAISE EXCEPTION 'student_dob_required' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_consultant
  FROM public.app_user u
  WHERE u.id = p_consultant_app_user_id
    AND u.organization_id = v_actor_org
    AND u.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_consultant' USING ERRCODE = 'P0001';
  END IF;
  IF v_consultant.consultant_operational_code IS NULL
     OR NOT public._cw2_validate_consultant_operational_code(v_consultant.consultant_operational_code) THEN
    RAISE EXCEPTION 'consultant_operational_code_required' USING ERRCODE = 'P0001';
  END IF;

  v_yy := lpad((EXTRACT(YEAR FROM v_student.date_of_birth)::integer % 100)::text, 2, '0');

  v_next := public._cw2_advance_organization_student_sequence(v_actor_org);

  v_code := v_consultant.consultant_operational_code
    || v_yy
    || lpad(v_next::text, 4, '0');

  PERFORM set_config('cw2.official_student_code_write', '1', true);

  UPDATE public.student
  SET student_code = v_code,
      updated_by = public.current_app_user_id()
  WHERE id = v_student.id;

  v_result.student_id := v_student.id;
  v_result.organization_id := v_student.organization_id;
  v_result.official_student_code := v_code;
  v_result.consultant_operational_code := v_consultant.consultant_operational_code;
  v_result.birth_year_suffix := v_yy;
  v_result.center_sequence_nnnn := v_next;
  v_result.idempotent_replay := false;
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.allocate_official_student_code(uuid, uuid) IS
  'CW2-T03: allocate official CCYYNNNN to a student (payment.record, same org). Idempotent when official code already set.';

REVOKE ALL ON FUNCTION public.allocate_official_student_code(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.allocate_official_student_code(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public._cw2_is_official_student_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_official_student_code_write_allowed() FROM PUBLIC;
