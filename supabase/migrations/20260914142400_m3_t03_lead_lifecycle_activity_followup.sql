-- M3-T03: Lead lifecycle transitions, activity timeline, follow-ups, status history.

-- =============================================================================
-- LEAD STATUS HISTORY (append-only)
-- =============================================================================

CREATE TABLE lead_status_history (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  lead_id         uuid NOT NULL,
  from_status     text,
  to_status       text NOT NULL,
  lost_reason_id  uuid,
  notes           text,
  changed_by      uuid NOT NULL,
  changed_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT lead_status_history_from_check CHECK (
    from_status IS NULL OR from_status IN (
      'new', 'contacted', 'qualified', 'trial_scheduled', 'trial_completed',
      'converted', 'lost', 'reactivated'
    )
  ),
  CONSTRAINT lead_status_history_to_check CHECK (
    to_status IN (
      'new', 'contacted', 'qualified', 'trial_scheduled', 'trial_completed',
      'converted', 'lost', 'reactivated'
    )
  ),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lost_reason_id) REFERENCES lead_lost_reason (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, changed_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_status_history_lead ON lead_status_history (organization_id, lead_id, changed_at DESC);

COMMENT ON TABLE lead_status_history IS
  'Append-only CRM pipeline transition audit. Canonical source for lifecycle history beyond mutable lead.status.';

-- =============================================================================
-- LEAD ACTIVITY (append-oriented)
-- =============================================================================

CREATE TABLE lead_activity (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    uuid NOT NULL,
  lead_id            uuid NOT NULL,
  activity_type_code text NOT NULL,
  occurred_at        timestamptz NOT NULL DEFAULT now(),
  content            text,
  metadata           jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by         uuid NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT lead_activity_type_check CHECK (
    activity_type_code IN (
      'call', 'message', 'consultation', 'note', 'appointment',
      'status_change', 'follow_up', 'other'
    )
  ),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_activity_lead ON lead_activity (organization_id, lead_id, occurred_at DESC);
CREATE INDEX idx_lead_activity_type ON lead_activity (organization_id, activity_type_code);

COMMENT ON TABLE lead_activity IS
  'Append-oriented CRM activity timeline. Corrections via new rows, not silent edits.';

-- =============================================================================
-- LEAD FOLLOW-UP (lead-scoped next action)
-- =============================================================================

CREATE TABLE lead_follow_up (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL,
  lead_id           uuid NOT NULL,
  due_at            timestamptz NOT NULL,
  note              text,
  assigned_user_id  uuid,
  status            text NOT NULL DEFAULT 'pending',
  completed_at      timestamptz,
  completed_by      uuid,
  cancelled_at      timestamptz,
  cancelled_by      uuid,
  created_by        uuid NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT lead_follow_up_status_check CHECK (
    status IN ('pending', 'completed', 'cancelled')
  ),
  CONSTRAINT lead_follow_up_completed_check CHECK (
    (status = 'completed' AND completed_at IS NOT NULL AND completed_by IS NOT NULL)
    OR status <> 'completed'
  ),
  CONSTRAINT lead_follow_up_cancelled_check CHECK (
    (status = 'cancelled' AND cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL)
    OR status <> 'cancelled'
  ),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, assigned_user_id) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, completed_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, cancelled_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_follow_up_lead ON lead_follow_up (organization_id, lead_id, due_at);
CREATE INDEX idx_lead_follow_up_pending ON lead_follow_up (organization_id, status, due_at)
  WHERE status = 'pending';

CREATE TRIGGER lead_follow_up_updated_at
  BEFORE UPDATE ON lead_follow_up
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_follow_up IS
  'Lightweight lead-scoped next action. Not a generic task manager.';

-- =============================================================================
-- LIFECYCLE DIRECT-UPDATE PROTECTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_lead_lifecycle_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_lifecycle_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     OR NEW.lost_reason_id IS DISTINCT FROM OLD.lost_reason_id
     OR NEW.lost_notes IS DISTINCT FROM OLD.lost_notes
     OR NEW.lost_at IS DISTINCT FROM OLD.lost_at
     OR NEW.lost_by IS DISTINCT FROM OLD.lost_by
     OR NEW.converted_at IS DISTINCT FROM OLD.converted_at
  THEN
    RAISE EXCEPTION 'Lead lifecycle fields must be changed through transition_lead_status()'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_protect_lifecycle_fields
  BEFORE UPDATE ON lead
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_lifecycle_fields();

COMMENT ON FUNCTION public.protect_lead_lifecycle_fields() IS
  'Blocks direct client mutation of lead.status and loss/conversion fields. Canonical path: transition_lead_status().';

-- =============================================================================
-- TRANSITION RULES
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_allowed_lead_status_transition(
  p_from_status text,
  p_to_status text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_from_status = p_to_status THEN false
    WHEN p_to_status = 'converted' THEN false
    WHEN p_from_status = 'converted' THEN false
    WHEN p_from_status = 'new' AND p_to_status IN ('contacted', 'qualified', 'trial_scheduled', 'lost') THEN true
    WHEN p_from_status = 'contacted' AND p_to_status IN ('qualified', 'trial_scheduled', 'lost') THEN true
    WHEN p_from_status = 'qualified' AND p_to_status IN ('trial_scheduled', 'trial_completed', 'lost') THEN true
    WHEN p_from_status = 'trial_scheduled' AND p_to_status IN ('trial_completed', 'lost', 'qualified') THEN true
    WHEN p_from_status = 'trial_completed' AND p_to_status IN ('lost', 'qualified') THEN true
    WHEN p_from_status = 'lost' AND p_to_status IN ('contacted', 'qualified', 'new') THEN true
    WHEN p_from_status = 'reactivated' AND p_to_status IN ('contacted', 'qualified', 'new') THEN true
    ELSE false
  END;
$$;

COMMENT ON FUNCTION public.is_allowed_lead_status_transition(text, text) IS
  'V1 whitelist. Skipping optional stages allowed. converted reserved for M3-T07 convert_lead().';

-- =============================================================================
-- RPC: TRANSITION LEAD STATUS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.transition_lead_status(
  p_lead_id uuid,
  p_to_status text,
  p_lost_reason_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_lead lead%ROWTYPE;
  v_reason lead_lost_reason%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_to_status = 'converted' THEN
    RAISE EXCEPTION 'conversion_reserved' USING ERRCODE = 'P0001';
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

  IF NOT public.is_allowed_lead_status_transition(v_lead.status, p_to_status) THEN
    RAISE EXCEPTION 'invalid_transition' USING ERRCODE = 'P0001';
  END IF;

  IF p_to_status = 'lost' THEN
    IF p_lost_reason_id IS NULL THEN
      RAISE EXCEPTION 'lost_reason_required' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_reason
    FROM lead_lost_reason
    WHERE id = p_lost_reason_id AND organization_id = v_org_id AND status = 'active';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'invalid_lost_reason' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  BEGIN
    PERFORM set_config('olli.lead_lifecycle_mutation', 'true', true);

    UPDATE lead
    SET
      status = p_to_status,
      lost_reason_id = CASE WHEN p_to_status = 'lost' THEN p_lost_reason_id ELSE lost_reason_id END,
      lost_notes = CASE WHEN p_to_status = 'lost' THEN NULLIF(btrim(p_notes), '') ELSE lost_notes END,
      lost_at = CASE WHEN p_to_status = 'lost' THEN now() ELSE lost_at END,
      lost_by = CASE WHEN p_to_status = 'lost' THEN v_actor ELSE lost_by END,
      updated_by = v_actor
    WHERE id = p_lead_id AND organization_id = v_org_id;

    PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);
    RAISE;
  END;

  INSERT INTO lead_status_history (
    organization_id, lead_id, from_status, to_status,
    lost_reason_id, notes, changed_by
  ) VALUES (
    v_org_id,
    p_lead_id,
    v_lead.status,
    p_to_status,
    CASE WHEN p_to_status = 'lost' THEN p_lost_reason_id ELSE NULL END,
    NULLIF(btrim(p_notes), ''),
    v_actor
  );

  INSERT INTO lead_activity (
    organization_id, lead_id, activity_type_code, occurred_at,
    content, metadata, created_by
  ) VALUES (
    v_org_id,
    p_lead_id,
    'status_change',
    now(),
    NULLIF(btrim(p_notes), ''),
    jsonb_build_object(
      'from_status', v_lead.status,
      'to_status', p_to_status,
      'lost_reason_id', CASE WHEN p_to_status = 'lost' THEN p_lost_reason_id ELSE NULL END
    ),
    v_actor
  );

  RETURN p_lead_id;
END;
$$;

-- =============================================================================
-- RPC: ADD LEAD ACTIVITY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.add_lead_activity(
  p_lead_id uuid,
  p_activity_type_code text,
  p_occurred_at timestamptz DEFAULT now(),
  p_content text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_activity_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF NOT EXISTS (
    SELECT 1 FROM lead WHERE id = p_lead_id AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_activity_type_code NOT IN (
    'call', 'message', 'consultation', 'note', 'appointment', 'follow_up', 'other'
  ) THEN
    RAISE EXCEPTION 'invalid_activity_type' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO lead_activity (
    organization_id, lead_id, activity_type_code, occurred_at,
    content, metadata, created_by
  ) VALUES (
    v_org_id,
    p_lead_id,
    p_activity_type_code,
    COALESCE(p_occurred_at, now()),
    NULLIF(btrim(p_content), ''),
    COALESCE(p_metadata, '{}'::jsonb),
    v_actor
  )
  RETURNING id INTO v_activity_id;

  RETURN v_activity_id;
END;
$$;

-- =============================================================================
-- RPC: CREATE LEAD FOLLOW-UP
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_lead_follow_up(
  p_lead_id uuid,
  p_due_at timestamptz,
  p_note text DEFAULT NULL,
  p_assigned_user_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_follow_up_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF NOT EXISTS (
    SELECT 1 FROM lead WHERE id = p_lead_id AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_due_at IS NULL THEN
    RAISE EXCEPTION 'due_at_required' USING ERRCODE = 'P0001';
  END IF;

  IF p_assigned_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM app_user
    WHERE id = p_assigned_user_id AND organization_id = v_org_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'invalid_assigned_user' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO lead_follow_up (
    organization_id, lead_id, due_at, note,
    assigned_user_id, status, created_by
  ) VALUES (
    v_org_id,
    p_lead_id,
    p_due_at,
    NULLIF(btrim(p_note), ''),
    p_assigned_user_id,
    'pending',
    v_actor
  )
  RETURNING id INTO v_follow_up_id;

  RETURN v_follow_up_id;
END;
$$;

-- =============================================================================
-- RPC: COMPLETE LEAD FOLLOW-UP
-- =============================================================================

CREATE OR REPLACE FUNCTION public.complete_lead_follow_up(
  p_follow_up_id uuid,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_row lead_follow_up%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_row
  FROM lead_follow_up
  WHERE id = p_follow_up_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'follow_up_not_pending' USING ERRCODE = 'P0001';
  END IF;

  UPDATE lead_follow_up
  SET
    status = 'completed',
    completed_at = now(),
    completed_by = v_actor,
    note = COALESCE(NULLIF(btrim(p_note), ''), note)
  WHERE id = p_follow_up_id AND organization_id = v_org_id;

  INSERT INTO lead_activity (
    organization_id, lead_id, activity_type_code, occurred_at,
    content, metadata, created_by
  ) VALUES (
    v_org_id,
    v_row.lead_id,
    'follow_up',
    now(),
    COALESCE(NULLIF(btrim(p_note), ''), v_row.note),
    jsonb_build_object('follow_up_id', p_follow_up_id, 'action', 'completed'),
    v_actor
  );

  RETURN p_follow_up_id;
END;
$$;

-- =============================================================================
-- RPC: CANCEL LEAD FOLLOW-UP
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cancel_lead_follow_up(
  p_follow_up_id uuid,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_row lead_follow_up%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_row
  FROM lead_follow_up
  WHERE id = p_follow_up_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'follow_up_not_pending' USING ERRCODE = 'P0001';
  END IF;

  UPDATE lead_follow_up
  SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = v_actor,
    note = COALESCE(NULLIF(btrim(p_note), ''), note)
  WHERE id = p_follow_up_id AND organization_id = v_org_id;

  RETURN p_follow_up_id;
END;
$$;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE lead_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_status_history FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_activity FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_follow_up ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_follow_up FORCE ROW LEVEL SECURITY;

CREATE POLICY lead_status_history_select ON lead_status_history FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_status_history_insert ON lead_status_history FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND changed_by = public.current_app_user_id()
  );

CREATE POLICY lead_activity_select ON lead_activity FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_activity_insert ON lead_activity FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND created_by = public.current_app_user_id()
  );

CREATE POLICY lead_follow_up_select ON lead_follow_up FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_follow_up_insert ON lead_follow_up FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND created_by = public.current_app_user_id()
  );

CREATE POLICY lead_follow_up_update ON lead_follow_up FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.update'))
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT ON lead_status_history, lead_activity TO authenticated;
GRANT SELECT, INSERT, UPDATE ON lead_follow_up TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_allowed_lead_status_transition(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_lead_status(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_lead_activity(uuid, text, timestamptz, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_lead_follow_up(uuid, timestamptz, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_lead_follow_up(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_lead_follow_up(uuid, text) TO authenticated;
