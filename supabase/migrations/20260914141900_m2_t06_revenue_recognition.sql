-- M2-T06: Revenue recognition (per-lesson and stage/checkpoint).

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('revenue.read'),
  ('revenue.recognize')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- RECOGNITION BASIS (extend T04 codes: stage is canonical; stage_checkpoint legacy)
-- =============================================================================

ALTER TABLE enrollment_financial_terms DROP CONSTRAINT IF EXISTS enrollment_financial_terms_recognition_check;
ALTER TABLE enrollment_financial_terms
  ADD CONSTRAINT enrollment_financial_terms_recognition_check CHECK (
    recognition_basis_code IS NULL OR recognition_basis_code IN (
      'per_lesson', 'stage', 'stage_checkpoint', 'deferred'
    )
  );

-- =============================================================================
-- RECOGNITION CONFIGURATION
-- =============================================================================

CREATE TABLE enrollment_recognition_config (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id              uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  enrollment_id                uuid NOT NULL,
  enrollment_financial_terms_id uuid NOT NULL,
  recognition_basis_code       text NOT NULL,
  net_tuition_snapshot         bigint NOT NULL,
  recognition_unit_count       integer,
  status                       text NOT NULL DEFAULT 'active',
  created_at                   timestamptz NOT NULL DEFAULT now(),
  created_by                   uuid,
  UNIQUE (organization_id, id),
  UNIQUE (enrollment_financial_terms_id),
  CONSTRAINT enrollment_recognition_config_basis_check CHECK (
    recognition_basis_code IN ('per_lesson', 'stage', 'stage_checkpoint')
  ),
  CONSTRAINT enrollment_recognition_config_status_check CHECK (
    status IN ('active', 'void')
  ),
  CONSTRAINT enrollment_recognition_config_net_check CHECK (net_tuition_snapshot >= 0),
  CONSTRAINT enrollment_recognition_config_unit_count_check CHECK (
    (recognition_basis_code IN ('stage', 'stage_checkpoint') AND recognition_unit_count IS NULL)
    OR (recognition_basis_code = 'per_lesson' AND recognition_unit_count IS NOT NULL AND recognition_unit_count > 0)
  ),
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_financial_terms_id)
    REFERENCES enrollment_financial_terms (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_enrollment_recognition_config_enrollment
  ON enrollment_recognition_config (organization_id, enrollment_id);

COMMENT ON TABLE enrollment_recognition_config IS
  'Financial recognition configuration for an enrollment agreement. Distinct from recognition events.';

-- =============================================================================
-- STAGE RECOGNITION CONFIGURATION
-- =============================================================================

CREATE TABLE enrollment_recognition_stage (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                 uuid NOT NULL,
  enrollment_recognition_config_id uuid NOT NULL,
  sequence_number                 integer NOT NULL,
  amount                          bigint NOT NULL,
  assessment_id                   uuid,
  label                           text,
  status                          text NOT NULL DEFAULT 'active',
  created_at                      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (enrollment_recognition_config_id, sequence_number),
  CONSTRAINT enrollment_recognition_stage_amount_check CHECK (amount > 0),
  CONSTRAINT enrollment_recognition_stage_sequence_check CHECK (sequence_number > 0),
  CONSTRAINT enrollment_recognition_stage_status_check CHECK (status IN ('active', 'void')),
  FOREIGN KEY (organization_id, enrollment_recognition_config_id)
    REFERENCES enrollment_recognition_config (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, assessment_id)
    REFERENCES assessment (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_enrollment_recognition_stage_config
  ON enrollment_recognition_stage (organization_id, enrollment_recognition_config_id, sequence_number);

COMMENT ON TABLE enrollment_recognition_stage IS
  'Stage/checkpoint recognition schedule referencing optional M1 assessment evidence.';

-- =============================================================================
-- RECOGNITION EVENTS
-- =============================================================================

CREATE TABLE revenue_recognition_event (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                 uuid NOT NULL,
  enrollment_id                   uuid NOT NULL,
  enrollment_financial_terms_id   uuid NOT NULL,
  enrollment_recognition_config_id uuid NOT NULL,
  enrollment_recognition_stage_id uuid,
  recognition_basis_code          text NOT NULL,
  amount                          bigint NOT NULL,
  lesson_sequence_number          integer,
  teaching_session_id             uuid,
  assessment_result_id            uuid,
  recognized_at                   timestamptz NOT NULL DEFAULT now(),
  status                          text NOT NULL DEFAULT 'posted',
  voided_at                       timestamptz,
  notes                           text,
  created_at                      timestamptz NOT NULL DEFAULT now(),
  created_by                      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT revenue_recognition_event_amount_check CHECK (amount > 0),
  CONSTRAINT revenue_recognition_event_status_check CHECK (status IN ('posted', 'void')),
  CONSTRAINT revenue_recognition_event_basis_check CHECK (
    recognition_basis_code IN ('per_lesson', 'stage', 'stage_checkpoint')
  ),
  CONSTRAINT revenue_recognition_event_per_lesson_shape CHECK (
    recognition_basis_code <> 'per_lesson'
    OR (teaching_session_id IS NOT NULL AND lesson_sequence_number IS NOT NULL)
  ),
  CONSTRAINT revenue_recognition_event_stage_shape CHECK (
    recognition_basis_code NOT IN ('stage', 'stage_checkpoint')
    OR enrollment_recognition_stage_id IS NOT NULL
  ),
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_financial_terms_id)
    REFERENCES enrollment_financial_terms (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_recognition_config_id)
    REFERENCES enrollment_recognition_config (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_recognition_stage_id)
    REFERENCES enrollment_recognition_stage (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teaching_session_id)
    REFERENCES teaching_session (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, assessment_result_id)
    REFERENCES assessment_result (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX idx_revenue_recognition_one_per_session
  ON revenue_recognition_event (enrollment_financial_terms_id, teaching_session_id)
  WHERE teaching_session_id IS NOT NULL AND status = 'posted';

CREATE UNIQUE INDEX idx_revenue_recognition_one_per_stage
  ON revenue_recognition_event (enrollment_recognition_stage_id)
  WHERE enrollment_recognition_stage_id IS NOT NULL AND status = 'posted';

CREATE INDEX idx_revenue_recognition_enrollment
  ON revenue_recognition_event (organization_id, enrollment_id, status);

COMMENT ON TABLE revenue_recognition_event IS
  'Immutable earned-revenue facts. Void reverses effect without deleting history.';

-- =============================================================================
-- HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.normalize_recognition_basis_code(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_code = 'stage_checkpoint' THEN 'stage'
    ELSE p_code
  END;
$$;

CREATE OR REPLACE FUNCTION public.recognition_lesson_amount(
  p_total bigint,
  p_lesson_count integer,
  p_sequence_number integer
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public.installment_schedule_amount(p_total, p_lesson_count, p_sequence_number);
$$;

CREATE OR REPLACE FUNCTION public.enrollment_recognition_entitlement(p_terms_id uuid)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(t.net_tuition_amount, 0)::bigint
  FROM enrollment_financial_terms t
  WHERE t.id = p_terms_id AND t.status = 'active';
$$;

CREATE OR REPLACE FUNCTION public.enrollment_recognized_revenue(p_enrollment_id uuid)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(r.amount), 0)::bigint
  FROM revenue_recognition_event r
  WHERE r.enrollment_id = p_enrollment_id AND r.status = 'posted';
$$;

CREATE OR REPLACE FUNCTION public.is_attendance_eligible_for_recognition(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_status IN ('present', 'late');
$$;

CREATE OR REPLACE FUNCTION public.validate_revenue_recognition_cap()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_entitlement bigint;
  v_recognized bigint;
BEGIN
  IF NEW.status IS DISTINCT FROM 'posted' THEN
    RETURN NEW;
  END IF;

  v_entitlement := public.enrollment_recognition_entitlement(NEW.enrollment_financial_terms_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_recognized
  FROM revenue_recognition_event
  WHERE enrollment_financial_terms_id = NEW.enrollment_financial_terms_id
    AND status = 'posted'
    AND id IS DISTINCT FROM NEW.id;

  IF v_recognized + NEW.amount > v_entitlement THEN
    RAISE EXCEPTION 'recognition_exceeds_entitlement';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER revenue_recognition_event_validate_cap
  BEFORE INSERT OR UPDATE ON revenue_recognition_event
  FOR EACH ROW EXECUTE FUNCTION validate_revenue_recognition_cap();

-- =============================================================================
-- RPC: INITIALIZE PER-LESSON RECOGNITION CONFIG
-- =============================================================================

CREATE OR REPLACE FUNCTION public.initialize_enrollment_per_lesson_recognition(
  p_terms_id uuid,
  p_lesson_count integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_config_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('revenue.recognize') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND OR v_terms.status <> 'active' THEN
    RAISE EXCEPTION 'active_terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF public.normalize_recognition_basis_code(v_terms.recognition_basis_code) <> 'per_lesson' THEN
    RAISE EXCEPTION 'invalid_recognition_basis' USING ERRCODE = 'P0001';
  END IF;

  IF p_lesson_count IS NULL OR p_lesson_count <= 0 THEN
    RAISE EXCEPTION 'invalid_lesson_count' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM revenue_recognition_event
    WHERE enrollment_financial_terms_id = p_terms_id AND status = 'posted'
  ) THEN
    RAISE EXCEPTION 'recognition_already_started' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO enrollment_recognition_config (
    organization_id,
    enrollment_id,
    enrollment_financial_terms_id,
    recognition_basis_code,
    net_tuition_snapshot,
    recognition_unit_count,
    created_by
  ) VALUES (
    v_terms.organization_id,
    v_terms.enrollment_id,
    v_terms.id,
    'per_lesson',
    v_terms.net_tuition_amount,
    p_lesson_count,
    public.current_app_user_id()
  )
  ON CONFLICT (enrollment_financial_terms_id) DO UPDATE
  SET
    net_tuition_snapshot = EXCLUDED.net_tuition_snapshot,
    recognition_unit_count = EXCLUDED.recognition_unit_count,
    status = 'active'
  RETURNING id INTO v_config_id;

  RETURN v_config_id;
END;
$$;

-- =============================================================================
-- RPC: CONFIGURE STAGE RECOGNITION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_enrollment_recognition_stages(
  p_terms_id uuid,
  p_stages jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_config_id uuid;
  v_item jsonb;
  v_total bigint := 0;
  v_seq integer;
  v_amount bigint;
  v_assessment_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('revenue.recognize') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND OR v_terms.status NOT IN ('draft', 'active') THEN
    RAISE EXCEPTION 'terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF public.normalize_recognition_basis_code(v_terms.recognition_basis_code) <> 'stage' THEN
    RAISE EXCEPTION 'invalid_recognition_basis' USING ERRCODE = 'P0001';
  END IF;

  IF p_stages IS NULL OR jsonb_typeof(p_stages) <> 'array' OR jsonb_array_length(p_stages) = 0 THEN
    RAISE EXCEPTION 'stages_required' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM revenue_recognition_event
    WHERE enrollment_financial_terms_id = p_terms_id AND status = 'posted'
  ) THEN
    RAISE EXCEPTION 'recognition_already_started' USING ERRCODE = 'P0001';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_stages)
  LOOP
    v_amount := (v_item->>'amount')::bigint;
    IF v_amount IS NULL OR v_amount <= 0 THEN
      RAISE EXCEPTION 'invalid_stage_amount' USING ERRCODE = 'P0001';
    END IF;
    v_total := v_total + v_amount;
  END LOOP;

  IF v_total <> v_terms.net_tuition_amount THEN
    RAISE EXCEPTION 'stage_total_mismatch' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO enrollment_recognition_config (
    organization_id,
    enrollment_id,
    enrollment_financial_terms_id,
    recognition_basis_code,
    net_tuition_snapshot,
    created_by
  ) VALUES (
    v_terms.organization_id,
    v_terms.enrollment_id,
    v_terms.id,
    'stage',
    v_terms.net_tuition_amount,
    public.current_app_user_id()
  )
  ON CONFLICT (enrollment_financial_terms_id) DO UPDATE
  SET
    recognition_basis_code = 'stage',
    net_tuition_snapshot = EXCLUDED.net_tuition_snapshot,
    recognition_unit_count = NULL,
    status = 'active'
  RETURNING id INTO v_config_id;

  UPDATE enrollment_recognition_stage
  SET status = 'void'
  WHERE enrollment_recognition_config_id = v_config_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_stages)
  LOOP
    v_seq := (v_item->>'sequence_number')::integer;
    v_amount := (v_item->>'amount')::bigint;
    v_assessment_id := NULLIF(v_item->>'assessment_id', '')::uuid;

    IF v_seq IS NULL OR v_seq <= 0 THEN
      RAISE EXCEPTION 'invalid_stage_sequence' USING ERRCODE = 'P0001';
    END IF;

    IF v_assessment_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM assessment a
      WHERE a.id = v_assessment_id AND a.organization_id = v_terms.organization_id
    ) THEN
      RAISE EXCEPTION 'assessment_not_found' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO enrollment_recognition_stage (
      organization_id,
      enrollment_recognition_config_id,
      sequence_number,
      amount,
      assessment_id,
      label,
      status
    ) VALUES (
      v_terms.organization_id,
      v_config_id,
      v_seq,
      v_amount,
      v_assessment_id,
      NULLIF(v_item->>'label', ''),
      'active'
    );
  END LOOP;

  RETURN v_config_id;
END;
$$;

-- =============================================================================
-- INTERNAL: RECOGNIZE PER-LESSON FOR ONE ENROLLMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION public._recognize_per_lesson_for_enrollment(
  p_enrollment_id uuid,
  p_teaching_session_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_config enrollment_recognition_config%ROWTYPE;
  v_rec record;
  v_created integer := 0;
BEGIN
  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE enrollment_id = p_enrollment_id
    AND organization_id = public.current_organization_id()
    AND status = 'active'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_config
  FROM enrollment_recognition_config
  WHERE enrollment_financial_terms_id = v_terms.id
    AND status = 'active';

  IF NOT FOUND OR v_config.recognition_basis_code <> 'per_lesson' THEN
    RETURN 0;
  END IF;

  FOR v_rec IN
    SELECT
      ts.id AS teaching_session_id,
      ROW_NUMBER() OVER (ORDER BY ts.scheduled_start_at, ts.id)::integer AS lesson_sequence_number
    FROM teaching_session ts
    JOIN enrollment e ON e.class_id = ts.class_id
    JOIN attendance a ON a.teaching_session_id = ts.id AND a.enrollment_id = e.id
    WHERE e.id = p_enrollment_id
      AND e.organization_id = v_terms.organization_id
      AND ts.organization_id = v_terms.organization_id
      AND ts.status = 'completed'
      AND public.is_attendance_eligible_for_recognition(a.status)
      AND (p_teaching_session_id IS NULL OR ts.id = p_teaching_session_id)
      AND NOT EXISTS (
        SELECT 1 FROM revenue_recognition_event r
        WHERE r.enrollment_financial_terms_id = v_terms.id
          AND r.teaching_session_id = ts.id
          AND r.status = 'posted'
      )
    ORDER BY ts.scheduled_start_at, ts.id
  LOOP
    IF v_rec.lesson_sequence_number > v_config.recognition_unit_count THEN
      CONTINUE;
    END IF;

    INSERT INTO revenue_recognition_event (
      organization_id,
      enrollment_id,
      enrollment_financial_terms_id,
      enrollment_recognition_config_id,
      recognition_basis_code,
      amount,
      lesson_sequence_number,
      teaching_session_id,
      created_by
    ) VALUES (
      v_terms.organization_id,
      p_enrollment_id,
      v_terms.id,
      v_config.id,
      'per_lesson',
      public.recognition_lesson_amount(
        v_config.net_tuition_snapshot,
        v_config.recognition_unit_count,
        v_rec.lesson_sequence_number
      ),
      v_rec.lesson_sequence_number,
      v_rec.teaching_session_id,
      public.current_app_user_id()
    );

    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$;

-- =============================================================================
-- INTERNAL: RECOGNIZE STAGE FOR ONE ENROLLMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION public._recognize_stage_for_enrollment(p_enrollment_id uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_config enrollment_recognition_config%ROWTYPE;
  v_stage record;
  v_created integer := 0;
BEGIN
  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE enrollment_id = p_enrollment_id
    AND organization_id = public.current_organization_id()
    AND status = 'active'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_config
  FROM enrollment_recognition_config
  WHERE enrollment_financial_terms_id = v_terms.id
    AND status = 'active';

  IF NOT FOUND OR v_config.recognition_basis_code NOT IN ('stage', 'stage_checkpoint') THEN
    RETURN 0;
  END IF;

  FOR v_stage IN
    SELECT s.*
    FROM enrollment_recognition_stage s
    WHERE s.enrollment_recognition_config_id = v_config.id
      AND s.status = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM revenue_recognition_event r
        WHERE r.enrollment_recognition_stage_id = s.id
          AND r.status = 'posted'
      )
    ORDER BY s.sequence_number
  LOOP
    IF v_stage.assessment_id IS NULL THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM assessment_result ar
      WHERE ar.enrollment_id = p_enrollment_id
        AND ar.assessment_id = v_stage.assessment_id
        AND ar.organization_id = v_terms.organization_id
        AND ar.status = 'finalized'
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO revenue_recognition_event (
      organization_id,
      enrollment_id,
      enrollment_financial_terms_id,
      enrollment_recognition_config_id,
      enrollment_recognition_stage_id,
      recognition_basis_code,
      amount,
      assessment_result_id,
      created_by
    )
    SELECT
      v_terms.organization_id,
      p_enrollment_id,
      v_terms.id,
      v_config.id,
      v_stage.id,
      'stage',
      v_stage.amount,
      ar.id,
      public.current_app_user_id()
    FROM assessment_result ar
    WHERE ar.enrollment_id = p_enrollment_id
      AND ar.assessment_id = v_stage.assessment_id
      AND ar.status = 'finalized'
    LIMIT 1;

    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$;

-- =============================================================================
-- RPC: RECOGNIZE ENROLLMENT REVENUE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.recognize_enrollment_revenue(p_enrollment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_terms enrollment_financial_terms%ROWTYPE;
  v_per_lesson integer := 0;
  v_stage integer := 0;
  v_entitlement bigint;
  v_recognized bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('revenue.recognize') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  IF NOT EXISTS (
    SELECT 1 FROM enrollment e
    WHERE e.id = p_enrollment_id AND e.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'enrollment_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE enrollment_id = p_enrollment_id
    AND organization_id = v_org
    AND status = 'active'
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'active_terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF public.normalize_recognition_basis_code(v_terms.recognition_basis_code) = 'per_lesson' THEN
    v_per_lesson := public._recognize_per_lesson_for_enrollment(p_enrollment_id, NULL);
  ELSIF public.normalize_recognition_basis_code(v_terms.recognition_basis_code) = 'stage' THEN
    v_stage := public._recognize_stage_for_enrollment(p_enrollment_id);
  END IF;

  v_entitlement := public.enrollment_recognition_entitlement(v_terms.id);
  v_recognized := public.enrollment_recognized_revenue(p_enrollment_id);

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'events_created', v_per_lesson + v_stage,
    'per_lesson_events_created', v_per_lesson,
    'stage_events_created', v_stage,
    'recognition_entitlement', v_entitlement,
    'recognized_revenue', v_recognized,
    'unrecognized_service_obligation', GREATEST(v_entitlement - v_recognized, 0)
  );
END;
$$;

-- =============================================================================
-- RPC: RECOGNIZE TEACHING SESSION REVENUE (BATCH)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.recognize_teaching_session_revenue(p_teaching_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_class_id uuid;
  v_total integer := 0;
  v_enrollment_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('revenue.recognize') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := public.current_organization_id();

  SELECT class_id INTO v_class_id
  FROM teaching_session
  WHERE id = p_teaching_session_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  FOR v_enrollment_id IN
    SELECT e.id
    FROM enrollment e
    JOIN enrollment_financial_terms t ON t.enrollment_id = e.id AND t.status = 'active'
    WHERE e.class_id = v_class_id
      AND e.organization_id = v_org
      AND e.status IN ('pending', 'active')
      AND public.normalize_recognition_basis_code(t.recognition_basis_code) = 'per_lesson'
  LOOP
    v_total := v_total + public._recognize_per_lesson_for_enrollment(v_enrollment_id, p_teaching_session_id);
  END LOOP;

  RETURN jsonb_build_object(
    'teaching_session_id', p_teaching_session_id,
    'events_created', v_total
  );
END;
$$;

-- =============================================================================
-- RPC: VOID RECOGNITION EVENT
-- =============================================================================

CREATE OR REPLACE FUNCTION public.void_revenue_recognition_event(
  p_event_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_event revenue_recognition_event%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('revenue.recognize') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_event
  FROM revenue_recognition_event
  WHERE id = p_event_id AND organization_id = public.current_organization_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'event_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_event.status <> 'posted' THEN
    RAISE EXCEPTION 'event_not_voidable' USING ERRCODE = 'P0001';
  END IF;

  UPDATE revenue_recognition_event
  SET status = 'void',
      voided_at = now(),
      notes = COALESCE(NULLIF(btrim(p_notes), ''), notes)
  WHERE id = p_event_id;

  RETURN jsonb_build_object(
    'event_id', p_event_id,
    'status', 'void',
    'recognized_revenue', public.enrollment_recognized_revenue(v_event.enrollment_id)
  );
END;
$$;

-- =============================================================================
-- UPDATE ENROLLMENT FINANCIAL SUMMARY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_enrollment_financial_summary(p_enrollment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_terms enrollment_financial_terms%ROWTYPE;
  v_student_id uuid;
  v_billing_guardian_id uuid;
  v_scheduled bigint;
  v_charged bigint;
  v_adjustments bigint;
  v_allocated bigint;
  v_outstanding bigint;
  v_unapplied bigint;
  v_entitlement bigint;
  v_recognized bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT e.student_id INTO v_student_id
  FROM enrollment e
  WHERE e.id = p_enrollment_id AND e.organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'enrollment_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE enrollment_id = p_enrollment_id
    AND organization_id = v_org_id
    AND status = 'active'
  LIMIT 1;

  SELECT public.resolve_enrollment_billing_guardian_id(p_enrollment_id)
    INTO v_billing_guardian_id;

  SELECT COALESCE(SUM(si.amount), 0) INTO v_scheduled
  FROM enrollment_payment_schedule_item si
  JOIN enrollment_financial_terms t ON t.id = si.enrollment_financial_terms_id
  WHERE t.enrollment_id = p_enrollment_id
    AND t.organization_id = v_org_id
    AND t.status = 'active'
    AND si.status = 'scheduled';

  SELECT COALESCE(SUM(c.amount), 0) INTO v_charged
  FROM charge c
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND c.charge_source_code = 'tuition'
    AND c.status <> 'void';

  SELECT COALESCE(SUM(fa.amount_delta), 0) INTO v_adjustments
  FROM financial_adjustment fa
  JOIN charge c ON c.id = fa.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND fa.status = 'posted';

  SELECT COALESCE(SUM(pa.amount), 0) INTO v_allocated
  FROM payment_allocation pa
  JOIN charge c ON c.id = pa.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND c.status <> 'void'
    AND pa.status = 'posted';

  SELECT COALESCE(SUM(cb.outstanding_balance), 0) INTO v_outstanding
  FROM charge_balance cb
  JOIN charge c ON c.id = cb.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND cb.organization_id = v_org_id;

  IF v_billing_guardian_id IS NOT NULL THEN
    SELECT COALESCE(SUM(
      p.amount - public.payment_allocated_amount(p.id)
    ), 0) INTO v_unapplied
    FROM payment p
    WHERE p.organization_id = v_org_id
      AND p.status = 'posted'
      AND p.guardian_id = v_billing_guardian_id
      AND (p.student_id IS NULL OR p.student_id = v_student_id)
      AND p.amount > public.payment_allocated_amount(p.id);
  ELSE
    v_unapplied := 0;
  END IF;

  v_entitlement := COALESCE(public.enrollment_recognition_entitlement(v_terms.id), COALESCE(v_terms.net_tuition_amount, 0));
  v_recognized := public.enrollment_recognized_revenue(p_enrollment_id);

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'active_terms_id', v_terms.id,
    'net_tuition', COALESCE(v_terms.net_tuition_amount, 0),
    'scheduled_amount', v_scheduled,
    'charged_amount', v_charged,
    'adjustments_amount', v_adjustments,
    'allocated_amount', v_allocated,
    'cash_allocated_to_enrollment', v_allocated,
    'outstanding_amount', v_outstanding,
    'outstanding_receivable', v_outstanding,
    'unapplied_payment_amount', v_unapplied,
    'recognition_entitlement', v_entitlement,
    'recognized_revenue', v_recognized,
    'unrecognized_service_obligation', GREATEST(v_entitlement - v_recognized, 0)
  );
END;
$$;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE enrollment_recognition_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollment_recognition_config FORCE ROW LEVEL SECURITY;
ALTER TABLE enrollment_recognition_stage ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollment_recognition_stage FORCE ROW LEVEL SECURITY;
ALTER TABLE revenue_recognition_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE revenue_recognition_event FORCE ROW LEVEL SECURITY;

CREATE POLICY enrollment_recognition_config_select ON enrollment_recognition_config FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.read'));

CREATE POLICY enrollment_recognition_config_insert ON enrollment_recognition_config FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.recognize'));

CREATE POLICY enrollment_recognition_config_update ON enrollment_recognition_config FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.recognize'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY enrollment_recognition_stage_select ON enrollment_recognition_stage FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.read'));

CREATE POLICY enrollment_recognition_stage_insert ON enrollment_recognition_stage FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.recognize'));

CREATE POLICY enrollment_recognition_stage_update ON enrollment_recognition_stage FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.recognize'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY revenue_recognition_event_select ON revenue_recognition_event FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.read'));

CREATE POLICY revenue_recognition_event_insert ON revenue_recognition_event FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.recognize'));

CREATE POLICY revenue_recognition_event_update ON revenue_recognition_event FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('revenue.recognize'))
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON enrollment_recognition_config, enrollment_recognition_stage, revenue_recognition_event TO authenticated;

GRANT EXECUTE ON FUNCTION public.normalize_recognition_basis_code(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recognition_lesson_amount(bigint, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enrollment_recognition_entitlement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enrollment_recognized_revenue(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_attendance_eligible_for_recognition(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_enrollment_per_lesson_recognition(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_enrollment_recognition_stages(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recognize_enrollment_revenue(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recognize_teaching_session_revenue(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.void_revenue_recognition_event(uuid, text) TO authenticated;
