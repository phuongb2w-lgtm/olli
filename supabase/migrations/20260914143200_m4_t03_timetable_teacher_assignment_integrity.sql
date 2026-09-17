-- M4-T03: Timetable and class teacher assignment transactional integrity.

-- =============================================================================
-- PARTIAL UNIQUE: prevent accidental duplicate active assignment rows
-- =============================================================================

CREATE UNIQUE INDEX class_teacher_assignment_active_exact_unique
  ON class_teacher_assignment (organization_id, class_id, teacher_id, role_code, effective_from)
  WHERE status = 'active';

COMMENT ON INDEX class_teacher_assignment_active_exact_unique IS
  'Prevents accidental duplicate active assignment rows; overlapping different roles/teachers remain valid.';

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._assert_teaching_write_permission(p_mode text)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_mode = 'create' AND NOT public.has_permission('enrollment.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  ELSIF p_mode IN ('update', 'end') AND NOT public.has_permission('enrollment.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._load_class_for_teaching_mutation(p_class_id uuid)
RETURNS class
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_class class%ROWTYPE;
BEGIN
  v_org_id := public.current_organization_id();

  SELECT * INTO v_class
  FROM class
  WHERE id = p_class_id
    AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_class' USING ERRCODE = 'P0002';
  END IF;

  RETURN v_class;
END;
$$;

CREATE OR REPLACE FUNCTION public._assert_class_open_for_teaching_create(p_class class)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_class.status = 'closed' THEN
    RAISE EXCEPTION 'invalid_class_state' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._validate_schedule_effective_range(
  p_effective_from date,
  p_effective_to date,
  p_term_start date,
  p_term_end date
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION 'invalid_schedule_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_effective_to IS NOT NULL AND p_effective_to < p_effective_from THEN
    RAISE EXCEPTION 'invalid_schedule_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_term_start IS NOT NULL AND p_effective_from < p_term_start THEN
    RAISE EXCEPTION 'invalid_schedule_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_term_end IS NOT NULL AND p_effective_from > p_term_end THEN
    RAISE EXCEPTION 'invalid_schedule_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_term_end IS NOT NULL AND p_effective_to IS NOT NULL AND p_effective_to > p_term_end THEN
    RAISE EXCEPTION 'invalid_schedule_range' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._validate_assignment_effective_range(
  p_effective_from date,
  p_effective_to date
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_effective_from IS NULL THEN
    RAISE EXCEPTION 'invalid_assignment_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_effective_to IS NOT NULL AND p_effective_to < p_effective_from THEN
    RAISE EXCEPTION 'invalid_assignment_range' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._validate_active_teacher_reference(p_teacher_id uuid, p_org_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_teacher teacher%ROWTYPE;
BEGIN
  IF p_teacher_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_teacher
  FROM teacher
  WHERE id = p_teacher_id
    AND organization_id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'cross_organization_reference' USING ERRCODE = 'P0001';
  END IF;

  IF v_teacher.status <> 'active' THEN
    RAISE EXCEPTION 'invalid_teacher' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._validate_active_room_reference(p_room_id uuid, p_org_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_room room%ROWTYPE;
BEGIN
  IF p_room_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_room
  FROM room
  WHERE id = p_room_id
    AND organization_id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'cross_organization_reference' USING ERRCODE = 'P0001';
  END IF;

  IF v_room.status <> 'active' THEN
    RAISE EXCEPTION 'room_inactive' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

-- =============================================================================
-- CLASS SCHEDULE RPCs
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_class_schedule(
  p_class_id uuid,
  p_weekday_code text,
  p_start_time time,
  p_end_time time,
  p_effective_from date,
  p_effective_to date DEFAULT NULL,
  p_room_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_class class%ROWTYPE;
  v_schedule_id uuid;
BEGIN
  PERFORM public._assert_teaching_write_permission('create');

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();
  v_class := public._load_class_for_teaching_mutation(p_class_id);
  PERFORM public._assert_class_open_for_teaching_create(v_class);
  PERFORM public._validate_schedule_effective_range(
    p_effective_from, p_effective_to, v_class.term_start_date, v_class.term_end_date
  );
  PERFORM public._validate_active_teacher_reference(p_teacher_id, v_org_id);
  PERFORM public._validate_active_room_reference(p_room_id, v_org_id);

  INSERT INTO class_schedule (
    organization_id,
    class_id,
    weekday_code,
    start_time,
    end_time,
    effective_from,
    effective_to,
    room_id,
    teacher_id,
    status,
    created_by,
    updated_by
  )
  VALUES (
    v_org_id,
    p_class_id,
    p_weekday_code,
    p_start_time,
    p_end_time,
    p_effective_from,
    p_effective_to,
    p_room_id,
    p_teacher_id,
    'active',
    v_actor,
    v_actor
  )
  RETURNING id INTO v_schedule_id;

  RETURN v_schedule_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_class_schedule(
  p_schedule_id uuid,
  p_weekday_code text,
  p_start_time time,
  p_end_time time,
  p_effective_from date,
  p_effective_to date DEFAULT NULL,
  p_room_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_schedule class_schedule%ROWTYPE;
  v_class class%ROWTYPE;
BEGIN
  PERFORM public._assert_teaching_write_permission('update');

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_schedule
  FROM class_schedule
  WHERE id = p_schedule_id
    AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_schedule.status <> 'active' THEN
    RAISE EXCEPTION 'schedule_not_active' USING ERRCODE = 'P0001';
  END IF;

  v_class := public._load_class_for_teaching_mutation(v_schedule.class_id);
  PERFORM public._assert_class_open_for_teaching_create(v_class);
  PERFORM public._validate_schedule_effective_range(
    p_effective_from, p_effective_to, v_class.term_start_date, v_class.term_end_date
  );
  PERFORM public._validate_active_teacher_reference(p_teacher_id, v_org_id);
  PERFORM public._validate_active_room_reference(p_room_id, v_org_id);

  UPDATE class_schedule
  SET
    weekday_code = p_weekday_code,
    start_time = p_start_time,
    end_time = p_end_time,
    effective_from = p_effective_from,
    effective_to = p_effective_to,
    room_id = p_room_id,
    teacher_id = p_teacher_id,
    updated_by = v_actor
  WHERE id = p_schedule_id;

  RETURN p_schedule_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.end_class_schedule(
  p_schedule_id uuid,
  p_effective_to date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_schedule class_schedule%ROWTYPE;
BEGIN
  PERFORM public._assert_teaching_write_permission('end');

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_schedule
  FROM class_schedule
  WHERE id = p_schedule_id
    AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_schedule.status = 'ended' THEN
    RETURN p_schedule_id;
  END IF;

  UPDATE class_schedule
  SET
    status = 'ended',
    effective_to = GREATEST(
      COALESCE(p_effective_to, effective_to, CURRENT_DATE),
      effective_from
    ),
    updated_by = v_actor
  WHERE id = p_schedule_id;

  RETURN p_schedule_id;
END;
$$;

-- =============================================================================
-- CLASS TEACHER ASSIGNMENT RPCs
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_class_teacher_assignment(
  p_class_id uuid,
  p_teacher_id uuid,
  p_role_code text,
  p_effective_from date,
  p_effective_to date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_class class%ROWTYPE;
  v_assignment_id uuid;
BEGIN
  PERFORM public._assert_teaching_write_permission('create');

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();
  v_class := public._load_class_for_teaching_mutation(p_class_id);
  PERFORM public._assert_class_open_for_teaching_create(v_class);
  PERFORM public._validate_assignment_effective_range(p_effective_from, p_effective_to);
  PERFORM public._validate_active_teacher_reference(p_teacher_id, v_org_id);

  INSERT INTO class_teacher_assignment (
    organization_id,
    class_id,
    teacher_id,
    role_code,
    effective_from,
    effective_to,
    status,
    created_by,
    updated_by
  )
  VALUES (
    v_org_id,
    p_class_id,
    p_teacher_id,
    p_role_code,
    p_effective_from,
    p_effective_to,
    'active',
    v_actor,
    v_actor
  )
  RETURNING id INTO v_assignment_id;

  RETURN v_assignment_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_assignment' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.update_class_teacher_assignment(
  p_assignment_id uuid,
  p_role_code text,
  p_effective_from date,
  p_effective_to date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_assignment class_teacher_assignment%ROWTYPE;
  v_class class%ROWTYPE;
BEGIN
  PERFORM public._assert_teaching_write_permission('update');

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_assignment
  FROM class_teacher_assignment
  WHERE id = p_assignment_id
    AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_assignment.status <> 'active' THEN
    RAISE EXCEPTION 'assignment_not_active' USING ERRCODE = 'P0001';
  END IF;

  v_class := public._load_class_for_teaching_mutation(v_assignment.class_id);
  PERFORM public._assert_class_open_for_teaching_create(v_class);
  PERFORM public._validate_assignment_effective_range(p_effective_from, p_effective_to);

  UPDATE class_teacher_assignment
  SET
    role_code = p_role_code,
    effective_from = p_effective_from,
    effective_to = p_effective_to,
    updated_by = v_actor
  WHERE id = p_assignment_id;

  RETURN p_assignment_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'duplicate_assignment' USING ERRCODE = '23505';
END;
$$;

CREATE OR REPLACE FUNCTION public.end_class_teacher_assignment(
  p_assignment_id uuid,
  p_effective_to date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_assignment class_teacher_assignment%ROWTYPE;
BEGIN
  PERFORM public._assert_teaching_write_permission('end');

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_assignment
  FROM class_teacher_assignment
  WHERE id = p_assignment_id
    AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_assignment.status = 'ended' THEN
    RETURN p_assignment_id;
  END IF;

  UPDATE class_teacher_assignment
  SET
    status = 'ended',
    effective_to = GREATEST(
      COALESCE(p_effective_to, effective_to, CURRENT_DATE),
      effective_from
    ),
    updated_by = v_actor
  WHERE id = p_assignment_id;

  RETURN p_assignment_id;
END;
$$;

COMMENT ON FUNCTION public.create_class_schedule IS
  'Creates an active recurring timetable rule. class_schedule.teacher_id is the slot default teacher; NULL falls back to primary assignment at generation.';

COMMENT ON FUNCTION public.create_class_teacher_assignment IS
  'Creates formal class teacher membership with role and effective dates.';

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.create_class_schedule(uuid, text, time, time, date, date, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_class_schedule(uuid, text, time, time, date, date, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_class_schedule(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_class_teacher_assignment(uuid, uuid, text, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_class_teacher_assignment(uuid, text, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_class_teacher_assignment(uuid, date) TO authenticated;
