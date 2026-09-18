-- M4-T06: Auditable teaching session operations (reschedule / cancel / substitute / room).
-- teaching_session remains canonical current state; teaching_session_change is append-only history.
-- Also adjusts T05 calendar session date filter to use scheduled local date (reschedule-aware).

-- =============================================================================
-- HISTORY TABLE
-- =============================================================================

CREATE TABLE teaching_session_change (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                 uuid NOT NULL,
  teaching_session_id             uuid NOT NULL,
  change_type                     text NOT NULL,
  reason                          text,
  actor_id                        uuid NOT NULL,
  occurred_at                     timestamptz NOT NULL DEFAULT clock_timestamp(),
  previous_scheduled_start_at     timestamptz,
  previous_scheduled_end_at       timestamptz,
  new_scheduled_start_at          timestamptz,
  new_scheduled_end_at            timestamptz,
  previous_teacher_id             uuid,
  new_teacher_id                  uuid,
  previous_room_id                uuid,
  new_room_id                     uuid,
  previous_status                 text,
  new_status                      text,
  UNIQUE (organization_id, id),
  CONSTRAINT teaching_session_change_type_check CHECK (
    change_type IN ('rescheduled', 'cancelled', 'teacher_substituted', 'room_changed')
  ),
  FOREIGN KEY (organization_id, teaching_session_id)
    REFERENCES teaching_session (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_id)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, previous_teacher_id)
    REFERENCES teacher (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, new_teacher_id)
    REFERENCES teacher (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, previous_room_id)
    REFERENCES room (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, new_room_id)
    REFERENCES room (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_teaching_session_change_session
  ON teaching_session_change (organization_id, teaching_session_id, occurred_at ASC, id ASC);

COMMENT ON TABLE teaching_session_change IS
  'Append-only operational history for teaching_session mutations. Does not replace current session state.';

-- =============================================================================
-- APPEND-ONLY + FIELD PROTECTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_teaching_session_change_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.teaching_session_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'teaching_session_change_immutable' USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER teaching_session_change_protect_immutable
  BEFORE UPDATE OR DELETE ON teaching_session_change
  FOR EACH ROW EXECUTE FUNCTION public.protect_teaching_session_change_immutable();

-- Force reschedule/cancel/substitute/room through RPCs; allow execution start/complete.
CREATE OR REPLACE FUNCTION public.protect_teaching_session_operational_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.teaching_session_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.scheduled_start_at IS DISTINCT FROM OLD.scheduled_start_at
     OR NEW.scheduled_end_at IS DISTINCT FROM OLD.scheduled_end_at
     OR NEW.teacher_id IS DISTINCT FROM OLD.teacher_id
     OR NEW.room_id IS DISTINCT FROM OLD.room_id
     OR NEW.occurrence_date IS DISTINCT FROM OLD.occurrence_date
     OR NEW.class_schedule_id IS DISTINCT FROM OLD.class_schedule_id
  THEN
    RAISE EXCEPTION 'teaching_session_operational_fields_protected' USING ERRCODE = '42501';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT (
       (OLD.status = 'scheduled' AND NEW.status = 'in_progress')
       OR (OLD.status = 'in_progress' AND NEW.status = 'completed')
       OR (OLD.status = 'scheduled' AND NEW.status = 'completed')
     )
  THEN
    RAISE EXCEPTION 'teaching_session_status_protected' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER teaching_session_protect_operational_fields
  BEFORE UPDATE ON teaching_session
  FOR EACH ROW EXECUTE FUNCTION public.protect_teaching_session_operational_fields();

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE teaching_session_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE teaching_session_change FORCE ROW LEVEL SECURITY;

CREATE POLICY teaching_session_change_select ON teaching_session_change
  FOR SELECT TO authenticated
  USING (
    organization_id = public.current_organization_id()
    AND public.has_permission('enrollment.read')
  );

CREATE POLICY teaching_session_change_insert ON teaching_session_change
  FOR INSERT TO authenticated
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND public.has_permission('enrollment.update')
    AND actor_id = public.current_app_user_id()
  );

GRANT SELECT, INSERT ON teaching_session_change TO authenticated;

-- =============================================================================
-- SESSION INTERVAL CONFLICT HELPER
-- =============================================================================

CREATE OR REPLACE FUNCTION public._assert_session_interval_ok(
  p_org_id uuid,
  p_exclude_session_id uuid,
  p_teacher_id uuid,
  p_room_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at THEN
    RAISE EXCEPTION 'invalid_interval' USING ERRCODE = 'P0001';
  END IF;

  IF p_teacher_id IS NOT NULL
     AND public.teacher_has_unavailability(p_teacher_id, p_starts_at, p_ends_at) THEN
    RAISE EXCEPTION 'teacher_unavailable' USING ERRCODE = 'P0001';
  END IF;

  IF p_teacher_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM teaching_session ts
    WHERE ts.organization_id = p_org_id
      AND ts.id IS DISTINCT FROM p_exclude_session_id
      AND ts.status IN ('scheduled', 'in_progress', 'completed')
      AND ts.teacher_id = p_teacher_id
      AND tstzrange(ts.scheduled_start_at, ts.scheduled_end_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) THEN
    RAISE EXCEPTION 'teacher_double_booked' USING ERRCODE = 'P0001';
  END IF;

  IF p_room_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM teaching_session ts
    WHERE ts.organization_id = p_org_id
      AND ts.id IS DISTINCT FROM p_exclude_session_id
      AND ts.status IN ('scheduled', 'in_progress', 'completed')
      AND ts.room_id = p_room_id
      AND tstzrange(ts.scheduled_start_at, ts.scheduled_end_at, '[)')
          && tstzrange(p_starts_at, p_ends_at, '[)')
  ) THEN
    RAISE EXCEPTION 'room_double_booked' USING ERRCODE = 'P0001';
  END IF;
END;
$$;

COMMENT ON FUNCTION public._assert_session_interval_ok(uuid, uuid, uuid, uuid, timestamptz, timestamptz) IS
  'Validates a proposed materialized session interval. Excludes p_exclude_session_id from self-conflict.';

CREATE OR REPLACE FUNCTION public._session_has_posted_financial_effects(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM revenue_recognition_event r
    WHERE r.teaching_session_id = p_session_id
      AND r.organization_id = public.current_organization_id()
      AND r.status = 'posted'
  )
  OR EXISTS (
    SELECT 1
    FROM personnel_cost_entry p
    WHERE p.teaching_session_id = p_session_id
      AND p.organization_id = public.current_organization_id()
      AND p.status = 'posted'
  );
$$;

CREATE OR REPLACE FUNCTION public._session_has_attendance(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM attendance a
    WHERE a.teaching_session_id = p_session_id
      AND a.organization_id = public.current_organization_id()
  );
$$;

CREATE OR REPLACE FUNCTION public._append_teaching_session_change(
  p_session_id uuid,
  p_change_type text,
  p_reason text,
  p_prev_start timestamptz DEFAULT NULL,
  p_new_start timestamptz DEFAULT NULL,
  p_prev_end timestamptz DEFAULT NULL,
  p_new_end timestamptz DEFAULT NULL,
  p_prev_teacher uuid DEFAULT NULL,
  p_new_teacher uuid DEFAULT NULL,
  p_prev_room uuid DEFAULT NULL,
  p_new_room uuid DEFAULT NULL,
  p_prev_status text DEFAULT NULL,
  p_new_status text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_actor uuid := public.current_app_user_id();
  v_id uuid;
BEGIN
  INSERT INTO teaching_session_change (
    organization_id, teaching_session_id, change_type, reason, actor_id,
    previous_scheduled_start_at, new_scheduled_start_at,
    previous_scheduled_end_at, new_scheduled_end_at,
    previous_teacher_id, new_teacher_id,
    previous_room_id, new_room_id,
    previous_status, new_status
  )
  VALUES (
    v_org_id, p_session_id, p_change_type, p_reason, v_actor,
    p_prev_start, p_new_start, p_prev_end, p_new_end,
    p_prev_teacher, p_new_teacher, p_prev_room, p_new_room,
    p_prev_status, p_new_status
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- =============================================================================
-- MUTATION RPCs
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reschedule_teaching_session(
  p_session_id uuid,
  p_scheduled_start_at timestamptz,
  p_scheduled_end_at timestamptz,
  p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_session teaching_session%ROWTYPE;
  v_reason text := NULLIF(btrim(p_reason), '');
  v_change_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'reason_required' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_session
  FROM teaching_session
  WHERE id = p_session_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_session.status <> 'scheduled' THEN
    RAISE EXCEPTION 'invalid_session_state' USING ERRCODE = 'P0001';
  END IF;

  IF p_scheduled_start_at IS NOT DISTINCT FROM v_session.scheduled_start_at
     AND p_scheduled_end_at IS NOT DISTINCT FROM v_session.scheduled_end_at THEN
    RAISE EXCEPTION 'same_schedule_time' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public._assert_session_interval_ok(
    v_org_id, v_session.id, v_session.teacher_id, v_session.room_id,
    p_scheduled_start_at, p_scheduled_end_at
  );

  BEGIN
    PERFORM set_config('olli.teaching_session_mutation', 'true', true);

    v_change_id := public._append_teaching_session_change(
      v_session.id, 'rescheduled', v_reason,
      v_session.scheduled_start_at, p_scheduled_start_at,
      v_session.scheduled_end_at, p_scheduled_end_at
    );

    -- occurrence_date retained as original timetable identity / projection ownership key.
    UPDATE teaching_session
    SET
      scheduled_start_at = p_scheduled_start_at,
      scheduled_end_at = p_scheduled_end_at,
      updated_by = v_actor
    WHERE id = v_session.id AND organization_id = v_org_id;

    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
    RAISE;
  END;

  RETURN v_change_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_teaching_session(
  p_session_id uuid,
  p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_session teaching_session%ROWTYPE;
  v_reason text := NULLIF(btrim(p_reason), '');
  v_change_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'reason_required' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_session
  FROM teaching_session
  WHERE id = p_session_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_session.status = 'cancelled' THEN
    RAISE EXCEPTION 'already_cancelled' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.status <> 'scheduled' THEN
    RAISE EXCEPTION 'invalid_session_state' USING ERRCODE = 'P0001';
  END IF;

  IF public._session_has_posted_financial_effects(v_session.id) THEN
    RAISE EXCEPTION 'financial_effect_exists' USING ERRCODE = 'P0001';
  END IF;

  IF public._session_has_attendance(v_session.id) THEN
    RAISE EXCEPTION 'attendance_already_recorded' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    PERFORM set_config('olli.teaching_session_mutation', 'true', true);

    v_change_id := public._append_teaching_session_change(
      v_session.id, 'cancelled', v_reason,
      NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
      v_session.status, 'cancelled'
    );

    UPDATE teaching_session
    SET status = 'cancelled', updated_by = v_actor
    WHERE id = v_session.id AND organization_id = v_org_id;

    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
    RAISE;
  END;

  RETURN v_change_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.substitute_session_teacher(
  p_session_id uuid,
  p_new_teacher_id uuid,
  p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_session teaching_session%ROWTYPE;
  v_teacher teacher%ROWTYPE;
  v_reason text := NULLIF(btrim(p_reason), '');
  v_change_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'reason_required' USING ERRCODE = 'P0001';
  END IF;

  IF p_new_teacher_id IS NULL THEN
    RAISE EXCEPTION 'invalid_teacher' USING ERRCODE = 'P0002';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_session
  FROM teaching_session
  WHERE id = p_session_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_session.status <> 'scheduled' THEN
    RAISE EXCEPTION 'invalid_session_state' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.teacher_id IS NOT DISTINCT FROM p_new_teacher_id THEN
    RAISE EXCEPTION 'same_teacher' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_teacher
  FROM teacher
  WHERE id = p_new_teacher_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_teacher' USING ERRCODE = 'P0002';
  END IF;

  IF v_teacher.status <> 'active' THEN
    RAISE EXCEPTION 'invalid_teacher' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public._assert_session_interval_ok(
    v_org_id, v_session.id, p_new_teacher_id, v_session.room_id,
    v_session.scheduled_start_at, v_session.scheduled_end_at
  );

  BEGIN
    PERFORM set_config('olli.teaching_session_mutation', 'true', true);

    v_change_id := public._append_teaching_session_change(
      v_session.id, 'teacher_substituted', v_reason,
      NULL, NULL, NULL, NULL,
      v_session.teacher_id, p_new_teacher_id
    );

    UPDATE teaching_session
    SET teacher_id = p_new_teacher_id, updated_by = v_actor
    WHERE id = v_session.id AND organization_id = v_org_id;

    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
    RAISE;
  END;

  RETURN v_change_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.change_session_room(
  p_session_id uuid,
  p_new_room_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_session teaching_session%ROWTYPE;
  v_room room%ROWTYPE;
  v_reason text := NULLIF(btrim(COALESCE(p_reason, '')), '');
  v_change_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_session
  FROM teaching_session
  WHERE id = p_session_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_session.status <> 'scheduled' THEN
    RAISE EXCEPTION 'invalid_session_state' USING ERRCODE = 'P0001';
  END IF;

  IF v_session.room_id IS NOT DISTINCT FROM p_new_room_id THEN
    RAISE EXCEPTION 'same_room' USING ERRCODE = 'P0001';
  END IF;

  IF p_new_room_id IS NOT NULL THEN
    SELECT * INTO v_room
    FROM room
    WHERE id = p_new_room_id AND organization_id = v_org_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_room' USING ERRCODE = 'P0002';
    END IF;

    IF v_room.status <> 'active' THEN
      RAISE EXCEPTION 'room_inactive' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  PERFORM public._assert_session_interval_ok(
    v_org_id, v_session.id, v_session.teacher_id, p_new_room_id,
    v_session.scheduled_start_at, v_session.scheduled_end_at
  );

  BEGIN
    PERFORM set_config('olli.teaching_session_mutation', 'true', true);

    v_change_id := public._append_teaching_session_change(
      v_session.id, 'room_changed', v_reason,
      NULL, NULL, NULL, NULL, NULL, NULL,
      v_session.room_id, p_new_room_id
    );

    UPDATE teaching_session
    SET room_id = p_new_room_id, updated_by = v_actor
    WHERE id = v_session.id AND organization_id = v_org_id;

    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.teaching_session_mutation', 'false', true);
    RAISE;
  END;

  RETURN v_change_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_teaching_session_changes(p_session_id uuid)
RETURNS SETOF teaching_session_change
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM teaching_session ts
    WHERE ts.id = p_session_id AND ts.organization_id = v_org_id
  ) THEN
    -- Cross-org or missing: no leak.
    RETURN;
  END IF;

  RETURN QUERY
  SELECT c.*
  FROM teaching_session_change c
  WHERE c.organization_id = v_org_id
    AND c.teaching_session_id = p_session_id
  ORDER BY c.occurred_at ASC, c.id ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reschedule_teaching_session(uuid, timestamptz, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_teaching_session(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.substitute_session_teacher(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.change_session_room(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_teaching_session_changes(uuid) TO authenticated;

COMMENT ON FUNCTION public.reschedule_teaching_session(uuid, timestamptz, timestamptz, text) IS
  'Reschedule a scheduled session. Keeps occurrence_date identity; updates scheduled_* only.';
COMMENT ON FUNCTION public.cancel_teaching_session(uuid, text) IS
  'Cancel a scheduled session with required reason. Blocks attendance and posted finance effects.';
COMMENT ON FUNCTION public.substitute_session_teacher(uuid, uuid, text) IS
  'One-session teacher override. Does not mutate timetable or class_teacher_assignment.';
COMMENT ON FUNCTION public.change_session_room(uuid, uuid, text) IS
  'One-session room override. Does not mutate class_schedule.room_id.';

-- =============================================================================
-- T05 CALENDAR FIX: filter sessions by current scheduled local date
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_operational_calendar(
  p_date_from date,
  p_date_to date,
  p_class_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS SETOF operational_calendar_entry
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to < p_date_from THEN
    RAISE EXCEPTION 'invalid_calendar_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_date_to - p_date_from > 89 THEN
    RAISE EXCEPTION 'calendar_range_too_large' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  IF p_class_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM class c WHERE c.id = p_class_id AND c.organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_class' USING ERRCODE = 'P0002';
  END IF;

  IF p_teacher_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM teacher t WHERE t.id = p_teacher_id AND t.organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_teacher' USING ERRCODE = 'P0002';
  END IF;

  IF p_room_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM room r WHERE r.id = p_room_id AND r.organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_room' USING ERRCODE = 'P0002';
  END IF;

  SELECT o.timezone INTO v_timezone
  FROM organization o
  WHERE o.id = v_org_id;

  RETURN QUERY
  WITH session_rows AS (
    SELECT
      'session'::text AS entry_type,
      -- Provenance / original recurrence identity (may differ from current scheduled day).
      COALESCE(ts.occurrence_date, (ts.scheduled_start_at AT TIME ZONE v_timezone)::date) AS occurrence_date,
      ts.scheduled_start_at AS starts_at,
      ts.scheduled_end_at AS ends_at,
      ts.class_id,
      c.name AS class_name,
      ts.class_schedule_id,
      ts.id AS teaching_session_id,
      ts.status AS session_status,
      ts.teacher_id,
      'resolved'::text AS teacher_resolution_status,
      NULLIF(trim(both FROM concat_ws(' ', t.given_name, t.family_name)), '') AS teacher_display_name,
      ts.room_id,
      r.name AS room_name,
      r.code AS room_code
    FROM teaching_session ts
    JOIN class c
      ON c.id = ts.class_id
     AND c.organization_id = ts.organization_id
    LEFT JOIN teacher t
      ON t.id = ts.teacher_id
     AND t.organization_id = ts.organization_id
    LEFT JOIN room r
      ON r.id = ts.room_id
     AND r.organization_id = ts.organization_id
    WHERE ts.organization_id = v_org_id
      -- Current operational day = local date of scheduled_start_at (reschedule-aware).
      AND (ts.scheduled_start_at AT TIME ZONE v_timezone)::date
          BETWEEN p_date_from AND p_date_to
      AND (p_class_id IS NULL OR ts.class_id = p_class_id)
      AND (p_teacher_id IS NULL OR ts.teacher_id = p_teacher_id)
      AND (p_room_id IS NULL OR ts.room_id = p_room_id)
  ),
  schedule_candidates AS (
    SELECT
      cs.id AS class_schedule_id,
      cs.class_id,
      c.name AS class_name,
      cs.weekday_code,
      cs.start_time,
      cs.end_time,
      cs.teacher_id AS schedule_teacher_id,
      cs.room_id,
      r.name AS room_name,
      r.code AS room_code,
      GREATEST(
        p_date_from,
        cs.effective_from,
        COALESCE(c.term_start_date, p_date_from)
      ) AS bound_start,
      LEAST(
        p_date_to,
        COALESCE(cs.effective_to, p_date_to),
        COALESCE(c.term_end_date, p_date_to)
      ) AS bound_end
    FROM class_schedule cs
    JOIN class c
      ON c.id = cs.class_id
     AND c.organization_id = cs.organization_id
    LEFT JOIN room r
      ON r.id = cs.room_id
     AND r.organization_id = cs.organization_id
    WHERE cs.organization_id = v_org_id
      AND cs.status = 'active'
      AND c.status <> 'closed'
      AND (p_class_id IS NULL OR cs.class_id = p_class_id)
      AND (p_room_id IS NULL OR cs.room_id = p_room_id)
      AND cs.effective_from <= p_date_to
      AND (cs.effective_to IS NULL OR cs.effective_to >= p_date_from)
  ),
  projected_dates AS (
    SELECT
      sc.*,
      d::date AS occurrence_date
    FROM schedule_candidates sc
    CROSS JOIN LATERAL generate_series(sc.bound_start, sc.bound_end, interval '1 day') AS d
    WHERE sc.bound_end >= sc.bound_start
      AND EXTRACT(DOW FROM d::date)::int = public._weekday_code_to_dow(sc.weekday_code)
      AND NOT EXISTS (
        SELECT 1
        FROM teaching_session ts
        WHERE ts.organization_id = v_org_id
          AND ts.class_schedule_id = sc.class_schedule_id
          AND ts.occurrence_date = d::date
      )
  ),
  projected_resolved AS (
    SELECT
      pd.*,
      res.p_teacher_id AS resolved_teacher_id,
      res.p_resolution_status AS resolution_status,
      (pd.occurrence_date + pd.start_time) AT TIME ZONE v_timezone AS starts_at,
      (pd.occurrence_date + pd.end_time) AT TIME ZONE v_timezone AS ends_at
    FROM projected_dates pd
    CROSS JOIN LATERAL public._resolve_occurrence_teacher(
      v_org_id, pd.class_id, pd.schedule_teacher_id, pd.occurrence_date
    ) AS res
  ),
  projected_rows AS (
    SELECT
      'projected'::text AS entry_type,
      pr.occurrence_date,
      pr.starts_at,
      pr.ends_at,
      pr.class_id,
      pr.class_name,
      pr.class_schedule_id,
      NULL::uuid AS teaching_session_id,
      NULL::text AS session_status,
      pr.resolved_teacher_id AS teacher_id,
      pr.resolution_status AS teacher_resolution_status,
      NULLIF(trim(both FROM concat_ws(' ', t.given_name, t.family_name)), '') AS teacher_display_name,
      pr.room_id,
      pr.room_name,
      pr.room_code
    FROM projected_resolved pr
    LEFT JOIN teacher t
      ON t.id = pr.resolved_teacher_id
     AND t.organization_id = v_org_id
    WHERE p_teacher_id IS NULL OR pr.resolved_teacher_id = p_teacher_id
  )
  SELECT *
  FROM (
    SELECT * FROM session_rows
    UNION ALL
    SELECT * FROM projected_rows
  ) AS calendar
  ORDER BY starts_at, class_name, class_schedule_id NULLS LAST, teaching_session_id NULLS LAST;
END;
$$;

COMMENT ON FUNCTION public.list_operational_calendar(date, date, uuid, uuid, uuid) IS
  'Org-scoped operational calendar. Sessions filtered by scheduled local date; occurrence_date retained for provenance. Projections suppressed by schedule+occurrence_date ownership.';
