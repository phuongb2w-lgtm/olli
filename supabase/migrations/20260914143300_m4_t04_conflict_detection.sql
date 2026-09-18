-- M4-T04: Scheduling conflict detection and enforcement.

-- =============================================================================
-- CONFLICT RESULT TYPE
-- =============================================================================

CREATE TYPE schedule_conflict_entry AS (
  conflict_type          text,
  occurrence_date        date,
  starts_at              timestamptz,
  ends_at                timestamptz,
  teacher_id             uuid,
  room_id                uuid,
  conflicting_class_id   uuid,
  conflicting_schedule_id uuid,
  conflicting_session_id uuid
);

COMMENT ON TYPE schedule_conflict_entry IS
  'Derived scheduling conflict for preview. Hard types: teacher_unavailable, teacher_double_booked, room_double_booked, invalid_interval, teacher_not_resolved, multiple_primary_teachers.';

-- Open-ended schedules evaluate effective_from through the lesser of class term_end_date
-- and effective_from + 180 days (one academic-term planning horizon).
CREATE OR REPLACE FUNCTION public._schedule_conflict_eval_end(
  p_effective_from date,
  p_effective_to date,
  p_term_end date
)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_horizon_end date := p_effective_from + 179;
BEGIN
  IF p_effective_from IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_effective_to IS NOT NULL THEN
    RETURN LEAST(p_effective_to, COALESCE(p_term_end, p_effective_to));
  END IF;

  IF p_term_end IS NOT NULL THEN
    RETURN LEAST(p_term_end, v_horizon_end);
  END IF;

  RETURN v_horizon_end;
END;
$$;

-- =============================================================================
-- CANONICAL TEACHER RESOLUTION (shared with session generation)
-- =============================================================================

CREATE OR REPLACE FUNCTION public._resolve_occurrence_teacher(
  p_org_id uuid,
  p_class_id uuid,
  p_schedule_teacher_id uuid,
  p_occurrence_date date,
  OUT p_teacher_id uuid,
  OUT p_resolution_status text
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_primary_count integer;
BEGIN
  p_resolution_status := 'resolved';
  p_teacher_id := NULL;

  IF p_schedule_teacher_id IS NOT NULL THEN
    p_teacher_id := p_schedule_teacher_id;
    RETURN;
  END IF;

  SELECT count(DISTINCT cta.teacher_id) INTO v_primary_count
  FROM class_teacher_assignment cta
  WHERE cta.organization_id = p_org_id
    AND cta.class_id = p_class_id
    AND cta.status = 'active'
    AND cta.role_code = 'primary'
    AND cta.effective_from <= p_occurrence_date
    AND (cta.effective_to IS NULL OR cta.effective_to >= p_occurrence_date);

  IF v_primary_count = 0 THEN
    p_resolution_status := 'teacher_not_resolved';
    RETURN;
  END IF;

  IF v_primary_count > 1 THEN
    p_resolution_status := 'multiple_primary_teachers';
    RETURN;
  END IF;

  SELECT cta.teacher_id INTO p_teacher_id
  FROM class_teacher_assignment cta
  WHERE cta.organization_id = p_org_id
    AND cta.class_id = p_class_id
    AND cta.status = 'active'
    AND cta.role_code = 'primary'
    AND cta.effective_from <= p_occurrence_date
    AND (cta.effective_to IS NULL OR cta.effective_to >= p_occurrence_date)
  LIMIT 1;
END;
$$;

-- =============================================================================
-- CONFLICT COLLECTION
-- Materialized sessions take precedence over recurring-rule projection for the
-- same schedule occurrence. Recurring rules are evaluated only when no active
-- (non-cancelled) session exists for that schedule+date.
-- =============================================================================

CREATE OR REPLACE FUNCTION public._collect_schedule_conflicts(
  p_org_id uuid,
  p_class_id uuid,
  p_weekday_code text,
  p_start_time time,
  p_end_time time,
  p_effective_from date,
  p_effective_to date,
  p_room_id uuid,
  p_teacher_id uuid,
  p_exclude_schedule_id uuid DEFAULT NULL,
  p_term_end date DEFAULT NULL
)
RETURNS SETOF schedule_conflict_entry
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_timezone text;
  v_eval_end date;
  v_cursor date;
  v_weekday int;
  v_proposed_weekday int;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_resolved_teacher uuid;
  v_resolution_status text;
  v_other record;
  v_other_teacher uuid;
  v_other_resolution text;
  v_other_start timestamptz;
  v_other_end timestamptz;
  v_entry schedule_conflict_entry;
BEGIN
  IF p_effective_from IS NULL OR p_start_time IS NULL OR p_end_time IS NULL THEN
    v_entry.conflict_type := 'invalid_interval';
    RETURN NEXT v_entry;
    RETURN;
  END IF;

  IF p_end_time <= p_start_time THEN
    v_entry.conflict_type := 'invalid_interval';
    RETURN NEXT v_entry;
    RETURN;
  END IF;

  IF p_effective_to IS NOT NULL AND p_effective_to < p_effective_from THEN
    v_entry.conflict_type := 'invalid_interval';
    RETURN NEXT v_entry;
    RETURN;
  END IF;

  SELECT o.timezone INTO v_timezone
  FROM organization o
  WHERE o.id = p_org_id;

  v_eval_end := public._schedule_conflict_eval_end(p_effective_from, p_effective_to, p_term_end);
  IF v_eval_end IS NULL OR v_eval_end < p_effective_from THEN
    RETURN;
  END IF;

  v_proposed_weekday := public._weekday_code_to_dow(p_weekday_code);
  v_cursor := p_effective_from;

  WHILE v_cursor <= v_eval_end LOOP
    v_weekday := EXTRACT(DOW FROM v_cursor)::int;

    IF v_weekday = v_proposed_weekday THEN
      v_start_at := (v_cursor + p_start_time) AT TIME ZONE v_timezone;
      v_end_at := (v_cursor + p_end_time) AT TIME ZONE v_timezone;

      SELECT x.p_teacher_id, x.p_resolution_status
      INTO v_resolved_teacher, v_resolution_status
      FROM public._resolve_occurrence_teacher(
        p_org_id, p_class_id, p_teacher_id, v_cursor
      ) AS x;

      IF v_resolution_status = 'teacher_not_resolved' THEN
        v_entry.conflict_type := 'teacher_not_resolved';
        v_entry.occurrence_date := v_cursor;
        v_entry.starts_at := v_start_at;
        v_entry.ends_at := v_end_at;
        v_entry.teacher_id := NULL;
        v_entry.room_id := p_room_id;
        v_entry.conflicting_class_id := NULL;
        v_entry.conflicting_schedule_id := NULL;
        v_entry.conflicting_session_id := NULL;
        RETURN NEXT v_entry;
      ELSIF v_resolution_status = 'multiple_primary_teachers' THEN
        v_entry.conflict_type := 'multiple_primary_teachers';
        v_entry.occurrence_date := v_cursor;
        v_entry.starts_at := v_start_at;
        v_entry.ends_at := v_end_at;
        v_entry.teacher_id := NULL;
        v_entry.room_id := p_room_id;
        v_entry.conflicting_class_id := NULL;
        v_entry.conflicting_schedule_id := NULL;
        v_entry.conflicting_session_id := NULL;
        RETURN NEXT v_entry;
      END IF;

      IF v_resolved_teacher IS NOT NULL
        AND public.teacher_has_unavailability(v_resolved_teacher, v_start_at, v_end_at) THEN
        v_entry.conflict_type := 'teacher_unavailable';
        v_entry.occurrence_date := v_cursor;
        v_entry.starts_at := v_start_at;
        v_entry.ends_at := v_end_at;
        v_entry.teacher_id := v_resolved_teacher;
        v_entry.room_id := p_room_id;
        v_entry.conflicting_class_id := NULL;
        v_entry.conflicting_schedule_id := NULL;
        v_entry.conflicting_session_id := NULL;
        RETURN NEXT v_entry;
      END IF;

      -- Materialized session conflicts (exclude self schedule and cancelled sessions)
      FOR v_other IN
        SELECT ts.id, ts.class_id, ts.class_schedule_id, ts.teacher_id, ts.room_id,
               ts.scheduled_start_at, ts.scheduled_end_at
        FROM teaching_session ts
        WHERE ts.organization_id = p_org_id
          AND ts.status IN ('scheduled', 'in_progress', 'completed')
          AND tstzrange(ts.scheduled_start_at, ts.scheduled_end_at, '[)')
              && tstzrange(v_start_at, v_end_at, '[)')
          AND (
            (v_resolved_teacher IS NOT NULL AND ts.teacher_id = v_resolved_teacher)
            OR (p_room_id IS NOT NULL AND ts.room_id = p_room_id)
          )
          AND (p_exclude_schedule_id IS NULL OR ts.class_schedule_id IS DISTINCT FROM p_exclude_schedule_id)
      LOOP
        IF v_resolved_teacher IS NOT NULL AND v_other.teacher_id = v_resolved_teacher THEN
          v_entry.conflict_type := 'teacher_double_booked';
          v_entry.occurrence_date := v_cursor;
          v_entry.starts_at := v_start_at;
          v_entry.ends_at := v_end_at;
          v_entry.teacher_id := v_resolved_teacher;
          v_entry.room_id := p_room_id;
          v_entry.conflicting_class_id := v_other.class_id;
          v_entry.conflicting_schedule_id := v_other.class_schedule_id;
          v_entry.conflicting_session_id := v_other.id;
          RETURN NEXT v_entry;
        END IF;

        IF p_room_id IS NOT NULL AND v_other.room_id = p_room_id THEN
          v_entry.conflict_type := 'room_double_booked';
          v_entry.occurrence_date := v_cursor;
          v_entry.starts_at := v_start_at;
          v_entry.ends_at := v_end_at;
          v_entry.teacher_id := v_resolved_teacher;
          v_entry.room_id := p_room_id;
          v_entry.conflicting_class_id := v_other.class_id;
          v_entry.conflicting_schedule_id := v_other.class_schedule_id;
          v_entry.conflicting_session_id := v_other.id;
          RETURN NEXT v_entry;
        END IF;
      END LOOP;

      -- Recurring schedule rule conflicts (skip dates already materialized)
      FOR v_other IN
        SELECT cs.id, cs.class_id, cs.weekday_code, cs.start_time, cs.end_time,
               cs.teacher_id, cs.room_id
        FROM class_schedule cs
        WHERE cs.organization_id = p_org_id
          AND cs.status = 'active'
          AND cs.id IS DISTINCT FROM p_exclude_schedule_id
          AND public._weekday_code_to_dow(cs.weekday_code) = v_proposed_weekday
          AND cs.start_time < p_end_time
          AND cs.end_time > p_start_time
          AND cs.effective_from <= v_cursor
          AND (cs.effective_to IS NULL OR cs.effective_to >= v_cursor)
          AND NOT EXISTS (
            SELECT 1
            FROM teaching_session ts
            WHERE ts.organization_id = p_org_id
              AND ts.class_schedule_id = cs.id
              AND ts.occurrence_date = v_cursor
              AND ts.status IN ('scheduled', 'in_progress', 'completed')
          )
      LOOP
        v_other_start := (v_cursor + v_other.start_time) AT TIME ZONE v_timezone;
        v_other_end := (v_cursor + v_other.end_time) AT TIME ZONE v_timezone;

        IF NOT (tstzrange(v_other_start, v_other_end, '[)') && tstzrange(v_start_at, v_end_at, '[)')) THEN
          CONTINUE;
        END IF;

        SELECT x.p_teacher_id, x.p_resolution_status
        INTO v_other_teacher, v_other_resolution
        FROM public._resolve_occurrence_teacher(
          p_org_id, v_other.class_id, v_other.teacher_id, v_cursor
        ) AS x;

        IF v_resolved_teacher IS NOT NULL
          AND v_other_teacher IS NOT NULL
          AND v_resolved_teacher = v_other_teacher THEN
          v_entry.conflict_type := 'teacher_double_booked';
          v_entry.occurrence_date := v_cursor;
          v_entry.starts_at := v_start_at;
          v_entry.ends_at := v_end_at;
          v_entry.teacher_id := v_resolved_teacher;
          v_entry.room_id := p_room_id;
          v_entry.conflicting_class_id := v_other.class_id;
          v_entry.conflicting_schedule_id := v_other.id;
          v_entry.conflicting_session_id := NULL;
          RETURN NEXT v_entry;
        END IF;

        IF p_room_id IS NOT NULL
          AND v_other.room_id IS NOT NULL
          AND p_room_id = v_other.room_id THEN
          v_entry.conflict_type := 'room_double_booked';
          v_entry.occurrence_date := v_cursor;
          v_entry.starts_at := v_start_at;
          v_entry.ends_at := v_end_at;
          v_entry.teacher_id := v_resolved_teacher;
          v_entry.room_id := p_room_id;
          v_entry.conflicting_class_id := v_other.class_id;
          v_entry.conflicting_schedule_id := v_other.id;
          v_entry.conflicting_session_id := NULL;
          RETURN NEXT v_entry;
        END IF;
      END LOOP;
    END IF;

    v_cursor := v_cursor + 1;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public._assert_no_schedule_conflicts(
  p_org_id uuid,
  p_class_id uuid,
  p_weekday_code text,
  p_start_time time,
  p_end_time time,
  p_effective_from date,
  p_effective_to date,
  p_room_id uuid,
  p_teacher_id uuid,
  p_exclude_schedule_id uuid DEFAULT NULL,
  p_term_end date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_conflict schedule_conflict_entry;
BEGIN
  SELECT * INTO v_conflict
  FROM public._collect_schedule_conflicts(
    p_org_id, p_class_id, p_weekday_code, p_start_time, p_end_time,
    p_effective_from, p_effective_to, p_room_id, p_teacher_id,
    p_exclude_schedule_id, p_term_end
  )
  WHERE conflict_type IN (
    'teacher_unavailable',
    'teacher_double_booked',
    'room_double_booked',
    'invalid_interval'
  )
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  CASE v_conflict.conflict_type
    WHEN 'teacher_unavailable' THEN
      RAISE EXCEPTION 'teacher_unavailable' USING ERRCODE = 'P0001';
    WHEN 'teacher_double_booked' THEN
      RAISE EXCEPTION 'teacher_double_booked' USING ERRCODE = 'P0001';
    WHEN 'room_double_booked' THEN
      RAISE EXCEPTION 'room_double_booked' USING ERRCODE = 'P0001';
    WHEN 'invalid_interval' THEN
      RAISE EXCEPTION 'invalid_interval' USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'schedule_conflict' USING ERRCODE = '23P01';
  END CASE;
END;
$$;

-- =============================================================================
-- PUBLIC PREVIEW RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_class_schedule_conflicts(
  p_class_id uuid,
  p_weekday_code text,
  p_start_time time,
  p_end_time time,
  p_effective_from date,
  p_effective_to date DEFAULT NULL,
  p_room_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL,
  p_exclude_schedule_id uuid DEFAULT NULL
)
RETURNS SETOF schedule_conflict_entry
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_class class%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_class := public._load_class_for_teaching_mutation(p_class_id);

  RETURN QUERY
  SELECT *
  FROM public._collect_schedule_conflicts(
    v_org_id,
    p_class_id,
    p_weekday_code,
    p_start_time,
    p_end_time,
    p_effective_from,
    p_effective_to,
    p_room_id,
    p_teacher_id,
    p_exclude_schedule_id,
    v_class.term_end_date
  );
END;
$$;

COMMENT ON FUNCTION public.check_class_schedule_conflicts IS
  'Preview hard scheduling conflicts for a proposed recurring timetable over a bounded date range. Open-ended schedules evaluate through term_end_date or a 180-day planning horizon.';

-- =============================================================================
-- INDEXES FOR CONFLICT QUERIES
-- =============================================================================

CREATE INDEX idx_class_schedule_active_weekday
  ON class_schedule (organization_id, weekday_code, status)
  WHERE status = 'active';

CREATE INDEX idx_class_schedule_active_effective
  ON class_schedule (organization_id, effective_from, effective_to)
  WHERE status = 'active';

-- =============================================================================
-- UPDATE TIMETABLE RPCs: enforce conflict checks on save
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

  PERFORM public._assert_no_schedule_conflicts(
    v_org_id, p_class_id, p_weekday_code, p_start_time, p_end_time,
    p_effective_from, p_effective_to, p_room_id, p_teacher_id,
    NULL, v_class.term_end_date
  );

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

  PERFORM public._assert_no_schedule_conflicts(
    v_org_id, v_schedule.class_id, p_weekday_code, p_start_time, p_end_time,
    p_effective_from, p_effective_to, p_room_id, p_teacher_id,
    p_schedule_id, v_class.term_end_date
  );

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

-- =============================================================================
-- UPDATE SESSION GENERATION: enforce teacher unavailability
-- =============================================================================

CREATE OR REPLACE FUNCTION public.generate_teaching_sessions(
  p_class_schedule_id uuid,
  p_range_start date,
  p_range_end date
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_timezone text;
  v_schedule class_schedule%ROWTYPE;
  v_class class%ROWTYPE;
  v_bound_start date;
  v_bound_end date;
  v_cursor date;
  v_weekday int;
  v_schedule_weekday int;
  v_occurrence_teacher uuid;
  v_resolution_status text;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_inserted integer := 0;
  v_row_count integer;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_range_start IS NULL OR p_range_end IS NULL OR p_range_end < p_range_start THEN
    RAISE EXCEPTION 'invalid_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_range_end - p_range_start > 366 THEN
    RAISE EXCEPTION 'range_too_large' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_schedule
  FROM class_schedule
  WHERE id = p_class_schedule_id
    AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_schedule.status <> 'active' THEN
    RAISE EXCEPTION 'schedule_not_active' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_class
  FROM class
  WHERE id = v_schedule.class_id
    AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_class' USING ERRCODE = 'P0002';
  END IF;

  IF v_class.status = 'closed' THEN
    RAISE EXCEPTION 'class_closed' USING ERRCODE = 'P0001';
  END IF;

  SELECT o.timezone INTO v_timezone
  FROM organization o
  WHERE o.id = v_org_id;

  v_bound_start := GREATEST(
    p_range_start,
    v_schedule.effective_from,
    COALESCE(v_class.term_start_date, p_range_start)
  );

  v_bound_end := LEAST(
    p_range_end,
    COALESCE(v_schedule.effective_to, p_range_end),
    COALESCE(v_class.term_end_date, p_range_end)
  );

  IF v_bound_end < v_bound_start THEN
    RETURN 0;
  END IF;

  v_schedule_weekday := public._weekday_code_to_dow(v_schedule.weekday_code);

  v_cursor := v_bound_start;
  WHILE v_cursor <= v_bound_end LOOP
    v_weekday := EXTRACT(DOW FROM v_cursor)::int;

    IF v_weekday = v_schedule_weekday THEN
      SELECT x.p_teacher_id, x.p_resolution_status
      INTO v_occurrence_teacher, v_resolution_status
      FROM public._resolve_occurrence_teacher(
        v_org_id, v_schedule.class_id, v_schedule.teacher_id, v_cursor
      ) AS x;

      IF v_resolution_status = 'multiple_primary_teachers' THEN
        RAISE EXCEPTION 'ambiguous_teacher' USING ERRCODE = 'P0001';
      END IF;

      IF v_occurrence_teacher IS NULL THEN
        RAISE EXCEPTION 'no_teacher' USING ERRCODE = 'P0001';
      END IF;

      v_start_at := (v_cursor + v_schedule.start_time) AT TIME ZONE v_timezone;
      v_end_at := (v_cursor + v_schedule.end_time) AT TIME ZONE v_timezone;

      IF public.teacher_has_unavailability(v_occurrence_teacher, v_start_at, v_end_at) THEN
        RAISE EXCEPTION 'teacher_unavailable' USING ERRCODE = 'P0001';
      END IF;

      INSERT INTO teaching_session (
        organization_id,
        class_id,
        class_schedule_id,
        teacher_id,
        room_id,
        occurrence_date,
        scheduled_start_at,
        scheduled_end_at,
        status,
        created_by,
        updated_by
      )
      VALUES (
        v_org_id,
        v_schedule.class_id,
        v_schedule.id,
        v_occurrence_teacher,
        v_schedule.room_id,
        v_cursor,
        v_start_at,
        v_end_at,
        'scheduled',
        v_actor,
        v_actor
      )
      ON CONFLICT (organization_id, class_schedule_id, occurrence_date)
      WHERE class_schedule_id IS NOT NULL AND occurrence_date IS NOT NULL
      DO NOTHING;

      GET DIAGNOSTICS v_row_count = ROW_COUNT;
      v_inserted := v_inserted + v_row_count;
    END IF;

    v_cursor := v_cursor + 1;
  END LOOP;

  RETURN v_inserted;
EXCEPTION
  WHEN exclusion_violation THEN
    RAISE EXCEPTION 'schedule_conflict' USING ERRCODE = '23P01';
END;
$$;

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.check_class_schedule_conflicts(uuid, text, time, time, date, date, uuid, uuid, uuid) TO authenticated;
