-- M5-T03: Academic & teaching quality intelligence.
-- Teacher-entered evidence remains canonical; review metadata augments existing rows.

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('attendance.review'),
  ('assessment_result.review'),
  ('observation.review')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- REVIEW STATUS TYPE
-- =============================================================================

CREATE TYPE academic_review_status AS ENUM (
  'draft',
  'submitted',
  'confirmed',
  'returned'
);

COMMENT ON TYPE academic_review_status IS
  'Academic Operations review lifecycle: draft (teacher editing) → submitted → confirmed | returned.';

-- =============================================================================
-- ATTENDANCE REVIEW METADATA
-- =============================================================================

ALTER TABLE attendance
  ADD COLUMN review_status academic_review_status NOT NULL DEFAULT 'draft',
  ADD COLUMN submitted_at timestamptz,
  ADD COLUMN submitted_by uuid,
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN reviewed_by uuid,
  ADD COLUMN review_notes text;

UPDATE attendance SET review_status = 'confirmed' WHERE review_status = 'draft';

COMMENT ON COLUMN attendance.review_status IS
  'Manager-facing attendance KPIs use review_status = confirmed only.';

CREATE INDEX idx_attendance_review_status
  ON attendance (organization_id, review_status, teaching_session_id);

-- =============================================================================
-- ASSESSMENT RESULT REVIEW (extends M1 status semantics)
-- =============================================================================

ALTER TABLE assessment_result DROP CONSTRAINT IF EXISTS assessment_result_status_check;
ALTER TABLE assessment_result
  ADD CONSTRAINT assessment_result_status_check
  CHECK (status IN ('draft', 'submitted', 'finalized', 'corrected', 'returned'));

ALTER TABLE assessment_result
  ADD COLUMN submitted_at timestamptz,
  ADD COLUMN submitted_by uuid,
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN reviewed_by uuid,
  ADD COLUMN review_notes text;

UPDATE assessment_result
SET
  submitted_at = COALESCE(finalized_at, updated_at),
  reviewed_at = finalized_at,
  reviewed_by = updated_by
WHERE status IN ('finalized', 'corrected');

COMMENT ON COLUMN assessment_result.status IS
  'draft/submitted/returned = teacher workflow; finalized = Academic Operations confirmed; corrected = auditable post-confirmation edit.';

CREATE INDEX idx_assessment_result_review
  ON assessment_result (organization_id, status, assessment_id);

-- =============================================================================
-- TEACHER OBSERVATION REVIEW + TRANSLATION
-- =============================================================================

ALTER TABLE teacher_observation
  ADD COLUMN review_status academic_review_status NOT NULL DEFAULT 'draft',
  ADD COLUMN submitted_at timestamptz,
  ADD COLUMN submitted_by uuid,
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN reviewed_by uuid,
  ADD COLUMN review_notes text,
  ADD COLUMN comment_language text,
  ADD COLUMN translated_comment text,
  ADD COLUMN translated_language text,
  ADD COLUMN translated_by uuid,
  ADD COLUMN translated_at timestamptz;

UPDATE teacher_observation
SET review_status = 'confirmed'
WHERE status = 'recorded' AND review_status = 'draft';

COMMENT ON COLUMN teacher_observation.comment IS
  'Original teacher comment — never overwritten by translation.';
COMMENT ON COLUMN teacher_observation.translated_comment IS
  'Academic Operations human translation; stored separately from original comment.';

CREATE INDEX idx_teacher_observation_review
  ON teacher_observation (organization_id, review_status);

-- =============================================================================
-- PROTECTION TRIGGERS
-- =============================================================================

CREATE OR REPLACE FUNCTION protect_reviewed_attendance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.academic_review_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.review_status IN ('submitted', 'confirmed')
     AND (
       OLD.status IS DISTINCT FROM NEW.status
       OR OLD.review_status IS DISTINCT FROM NEW.review_status
     ) THEN
    RAISE EXCEPTION 'attendance_not_editable' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER attendance_protect_reviewed
  BEFORE UPDATE ON attendance
  FOR EACH ROW EXECUTE FUNCTION protect_reviewed_attendance();

CREATE OR REPLACE FUNCTION protect_reviewed_assessment_result()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.academic_review_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.status IN ('submitted', 'finalized')
     AND (
       OLD.raw_score IS DISTINCT FROM NEW.raw_score
       OR OLD.max_score IS DISTINCT FROM NEW.max_score
       OR (OLD.status IS DISTINCT FROM NEW.status AND NEW.status NOT IN ('draft', 'corrected', 'returned'))
     ) THEN
    RAISE EXCEPTION 'assessment_result_not_editable' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER assessment_result_protect_reviewed
  BEFORE UPDATE ON assessment_result
  FOR EACH ROW EXECUTE FUNCTION protect_reviewed_assessment_result();

CREATE OR REPLACE FUNCTION protect_reviewed_observation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.academic_review_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.review_status IN ('submitted', 'confirmed')
     AND (
       OLD.comment IS DISTINCT FROM NEW.comment
       OR OLD.review_status IS DISTINCT FROM NEW.review_status
     ) THEN
    RAISE EXCEPTION 'observation_not_editable' USING ERRCODE = 'P0001';
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.translated_comment IS DISTINCT FROM NEW.translated_comment
     AND NOT public.has_permission('observation.review') THEN
    RAISE EXCEPTION 'observation_translation_denied' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER teacher_observation_protect_reviewed
  BEFORE UPDATE ON teacher_observation
  FOR EACH ROW EXECUTE FUNCTION protect_reviewed_observation();

-- =============================================================================
-- REVIEW RPCs
-- =============================================================================

CREATE OR REPLACE FUNCTION public.submit_session_attendance(p_session_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_count integer;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('attendance.record') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  PERFORM set_config('olli.academic_review_mutation', 'true', true);

  UPDATE attendance a
  SET
    review_status = 'submitted',
    submitted_at = now(),
    submitted_by = public.current_app_user_id(),
    updated_at = now()
  FROM teaching_session ts
  WHERE a.teaching_session_id = p_session_id
    AND a.organization_id = v_org
    AND ts.id = p_session_id
    AND ts.organization_id = v_org
    AND a.review_status IN ('draft', 'returned');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_attendance(
  p_attendance_id uuid,
  p_action text,
  p_review_notes text DEFAULT NULL
)
RETURNS attendance
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row attendance;
  v_new_status academic_review_status;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('attendance.review') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_action NOT IN ('confirm', 'return') THEN
    RAISE EXCEPTION 'invalid_review_action' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM attendance
  WHERE id = p_attendance_id
    AND organization_id = public.current_organization_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'attendance_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.review_status NOT IN ('submitted') THEN
    RAISE EXCEPTION 'attendance_not_reviewable' USING ERRCODE = 'P0001';
  END IF;

  v_new_status := CASE p_action
    WHEN 'confirm' THEN 'confirmed'::academic_review_status
    WHEN 'return' THEN 'returned'::academic_review_status
  END;

  PERFORM set_config('olli.academic_review_mutation', 'true', true);

  UPDATE attendance
  SET
    review_status = v_new_status,
    reviewed_at = now(),
    reviewed_by = public.current_app_user_id(),
    review_notes = NULLIF(trim(p_review_notes), ''),
    updated_at = now()
  WHERE id = p_attendance_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assessment_result(p_result_id uuid)
RETURNS assessment_result
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row assessment_result;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('assessment_result.record') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM assessment_result
  WHERE id = p_result_id
    AND organization_id = public.current_organization_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'assessment_result_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.status NOT IN ('draft', 'returned', 'corrected') THEN
    RAISE EXCEPTION 'assessment_result_not_submittable' USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('olli.academic_review_mutation', 'true', true);

  UPDATE assessment_result
  SET
    status = 'submitted',
    submitted_at = now(),
    submitted_by = public.current_app_user_id(),
    updated_at = now()
  WHERE id = p_result_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_assessment_result(
  p_result_id uuid,
  p_action text,
  p_review_notes text DEFAULT NULL
)
RETURNS assessment_result
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row assessment_result;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('assessment_result.review') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_action NOT IN ('confirm', 'return', 'correct') THEN
    RAISE EXCEPTION 'invalid_review_action' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM assessment_result
  WHERE id = p_result_id
    AND organization_id = public.current_organization_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'assessment_result_not_found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('olli.academic_review_mutation', 'true', true);

  IF p_action = 'confirm' THEN
    IF v_row.status <> 'submitted' THEN
      RAISE EXCEPTION 'assessment_result_not_reviewable' USING ERRCODE = 'P0001';
    END IF;
    UPDATE assessment_result
    SET
      status = 'finalized',
      finalized_at = now(),
      reviewed_at = now(),
      reviewed_by = public.current_app_user_id(),
      review_notes = NULLIF(trim(p_review_notes), ''),
      updated_at = now()
    WHERE id = p_result_id
    RETURNING * INTO v_row;
  ELSIF p_action = 'return' THEN
    IF v_row.status <> 'submitted' THEN
      RAISE EXCEPTION 'assessment_result_not_reviewable' USING ERRCODE = 'P0001';
    END IF;
    UPDATE assessment_result
    SET
      status = 'returned',
      reviewed_at = now(),
      reviewed_by = public.current_app_user_id(),
      review_notes = NULLIF(trim(p_review_notes), ''),
      updated_at = now()
    WHERE id = p_result_id
    RETURNING * INTO v_row;
  ELSIF p_action = 'correct' THEN
    IF v_row.status <> 'finalized' THEN
      RAISE EXCEPTION 'assessment_result_not_correctable' USING ERRCODE = 'P0001';
    END IF;
    UPDATE assessment_result
    SET
      status = 'corrected',
      reviewed_at = now(),
      reviewed_by = public.current_app_user_id(),
      review_notes = NULLIF(trim(p_review_notes), ''),
      updated_at = now()
    WHERE id = p_result_id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_teacher_observation(p_observation_id uuid)
RETURNS teacher_observation
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row teacher_observation;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('observation.record') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM teacher_observation
  WHERE id = p_observation_id
    AND organization_id = public.current_organization_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'observation_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.review_status NOT IN ('draft', 'returned') THEN
    RAISE EXCEPTION 'observation_not_submittable' USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('olli.academic_review_mutation', 'true', true);

  UPDATE teacher_observation
  SET
    review_status = 'submitted',
    status = 'recorded',
    submitted_at = now(),
    submitted_by = public.current_app_user_id(),
    updated_at = now()
  WHERE id = p_observation_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_teacher_observation(
  p_observation_id uuid,
  p_action text,
  p_review_notes text DEFAULT NULL
)
RETURNS teacher_observation
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row teacher_observation;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('observation.review') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_action NOT IN ('confirm', 'return') THEN
    RAISE EXCEPTION 'invalid_review_action' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM teacher_observation
  WHERE id = p_observation_id
    AND organization_id = public.current_organization_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'observation_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.review_status <> 'submitted' THEN
    RAISE EXCEPTION 'observation_not_reviewable' USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('olli.academic_review_mutation', 'true', true);

  UPDATE teacher_observation
  SET
    review_status = CASE p_action
      WHEN 'confirm' THEN 'confirmed'::academic_review_status
      WHEN 'return' THEN 'returned'::academic_review_status
    END,
    reviewed_at = now(),
    reviewed_by = public.current_app_user_id(),
    review_notes = NULLIF(trim(p_review_notes), ''),
    updated_at = now()
  WHERE id = p_observation_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.translate_teacher_observation(
  p_observation_id uuid,
  p_translated_comment text,
  p_translated_language text DEFAULT NULL
)
RETURNS teacher_observation
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row teacher_observation;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('observation.review') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM teacher_observation
  WHERE id = p_observation_id
    AND organization_id = public.current_organization_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'observation_not_found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('olli.academic_review_mutation', 'true', true);

  UPDATE teacher_observation
  SET
    translated_comment = NULLIF(trim(p_translated_comment), ''),
    translated_language = NULLIF(trim(p_translated_language), ''),
    translated_by = public.current_app_user_id(),
    translated_at = now(),
    updated_at = now()
  WHERE id = p_observation_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- =============================================================================
-- PERMISSION GATES
-- =============================================================================

CREATE OR REPLACE FUNCTION public._assert_academic_quality_overview_access()
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

COMMENT ON FUNCTION public._assert_academic_quality_overview_access() IS
  'Center-wide academic quality intelligence — Manager only via report.executive.read.';

CREATE OR REPLACE FUNCTION public._assert_academic_review_access()
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

  IF NOT (
    public.has_permission('attendance.review')
    OR public.has_permission('assessment_result.review')
    OR public.has_permission('observation.review')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

COMMENT ON FUNCTION public._assert_academic_review_access() IS
  'Academic Operations review queues — not center-wide executive reporting.';

-- =============================================================================
-- KPI HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._academic_session_operational_date(
  p_scheduled_start_at timestamptz,
  p_timezone text
)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (p_scheduled_start_at AT TIME ZONE p_timezone)::date;
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
  v_materialized bigint;
  v_delivered bigint;
  v_cancelled bigint;
  v_in_progress bigint;
  v_scheduled bigint;
BEGIN
  PERFORM public._assert_academic_quality_overview_access();

  v_org := public.current_organization_id();
  SELECT o.timezone INTO v_tz FROM organization o WHERE o.id = v_org;

  SELECT
    count(*) FILTER (WHERE ts.status <> 'cancelled'),
    count(*) FILTER (WHERE ts.status = 'completed'),
    count(*) FILTER (WHERE ts.status = 'cancelled'),
    count(*) FILTER (WHERE ts.status = 'in_progress'),
    count(*) FILTER (WHERE ts.status = 'scheduled')
  INTO v_materialized, v_delivered, v_cancelled, v_in_progress, v_scheduled
  FROM teaching_session ts
  WHERE ts.organization_id = v_org
    AND public._academic_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date
    AND (p_class_id IS NULL OR ts.class_id = p_class_id);

  RETURN jsonb_build_object(
    'materialized_sessions', COALESCE(v_materialized, 0),
    'delivered_sessions', COALESCE(v_delivered, 0),
    'cancelled_sessions', COALESCE(v_cancelled, 0),
    'in_progress_sessions', COALESCE(v_in_progress, 0),
    'scheduled_sessions', COALESCE(v_scheduled, 0),
    'delivery_completion_ratio',
      CASE
        WHEN COALESCE(v_materialized, 0) = 0 THEN NULL
        ELSE round((v_delivered::numeric / v_materialized::numeric), 4)
      END,
    'denominator_rule', 'materialized non-cancelled sessions in period; delivered = status completed only'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_academic_attendance_metrics(
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
  v_present bigint;
  v_absent bigint;
  v_late bigint;
  v_excused bigint;
  v_unconfirmed bigint;
  v_rate numeric;
BEGIN
  PERFORM public._assert_academic_quality_overview_access();

  v_org := public.current_organization_id();
  SELECT o.timezone INTO v_tz FROM organization o WHERE o.id = v_org;

  SELECT
    count(*) FILTER (WHERE a.status = 'present'),
    count(*) FILTER (WHERE a.status = 'absent'),
    count(*) FILTER (WHERE a.status = 'late'),
    count(*) FILTER (WHERE a.status = 'excused')
  INTO v_present, v_absent, v_late, v_excused
  FROM attendance a
  JOIN teaching_session ts ON ts.id = a.teaching_session_id
  WHERE a.organization_id = v_org
    AND a.review_status = 'confirmed'
    AND ts.status = 'completed'
    AND public._academic_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date
    AND (p_class_id IS NULL OR ts.class_id = p_class_id);

  SELECT count(*) INTO v_unconfirmed
  FROM attendance a
  JOIN teaching_session ts ON ts.id = a.teaching_session_id
  WHERE a.organization_id = v_org
    AND a.review_status <> 'confirmed'
    AND ts.status = 'completed'
    AND public._academic_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date
    AND (p_class_id IS NULL OR ts.class_id = p_class_id);

  v_rate := CASE
    WHEN (COALESCE(v_present, 0) + COALESCE(v_absent, 0) + COALESCE(v_late, 0)) = 0 THEN NULL
    ELSE round(
      (COALESCE(v_present, 0) + COALESCE(v_late, 0))::numeric
      / (COALESCE(v_present, 0) + COALESCE(v_absent, 0) + COALESCE(v_late, 0))::numeric,
      4
    )
  END;

  RETURN jsonb_build_object(
    'confirmed_present', COALESCE(v_present, 0),
    'confirmed_absent', COALESCE(v_absent, 0),
    'confirmed_late', COALESCE(v_late, 0),
    'confirmed_excused', COALESCE(v_excused, 0),
    'unconfirmed_count', COALESCE(v_unconfirmed, 0),
    'attendance_rate', v_rate,
    'denominator_rule', 'confirmed attendance on completed sessions; excused excluded from rate; unconfirmed excluded'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_academic_assessment_metrics(
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
  v_total bigint;
  v_finalized bigint;
  v_submitted bigint;
  v_scales jsonb;
BEGIN
  PERFORM public._assert_academic_quality_overview_access();
  v_org := public.current_organization_id();

  SELECT
    count(*),
    count(*) FILTER (WHERE ar.status = 'finalized'),
    count(*) FILTER (WHERE ar.status = 'submitted')
  INTO v_total, v_finalized, v_submitted
  FROM assessment_result ar
  JOIN assessment asm ON asm.id = ar.assessment_id
  WHERE ar.organization_id = v_org
    AND asm.assessed_on BETWEEN p_start_date AND p_end_date
    AND (p_class_id IS NULL OR asm.class_id = p_class_id);

  SELECT COALESCE(jsonb_agg(scale_row ORDER BY scale_row->>'assessment_type_code'), '[]'::jsonb)
  INTO v_scales
  FROM (
    SELECT jsonb_build_object(
      'assessment_type_code', asm.assessment_type_code,
      'max_score', asm.max_score,
      'result_count', count(*),
      'finalized_count', count(*) FILTER (WHERE ar.status = 'finalized'),
      'average_raw_score', round(avg(ar.raw_score) FILTER (WHERE ar.status = 'finalized'), 2),
      'average_percent', round(
        avg((ar.raw_score / ar.max_score) * 100) FILTER (WHERE ar.status = 'finalized'),
        2
      )
    ) AS scale_row
    FROM assessment_result ar
    JOIN assessment asm ON asm.id = ar.assessment_id
    WHERE ar.organization_id = v_org
      AND asm.assessed_on BETWEEN p_start_date AND p_end_date
      AND (p_class_id IS NULL OR asm.class_id = p_class_id)
    GROUP BY asm.assessment_type_code, asm.max_score
  ) s;

  RETURN jsonb_build_object(
    'total_results', COALESCE(v_total, 0),
    'finalized_results', COALESCE(v_finalized, 0),
    'submitted_results', COALESCE(v_submitted, 0),
    'coverage_ratio', CASE WHEN COALESCE(v_total, 0) = 0 THEN NULL
      ELSE round(v_finalized::numeric / v_total::numeric, 4) END,
    'score_by_scale', COALESCE(v_scales, '[]'::jsonb),
    'denominator_rule', 'averages grouped by assessment_type_code + max_score; finalized status only'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_academic_observation_metrics(
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
  v_total bigint;
  v_confirmed bigint;
  v_awaiting_translation bigint;
BEGIN
  PERFORM public._assert_academic_quality_overview_access();
  v_org := public.current_organization_id();

  SELECT
    count(*) FILTER (WHERE obs.status <> 'void'),
    count(*) FILTER (WHERE obs.review_status = 'confirmed'),
    count(*) FILTER (
      WHERE obs.review_status = 'confirmed'
        AND obs.comment IS NOT NULL
        AND trim(obs.comment) <> ''
        AND (obs.translated_comment IS NULL OR trim(obs.translated_comment) = '')
    )
  INTO v_total, v_confirmed, v_awaiting_translation
  FROM teacher_observation obs
  WHERE obs.organization_id = v_org
    AND (obs.observed_at AT TIME ZONE (
      SELECT timezone FROM organization WHERE id = v_org
    ))::date BETWEEN p_start_date AND p_end_date
    AND (p_class_id IS NULL OR obs.class_id = p_class_id);

  RETURN jsonb_build_object(
    'observation_count', COALESCE(v_total, 0),
    'confirmed_observations', COALESCE(v_confirmed, 0),
    'coverage_ratio', CASE WHEN COALESCE(v_total, 0) = 0 THEN NULL
      ELSE round(v_confirmed::numeric / v_total::numeric, 4) END,
    'awaiting_translation', COALESCE(v_awaiting_translation, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_academic_review_backlog()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('report.executive.read')
    OR public.has_permission('attendance.review')
    OR public.has_permission('assessment_result.review')
    OR public.has_permission('observation.review')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  RETURN jsonb_build_object(
    'attendance_pending', (
      SELECT count(*) FROM attendance
      WHERE organization_id = v_org AND review_status = 'submitted'
    ),
    'scores_pending', (
      SELECT count(*) FROM assessment_result
      WHERE organization_id = v_org AND status = 'submitted'
    ),
    'comments_pending', (
      SELECT count(*) FROM teacher_observation
      WHERE organization_id = v_org AND review_status = 'submitted'
    ),
    'translation_pending', (
      SELECT count(*) FROM teacher_observation
      WHERE organization_id = v_org
        AND review_status = 'confirmed'
        AND comment IS NOT NULL AND trim(comment) <> ''
        AND (translated_comment IS NULL OR trim(translated_comment) = '')
    ),
    'returned_attendance', (
      SELECT count(*) FROM attendance
      WHERE organization_id = v_org AND review_status = 'returned'
    ),
    'returned_scores', (
      SELECT count(*) FROM assessment_result
      WHERE organization_id = v_org AND status = 'returned'
    ),
    'returned_comments', (
      SELECT count(*) FROM teacher_observation
      WHERE organization_id = v_org AND review_status = 'returned'
    )
  );
END;
$$;

-- =============================================================================
-- OVERVIEW RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_academic_quality_overview(
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
  v_delivery jsonb;
  v_attendance jsonb;
  v_assessment jsonb;
  v_observation jsonb;
  v_backlog jsonb;
  v_attendance_prev jsonb;
BEGIN
  PERFORM public._assert_academic_quality_overview_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);

  IF p_compare_previous THEN
    v_prev := public.resolve_finance_comparison_period(p_start_date, p_end_date);
    v_prev_start := (v_prev->>'start_date')::date;
    v_prev_end := (v_prev->>'end_date')::date;
    v_attendance_prev := public.get_academic_attendance_metrics(v_prev_start, v_prev_end, NULL);
  END IF;

  v_delivery := public.get_academic_teaching_delivery(p_start_date, p_end_date, NULL);
  v_attendance := public.get_academic_attendance_metrics(p_start_date, p_end_date, NULL);
  v_assessment := public.get_academic_assessment_metrics(p_start_date, p_end_date, NULL);
  v_observation := public.get_academic_observation_metrics(p_start_date, p_end_date, NULL);
  v_backlog := public.get_academic_review_backlog();

  RETURN jsonb_build_object(
    'period', jsonb_build_object(
      'start_date', v_bounds.start_date,
      'end_date', v_bounds.end_date,
      'timezone', v_bounds.timezone,
      'start_at_utc', v_bounds.start_at_utc,
      'end_at_exclusive', v_bounds.end_at_exclusive
    ),
    'comparison_period', CASE WHEN p_compare_previous THEN v_prev ELSE NULL END,
    'teaching_delivery', v_delivery,
    'attendance', jsonb_build_object(
      'current', v_attendance,
      'previous', v_attendance_prev,
      'rate_change', CASE
        WHEN v_attendance_prev IS NULL THEN NULL
        WHEN (v_attendance->>'attendance_rate') IS NULL
          OR (v_attendance_prev->>'attendance_rate') IS NULL THEN NULL
        ELSE round(
          (v_attendance->>'attendance_rate')::numeric
          - (v_attendance_prev->>'attendance_rate')::numeric,
          4
        )
      END
    ),
    'assessment', v_assessment,
    'observation', v_observation,
    'review_backlog', v_backlog
  );
END;
$$;

COMMENT ON FUNCTION public.get_academic_quality_overview(date, date, boolean) IS
  'Center-wide academic quality intelligence for Manager. Uses confirmed/finalized canonical data.';

-- =============================================================================
-- REVIEW QUEUE RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_academic_review_queue(
  p_queue_type text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  PERFORM public._assert_academic_review_access();
  v_org := public.current_organization_id();

  IF p_queue_type = 'attendance_pending' AND public.has_permission('attendance.review') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'queue_type', p_queue_type,
      'record_id', a.id,
      'entity_type', 'attendance',
      'session_id', a.teaching_session_id,
      'enrollment_id', a.enrollment_id,
      'status', a.status,
      'review_status', a.review_status,
      'submitted_at', a.submitted_at,
      'drill_down_path', '/academic/review/attendance/' || a.id::text
    )
    FROM attendance a
    WHERE a.organization_id = v_org AND a.review_status = 'submitted'
    ORDER BY a.submitted_at NULLS LAST
    LIMIT p_limit OFFSET p_offset;

  ELSIF p_queue_type = 'attendance_returned' AND public.has_permission('attendance.review') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'queue_type', p_queue_type,
      'record_id', a.id,
      'entity_type', 'attendance',
      'review_status', a.review_status,
      'review_notes', a.review_notes,
      'drill_down_path', '/academic/review/attendance/' || a.id::text
    )
    FROM attendance a
    WHERE a.organization_id = v_org AND a.review_status = 'returned'
    ORDER BY a.reviewed_at DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;

  ELSIF p_queue_type = 'scores_pending' AND public.has_permission('assessment_result.review') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'queue_type', p_queue_type,
      'record_id', ar.id,
      'entity_type', 'assessment_result',
      'assessment_id', ar.assessment_id,
      'enrollment_id', ar.enrollment_id,
      'raw_score', ar.raw_score,
      'max_score', ar.max_score,
      'status', ar.status,
      'submitted_at', ar.submitted_at,
      'drill_down_path', '/academic/review/scores/' || ar.id::text
    )
    FROM assessment_result ar
    WHERE ar.organization_id = v_org AND ar.status = 'submitted'
    ORDER BY ar.submitted_at NULLS LAST
    LIMIT p_limit OFFSET p_offset;

  ELSIF p_queue_type = 'scores_returned' AND public.has_permission('assessment_result.review') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'queue_type', p_queue_type,
      'record_id', ar.id,
      'entity_type', 'assessment_result',
      'status', ar.status,
      'review_notes', ar.review_notes,
      'drill_down_path', '/academic/review/scores/' || ar.id::text
    )
    FROM assessment_result ar
    WHERE ar.organization_id = v_org AND ar.status = 'returned'
    ORDER BY ar.reviewed_at DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;

  ELSIF p_queue_type = 'comments_pending' AND public.has_permission('observation.review') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'queue_type', p_queue_type,
      'record_id', obs.id,
      'entity_type', 'teacher_observation',
      'class_id', obs.class_id,
      'enrollment_id', obs.enrollment_id,
      'comment_preview', left(obs.comment, 120),
      'review_status', obs.review_status,
      'submitted_at', obs.submitted_at,
      'drill_down_path', '/academic/review/comments/' || obs.id::text
    )
    FROM teacher_observation obs
    WHERE obs.organization_id = v_org AND obs.review_status = 'submitted'
    ORDER BY obs.submitted_at NULLS LAST
    LIMIT p_limit OFFSET p_offset;

  ELSIF p_queue_type = 'translation_pending' AND public.has_permission('observation.review') THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'queue_type', p_queue_type,
      'record_id', obs.id,
      'entity_type', 'teacher_observation',
      'comment_preview', left(obs.comment, 120),
      'drill_down_path', '/academic/review/comments/' || obs.id::text
    )
    FROM teacher_observation obs
    WHERE obs.organization_id = v_org
      AND obs.review_status = 'confirmed'
      AND obs.comment IS NOT NULL AND trim(obs.comment) <> ''
      AND (obs.translated_comment IS NULL OR trim(obs.translated_comment) = '')
    ORDER BY obs.reviewed_at DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;

  ELSIF p_queue_type = 'incomplete_sessions' THEN
    RETURN QUERY
    SELECT jsonb_build_object(
      'queue_type', p_queue_type,
      'record_id', ts.id,
      'entity_type', 'teaching_session',
      'class_id', ts.class_id,
      'session_status', ts.status,
      'scheduled_start_at', ts.scheduled_start_at,
      'missing_attendance', (
        SELECT count(*)
        FROM enrollment e
        WHERE e.organization_id = v_org
          AND e.class_id = ts.class_id
          AND e.status = 'active'
          AND NOT EXISTS (
            SELECT 1 FROM attendance a
            WHERE a.teaching_session_id = ts.id AND a.enrollment_id = e.id
          )
      ),
      'drill_down_path', '/classes/' || ts.class_id::text || '/teaching/sessions/' || ts.id::text
    )
    FROM teaching_session ts
    WHERE ts.organization_id = v_org
      AND ts.status = 'completed'
      AND EXISTS (
        SELECT 1 FROM enrollment e
        WHERE e.organization_id = v_org
          AND e.class_id = ts.class_id
          AND e.status = 'active'
          AND NOT EXISTS (
            SELECT 1 FROM attendance a
            WHERE a.teaching_session_id = ts.id AND a.enrollment_id = e.id
          )
      )
    ORDER BY ts.scheduled_start_at DESC
    LIMIT p_limit OFFSET p_offset;
  END IF;
END;
$$;

-- =============================================================================
-- EXCEPTIONS RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_academic_exceptions(
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
  v_org uuid;
  v_tz text;
  v_bounds reporting_period_bounds;
BEGIN
  PERFORM public._assert_academic_quality_overview_access();
  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org := v_bounds.organization_id;
  SELECT o.timezone INTO v_tz FROM organization o WHERE o.id = v_org;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'completed_session_missing_attendance',
    'reason', 'Completed session has active enrollments without attendance records',
    'metric_value', sub.missing_count,
    'entity_type', 'teaching_session',
    'entity_id', sub.session_id,
    'drill_down_path', '/classes/' || sub.class_id::text || '/teaching/sessions/' || sub.session_id::text,
    'context', jsonb_build_object('class_id', sub.class_id, 'missing_count', sub.missing_count)
  )
  FROM (
    SELECT ts.id AS session_id, ts.class_id,
      count(*) AS missing_count
    FROM teaching_session ts
    JOIN enrollment e ON e.class_id = ts.class_id AND e.organization_id = ts.organization_id
    WHERE ts.organization_id = v_org
      AND ts.status = 'completed'
      AND e.status = 'active'
      AND public._academic_session_operational_date(ts.scheduled_start_at, v_tz)
          BETWEEN p_start_date AND p_end_date
      AND NOT EXISTS (
        SELECT 1 FROM attendance a
        WHERE a.teaching_session_id = ts.id AND a.enrollment_id = e.id
      )
    GROUP BY ts.id, ts.class_id
  ) sub;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'attendance_awaiting_review',
    'reason', 'Attendance submitted but awaiting Academic Operations confirmation',
    'metric_value', 1,
    'entity_type', 'attendance',
    'entity_id', a.id,
    'drill_down_path', '/academic/review/attendance/' || a.id::text,
    'context', jsonb_build_object('session_id', a.teaching_session_id, 'status', a.status)
  )
  FROM attendance a
  JOIN teaching_session ts ON ts.id = a.teaching_session_id
  WHERE a.organization_id = v_org
    AND a.review_status = 'submitted'
    AND public._academic_session_operational_date(ts.scheduled_start_at, v_tz)
        BETWEEN p_start_date AND p_end_date;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'comment_awaiting_translation',
    'reason', 'Confirmed comment has no translation',
    'metric_value', 1,
    'entity_type', 'teacher_observation',
    'entity_id', obs.id,
    'drill_down_path', '/academic/review/comments/' || obs.id::text,
    'context', jsonb_build_object('class_id', obs.class_id)
  )
  FROM teacher_observation obs
  WHERE obs.organization_id = v_org
    AND obs.review_status = 'confirmed'
    AND obs.comment IS NOT NULL AND trim(obs.comment) <> ''
    AND (obs.translated_comment IS NULL OR trim(obs.translated_comment) = '')
    AND (obs.observed_at AT TIME ZONE v_tz)::date BETWEEN p_start_date AND p_end_date;

  RETURN QUERY
  SELECT jsonb_build_object(
    'exception_code', 'repeated_absence',
    'reason', 'Student absent 3+ times in period on confirmed attendance',
    'metric_value', sub.absence_count,
    'entity_type', 'enrollment',
    'entity_id', sub.enrollment_id,
    'drill_down_path', '/students/' || sub.student_id::text,
    'context', jsonb_build_object('absence_count', sub.absence_count)
  )
  FROM (
    SELECT e.id AS enrollment_id, e.student_id, count(*) AS absence_count
    FROM attendance a
    JOIN teaching_session ts ON ts.id = a.teaching_session_id
    JOIN enrollment e ON e.id = a.enrollment_id
    WHERE a.organization_id = v_org
      AND a.review_status = 'confirmed'
      AND a.status = 'absent'
      AND ts.status = 'completed'
      AND public._academic_session_operational_date(ts.scheduled_start_at, v_tz)
          BETWEEN p_start_date AND p_end_date
    GROUP BY e.id, e.student_id
    HAVING count(*) >= 3
  ) sub;
END;
$$;

-- =============================================================================
-- RLS: REVIEW PERMISSIONS ON UPDATE
-- =============================================================================

DROP POLICY IF EXISTS attendance_update ON attendance;
CREATE POLICY attendance_update ON attendance FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      public.has_permission('attendance.record')
      OR public.has_permission('attendance.review')
    )
  )
  WITH CHECK (organization_id = public.current_organization_id());

DROP POLICY IF EXISTS assessment_result_update ON assessment_result;
CREATE POLICY assessment_result_update ON assessment_result FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      public.has_permission('assessment_result.record')
      OR public.has_permission('assessment_result.review')
    )
  )
  WITH CHECK (organization_id = public.current_organization_id());

DROP POLICY IF EXISTS teacher_observation_update ON teacher_observation;
CREATE POLICY teacher_observation_update ON teacher_observation FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      public.has_permission('observation.record')
      OR public.has_permission('observation.review')
    )
  )
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.submit_session_attendance(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_attendance(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assessment_result(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_assessment_result(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_teacher_observation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_teacher_observation(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.translate_teacher_observation(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_academic_quality_overview(date, date, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_academic_teaching_delivery(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_academic_attendance_metrics(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_academic_assessment_metrics(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_academic_observation_metrics(date, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_academic_review_backlog() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_academic_review_queue(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_academic_exceptions(date, date) TO authenticated;
