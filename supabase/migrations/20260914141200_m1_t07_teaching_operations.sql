-- M1-T07: Room master, teaching audit columns, session idempotency, conflict constraints, generation RPC.

CREATE TABLE room (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  code            text,
  name            text NOT NULL,
  capacity        integer,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT room_status_check CHECK (status IN ('active', 'inactive')),
  CONSTRAINT room_capacity_check CHECK (capacity IS NULL OR capacity > 0)
);

CREATE INDEX idx_room_organization ON room (organization_id);
CREATE INDEX idx_room_active ON room (organization_id) WHERE status = 'active';

CREATE TRIGGER room_updated_at
  BEFORE UPDATE ON room
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE class_schedule
  ADD COLUMN room_id uuid,
  ADD COLUMN teacher_id uuid,
  ADD COLUMN created_by uuid,
  ADD COLUMN updated_by uuid;

ALTER TABLE class_teacher_assignment
  ADD COLUMN created_by uuid,
  ADD COLUMN updated_by uuid;

ALTER TABLE teaching_session
  ADD COLUMN room_id uuid,
  ADD COLUMN occurrence_date date;

ALTER TABLE class_schedule
  ADD CONSTRAINT class_schedule_room_fk
  FOREIGN KEY (organization_id, room_id) REFERENCES room (organization_id, id),
  ADD CONSTRAINT class_schedule_teacher_fk
  FOREIGN KEY (organization_id, teacher_id) REFERENCES teacher (organization_id, id);

ALTER TABLE teaching_session
  ADD CONSTRAINT teaching_session_room_fk
  FOREIGN KEY (organization_id, room_id) REFERENCES room (organization_id, id);

ALTER TABLE room
  ADD CONSTRAINT room_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT room_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

ALTER TABLE class_schedule
  ADD CONSTRAINT class_schedule_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT class_schedule_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

ALTER TABLE class_teacher_assignment
  ADD CONSTRAINT class_teacher_assignment_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT class_teacher_assignment_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

ALTER TABLE teaching_session
  ADD CONSTRAINT teaching_session_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT teaching_session_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

CREATE UNIQUE INDEX teaching_session_schedule_occurrence_unique
  ON teaching_session (organization_id, class_schedule_id, occurrence_date)
  WHERE class_schedule_id IS NOT NULL AND occurrence_date IS NOT NULL;

ALTER TABLE teaching_session
  ADD CONSTRAINT teaching_session_occurrence_dates_check
  CHECK (occurrence_date IS NULL OR class_schedule_id IS NOT NULL);

CREATE INDEX idx_teaching_session_room_time
  ON teaching_session (organization_id, room_id, scheduled_start_at)
  WHERE room_id IS NOT NULL;

ALTER TABLE teaching_session
  ADD CONSTRAINT teaching_session_room_no_overlap EXCLUDE USING gist (
    organization_id WITH =,
    room_id WITH =,
    tstzrange(scheduled_start_at, scheduled_end_at, '[)') WITH &&
  ) WHERE (
    room_id IS NOT NULL
    AND status IN ('scheduled', 'in_progress', 'completed')
  );

ALTER TABLE teaching_session
  ADD CONSTRAINT teaching_session_teacher_no_overlap EXCLUDE USING gist (
    organization_id WITH =,
    teacher_id WITH =,
    tstzrange(scheduled_start_at, scheduled_end_at, '[)') WITH &&
  ) WHERE (
    status IN ('scheduled', 'in_progress', 'completed')
  );

ALTER TABLE room ENABLE ROW LEVEL SECURITY;
ALTER TABLE room FORCE ROW LEVEL SECURITY;

CREATE POLICY room_select ON room FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.read'));
CREATE POLICY room_insert ON room FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.create'));
CREATE POLICY room_update ON room FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'))
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'));

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
  v_primary_count integer;
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

  v_schedule_weekday := CASE v_schedule.weekday_code
    WHEN 'mon' THEN 1 WHEN 'tue' THEN 2 WHEN 'wed' THEN 3 WHEN 'thu' THEN 4
    WHEN 'fri' THEN 5 WHEN 'sat' THEN 6 WHEN 'sun' THEN 0
  END;

  v_cursor := v_bound_start;
  WHILE v_cursor <= v_bound_end LOOP
    v_weekday := EXTRACT(DOW FROM v_cursor)::int;

    IF v_weekday = v_schedule_weekday THEN
      IF v_schedule.teacher_id IS NOT NULL THEN
        v_occurrence_teacher := v_schedule.teacher_id;
      ELSE
        SELECT count(DISTINCT cta.teacher_id) INTO v_primary_count
        FROM class_teacher_assignment cta
        WHERE cta.organization_id = v_org_id
          AND cta.class_id = v_schedule.class_id
          AND cta.status = 'active'
          AND cta.role_code = 'primary'
          AND cta.effective_from <= v_cursor
          AND (cta.effective_to IS NULL OR cta.effective_to >= v_cursor);

        IF v_primary_count <> 1 THEN
          RAISE EXCEPTION 'ambiguous_teacher' USING ERRCODE = 'P0001';
        END IF;

        SELECT cta.teacher_id INTO v_occurrence_teacher
        FROM class_teacher_assignment cta
        WHERE cta.organization_id = v_org_id
          AND cta.class_id = v_schedule.class_id
          AND cta.status = 'active'
          AND cta.role_code = 'primary'
          AND cta.effective_from <= v_cursor
          AND (cta.effective_to IS NULL OR cta.effective_to >= v_cursor)
        LIMIT 1;
      END IF;

      IF v_occurrence_teacher IS NULL THEN
        RAISE EXCEPTION 'no_teacher' USING ERRCODE = 'P0001';
      END IF;

      v_start_at := (v_cursor + v_schedule.start_time) AT TIME ZONE v_timezone;
      v_end_at := (v_cursor + v_schedule.end_time) AT TIME ZONE v_timezone;

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

GRANT EXECUTE ON FUNCTION public.generate_teaching_sessions(uuid, date, date) TO authenticated;
