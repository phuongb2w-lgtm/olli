-- M4-T07: Teacher workload and room usage operational analytics.
-- Reuses T05/T06 projection/dedup semantics via internal occurrence helper.
-- Max read range: 366 days inclusive (date_to - date_from <= 365).

-- =============================================================================
-- INTERNAL OCCURRENCE ROW (shared projection/dedup with operational calendar)
-- =============================================================================

CREATE TYPE operational_occurrence_row AS (
  source_type                 text,
  operational_date            date,
  starts_at                   timestamptz,
  ends_at                     timestamptz,
  class_id                    uuid,
  class_schedule_id           uuid,
  teaching_session_id         uuid,
  session_status              text,
  teacher_id                  uuid,
  teacher_resolution_status   text,
  room_id                     uuid
);

COMMENT ON TYPE operational_occurrence_row IS
  'Internal occurrence row for analytics. source_type: session | projected. Same dedup as list_operational_calendar.';

-- =============================================================================
-- RESULT TYPES
-- =============================================================================

CREATE TYPE teacher_workload_row AS (
  teacher_id                      uuid,
  teacher_display_name            text,
  materialized_session_count      integer,
  materialized_scheduled_minutes  integer,
  projected_session_count         integer,
  projected_minutes               integer,
  completed_session_count         integer,
  delivered_scheduled_minutes     integer,
  actual_delivered_minutes        integer,
  in_progress_session_count       integer,
  cancelled_session_count         integer,
  distinct_class_count            integer
);

COMMENT ON TYPE teacher_workload_row IS
  'Per-teacher operational workload. delivered_scheduled_minutes uses scheduled duration for completed sessions (actual_* rarely populated). actual_delivered_minutes only when both actual timestamps exist.';

CREATE TYPE room_usage_row AS (
  room_id                         uuid,
  room_name                       text,
  room_code                       text,
  materialized_session_count      integer,
  materialized_booked_minutes     integer,
  projected_session_count         integer,
  projected_booked_minutes        integer,
  completed_session_count         integer,
  delivered_scheduled_minutes     integer,
  actual_delivered_minutes        integer,
  cancelled_session_count         integer,
  distinct_class_count            integer
);

COMMENT ON TYPE room_usage_row IS
  'Per-room operational usage. No utilization percentage — booked/planned/delivered hours only.';

CREATE TYPE operational_planning_gaps_row AS (
  unresolved_projected_session_count  integer,
  unresolved_projected_minutes        integer,
  roomless_projected_session_count    integer,
  roomless_projected_minutes          integer
);

COMMENT ON TYPE operational_planning_gaps_row IS
  'Org-level planning gaps: projected occurrences without resolved teacher or without room.';

-- =============================================================================
-- SHARED VALIDATION
-- =============================================================================

CREATE OR REPLACE FUNCTION public._validate_analytics_range(
  p_date_from date,
  p_date_to date,
  p_org_id uuid,
  p_class_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to < p_date_from THEN
    RAISE EXCEPTION 'invalid_analytics_range' USING ERRCODE = 'P0001';
  END IF;

  IF p_date_to - p_date_from > 365 THEN
    RAISE EXCEPTION 'analytics_range_too_large' USING ERRCODE = 'P0001';
  END IF;

  IF p_class_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM class c WHERE c.id = p_class_id AND c.organization_id = p_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_class' USING ERRCODE = 'P0002';
  END IF;

  IF p_teacher_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM teacher t WHERE t.id = p_teacher_id AND t.organization_id = p_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_teacher' USING ERRCODE = 'P0002';
  END IF;

  IF p_room_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM room r WHERE r.id = p_room_id AND r.organization_id = p_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_room' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

-- =============================================================================
-- INTERNAL OCCURRENCE HELPER (canonical T05/T06 semantics)
-- =============================================================================

CREATE OR REPLACE FUNCTION public._list_operational_occurrences(
  p_org_id uuid,
  p_timezone text,
  p_date_from date,
  p_date_to date,
  p_class_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS SETOF operational_occurrence_row
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH session_rows AS (
    SELECT
      'session'::text AS source_type,
      (ts.scheduled_start_at AT TIME ZONE p_timezone)::date AS operational_date,
      ts.scheduled_start_at AS starts_at,
      ts.scheduled_end_at AS ends_at,
      ts.class_id,
      ts.class_schedule_id,
      ts.id AS teaching_session_id,
      ts.status AS session_status,
      ts.teacher_id,
      'resolved'::text AS teacher_resolution_status,
      ts.room_id
    FROM teaching_session ts
    WHERE ts.organization_id = p_org_id
      AND (ts.scheduled_start_at AT TIME ZONE p_timezone)::date
          BETWEEN p_date_from AND p_date_to
      AND (p_class_id IS NULL OR ts.class_id = p_class_id)
      AND (p_teacher_id IS NULL OR ts.teacher_id = p_teacher_id)
      AND (p_room_id IS NULL OR ts.room_id = p_room_id)
  ),
  schedule_candidates AS (
    SELECT
      cs.id AS class_schedule_id,
      cs.class_id,
      cs.weekday_code,
      cs.start_time,
      cs.end_time,
      cs.teacher_id AS schedule_teacher_id,
      cs.room_id,
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
    WHERE cs.organization_id = p_org_id
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
        WHERE ts.organization_id = p_org_id
          AND ts.class_schedule_id = sc.class_schedule_id
          AND ts.occurrence_date = d::date
      )
  ),
  projected_resolved AS (
    SELECT
      pd.*,
      res.p_teacher_id AS resolved_teacher_id,
      res.p_resolution_status AS resolution_status,
      (pd.occurrence_date + pd.start_time) AT TIME ZONE p_timezone AS starts_at,
      (pd.occurrence_date + pd.end_time) AT TIME ZONE p_timezone AS ends_at
    FROM projected_dates pd
    CROSS JOIN LATERAL public._resolve_occurrence_teacher(
      p_org_id, pd.class_id, pd.schedule_teacher_id, pd.occurrence_date
    ) AS res
  ),
  projected_rows AS (
    SELECT
      'projected'::text AS source_type,
      pr.occurrence_date AS operational_date,
      pr.starts_at,
      pr.ends_at,
      pr.class_id,
      pr.class_schedule_id,
      NULL::uuid AS teaching_session_id,
      NULL::text AS session_status,
      pr.resolved_teacher_id AS teacher_id,
      pr.resolution_status AS teacher_resolution_status,
      pr.room_id
    FROM projected_resolved pr
    WHERE p_teacher_id IS NULL OR pr.resolved_teacher_id = p_teacher_id
  )
  SELECT
    sr.source_type,
    sr.operational_date,
    sr.starts_at,
    sr.ends_at,
    sr.class_id,
    sr.class_schedule_id,
    sr.teaching_session_id,
    sr.session_status,
    sr.teacher_id,
    sr.teacher_resolution_status,
    sr.room_id
  FROM session_rows sr
  UNION ALL
  SELECT
    pr.source_type,
    pr.operational_date,
    pr.starts_at,
    pr.ends_at,
    pr.class_id,
    pr.class_schedule_id,
    pr.teaching_session_id,
    pr.session_status,
    pr.teacher_id,
    pr.teacher_resolution_status,
    pr.room_id
  FROM projected_rows pr;
$$;

COMMENT ON FUNCTION public._list_operational_occurrences(uuid, text, date, date, uuid, uuid, uuid) IS
  'Internal occurrence set for analytics. Session filtered by scheduled local date; projection dedup by schedule+occurrence_date.';

-- =============================================================================
-- PLANNING GAPS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_operational_planning_gaps(
  p_date_from date,
  p_date_to date,
  p_class_id uuid DEFAULT NULL
)
RETURNS operational_planning_gaps_row
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
  v_result operational_planning_gaps_row;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM public._validate_analytics_range(p_date_from, p_date_to, v_org_id, p_class_id, NULL, NULL);

  SELECT o.timezone INTO v_timezone FROM organization o WHERE o.id = v_org_id;

  SELECT
    COALESCE(SUM(CASE
      WHEN o.source_type = 'projected'
       AND o.teacher_resolution_status <> 'resolved'
      THEN 1 ELSE 0 END), 0)::integer,
    COALESCE(SUM(CASE
      WHEN o.source_type = 'projected'
       AND o.teacher_resolution_status <> 'resolved'
      THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
      ELSE 0 END), 0)::integer,
    COALESCE(SUM(CASE
      WHEN o.source_type = 'projected' AND o.room_id IS NULL
      THEN 1 ELSE 0 END), 0)::integer,
    COALESCE(SUM(CASE
      WHEN o.source_type = 'projected' AND o.room_id IS NULL
      THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
      ELSE 0 END), 0)::integer
  INTO v_result
  FROM public._list_operational_occurrences(
    v_org_id, v_timezone, p_date_from, p_date_to, p_class_id, NULL, NULL
  ) o;

  RETURN v_result;
END;
$$;

-- =============================================================================
-- TEACHER WORKLOAD
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_teacher_workload(
  p_date_from date,
  p_date_to date,
  p_class_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS SETOF teacher_workload_row
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
  v_include_zero boolean;
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

  PERFORM public._validate_analytics_range(p_date_from, p_date_to, v_org_id, p_class_id, p_teacher_id, p_room_id);

  SELECT o.timezone INTO v_timezone FROM organization o WHERE o.id = v_org_id;

  -- Include active teachers with zero workload when no specific teacher filter.
  v_include_zero := (p_teacher_id IS NULL AND p_room_id IS NULL);

  RETURN QUERY
  WITH occurrences AS (
    SELECT o.*
    FROM public._list_operational_occurrences(
      v_org_id, v_timezone, p_date_from, p_date_to, p_class_id, p_teacher_id, p_room_id
    ) o
  ),
  session_actuals AS (
    SELECT
      ts.id,
      ts.actual_start_at,
      ts.actual_end_at
    FROM teaching_session ts
    WHERE ts.organization_id = v_org_id
  ),
  teacher_agg AS (
    SELECT
      o.teacher_id,
      COUNT(*) FILTER (
        WHERE o.source_type = 'session' AND o.session_status <> 'cancelled'
      )::integer AS materialized_session_count,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'session' AND o.session_status <> 'cancelled'
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS materialized_scheduled_minutes,
      COUNT(*) FILTER (
        WHERE o.source_type = 'projected'
         AND o.teacher_resolution_status = 'resolved'
         AND o.teacher_id IS NOT NULL
      )::integer AS projected_session_count,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'projected'
              AND o.teacher_resolution_status = 'resolved'
              AND o.teacher_id IS NOT NULL
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS projected_minutes,
      COUNT(*) FILTER (
        WHERE o.source_type = 'session' AND o.session_status = 'completed'
      )::integer AS completed_session_count,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'session' AND o.session_status = 'completed'
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS delivered_scheduled_minutes,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'session'
              AND o.session_status = 'completed'
              AND sa.actual_start_at IS NOT NULL
              AND sa.actual_end_at IS NOT NULL
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (sa.actual_end_at - sa.actual_start_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS actual_delivered_minutes,
      COUNT(*) FILTER (
        WHERE o.source_type = 'session' AND o.session_status = 'in_progress'
      )::integer AS in_progress_session_count,
      COUNT(*) FILTER (
        WHERE o.source_type = 'session' AND o.session_status = 'cancelled'
      )::integer AS cancelled_session_count,
      COUNT(DISTINCT o.class_id)::integer AS distinct_class_count
    FROM occurrences o
    LEFT JOIN session_actuals sa ON sa.id = o.teaching_session_id
    WHERE o.teacher_id IS NOT NULL
    GROUP BY o.teacher_id
  ),
  teacher_base AS (
    SELECT t.id, t.given_name, t.family_name
    FROM teacher t
    WHERE t.organization_id = v_org_id
      AND t.status = 'active'
      AND (p_teacher_id IS NULL OR t.id = p_teacher_id)
  )
  SELECT
    tb.id,
    NULLIF(trim(both FROM concat_ws(' ', tb.given_name, tb.family_name)), ''),
    COALESCE(ta.materialized_session_count, 0),
    COALESCE(ta.materialized_scheduled_minutes, 0),
    COALESCE(ta.projected_session_count, 0),
    COALESCE(ta.projected_minutes, 0),
    COALESCE(ta.completed_session_count, 0),
    COALESCE(ta.delivered_scheduled_minutes, 0),
    COALESCE(ta.actual_delivered_minutes, 0),
    COALESCE(ta.in_progress_session_count, 0),
    COALESCE(ta.cancelled_session_count, 0),
    COALESCE(ta.distinct_class_count, 0)
  FROM teacher_base tb
  LEFT JOIN teacher_agg ta ON ta.teacher_id = tb.id
  WHERE v_include_zero
     OR ta.teacher_id IS NOT NULL
     OR p_teacher_id IS NOT NULL
  ORDER BY
    COALESCE(ta.materialized_scheduled_minutes, 0) DESC,
    tb.family_name,
    tb.given_name;
END;
$$;

COMMENT ON FUNCTION public.list_teacher_workload(date, date, uuid, uuid, uuid) IS
  'Per-teacher workload: materialized scheduled (non-cancelled), projected, delivered (completed). Max range 366 days inclusive. Includes active zero-workload teachers when unfiltered.';

-- =============================================================================
-- ROOM USAGE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_room_usage(
  p_date_from date,
  p_date_to date,
  p_class_id uuid DEFAULT NULL,
  p_room_id uuid DEFAULT NULL
)
RETURNS SETOF room_usage_row
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
  v_include_zero boolean;
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

  PERFORM public._validate_analytics_range(p_date_from, p_date_to, v_org_id, p_class_id, NULL, p_room_id);

  SELECT o.timezone INTO v_timezone FROM organization o WHERE o.id = v_org_id;

  v_include_zero := (p_room_id IS NULL);

  RETURN QUERY
  WITH occurrences AS (
    SELECT o.*
    FROM public._list_operational_occurrences(
      v_org_id, v_timezone, p_date_from, p_date_to, p_class_id, NULL, p_room_id
    ) o
  ),
  session_actuals AS (
    SELECT ts.id, ts.actual_start_at, ts.actual_end_at
    FROM teaching_session ts
    WHERE ts.organization_id = v_org_id
  ),
  room_agg AS (
    SELECT
      o.room_id,
      COUNT(*) FILTER (
        WHERE o.source_type = 'session' AND o.session_status <> 'cancelled'
      )::integer AS materialized_session_count,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'session' AND o.session_status <> 'cancelled'
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS materialized_booked_minutes,
      COUNT(*) FILTER (
        WHERE o.source_type = 'projected' AND o.room_id IS NOT NULL
      )::integer AS projected_session_count,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'projected' AND o.room_id IS NOT NULL
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS projected_booked_minutes,
      COUNT(*) FILTER (
        WHERE o.source_type = 'session' AND o.session_status = 'completed'
      )::integer AS completed_session_count,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'session' AND o.session_status = 'completed'
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS delivered_scheduled_minutes,
      COALESCE(SUM(
        CASE WHEN o.source_type = 'session'
              AND o.session_status = 'completed'
              AND sa.actual_start_at IS NOT NULL
              AND sa.actual_end_at IS NOT NULL
        THEN GREATEST(0, (EXTRACT(EPOCH FROM (sa.actual_end_at - sa.actual_start_at)) / 60)::integer)
        ELSE 0 END
      ), 0)::integer AS actual_delivered_minutes,
      COUNT(*) FILTER (
        WHERE o.source_type = 'session' AND o.session_status = 'cancelled'
      )::integer AS cancelled_session_count,
      COUNT(DISTINCT o.class_id)::integer AS distinct_class_count
    FROM occurrences o
    LEFT JOIN session_actuals sa ON sa.id = o.teaching_session_id
    WHERE o.room_id IS NOT NULL
    GROUP BY o.room_id
  ),
  room_base AS (
    SELECT r.id, r.name, r.code
    FROM room r
    WHERE r.organization_id = v_org_id
      AND r.status = 'active'
      AND (p_room_id IS NULL OR r.id = p_room_id)
  )
  SELECT
    rb.id,
    rb.name,
    rb.code,
    COALESCE(ra.materialized_session_count, 0),
    COALESCE(ra.materialized_booked_minutes, 0),
    COALESCE(ra.projected_session_count, 0),
    COALESCE(ra.projected_booked_minutes, 0),
    COALESCE(ra.completed_session_count, 0),
    COALESCE(ra.delivered_scheduled_minutes, 0),
    COALESCE(ra.actual_delivered_minutes, 0),
    COALESCE(ra.cancelled_session_count, 0),
    COALESCE(ra.distinct_class_count, 0)
  FROM room_base rb
  LEFT JOIN room_agg ra ON ra.room_id = rb.id
  WHERE v_include_zero
     OR ra.room_id IS NOT NULL
     OR p_room_id IS NOT NULL
  ORDER BY
    COALESCE(ra.materialized_booked_minutes, 0) DESC,
    rb.name;
END;
$$;

COMMENT ON FUNCTION public.list_room_usage(date, date, uuid, uuid) IS
  'Per-room usage: materialized booked (non-cancelled), projected, delivered (completed). Max range 366 days inclusive. Includes active zero-usage rooms when unfiltered.';

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.list_teacher_workload(date, date, uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_room_usage(date, date, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_operational_planning_gaps(date, date, uuid) TO authenticated;
