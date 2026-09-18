-- M4-T08: Daily operations read model (T07 occurrence semantics + calendar display fields).

CREATE OR REPLACE FUNCTION public.list_daily_operations(
  p_date date,
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

  IF p_date IS NULL THEN
    RAISE EXCEPTION 'invalid_daily_date' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RETURN;
  END IF;

  PERFORM public._validate_analytics_range(p_date, p_date, v_org_id, p_class_id, p_teacher_id, p_room_id);

  SELECT o.timezone INTO v_timezone
  FROM organization o
  WHERE o.id = v_org_id;

  RETURN QUERY
  SELECT
    o.source_type AS entry_type,
    o.operational_date AS occurrence_date,
    o.starts_at,
    o.ends_at,
    o.class_id,
    c.name AS class_name,
    o.class_schedule_id,
    o.teaching_session_id,
    o.session_status,
    o.teacher_id,
    o.teacher_resolution_status,
    NULLIF(trim(both FROM concat_ws(' ', t.given_name, t.family_name)), '') AS teacher_display_name,
    o.room_id,
    r.name AS room_name,
    r.code AS room_code
  FROM public._list_operational_occurrences(
    v_org_id, v_timezone, p_date, p_date, p_class_id, p_teacher_id, p_room_id
  ) o
  JOIN class c
    ON c.id = o.class_id
   AND c.organization_id = v_org_id
  LEFT JOIN teacher t
    ON t.id = o.teacher_id
   AND t.organization_id = v_org_id
  LEFT JOIN room r
    ON r.id = o.room_id
   AND r.organization_id = v_org_id
  ORDER BY o.starts_at, c.name, o.class_schedule_id NULLS LAST, o.teaching_session_id NULLS LAST;
END;
$$;

COMMENT ON FUNCTION public.list_daily_operations(date, uuid, uuid, uuid) IS
  'Org-scoped daily operations for one local calendar day. Materialized sessions are placed by current scheduled_start_at local date (reschedule-aware). Projections dedup on schedule+occurrence_date. Same semantics as list_operational_calendar (T06) and workload analytics (T07).';

GRANT EXECUTE ON FUNCTION public.list_daily_operations(date, uuid, uuid, uuid) TO authenticated;
