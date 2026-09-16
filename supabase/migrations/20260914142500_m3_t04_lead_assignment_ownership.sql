-- M3-T04: Lead assignment ownership, immutable history, and assign_lead() RPC.

-- =============================================================================
-- ASSIGNMENT HISTORY (append-only)
-- =============================================================================

CREATE TABLE lead_assignment (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id            uuid NOT NULL,
  lead_id                    uuid NOT NULL,
  previous_assigned_user_id  uuid,
  new_assigned_user_id       uuid,
  changed_by                 uuid NOT NULL,
  changed_at                 timestamptz NOT NULL DEFAULT now(),
  note                       text,
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, previous_assigned_user_id) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, new_assigned_user_id) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, changed_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_assignment_lead ON lead_assignment (organization_id, lead_id, changed_at DESC);
CREATE INDEX idx_lead_assignment_new_user ON lead_assignment (organization_id, new_assigned_user_id)
  WHERE new_assigned_user_id IS NOT NULL;

COMMENT ON TABLE lead_assignment IS
  'Append-only lead ownership change audit. assign/reassign/unassign via assign_lead() only.';

COMMENT ON COLUMN lead_assignment.previous_assigned_user_id IS
  'Owner before change. NULL for initial assign from unassigned.';

COMMENT ON COLUMN lead_assignment.new_assigned_user_id IS
  'Owner after change. NULL for unassign.';

-- =============================================================================
-- ELIGIBLE ASSIGNEE RULE
-- Active app_user in current organization with effective lead.read permission.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_eligible_lead_assignee(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_user u
    JOIN public.user_role ur
      ON ur.organization_id = u.organization_id
     AND ur.user_id = u.id
    JOIN public.role r
      ON r.organization_id = ur.organization_id
     AND r.id = ur.role_id
    JOIN public.role_permission rp ON rp.role_id = r.id
    JOIN public.permission p ON p.id = rp.permission_id
    WHERE u.id = p_user_id
      AND u.organization_id = public.current_organization_id()
      AND u.status = 'active'
      AND ur.status = 'active'
      AND ur.effective_from <= CURRENT_DATE
      AND (ur.effective_to IS NULL OR ur.effective_to >= CURRENT_DATE)
      AND r.status = 'active'
      AND p.code = 'lead.read'
  );
$$;

COMMENT ON FUNCTION public.is_eligible_lead_assignee(uuid) IS
  'Eligible assignee: active same-org member with effective lead.read. No fixed sales role required.';

-- =============================================================================
-- DIRECT assigned_user_id MUTATION PROTECTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_lead_assigned_user_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_assignment_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.assigned_user_id IS NOT NULL THEN
      RAISE EXCEPTION 'Lead assignment must be set through assign_lead()'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.assigned_user_id IS DISTINCT FROM OLD.assigned_user_id THEN
    RAISE EXCEPTION 'Lead assignment must be changed through assign_lead()'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_protect_assigned_user_id
  BEFORE INSERT OR UPDATE OF assigned_user_id ON lead
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_assigned_user_id();

COMMENT ON FUNCTION public.protect_lead_assigned_user_id() IS
  'Blocks direct client mutation of lead.assigned_user_id. Canonical path: assign_lead(). Service role may set olli.lead_assignment_mutation=true for privileged bootstrap.';

-- =============================================================================
-- RPC: ASSIGN LEAD (assign / reassign / unassign)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.assign_lead(
  p_lead_id uuid,
  p_assigned_user_id uuid DEFAULT NULL,
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
  v_assignment_id uuid;
  v_note text := NULLIF(btrim(p_note), '');
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.assign') THEN
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

  IF p_assigned_user_id IS NOT NULL THEN
    IF NOT public.is_eligible_lead_assignee(p_assigned_user_id) THEN
      RAISE EXCEPTION 'invalid_assignee' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF v_lead.assigned_user_id IS NOT DISTINCT FROM p_assigned_user_id THEN
    RETURN jsonb_build_object(
      'lead_id', p_lead_id,
      'assignment_id', NULL,
      'previous_assigned_user_id', v_lead.assigned_user_id,
      'new_assigned_user_id', p_assigned_user_id,
      'no_op', true
    );
  END IF;

  BEGIN
    PERFORM set_config('olli.lead_assignment_mutation', 'true', true);

    UPDATE lead
    SET
      assigned_user_id = p_assigned_user_id,
      updated_by = v_actor
    WHERE id = p_lead_id AND organization_id = v_org_id;

    PERFORM set_config('olli.lead_assignment_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_assignment_mutation', 'false', true);
    RAISE;
  END;

  INSERT INTO lead_assignment (
    organization_id,
    lead_id,
    previous_assigned_user_id,
    new_assigned_user_id,
    changed_by,
    note
  ) VALUES (
    v_org_id,
    p_lead_id,
    v_lead.assigned_user_id,
    p_assigned_user_id,
    v_actor,
    v_note
  )
  RETURNING id INTO v_assignment_id;

  RETURN jsonb_build_object(
    'lead_id', p_lead_id,
    'assignment_id', v_assignment_id,
    'previous_assigned_user_id', v_lead.assigned_user_id,
    'new_assigned_user_id', p_assigned_user_id,
    'no_op', false
  );
END;
$$;

COMMENT ON FUNCTION public.assign_lead(uuid, uuid, text) IS
  'Atomic assign/reassign/unassign. Requires lead.assign. Actor is server-derived. No-op when owner unchanged.';

-- =============================================================================
-- RPC: LIST ELIGIBLE ASSIGNEES (for assignment UI)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_eligible_lead_assignees()
RETURNS TABLE (user_id uuid, display_name text)
LANGUAGE plpgsql
SECURITY INVOKER
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
  SELECT DISTINCT u.id AS user_id, u.display_name
  FROM public.app_user u
  WHERE u.organization_id = public.current_organization_id()
    AND u.status = 'active'
    AND public.is_eligible_lead_assignee(u.id)
  ORDER BY u.display_name;
END;
$$;

COMMENT ON FUNCTION public.list_eligible_lead_assignees() IS
  'Same-org users eligible for lead ownership (active + lead.read). Used for filters and assignment UI.';

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE lead_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_assignment FORCE ROW LEVEL SECURITY;

CREATE POLICY lead_assignment_select ON lead_assignment FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_assignment_insert ON lead_assignment FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.assign')
    AND changed_by = public.current_app_user_id()
  );

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT ON lead_assignment TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_eligible_lead_assignee(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_lead(uuid, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_eligible_lead_assignees() TO authenticated;
