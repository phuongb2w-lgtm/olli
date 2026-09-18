-- M4-T05: Operational calendar read model.
-- Derived over teaching_session + class_schedule projection. No persistent calendar table.
-- Max read range: 90 days inclusive (date_to - date_from <= 89).

-- =============================================================================
-- RESULT TYPE
-- =============================================================================

CREATE TYPE operational_calendar_entry AS (
  entry_type                 text,
  occurrence_date            date,
  starts_at                  timestamptz,
  ends_at                    timestamptz,
  class_id                   uuid,
  class_name                 text,
  class_schedule_id          uuid,
  teaching_session_id        uuid,
  session_status             text,
  teacher_id                 uuid,
  teacher_resolution_status  text,
  teacher_display_name       text,
  room_id                    uuid,
  room_name                  text,
  room_code                  text
);

COMMENT ON TYPE operational_calendar_entry IS
  'Derived operational calendar row. entry_type: session | projected. teacher_resolution_status: resolved | teacher_not_resolved | multiple_primary_teachers.';

-- =============================================================================
-- INDEXES FOR CALENDAR READ PATHS
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_teaching_session_org_occurrence
  ON teaching_session (organization_id, occurrence_date)
  WHERE occurrence_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_teaching_session_teacher_start
  ON teaching_session (organization_id, teacher_id, scheduled_start_at);

-- =============================================================================
-- LIST OPERATIONAL CALENDAR
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

  -- Inclusive max window of 90 days => span of at most 89 days between endpoints.
  IF p_date_to - p_date_from > 89 THEN
    RAISE EXCEPTION 'calendar_range_too_large' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  -- Cross-org filter IDs must not leak: reject unknown-to-org filters.
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
      AND COALESCE(ts.occurrence_date, (ts.scheduled_start_at AT TIME ZONE v_timezone)::date)
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
  'Org-scoped operational calendar. Sessions own schedule+occurrence_date (including cancelled). Projections fill gaps only. Max range 90 days inclusive.';

GRANT EXECUTE ON FUNCTION public.list_operational_calendar(date, date, uuid, uuid, uuid) TO authenticated;
