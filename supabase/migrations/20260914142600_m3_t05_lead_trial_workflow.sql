-- M3-T05: CRM pre-enrollment trial workflow (candidate-scoped, no Enrollment/Attendance).

-- =============================================================================
-- TRIAL ENTITY
-- =============================================================================

CREATE TABLE lead_trial (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL,
  lead_id              uuid NOT NULL,
  lead_candidate_id    uuid NOT NULL,
  class_id             uuid NOT NULL,
  teaching_session_id  uuid,
  status               text NOT NULL DEFAULT 'scheduled',
  scheduled_start_at   timestamptz NOT NULL,
  scheduled_end_at     timestamptz NOT NULL,
  operational_note     text,
  outcome_note         text,
  completed_at         timestamptz,
  completed_by         uuid,
  cancelled_at         timestamptz,
  cancelled_by         uuid,
  no_show_at           timestamptz,
  no_show_by           uuid,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  created_by           uuid NOT NULL,
  updated_by           uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT lead_trial_status_check CHECK (
    status IN ('scheduled', 'completed', 'cancelled', 'no_show')
  ),
  CONSTRAINT lead_trial_schedule_check CHECK (scheduled_end_at > scheduled_start_at),
  CONSTRAINT lead_trial_completed_check CHECK (
    (status = 'completed' AND completed_at IS NOT NULL AND completed_by IS NOT NULL)
    OR (status <> 'completed' AND completed_at IS NULL AND completed_by IS NULL)
  ),
  CONSTRAINT lead_trial_cancelled_check CHECK (
    (status = 'cancelled' AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL)
    OR (status <> 'cancelled' AND cancelled_at IS NULL AND cancelled_by IS NULL)
  ),
  CONSTRAINT lead_trial_no_show_check CHECK (
    (status = 'no_show' AND no_show_at IS NOT NULL AND no_show_by IS NOT NULL)
    OR (status <> 'no_show' AND no_show_at IS NULL AND no_show_by IS NULL)
  ),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_candidate_id) REFERENCES lead_candidate (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teaching_session_id) REFERENCES teaching_session (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, completed_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, cancelled_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, no_show_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_trial_lead ON lead_trial (organization_id, lead_id, created_at DESC);
CREATE INDEX idx_lead_trial_candidate ON lead_trial (organization_id, lead_candidate_id, created_at DESC);
CREATE INDEX idx_lead_trial_class ON lead_trial (organization_id, class_id);
CREATE INDEX idx_lead_trial_scheduled ON lead_trial (organization_id, status, scheduled_start_at)
  WHERE status = 'scheduled';

CREATE TRIGGER lead_trial_updated_at
  BEFORE UPDATE ON lead_trial
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_trial IS
  'CRM-owned pre-enrollment trial for a specific lead candidate. Does not create Enrollment or Attendance.';

COMMENT ON COLUMN lead_trial.teaching_session_id IS
  'Optional link to an existing teaching session. Snapshot schedule is stored on the trial row.';

-- =============================================================================
-- TRIAL EVENT HISTORY (append-only)
-- =============================================================================

CREATE TABLE lead_trial_event (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id              uuid NOT NULL,
  lead_trial_id                uuid NOT NULL,
  event_type                   text NOT NULL,
  occurred_at                  timestamptz NOT NULL DEFAULT now(),
  changed_by                   uuid NOT NULL,
  previous_scheduled_start_at    timestamptz,
  new_scheduled_start_at         timestamptz,
  previous_scheduled_end_at      timestamptz,
  new_scheduled_end_at           timestamptz,
  previous_class_id              uuid,
  new_class_id                   uuid,
  previous_teaching_session_id   uuid,
  new_teaching_session_id        uuid,
  note                         text,
  outcome_snapshot             jsonb,
  UNIQUE (organization_id, id),
  CONSTRAINT lead_trial_event_type_check CHECK (
    event_type IN ('scheduled', 'rescheduled', 'completed', 'cancelled', 'no_show')
  ),
  FOREIGN KEY (organization_id, lead_trial_id) REFERENCES lead_trial (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, changed_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, previous_class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, new_class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, previous_teaching_session_id) REFERENCES teaching_session (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, new_teaching_session_id) REFERENCES teaching_session (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_trial_event_trial ON lead_trial_event (organization_id, lead_trial_id, occurred_at DESC);

COMMENT ON TABLE lead_trial_event IS
  'Append-only trial audit history. Reschedule and outcome changes never destroy prior facts.';

-- =============================================================================
-- CLASS ELIGIBILITY
-- V1: planned, trial, and active classes may receive trials; closed classes may not.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_eligible_trial_class(p_class_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.class c
    WHERE c.id = p_class_id
      AND c.organization_id = public.current_organization_id()
      AND c.status IN ('planned', 'trial', 'active')
  );
$$;

COMMENT ON FUNCTION public.is_eligible_trial_class(uuid) IS
  'V1 trial class rule: same-org class with status planned, trial, or active. Closed classes rejected.';

-- =============================================================================
-- DIRECT MUTATION PROTECTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_lead_trial_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_trial_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    RAISE EXCEPTION 'Lead trial must be created through schedule_lead_trial()'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     OR NEW.scheduled_start_at IS DISTINCT FROM OLD.scheduled_start_at
     OR NEW.scheduled_end_at IS DISTINCT FROM OLD.scheduled_end_at
     OR NEW.class_id IS DISTINCT FROM OLD.class_id
     OR NEW.teaching_session_id IS DISTINCT FROM OLD.teaching_session_id
     OR NEW.outcome_note IS DISTINCT FROM OLD.outcome_note
     OR NEW.completed_at IS DISTINCT FROM OLD.completed_at
     OR NEW.completed_by IS DISTINCT FROM OLD.completed_by
     OR NEW.cancelled_at IS DISTINCT FROM OLD.cancelled_at
     OR NEW.cancelled_by IS DISTINCT FROM OLD.cancelled_by
     OR NEW.no_show_at IS DISTINCT FROM OLD.no_show_at
     OR NEW.no_show_by IS DISTINCT FROM OLD.no_show_by
     OR NEW.operational_note IS DISTINCT FROM OLD.operational_note
  THEN
    RAISE EXCEPTION 'Lead trial fields must be changed through trial RPCs'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_trial_protect_fields
  BEFORE INSERT OR UPDATE ON lead_trial
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_trial_fields();

CREATE OR REPLACE FUNCTION public.protect_lead_trial_event_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_trial_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Lead trial event history is immutable'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER lead_trial_event_protect_immutable
  BEFORE UPDATE OR DELETE ON lead_trial_event
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_trial_event_immutable();

COMMENT ON FUNCTION public.protect_lead_trial_fields() IS
  'Blocks direct client mutation of lead_trial scheduling/state fields. Canonical paths: schedule/reschedule/complete/cancel/no-show RPCs. Service role may set olli.lead_trial_mutation=true for privileged bootstrap.';

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.try_advance_lead_lifecycle_for_trial(
  p_lead_id uuid,
  p_from_status text,
  p_to_status text,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_actor uuid := public.current_app_user_id();
  v_note text := NULLIF(btrim(p_notes), '');
BEGIN
  IF NOT public.is_allowed_lead_status_transition(p_from_status, p_to_status) THEN
    RETURN;
  END IF;

  BEGIN
    PERFORM set_config('olli.lead_lifecycle_mutation', 'true', true);

    UPDATE lead
    SET
      status = p_to_status,
      updated_by = v_actor
    WHERE id = p_lead_id AND organization_id = v_org_id;

    PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);
    RAISE;
  END;

  INSERT INTO lead_status_history (
    organization_id, lead_id, from_status, to_status, notes, changed_by
  ) VALUES (
    v_org_id,
    p_lead_id,
    p_from_status,
    p_to_status,
    v_note,
    v_actor
  );

  INSERT INTO lead_activity (
    organization_id, lead_id, activity_type_code, occurred_at, content, metadata, created_by
  ) VALUES (
    v_org_id,
    p_lead_id,
    'status_change',
    now(),
    v_note,
    jsonb_build_object('from_status', p_from_status, 'to_status', p_to_status),
    v_actor
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_lead_trial_schedule(
  p_class_id uuid,
  p_teaching_session_id uuid,
  p_scheduled_start_at timestamptz,
  p_scheduled_end_at timestamptz
)
RETURNS TABLE (o_start timestamptz, o_end timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_session teaching_session%ROWTYPE;
BEGIN
  IF p_teaching_session_id IS NOT NULL THEN
    SELECT * INTO v_session
    FROM teaching_session
    WHERE id = p_teaching_session_id AND organization_id = v_org_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_teaching_session' USING ERRCODE = 'P0002';
    END IF;

    IF v_session.class_id <> p_class_id THEN
      RAISE EXCEPTION 'session_class_mismatch' USING ERRCODE = 'P0001';
    END IF;

    RETURN QUERY SELECT v_session.scheduled_start_at, v_session.scheduled_end_at;
    RETURN;
  END IF;

  IF p_scheduled_start_at IS NULL OR p_scheduled_end_at IS NULL THEN
    RAISE EXCEPTION 'schedule_required' USING ERRCODE = 'P0001';
  END IF;

  IF p_scheduled_end_at <= p_scheduled_start_at THEN
    RAISE EXCEPTION 'invalid_schedule' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY SELECT p_scheduled_start_at, p_scheduled_end_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_lead_trial_academic_refs(
  p_lead_id uuid,
  p_candidate_id uuid,
  p_class_id uuid,
  p_teaching_session_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_candidate lead_candidate%ROWTYPE;
  v_class class%ROWTYPE;
  v_session teaching_session%ROWTYPE;
BEGIN
  SELECT * INTO v_candidate
  FROM lead_candidate
  WHERE id = p_candidate_id AND organization_id = v_org_id;

  IF NOT FOUND OR v_candidate.lead_id <> p_lead_id OR v_candidate.status <> 'active' THEN
    RAISE EXCEPTION 'invalid_candidate' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_class
  FROM class
  WHERE id = p_class_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_class' USING ERRCODE = 'P0002';
  END IF;

  IF v_class.status NOT IN ('planned', 'trial', 'active') THEN
    RAISE EXCEPTION 'class_not_eligible' USING ERRCODE = 'P0001';
  END IF;

  IF p_teaching_session_id IS NOT NULL THEN
    SELECT * INTO v_session
    FROM teaching_session
    WHERE id = p_teaching_session_id AND organization_id = v_org_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_teaching_session' USING ERRCODE = 'P0002';
    END IF;

    IF v_session.class_id <> p_class_id THEN
      RAISE EXCEPTION 'session_class_mismatch' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.append_lead_trial_event(
  p_trial_id uuid,
  p_event_type text,
  p_note text DEFAULT NULL,
  p_previous_start timestamptz DEFAULT NULL,
  p_new_start timestamptz DEFAULT NULL,
  p_previous_end timestamptz DEFAULT NULL,
  p_new_end timestamptz DEFAULT NULL,
  p_previous_class uuid DEFAULT NULL,
  p_new_class uuid DEFAULT NULL,
  p_previous_session uuid DEFAULT NULL,
  p_new_session uuid DEFAULT NULL,
  p_outcome_snapshot jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_actor uuid := public.current_app_user_id();
  v_event_id uuid;
BEGIN
  INSERT INTO lead_trial_event (
    organization_id,
    lead_trial_id,
    event_type,
    changed_by,
    previous_scheduled_start_at,
    new_scheduled_start_at,
    previous_scheduled_end_at,
    new_scheduled_end_at,
    previous_class_id,
    new_class_id,
    previous_teaching_session_id,
    new_teaching_session_id,
    note,
    outcome_snapshot
  ) VALUES (
    v_org_id,
    p_trial_id,
    p_event_type,
    v_actor,
    p_previous_start,
    p_new_start,
    p_previous_end,
    p_new_end,
    p_previous_class,
    p_new_class,
    p_previous_session,
    p_new_session,
    NULLIF(btrim(p_note), ''),
    p_outcome_snapshot
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

-- =============================================================================
-- RPC: SCHEDULE LEAD TRIAL
-- TeachingSession precedence: when supplied, session times are authoritative snapshot.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.schedule_lead_trial(
  p_lead_id uuid,
  p_lead_candidate_id uuid,
  p_class_id uuid,
  p_teaching_session_id uuid DEFAULT NULL,
  p_scheduled_start_at timestamptz DEFAULT NULL,
  p_scheduled_end_at timestamptz DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_lead lead%ROWTYPE;
  v_trial_id uuid;
  v_event_id uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_note text := NULLIF(btrim(p_note), '');
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_lead
  FROM lead
  WHERE id = p_lead_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_lead.status = 'converted' THEN
    RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
  END IF;

  IF v_lead.status = 'lost' THEN
    RAISE EXCEPTION 'lead_lost' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.validate_lead_trial_academic_refs(
    p_lead_id, p_lead_candidate_id, p_class_id, p_teaching_session_id
  );

  SELECT r.o_start, r.o_end INTO v_start, v_end
  FROM public.resolve_lead_trial_schedule(
    p_class_id, p_teaching_session_id, p_scheduled_start_at, p_scheduled_end_at
  ) AS r;

  BEGIN
    PERFORM set_config('olli.lead_trial_mutation', 'true', true);

    INSERT INTO lead_trial (
      organization_id,
      lead_id,
      lead_candidate_id,
      class_id,
      teaching_session_id,
      status,
      scheduled_start_at,
      scheduled_end_at,
      operational_note,
      created_by,
      updated_by
    ) VALUES (
      v_org_id,
      p_lead_id,
      p_lead_candidate_id,
      p_class_id,
      p_teaching_session_id,
      'scheduled',
      v_start,
      v_end,
      v_note,
      v_actor,
      v_actor
    )
    RETURNING id INTO v_trial_id;

    v_event_id := public.append_lead_trial_event(
      v_trial_id,
      'scheduled',
      v_note,
      NULL,
      v_start,
      NULL,
      v_end,
      NULL,
      p_class_id,
      NULL,
      p_teaching_session_id
    );

    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
    RAISE;
  END;

  IF v_lead.status IN ('new', 'contacted', 'qualified') THEN
    PERFORM public.try_advance_lead_lifecycle_for_trial(
      p_lead_id, v_lead.status, 'trial_scheduled', v_note
    );
  END IF;

  RETURN jsonb_build_object(
    'trial_id', v_trial_id,
    'event_id', v_event_id,
    'lead_id', p_lead_id,
    'status', 'scheduled',
    'scheduled_start_at', v_start,
    'scheduled_end_at', v_end
  );
END;
$$;

-- =============================================================================
-- RPC: RESCHEDULE LEAD TRIAL
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reschedule_lead_trial(
  p_trial_id uuid,
  p_class_id uuid DEFAULT NULL,
  p_teaching_session_id uuid DEFAULT NULL,
  p_scheduled_start_at timestamptz DEFAULT NULL,
  p_scheduled_end_at timestamptz DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_trial lead_trial%ROWTYPE;
  v_lead lead%ROWTYPE;
  v_new_class_id uuid;
  v_new_session_id uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_event_id uuid;
  v_note text := NULLIF(btrim(p_note), '');
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_trial
  FROM lead_trial
  WHERE id = p_trial_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_trial.status <> 'scheduled' THEN
    RAISE EXCEPTION 'trial_not_scheduled' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_lead
  FROM lead
  WHERE id = v_trial.lead_id AND organization_id = v_org_id;

  IF v_lead.status = 'converted' THEN
    RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
  END IF;

  IF v_lead.status = 'lost' THEN
    RAISE EXCEPTION 'lead_lost' USING ERRCODE = 'P0001';
  END IF;

  v_new_class_id := COALESCE(p_class_id, v_trial.class_id);
  v_new_session_id := CASE
    WHEN p_teaching_session_id IS NOT NULL THEN p_teaching_session_id
    WHEN p_class_id IS NOT NULL AND p_class_id <> v_trial.class_id THEN NULL
    ELSE v_trial.teaching_session_id
  END;

  PERFORM public.validate_lead_trial_academic_refs(
    v_trial.lead_id, v_trial.lead_candidate_id, v_new_class_id, v_new_session_id
  );

  SELECT r.o_start, r.o_end INTO v_start, v_end
  FROM public.resolve_lead_trial_schedule(
    v_new_class_id,
    v_new_session_id,
    COALESCE(p_scheduled_start_at, v_trial.scheduled_start_at),
    COALESCE(p_scheduled_end_at, v_trial.scheduled_end_at)
  ) AS r;

  BEGIN
    PERFORM set_config('olli.lead_trial_mutation', 'true', true);

    v_event_id := public.append_lead_trial_event(
      p_trial_id,
      'rescheduled',
      v_note,
      v_trial.scheduled_start_at,
      v_start,
      v_trial.scheduled_end_at,
      v_end,
      v_trial.class_id,
      v_new_class_id,
      v_trial.teaching_session_id,
      v_new_session_id
    );

    UPDATE lead_trial
    SET
      class_id = v_new_class_id,
      teaching_session_id = v_new_session_id,
      scheduled_start_at = v_start,
      scheduled_end_at = v_end,
      updated_by = v_actor
    WHERE id = p_trial_id AND organization_id = v_org_id;

    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
    RAISE;
  END;

  RETURN jsonb_build_object(
    'trial_id', p_trial_id,
    'event_id', v_event_id,
    'status', 'scheduled',
    'scheduled_start_at', v_start,
    'scheduled_end_at', v_end
  );
END;
$$;

-- =============================================================================
-- RPC: COMPLETE LEAD TRIAL
-- =============================================================================

CREATE OR REPLACE FUNCTION public.complete_lead_trial(
  p_trial_id uuid,
  p_outcome_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_trial lead_trial%ROWTYPE;
  v_lead lead%ROWTYPE;
  v_event_id uuid;
  v_note text := NULLIF(btrim(p_outcome_note), '');
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_trial
  FROM lead_trial
  WHERE id = p_trial_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_trial.status <> 'scheduled' THEN
    RAISE EXCEPTION 'trial_not_scheduled' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_lead
  FROM lead
  WHERE id = v_trial.lead_id AND organization_id = v_org_id
  FOR UPDATE;

  BEGIN
    PERFORM set_config('olli.lead_trial_mutation', 'true', true);

    v_event_id := public.append_lead_trial_event(
      p_trial_id,
      'completed',
      v_note,
      v_trial.scheduled_start_at,
      v_trial.scheduled_start_at,
      v_trial.scheduled_end_at,
      v_trial.scheduled_end_at,
      v_trial.class_id,
      v_trial.class_id,
      v_trial.teaching_session_id,
      v_trial.teaching_session_id,
      jsonb_build_object('outcome_note', v_note, 'status', 'completed')
    );

    UPDATE lead_trial
    SET
      status = 'completed',
      outcome_note = v_note,
      completed_at = now(),
      completed_by = v_actor,
      updated_by = v_actor
    WHERE id = p_trial_id AND organization_id = v_org_id;

    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
    RAISE;
  END;

  PERFORM public.try_advance_lead_lifecycle_for_trial(
    v_lead.id, v_lead.status, 'trial_completed', v_note
  );

  RETURN jsonb_build_object(
    'trial_id', p_trial_id,
    'event_id', v_event_id,
    'status', 'completed'
  );
END;
$$;

-- =============================================================================
-- RPC: CANCEL LEAD TRIAL
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cancel_lead_trial(
  p_trial_id uuid,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_trial lead_trial%ROWTYPE;
  v_event_id uuid;
  v_note text := NULLIF(btrim(p_note), '');
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_trial
  FROM lead_trial
  WHERE id = p_trial_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_trial.status <> 'scheduled' THEN
    RAISE EXCEPTION 'trial_not_scheduled' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    PERFORM set_config('olli.lead_trial_mutation', 'true', true);

    v_event_id := public.append_lead_trial_event(
      p_trial_id,
      'cancelled',
      v_note,
      v_trial.scheduled_start_at,
      v_trial.scheduled_start_at,
      v_trial.scheduled_end_at,
      v_trial.scheduled_end_at,
      v_trial.class_id,
      v_trial.class_id,
      v_trial.teaching_session_id,
      v_trial.teaching_session_id,
      jsonb_build_object('status', 'cancelled')
    );

    UPDATE lead_trial
    SET
      status = 'cancelled',
      cancelled_at = now(),
      cancelled_by = v_actor,
      updated_by = v_actor
    WHERE id = p_trial_id AND organization_id = v_org_id;

    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
    RAISE;
  END;

  RETURN jsonb_build_object(
    'trial_id', p_trial_id,
    'event_id', v_event_id,
    'status', 'cancelled'
  );
END;
$$;

-- =============================================================================
-- RPC: MARK LEAD TRIAL NO-SHOW
-- =============================================================================

CREATE OR REPLACE FUNCTION public.mark_lead_trial_no_show(
  p_trial_id uuid,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_trial lead_trial%ROWTYPE;
  v_event_id uuid;
  v_note text := NULLIF(btrim(p_note), '');
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_trial
  FROM lead_trial
  WHERE id = p_trial_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_trial.status <> 'scheduled' THEN
    RAISE EXCEPTION 'trial_not_scheduled' USING ERRCODE = 'P0001';
  END IF;

  BEGIN
    PERFORM set_config('olli.lead_trial_mutation', 'true', true);

    v_event_id := public.append_lead_trial_event(
      p_trial_id,
      'no_show',
      v_note,
      v_trial.scheduled_start_at,
      v_trial.scheduled_start_at,
      v_trial.scheduled_end_at,
      v_trial.scheduled_end_at,
      v_trial.class_id,
      v_trial.class_id,
      v_trial.teaching_session_id,
      v_trial.teaching_session_id,
      jsonb_build_object('status', 'no_show')
    );

    UPDATE lead_trial
    SET
      status = 'no_show',
      no_show_at = now(),
      no_show_by = v_actor,
      updated_by = v_actor
    WHERE id = p_trial_id AND organization_id = v_org_id;

    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_trial_mutation', 'false', true);
    RAISE;
  END;

  RETURN jsonb_build_object(
    'trial_id', p_trial_id,
    'event_id', v_event_id,
    'status', 'no_show'
  );
END;
$$;

-- =============================================================================
-- READ HELPERS FOR UI (SECURITY DEFINER bypasses enrollment.read on class/session)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_eligible_trial_classes()
RETURNS TABLE (class_id uuid, class_name text, class_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT c.id, c.name, c.status
  FROM public.class c
  WHERE c.organization_id = public.current_organization_id()
    AND c.status IN ('planned', 'trial', 'active')
  ORDER BY c.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_trial_teaching_sessions(p_class_id uuid)
RETURNS TABLE (
  session_id uuid,
  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_eligible_trial_class(p_class_id) THEN
    RAISE EXCEPTION 'class_not_eligible' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  SELECT ts.id, ts.scheduled_start_at, ts.scheduled_end_at, ts.status
  FROM public.teaching_session ts
  WHERE ts.organization_id = public.current_organization_id()
    AND ts.class_id = p_class_id
    AND ts.status IN ('scheduled', 'in_progress')
  ORDER BY ts.scheduled_start_at;
END;
$$;

COMMENT ON FUNCTION public.schedule_lead_trial(uuid, uuid, uuid, uuid, timestamptz, timestamptz, text) IS
  'Schedule a candidate-scoped CRM trial. No Enrollment or Attendance. Advances lifecycle to trial_scheduled when allowed. Session times take precedence when teaching_session_id is supplied.';

COMMENT ON FUNCTION public.resolve_lead_trial_schedule(uuid, uuid, timestamptz, timestamptz) IS
  'Precedence: teaching session supplies schedule snapshot; otherwise explicit start/end required.';

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE lead_trial ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_trial FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_trial_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_trial_event FORCE ROW LEVEL SECURITY;

CREATE POLICY lead_trial_select ON lead_trial FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_trial_event_select ON lead_trial_event FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_trial_insert ON lead_trial FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND created_by = public.current_app_user_id()
  );

CREATE POLICY lead_trial_update ON lead_trial FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
  )
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY lead_trial_event_insert ON lead_trial_event FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND changed_by = public.current_app_user_id()
  );

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON lead_trial TO authenticated;
GRANT SELECT, INSERT ON lead_trial_event TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_eligible_trial_class(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_lead_trial(uuid, uuid, uuid, uuid, timestamptz, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_lead_trial(uuid, uuid, uuid, timestamptz, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_lead_trial(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_lead_trial(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_lead_trial_no_show(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_eligible_trial_classes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_trial_teaching_sessions(uuid) TO authenticated;
