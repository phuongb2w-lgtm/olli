-- M4-T02: Teacher unavailability foundation and optional room notes hardening.

-- =============================================================================
-- ROOM HARDENING
-- =============================================================================

ALTER TABLE room
  ADD COLUMN IF NOT EXISTS notes text;

COMMENT ON COLUMN room.notes IS
  'Optional operational notes for schedulers. Not facility inventory.';

-- =============================================================================
-- TEACHER UNAVAILABILITY
-- =============================================================================

CREATE TABLE teacher_unavailability (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  teacher_id      uuid NOT NULL,
  block_type      text NOT NULL,
  weekday_code    text,
  start_time      time,
  end_time        time,
  effective_from  date,
  effective_to    date,
  starts_at       timestamptz,
  ends_at         timestamptz,
  reason          text,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT teacher_unavailability_block_type_check CHECK (
    block_type IN ('recurring', 'one_off')
  ),
  CONSTRAINT teacher_unavailability_status_check CHECK (
    status IN ('active', 'ended')
  ),
  CONSTRAINT teacher_unavailability_weekday_check CHECK (
    weekday_code IS NULL OR weekday_code IN ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')
  ),
  CONSTRAINT teacher_unavailability_recurring_shape CHECK (
    block_type <> 'recurring' OR (
      weekday_code IS NOT NULL
      AND start_time IS NOT NULL
      AND end_time IS NOT NULL
      AND effective_from IS NOT NULL
      AND end_time > start_time
      AND (effective_to IS NULL OR effective_to >= effective_from)
      AND starts_at IS NULL
      AND ends_at IS NULL
    )
  ),
  CONSTRAINT teacher_unavailability_one_off_shape CHECK (
    block_type <> 'one_off' OR (
      starts_at IS NOT NULL
      AND ends_at IS NOT NULL
      AND ends_at > starts_at
      AND weekday_code IS NULL
      AND start_time IS NULL
      AND end_time IS NULL
      AND effective_from IS NULL
      AND effective_to IS NULL
    )
  ),
  FOREIGN KEY (organization_id, teacher_id)
    REFERENCES teacher (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_teacher_unavailability_teacher
  ON teacher_unavailability (organization_id, teacher_id, status);

CREATE INDEX idx_teacher_unavailability_recurring_active
  ON teacher_unavailability (organization_id, teacher_id, weekday_code, effective_from, effective_to)
  WHERE block_type = 'recurring' AND status = 'active';

CREATE INDEX idx_teacher_unavailability_one_off_active
  ON teacher_unavailability (organization_id, teacher_id, starts_at, ends_at)
  WHERE block_type = 'one_off' AND status = 'active';

CREATE UNIQUE INDEX teacher_unavailability_recurring_exact_active_unique
  ON teacher_unavailability (
    organization_id,
    teacher_id,
    weekday_code,
    start_time,
    end_time,
    effective_from
  )
  WHERE block_type = 'recurring' AND status = 'active';

CREATE UNIQUE INDEX teacher_unavailability_one_off_exact_active_unique
  ON teacher_unavailability (organization_id, teacher_id, starts_at, ends_at)
  WHERE block_type = 'one_off' AND status = 'active';

CREATE TRIGGER teacher_unavailability_updated_at
  BEFORE UPDATE ON teacher_unavailability
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE teacher_unavailability
  ADD CONSTRAINT teacher_unavailability_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT teacher_unavailability_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

COMMENT ON TABLE teacher_unavailability IS
  'Periods when a teacher cannot be scheduled. Absence of a row does not imply availability.';

-- =============================================================================
-- UNAVAILABILITY INTERSECTION HELPER (M4-T04 will consume; no generation change)
-- =============================================================================

CREATE OR REPLACE FUNCTION public._weekday_code_to_dow(p_weekday_code text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_weekday_code
    WHEN 'mon' THEN 1 WHEN 'tue' THEN 2 WHEN 'wed' THEN 3 WHEN 'thu' THEN 4
    WHEN 'fri' THEN 5 WHEN 'sat' THEN 6 WHEN 'sun' THEN 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.teacher_has_unavailability(
  p_teacher_id uuid,
  p_range_start timestamptz,
  p_range_end timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
  v_cursor date;
  v_range_end_date date;
  v_weekday int;
  v_block record;
  v_block_start timestamptz;
  v_block_end timestamptz;
BEGIN
  IF p_teacher_id IS NULL OR p_range_start IS NULL OR p_range_end IS NULL OR p_range_end <= p_range_start THEN
    RETURN false;
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RETURN false;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM teacher_unavailability tu
    WHERE tu.organization_id = v_org_id
      AND tu.teacher_id = p_teacher_id
      AND tu.block_type = 'one_off'
      AND tu.status = 'active'
      AND tstzrange(tu.starts_at, tu.ends_at, '[)') && tstzrange(p_range_start, p_range_end, '[)')
  ) THEN
    RETURN true;
  END IF;

  SELECT o.timezone INTO v_timezone
  FROM organization o
  WHERE o.id = v_org_id;

  v_cursor := (p_range_start AT TIME ZONE v_timezone)::date;
  v_range_end_date := (p_range_end AT TIME ZONE v_timezone)::date;

  WHILE v_cursor <= v_range_end_date LOOP
    v_weekday := EXTRACT(DOW FROM v_cursor)::int;

    FOR v_block IN
      SELECT tu.weekday_code, tu.start_time, tu.end_time
      FROM teacher_unavailability tu
      WHERE tu.organization_id = v_org_id
        AND tu.teacher_id = p_teacher_id
        AND tu.block_type = 'recurring'
        AND tu.status = 'active'
        AND tu.effective_from <= v_cursor
        AND (tu.effective_to IS NULL OR tu.effective_to >= v_cursor)
        AND public._weekday_code_to_dow(tu.weekday_code) = v_weekday
    LOOP
      v_block_start := (v_cursor + v_block.start_time) AT TIME ZONE v_timezone;
      v_block_end := (v_cursor + v_block.end_time) AT TIME ZONE v_timezone;

      IF tstzrange(v_block_start, v_block_end, '[)') && tstzrange(p_range_start, p_range_end, '[)') THEN
        RETURN true;
      END IF;
    END LOOP;

    v_cursor := v_cursor + 1;
  END LOOP;

  RETURN false;
END;
$$;

COMMENT ON FUNCTION public.teacher_has_unavailability(uuid, timestamptz, timestamptz) IS
  'Returns true when an active unavailability block intersects the proposed interval in organization timezone.';

-- =============================================================================
-- RLS
-- Temporary permissions until M4-T09 scheduling.* family:
--   SELECT -> enrollment.read
--   INSERT -> enrollment.create
--   UPDATE -> enrollment.update
-- =============================================================================

ALTER TABLE teacher_unavailability ENABLE ROW LEVEL SECURITY;
ALTER TABLE teacher_unavailability FORCE ROW LEVEL SECURITY;

CREATE POLICY teacher_unavailability_select ON teacher_unavailability FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('enrollment.read')
  );

CREATE POLICY teacher_unavailability_insert ON teacher_unavailability FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('enrollment.create')
  );

CREATE POLICY teacher_unavailability_update ON teacher_unavailability FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('enrollment.update')
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('enrollment.update')
  );

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON teacher_unavailability TO authenticated;
GRANT SELECT, INSERT, UPDATE ON room TO authenticated;

GRANT EXECUTE ON FUNCTION public.teacher_has_unavailability(uuid, timestamptz, timestamptz) TO authenticated;
