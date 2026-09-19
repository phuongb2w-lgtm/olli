-- M5-T05: Teaching operations & resource intelligence read layer over M4.
-- Reuses _list_operational_occurrences, list_teacher_workload, list_room_usage,
-- teaching_session_change, resolve_reporting_period. M4 remains scheduling source of truth.

-- =============================================================================
-- ACCESS HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._current_linked_teacher_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.id
  FROM teacher t
  WHERE t.organization_id = public.current_organization_id()
    AND t.user_id = public.current_app_user_id()
    AND t.status = 'active'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._is_teacher_only_app_user()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF public._current_linked_teacher_id() IS NULL THEN
    RETURN false;
  END IF;

  RETURN NOT public.has_permission('report.executive.read')
     AND NOT public.has_permission('enrollment.update');
END;
$$;

COMMENT ON FUNCTION public._is_teacher_only_app_user() IS
  'Linked teacher account without scheduling or executive permissions — personal teaching scope only.';

CREATE OR REPLACE FUNCTION public._assert_teaching_ops_executive_access()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('report.executive.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._assert_teaching_ops_scheduling_access()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF public._is_teacher_only_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

COMMENT ON FUNCTION public._assert_teaching_ops_scheduling_access() IS
  'Academic Operations scheduling intelligence — center-wide workload/room/changes, not teacher-only accounts.';

-- =============================================================================
-- SHARED MATERIALIZED SESSION METRICS (reuse from M5-T03 delivery semantics)
-- =============================================================================

CREATE OR REPLACE FUNCTION public._teaching_ops_materialized_session_metrics(
  p_org_id uuid,
  p_timezone text,
  p_start_date date,
  p_end_date date,
  p_class_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_materialized bigint;
  v_delivered bigint;
  v_cancelled bigint;
  v_in_progress bigint;
  v_scheduled bigint;
BEGIN
  SELECT
    count(*) FILTER (WHERE ts.status <> 'cancelled'),
    count(*) FILTER (WHERE ts.status = 'completed'),
    count(*) FILTER (WHERE ts.status = 'cancelled'),
    count(*) FILTER (WHERE ts.status = 'in_progress'),
    count(*) FILTER (WHERE ts.status = 'scheduled')
  INTO v_materialized, v_delivered, v_cancelled, v_in_progress, v_scheduled
  FROM teaching_session ts
  WHERE ts.organization_id = p_org_id
    AND public.teaching_session_operational_date(ts.scheduled_start_at, p_timezone)
        BETWEEN p_start_date AND p_end_date
    AND (p_class_id IS NULL OR ts.class_id = p_class_id);

  RETURN jsonb_build_object(
    'kpi', 'teaching_ops.materialized_sessions',
    'materialized_sessions', COALESCE(v_materialized, 0),
    'scheduled_sessions', COALESCE(v_scheduled, 0),
    'in_progress_sessions', COALESCE(v_in_progress, 0),
    'delivered_sessions', COALESCE(v_delivered, 0),
    'cancelled_sessions', COALESCE(v_cancelled, 0),
    'delivery_ratio',
      CASE
        WHEN COALESCE(v_materialized, 0) = 0 THEN NULL
        ELSE round((v_delivered::numeric / v_materialized::numeric), 4)
      END,
    'delivery_ratio_denominator_rule',
      'completed sessions / non-cancelled materialized sessions in period (operational date from current scheduled_start_at)',
    'operational_date_rule',
      'teaching_session_operational_date(scheduled_start_at, organization.timezone); occurrence_date is provenance only'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_academic_teaching_delivery(
  p_start_date date,
  p_end_date date,
  p_class_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_tz text;
  v_core jsonb;
BEGIN
  PERFORM public._assert_academic_quality_overview_access();

  v_org := public.current_organization_id();
  SELECT o.timezone INTO v_tz FROM organization o WHERE o.id = v_org;

  v_core := public._teaching_ops_materialized_session_metrics(
    v_org, v_tz, p_start_date, p_end_date, p_class_id
  );

  RETURN jsonb_build_object(
    'materialized_sessions', v_core->'materialized_sessions',
    'delivered_sessions', v_core->'delivered_sessions',
    'cancelled_sessions', v_core->'cancelled_sessions',
    'in_progress_sessions', v_core->'in_progress_sessions',
    'scheduled_sessions', v_core->'scheduled_sessions',
    'delivery_completion_ratio', v_core->'delivery_ratio',
    'denominator_rule', v_core->'delivery_ratio_denominator_rule'
  );
END;
$$;

-- =============================================================================
-- SESSION KPIs (projected + materialized distinction)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_teaching_ops_session_metrics(
  p_start_date date,
  p_end_date date,
  p_class_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_tz text;
  v_bounds reporting_period_bounds;
  v_materialized jsonb;
  v_projected bigint;
  v_projected_minutes bigint;
BEGIN
  IF public.has_permission('report.executive.read') THEN
    PERFORM public._assert_teaching_ops_executive_access();
  ELSE
    PERFORM public._assert_teaching_ops_scheduling_access();
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  v_tz := v_bounds.timezone;

  v_materialized := public._teaching_ops_materialized_session_metrics(
    v_org, v_tz, p_start_date, p_end_date, p_class_id
  );

  SELECT
    count(*) FILTER (WHERE o.source_type = 'projected'),
    COALESCE(sum(
      CASE WHEN o.source_type = 'projected'
      THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
      ELSE 0 END
    ), 0)
  INTO v_projected, v_projected_minutes
  FROM public._list_operational_occurrences(
    v_org, v_tz, p_start_date, p_end_date, p_class_id, NULL, NULL
  ) o;

  RETURN v_materialized || jsonb_build_object(
    'kpi', 'teaching_ops.session_operations',
    'projected_occurrences', COALESCE(v_projected, 0),
    'projected_minutes', COALESCE(v_projected_minutes, 0),
    'event_timestamp_rule', 'operational placement uses current scheduled_start_at local date',
    'projected_rule', 'schedule occurrence without materialized teaching_session (M4 dedup semantics)'
  );
END;
$$;

COMMENT ON FUNCTION public.get_teaching_ops_session_metrics(date, date, uuid) IS
  'Distinct projected vs materialized session KPIs. Delivered = status completed only.';

-- =============================================================================
-- CHANGE EVENT METRICS (teaching_session_change.occurred_at)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_teaching_ops_change_metrics(
  p_start_date date,
  p_end_date date,
  p_class_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_org uuid;
  v_reschedule_events bigint;
  v_reschedule_sessions bigint;
  v_reschedule_multi bigint;
  v_cancel_events bigint;
  v_cancel_sessions bigint;
  v_sub_events bigint;
  v_sub_sessions bigint;
  v_room_events bigint;
  v_room_sessions bigint;
BEGIN
  IF public.has_permission('report.executive.read') THEN
    PERFORM public._assert_teaching_ops_executive_access();
  ELSE
    PERFORM public._assert_teaching_ops_scheduling_access();
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;

  SELECT
    count(*) FILTER (WHERE c.change_type = 'rescheduled'),
    count(DISTINCT c.teaching_session_id) FILTER (WHERE c.change_type = 'rescheduled'),
    count(*) FILTER (WHERE c.change_type = 'cancelled'),
    count(DISTINCT c.teaching_session_id) FILTER (WHERE c.change_type = 'cancelled'),
    count(*) FILTER (WHERE c.change_type = 'teacher_substituted'),
    count(DISTINCT c.teaching_session_id) FILTER (WHERE c.change_type = 'teacher_substituted'),
    count(*) FILTER (WHERE c.change_type = 'room_changed'),
    count(DISTINCT c.teaching_session_id) FILTER (WHERE c.change_type = 'room_changed')
  INTO
    v_reschedule_events, v_reschedule_sessions,
    v_cancel_events, v_cancel_sessions,
    v_sub_events, v_sub_sessions,
    v_room_events, v_room_sessions
  FROM teaching_session_change c
  JOIN teaching_session ts
    ON ts.id = c.teaching_session_id AND ts.organization_id = c.organization_id
  WHERE c.organization_id = v_org
    AND c.occurred_at >= v_bounds.start_at_utc
    AND c.occurred_at < v_bounds.end_at_exclusive
    AND (p_class_id IS NULL OR ts.class_id = p_class_id);

  SELECT count(*) INTO v_reschedule_multi
  FROM (
    SELECT c.teaching_session_id
    FROM teaching_session_change c
    JOIN teaching_session ts
      ON ts.id = c.teaching_session_id AND ts.organization_id = c.organization_id
    WHERE c.organization_id = v_org
      AND c.change_type = 'rescheduled'
      AND c.occurred_at >= v_bounds.start_at_utc
      AND c.occurred_at < v_bounds.end_at_exclusive
      AND (p_class_id IS NULL OR ts.class_id = p_class_id)
    GROUP BY c.teaching_session_id
    HAVING count(*) > 1
  ) multi;

  RETURN jsonb_build_object(
    'kpi', 'teaching_ops.change_events',
    'event_timestamp_rule', 'teaching_session_change.occurred_at within reporting period UTC bounds',
    'reschedule', jsonb_build_object(
      'event_count', COALESCE(v_reschedule_events, 0),
      'affected_session_count', COALESCE(v_reschedule_sessions, 0),
      'sessions_with_multiple_events', COALESCE(v_reschedule_multi, 0)
    ),
    'cancellation', jsonb_build_object(
      'event_count', COALESCE(v_cancel_events, 0),
      'affected_session_count', COALESCE(v_cancel_sessions, 0)
    ),
    'teacher_substitution', jsonb_build_object(
      'event_count', COALESCE(v_sub_events, 0),
      'affected_session_count', COALESCE(v_sub_sessions, 0)
    ),
    'room_change', jsonb_build_object(
      'event_count', COALESCE(v_room_events, 0),
      'affected_session_count', COALESCE(v_room_sessions, 0)
    )
  );
END;
$$;

CREATE INDEX IF NOT EXISTS idx_teaching_session_change_org_occurred
  ON teaching_session_change (organization_id, occurred_at);

-- =============================================================================
-- OPERATIONAL CHANGE HISTORY (append-only read surface)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_teaching_session_operational_changes(
  p_start_date date,
  p_end_date date,
  p_change_type text DEFAULT NULL,
  p_class_id uuid DEFAULT NULL,
  p_teacher_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_org uuid;
  v_tz text;
BEGIN
  PERFORM public._assert_teaching_ops_scheduling_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  SELECT o.timezone INTO v_tz FROM organization o WHERE o.id = v_org;

  IF p_change_type IS NOT NULL
     AND p_change_type NOT IN ('rescheduled', 'cancelled', 'teacher_substituted', 'room_changed') THEN
    RAISE EXCEPTION 'invalid_change_type' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT jsonb_build_object(
    'change_id', c.id,
    'change_type', c.change_type,
    'occurred_at', c.occurred_at,
    'reason', c.reason,
    'teaching_session_id', c.teaching_session_id,
    'class_id', ts.class_id,
    'class_name', cl.name,
    'operational_date',
      public.teaching_session_operational_date(ts.scheduled_start_at, v_tz),
    'current_teacher_id', ts.teacher_id,
    'current_room_id', ts.room_id,
    'previous_scheduled_start_at', c.previous_scheduled_start_at,
    'new_scheduled_start_at', c.new_scheduled_start_at,
    'previous_teacher_id', c.previous_teacher_id,
    'new_teacher_id', c.new_teacher_id,
    'previous_room_id', c.previous_room_id,
    'new_room_id', c.new_room_id,
    'drill_down_path', '/operations/calendar?classId=' || ts.class_id::text
  )
  FROM teaching_session_change c
  JOIN teaching_session ts
    ON ts.id = c.teaching_session_id AND ts.organization_id = c.organization_id
  JOIN class cl ON cl.id = ts.class_id AND cl.organization_id = ts.organization_id
  WHERE c.organization_id = v_org
    AND c.occurred_at >= v_bounds.start_at_utc
    AND c.occurred_at < v_bounds.end_at_exclusive
    AND (p_change_type IS NULL OR c.change_type = p_change_type)
    AND (p_class_id IS NULL OR ts.class_id = p_class_id)
    AND (
      p_teacher_id IS NULL
      OR ts.teacher_id = p_teacher_id
      OR c.previous_teacher_id = p_teacher_id
      OR c.new_teacher_id = p_teacher_id
    )
  ORDER BY c.occurred_at DESC, c.id DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
END;
$$;

COMMENT ON FUNCTION public.list_teaching_session_operational_changes(date, date, text, uuid, uuid, integer, integer) IS
  'Append-only operational change feed. Event time = occurred_at. Current teacher/room from teaching_session.';

-- =============================================================================
-- OPERATIONAL EXCEPTIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_teaching_ops_exceptions(
  p_start_date date,
  p_end_date date
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_org uuid;
  v_tz text;
  v_gaps operational_planning_gaps_row;
BEGIN
  IF public.has_permission('report.executive.read') THEN
    PERFORM public._assert_teaching_ops_executive_access();
  ELSE
    PERFORM public._assert_teaching_ops_scheduling_access();
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  SELECT o.timezone INTO v_tz FROM organization o WHERE o.id = v_org;

  SELECT * INTO v_gaps
  FROM public.get_operational_planning_gaps(p_start_date, p_end_date, NULL);

  IF COALESCE(v_gaps.unresolved_projected_session_count, 0) > 0 THEN
    RETURN QUERY SELECT jsonb_build_object(
      'exception_code', 'unresolved_projected_teacher',
      'reason', 'Projected occurrence without resolved teacher assignment',
      'entity_type', 'organization',
      'entity_id', v_org,
      'metric_value', v_gaps.unresolved_projected_session_count,
      'drill_down_path', '/operations/workload',
      'context', jsonb_build_object(
        'unresolved_projected_minutes', v_gaps.unresolved_projected_minutes
      )
    );
  END IF;

  IF COALESCE(v_gaps.roomless_projected_session_count, 0) > 0 THEN
    RETURN QUERY SELECT jsonb_build_object(
      'exception_code', 'roomless_projected_occurrence',
      'reason', 'Projected occurrence without room assignment',
      'entity_type', 'organization',
      'entity_id', v_org,
      'metric_value', v_gaps.roomless_projected_session_count,
      'drill_down_path', '/operations/workload',
      'context', jsonb_build_object(
        'roomless_projected_minutes', v_gaps.roomless_projected_minutes
      )
    );
  END IF;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'session_missing_teacher',
    'reason', 'Materialized session scheduled without teacher',
    'entity_type', 'teaching_session',
    'entity_id', ts.id,
    'metric_value', 1,
    'drill_down_path', '/operations/calendar?classId=' || ts.class_id::text,
    'context', jsonb_build_object(
      'class_id', ts.class_id,
      'operational_date', public.teaching_session_operational_date(ts.scheduled_start_at, v_tz),
      'status', ts.status
    )
  )
  FROM teaching_session ts
  WHERE ts.organization_id = v_org
    AND ts.status IN ('scheduled', 'in_progress')
    AND ts.teacher_id IS NULL
    AND public.teaching_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'session_missing_room',
    'reason', 'Materialized session scheduled without room',
    'entity_type', 'teaching_session',
    'entity_id', ts.id,
    'metric_value', 1,
    'drill_down_path', '/operations/calendar?classId=' || ts.class_id::text,
    'context', jsonb_build_object(
      'class_id', ts.class_id,
      'operational_date', public.teaching_session_operational_date(ts.scheduled_start_at, v_tz),
      'status', ts.status
    )
  )
  FROM teaching_session ts
  WHERE ts.organization_id = v_org
    AND ts.status IN ('scheduled', 'in_progress')
    AND ts.room_id IS NULL
    AND public.teaching_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'in_progress_past_scheduled_end',
    'reason', 'Session still in progress after scheduled end time',
    'entity_type', 'teaching_session',
    'entity_id', ts.id,
    'metric_value', extract(epoch FROM (now() - ts.scheduled_end_at)) / 60,
    'drill_down_path', '/operations?date=' ||
      public.teaching_session_operational_date(ts.scheduled_start_at, v_tz)::text,
    'context', jsonb_build_object(
      'scheduled_end_at', ts.scheduled_end_at,
      'class_id', ts.class_id
    )
  )
  FROM teaching_session ts
  WHERE ts.organization_id = v_org
    AND ts.status = 'in_progress'
    AND ts.scheduled_end_at < now()
    AND public.teaching_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'repeated_reschedule_events',
    'reason', 'Session has multiple reschedule events in period',
    'entity_type', 'teaching_session',
    'entity_id', sub.teaching_session_id,
    'metric_value', sub.event_count,
    'drill_down_path', '/operations/intelligence',
    'context', jsonb_build_object('reschedule_event_count', sub.event_count)
  )
  FROM (
    SELECT c.teaching_session_id, count(*) AS event_count
    FROM teaching_session_change c
    WHERE c.organization_id = v_org
      AND c.change_type = 'rescheduled'
      AND c.occurred_at >= v_bounds.start_at_utc
      AND c.occurred_at < v_bounds.end_at_exclusive
    GROUP BY c.teaching_session_id
    HAVING count(*) >= 2
  ) sub;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'room_capacity_exceeded',
    'reason', 'Active enrollment count exceeds configured room capacity for session',
    'entity_type', 'teaching_session',
    'entity_id', ts.id,
    'metric_value', enr.cnt - r.capacity,
    'drill_down_path', '/operations/calendar?classId=' || ts.class_id::text,
    'context', jsonb_build_object(
      'room_id', r.id,
      'room_capacity', r.capacity,
      'active_enrollment_count', enr.cnt,
      'operational_date', public.teaching_session_operational_date(ts.scheduled_start_at, v_tz)
    )
  )
  FROM teaching_session ts
  JOIN room r ON r.id = ts.room_id AND r.organization_id = ts.organization_id
  JOIN LATERAL (
    SELECT count(*) AS cnt
    FROM enrollment e
    WHERE e.organization_id = ts.organization_id
      AND e.class_id = ts.class_id
      AND e.status = 'active'
  ) enr ON true
  WHERE ts.organization_id = v_org
    AND ts.status IN ('scheduled', 'in_progress')
    AND r.capacity IS NOT NULL
    AND enr.cnt > r.capacity
    AND public.teaching_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date;
END;
$$;

-- =============================================================================
-- TEACHER PERSONAL OVERVIEW
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_my_teaching_ops_overview(
  p_start_date date,
  p_end_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_teacher uuid;
  v_bounds reporting_period_bounds;
  v_org uuid;
  v_tz text;
  v_scheduled integer := 0;
  v_projected integer := 0;
  v_completed integer := 0;
  v_scheduled_minutes integer := 0;
  v_delivered_minutes integer := 0;
  v_cancelled integer := 0;
  v_upcoming bigint;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_teacher := public._current_linked_teacher_id();
  IF v_teacher IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  v_tz := v_bounds.timezone;

  SELECT
    count(*) FILTER (WHERE o.source_type = 'session' AND o.session_status <> 'cancelled'),
    count(*) FILTER (WHERE o.source_type = 'projected'),
    count(*) FILTER (WHERE o.source_type = 'session' AND o.session_status = 'completed'),
    COALESCE(sum(
      CASE WHEN o.source_type = 'session' AND o.session_status <> 'cancelled'
      THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
      ELSE 0 END
    ), 0),
    COALESCE(sum(
      CASE WHEN o.source_type = 'session' AND o.session_status = 'completed'
      THEN GREATEST(0, (EXTRACT(EPOCH FROM (o.ends_at - o.starts_at)) / 60)::integer)
      ELSE 0 END
    ), 0),
    count(*) FILTER (WHERE o.source_type = 'session' AND o.session_status = 'cancelled')
  INTO v_scheduled, v_projected, v_completed, v_scheduled_minutes, v_delivered_minutes, v_cancelled
  FROM public._list_operational_occurrences(
    v_org, v_tz, p_start_date, p_end_date, NULL, v_teacher, NULL
  ) o;

  SELECT count(*) INTO v_upcoming
  FROM teaching_session ts
  WHERE ts.organization_id = v_org
    AND ts.teacher_id = v_teacher
    AND ts.status = 'scheduled'
    AND public.teaching_session_operational_date(ts.scheduled_start_at, v_tz) >= CURRENT_DATE;

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_tz
    ),
    'teacher_id', v_teacher,
    'scope_rule', 'personal teacher linked to current app user only',
    'scheduled_sessions', COALESCE(v_scheduled, 0),
    'projected_sessions', COALESCE(v_projected, 0),
    'completed_sessions', COALESCE(v_completed, 0),
    'delivered_minutes', COALESCE(v_delivered_minutes, 0),
    'scheduled_minutes', COALESCE(v_scheduled_minutes, 0),
    'upcoming_sessions', COALESCE(v_upcoming, 0),
    'cancelled_sessions', COALESCE(v_cancelled, 0),
    'attribution_rule', 'current teacher_id and current scheduled_start_at; substitution history separate'
  );
END;
$$;

COMMENT ON FUNCTION public.get_my_teaching_ops_overview(date, date) IS
  'Teacher personal operational metrics — no peer or center-wide workload.';

-- =============================================================================
-- EXECUTIVE OVERVIEW COMPOSITE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_teaching_ops_intelligence_overview(
  p_start_date date,
  p_end_date date,
  p_compare_previous boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_bounds reporting_period_bounds;
  v_prev jsonb;
  v_prev_start date;
  v_prev_end date;
  v_sessions jsonb;
  v_sessions_prev jsonb;
  v_changes jsonb;
  v_changes_prev jsonb;
BEGIN
  PERFORM public._assert_teaching_ops_executive_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  IF p_compare_previous THEN
    v_prev := public.resolve_finance_comparison_period(p_start_date, p_end_date);
    v_prev_start := (v_prev->>'start_date')::date;
    v_prev_end := (v_prev->>'end_date')::date;
  END IF;

  v_sessions := public.get_teaching_ops_session_metrics(p_start_date, p_end_date, NULL);
  v_changes := public.get_teaching_ops_change_metrics(p_start_date, p_end_date, NULL);

  IF p_compare_previous THEN
    v_sessions_prev := public.get_teaching_ops_session_metrics(v_prev_start, v_prev_end, NULL);
    v_changes_prev := public.get_teaching_ops_change_metrics(v_prev_start, v_prev_end, NULL);
  END IF;

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_bounds.timezone,
      'start_at_utc', v_bounds.start_at_utc,
      'end_at_exclusive', v_bounds.end_at_exclusive
    ),
    'comparison_period', CASE WHEN p_compare_previous THEN v_prev ELSE NULL END,
    'sessionMetrics', jsonb_build_object('current', v_sessions, 'previous', v_sessions_prev),
    'changeMetrics', jsonb_build_object('current', v_changes, 'previous', v_changes_prev),
    'workload_read_model', 'list_teacher_workload (M4-T07)',
    'room_usage_read_model', 'list_room_usage (M4-T07)',
    'utilization_percentage_rule', 'not computed — no canonical room operating-hours denominator in product'
  );
END;
$$;

COMMENT ON FUNCTION public.get_teaching_ops_intelligence_overview(date, date, boolean) IS
  'Center-wide teaching operations intelligence for center managers.';

-- =============================================================================
-- M4 WORKLOAD RPCs — teacher-only scope (no peer / center-wide room intelligence)
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
  v_teacher_id uuid := p_teacher_id;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('enrollment.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF public._is_teacher_only_app_user() THEN
    v_teacher_id := public._current_linked_teacher_id();
    IF p_teacher_id IS NOT NULL AND p_teacher_id IS DISTINCT FROM v_teacher_id THEN
      RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
    END IF;
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM public._validate_analytics_range(p_date_from, p_date_to, v_org_id, p_class_id, v_teacher_id, p_room_id);

  SELECT o.timezone INTO v_timezone FROM organization o WHERE o.id = v_org_id;

  v_include_zero := (v_teacher_id IS NULL AND p_room_id IS NULL);

  RETURN QUERY
  WITH occurrences AS (
    SELECT o.*
    FROM public._list_operational_occurrences(
      v_org_id, v_timezone, p_date_from, p_date_to, p_class_id, v_teacher_id, p_room_id
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
      AND (v_teacher_id IS NULL OR t.id = v_teacher_id)
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
     OR v_teacher_id IS NOT NULL
  ORDER BY
    COALESCE(ta.materialized_scheduled_minutes, 0) DESC,
    tb.family_name,
    tb.given_name;
END;
$$;

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

  IF public._is_teacher_only_app_user() THEN
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

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT EXECUTE ON FUNCTION public._current_linked_teacher_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public._is_teacher_only_app_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public._assert_teaching_ops_executive_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public._assert_teaching_ops_scheduling_access() TO authenticated;
GRANT EXECUTE ON FUNCTION public._teaching_ops_materialized_session_metrics(uuid, text, date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teaching_ops_session_metrics(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teaching_ops_change_metrics(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_teaching_session_operational_changes(date, date, text, uuid, uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_teaching_ops_exceptions(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_teaching_ops_overview(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_teaching_ops_intelligence_overview(date, date, boolean) TO authenticated;
