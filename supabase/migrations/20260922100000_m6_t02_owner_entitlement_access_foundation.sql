-- M6-T02: Owner invariant, organization entitlement, canonical roles, permission hardening.

-- =============================================================================
-- PERMISSION CATALOG ADDITIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('center_account.manage'),
  ('identity.read')
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE permission IS
  'Global permission catalog. Owner-only codes (center_account.manage, report.executive.*) are enforced via is_primary_owner() in has_permission(), not only via role_permission.';

-- =============================================================================
-- ORGANIZATION ENTITLEMENT
-- =============================================================================

CREATE TABLE organization_entitlement (
  organization_id       uuid PRIMARY KEY REFERENCES organization (id) ON DELETE RESTRICT,
  staff_limit           integer NOT NULL DEFAULT 5,
  primary_owner_limit   integer NOT NULL DEFAULT 1,
  primary_app_user_id   uuid,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organization_entitlement_staff_limit_check CHECK (staff_limit >= 0),
  CONSTRAINT organization_entitlement_primary_owner_limit_check CHECK (primary_owner_limit = 1),
  CONSTRAINT organization_entitlement_primary_user_fk
    FOREIGN KEY (organization_id, primary_app_user_id)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_organization_entitlement_primary_user
  ON organization_entitlement (primary_app_user_id)
  WHERE primary_app_user_id IS NOT NULL;

CREATE TRIGGER organization_entitlement_updated_at
  BEFORE UPDATE ON organization_entitlement
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE organization_entitlement IS
  'Runtime product authority for staff seats and primary Owner identity. Not a billing/subscription table.';

-- =============================================================================
-- APP USER MEMBERSHIP (SEAT VS ACCESS)
-- =============================================================================

ALTER TABLE app_user
  ADD COLUMN membership_status text NOT NULL DEFAULT 'member';

ALTER TABLE app_user
  ADD CONSTRAINT app_user_membership_status_check
  CHECK (membership_status IN ('member', 'removed'));

COMMENT ON COLUMN app_user.membership_status IS
  'Organization membership lifecycle. member = belongs to org (occupies staff seat unless primary Owner). removed = seat released; app_user row preserved for history. Access is app_user.status.';

UPDATE app_user SET membership_status = 'member' WHERE membership_status IS NULL;

-- =============================================================================
-- CANONICAL ROLE TEMPLATE METADATA
-- =============================================================================

ALTER TABLE role
  ADD COLUMN is_canonical_template boolean NOT NULL DEFAULT false;

ALTER TABLE role
  ADD COLUMN canonical_code text;

ALTER TABLE role
  ADD CONSTRAINT role_canonical_code_required
  CHECK (NOT is_canonical_template OR canonical_code IS NOT NULL);

CREATE UNIQUE INDEX role_canonical_code_unique
  ON role (organization_id, canonical_code)
  WHERE is_canonical_template AND canonical_code IS NOT NULL;

COMMENT ON COLUMN role.is_canonical_template IS
  'System-managed product role template. Center users cannot mutate template permissions.';

-- =============================================================================
-- OWNER-ONLY PERMISSION CODES (identity-derived in has_permission)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_owner_only_permission(p_code text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT p_code IN (
    'report.executive.read',
    'report.executive.follow_up.manage',
    'center_account.manage'
  );
$$;

-- =============================================================================
-- PRIMARY OWNER IDENTITY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_primary_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_entitlement oe
    JOIN public.organization o
      ON o.id = oe.organization_id
    JOIN public.app_user u
      ON u.organization_id = oe.organization_id
     AND u.id = oe.primary_app_user_id
    WHERE oe.organization_id = public.current_organization_id()
      AND oe.primary_app_user_id IS NOT NULL
      AND oe.primary_app_user_id = public.current_app_user_id()
      AND o.status = 'active'
      AND u.status = 'active'
      AND u.membership_status = 'member'
      AND public.is_active_app_user()
  );
$$;

COMMENT ON FUNCTION public.is_primary_owner() IS
  'Subscribed primary Owner with active org, active membership, and active access. Executive and account administration derive from this identity.';

-- =============================================================================
-- PERMISSION HELPERS (UPDATED)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.has_permission(p_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN public.is_owner_only_permission(p_code) THEN public.is_primary_owner()
    ELSE EXISTS (
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
      WHERE u.auth_user_id = auth.uid()
        AND u.status = 'active'
        AND u.membership_status = 'member'
        AND ur.status = 'active'
        AND ur.effective_from <= CURRENT_DATE
        AND (ur.effective_to IS NULL OR ur.effective_to >= CURRENT_DATE)
        AND r.status = 'active'
        AND p.code = p_code
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_permissions()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT codes.code
  FROM (
    SELECT p.code
    FROM public.app_user u
    JOIN public.user_role ur
      ON ur.organization_id = u.organization_id
     AND ur.user_id = u.id
    JOIN public.role r
      ON r.organization_id = ur.organization_id
     AND r.id = ur.role_id
    JOIN public.role_permission rp ON rp.role_id = r.id
    JOIN public.permission p ON p.id = rp.permission_id
    WHERE u.auth_user_id = auth.uid()
      AND u.status = 'active'
      AND u.membership_status = 'member'
      AND ur.status = 'active'
      AND ur.effective_from <= CURRENT_DATE
      AND (ur.effective_to IS NULL OR ur.effective_to >= CURRENT_DATE)
      AND r.status = 'active'
      AND NOT public.is_owner_only_permission(p.code)
    UNION ALL
    SELECT 'report.executive.read'
    WHERE public.is_primary_owner()
    UNION ALL
    SELECT 'report.executive.follow_up.manage'
    WHERE public.is_primary_owner()
    UNION ALL
    SELECT 'center_account.manage'
    WHERE public.is_primary_owner()
  ) AS codes(code)
  ORDER BY 1;
$$;

-- =============================================================================
-- STAFF SEAT COUNTING
-- =============================================================================

CREATE OR REPLACE FUNCTION public.count_member_staff_seats(p_organization_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::integer
  FROM public.app_user u
  JOIN public.organization_entitlement oe
    ON oe.organization_id = u.organization_id
  WHERE u.organization_id = p_organization_id
    AND u.membership_status = 'member'
    AND u.id IS DISTINCT FROM oe.primary_app_user_id;
$$;

-- =============================================================================
-- INTERNAL: CANONICAL TEMPLATE PERMISSIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._m6_apply_canonical_role_permissions(
  p_organization_id uuid,
  p_canonical_code text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
BEGIN
  SELECT id INTO v_role_id
  FROM public.role
  WHERE organization_id = p_organization_id
    AND is_canonical_template
    AND canonical_code = p_canonical_code;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'canonical_role_missing';
  END IF;

  IF p_canonical_code = 'center_manager' THEN
    INSERT INTO public.role_permission (role_id, permission_id)
    SELECT v_role_id, p.id
    FROM public.permission p
    WHERE p.code NOT IN (
      'report.executive.read',
      'report.executive.follow_up.manage',
      'center_account.manage',
      'role.manage',
      'user.manage'
    )
    ON CONFLICT DO NOTHING;
    RETURN;
  END IF;

  IF p_canonical_code = 'accountant' THEN
    INSERT INTO public.role_permission (role_id, permission_id)
    SELECT v_role_id, p.id
    FROM public.permission p
    WHERE p.code IN (
      'charge.read', 'charge.create',
      'payment.read', 'payment.record', 'payment.reverse',
      'expense.read', 'expense.create',
      'asset.read', 'asset.create', 'asset.update',
      'revenue.read', 'revenue.recognize',
      'personnel_cost.read', 'personnel_cost.manage',
      'class_economics.read',
      'consultant_revenue.review',
      'organization.read', 'identity.read'
    )
    ON CONFLICT DO NOTHING;
    RETURN;
  END IF;

  IF p_canonical_code = 'consultant' THEN
    INSERT INTO public.role_permission (role_id, permission_id)
    SELECT v_role_id, p.id
    FROM public.permission p
    WHERE p.code IN (
      'lead.read', 'lead.create', 'lead.update', 'lead.assign', 'lead.convert',
      'consultant_revenue.declare',
      'organization.read', 'identity.read'
    )
    ON CONFLICT DO NOTHING;
    RETURN;
  END IF;

  IF p_canonical_code = 'academic_operations' THEN
    INSERT INTO public.role_permission (role_id, permission_id)
    SELECT v_role_id, p.id
    FROM public.permission p
    WHERE p.code IN (
      'student.read', 'student.create', 'student.update',
      'guardian.read', 'guardian.create', 'guardian.update',
      'teacher.read', 'teacher.create',
      'enrollment.read', 'enrollment.create', 'enrollment.update',
      'attendance.read', 'attendance.review',
      'assessment.read', 'assessment.create',
      'assessment_result.review',
      'observation.read', 'observation.review',
      'organization.read', 'identity.read'
    )
    ON CONFLICT DO NOTHING;
    RETURN;
  END IF;

  IF p_canonical_code = 'teacher' THEN
    INSERT INTO public.role_permission (role_id, permission_id)
    SELECT v_role_id, p.id
    FROM public.permission p
    WHERE p.code IN (
      'attendance.record', 'attendance.read',
      'assessment.read', 'assessment_result.record',
      'observation.record', 'observation.read',
      'enrollment.read',
      'organization.read', 'identity.read'
    )
    ON CONFLICT DO NOTHING;
    RETURN;
  END IF;

  RAISE EXCEPTION 'unknown_canonical_code';
END;
$$;

CREATE OR REPLACE FUNCTION public.initialize_organization_access_foundation(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_role_id uuid;
  v_codes text[] := ARRAY[
    'center_manager', 'accountant', 'consultant', 'academic_operations', 'teacher'
  ];
BEGIN
  INSERT INTO public.organization_entitlement (organization_id)
  VALUES (p_organization_id)
  ON CONFLICT (organization_id) DO NOTHING;

  FOREACH v_code IN ARRAY v_codes LOOP
    SELECT id INTO v_role_id
    FROM public.role
    WHERE organization_id = p_organization_id
      AND is_canonical_template
      AND canonical_code = v_code;

    IF v_role_id IS NULL THEN
      INSERT INTO public.role (organization_id, code, canonical_code, is_canonical_template, status)
      VALUES (p_organization_id, v_code, v_code, true, 'active')
      RETURNING id INTO v_role_id;
    END IF;

    PERFORM public._m6_apply_canonical_role_permissions(p_organization_id, v_code);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_initialize_organization_access_foundation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.initialize_organization_access_foundation(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER organization_initialize_access_foundation
  AFTER INSERT ON organization
  FOR EACH ROW EXECUTE FUNCTION public.trg_initialize_organization_access_foundation();

-- Backfill existing organizations (no fixture Owner UUIDs).
DO $$
DECLARE
  org_record record;
BEGIN
  FOR org_record IN SELECT id FROM public.organization LOOP
    PERFORM public.initialize_organization_access_foundation(org_record.id);
  END LOOP;
END;
$$;

-- =============================================================================
-- TRUSTED: SET PRIMARY OWNER (BOOTSTRAP / SEED / RIUDA ONLY)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_primary_owner_for_organization(
  p_organization_id uuid,
  p_app_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_app_user_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.app_user u
      WHERE u.organization_id = p_organization_id
        AND u.id = p_app_user_id
        AND u.membership_status = 'member'
    ) THEN
      RAISE EXCEPTION 'invalid_primary_owner_candidate';
    END IF;
  END IF;

  UPDATE public.organization_entitlement oe
  SET primary_app_user_id = p_app_user_id
  WHERE oe.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entitlement_missing';
  END IF;
END;
$$;

-- =============================================================================
-- INTERNAL: TRANSACTIONAL STAFF MEMBERSHIP CREATION (T03 ORCHESTRATION)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_staff_membership_record(
  p_organization_id uuid,
  p_email text,
  p_display_name text,
  p_preferred_locale text DEFAULT 'vi'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer;
  v_primary uuid;
  v_count integer;
  v_user_id uuid;
BEGIN
  IF p_organization_id IS NULL OR NULLIF(btrim(p_email), '') IS NULL OR NULLIF(btrim(p_display_name), '') IS NULL THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  SELECT oe.staff_limit, oe.primary_app_user_id
    INTO v_limit, v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entitlement_missing';
  END IF;

  IF v_primary IS NULL THEN
    RAISE EXCEPTION 'primary_owner_unassigned';
  END IF;

  SELECT public.count_member_staff_seats(p_organization_id) INTO v_count;

  IF v_count >= v_limit THEN
    RAISE EXCEPTION 'staff_seat_limit_exceeded';
  END IF;

  INSERT INTO public.app_user (
    organization_id,
    email,
    display_name,
    preferred_locale,
    status,
    membership_status
  ) VALUES (
    p_organization_id,
    lower(btrim(p_email)),
    btrim(p_display_name),
    COALESCE(p_preferred_locale, 'vi'),
    'active',
    'member'
  )
  RETURNING id INTO v_user_id;

  RETURN v_user_id;
END;
$$;

-- =============================================================================
-- ASSIGN CANONICAL STAFF / OWNER ROLE (PRIMARY OWNER ONLY)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.assign_canonical_staff_role(
  p_target_user_id uuid,
  p_canonical_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_role_id uuid;
  v_primary uuid;
  v_allowed text[] := ARRAY['accountant', 'consultant', 'academic_operations', 'teacher'];
BEGIN
  IF NOT public.is_primary_owner() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  IF v_primary IS NULL THEN
    RAISE EXCEPTION 'primary_owner_unassigned';
  END IF;

  IF p_target_user_id = v_actor THEN
    RAISE EXCEPTION 'self_assignment_denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.id = p_target_user_id
      AND u.organization_id = v_org_id
      AND u.membership_status = 'member'
  ) THEN
    RAISE EXCEPTION 'invalid_target_user';
  END IF;

  IF p_canonical_code = 'center_manager' THEN
    IF p_target_user_id IS DISTINCT FROM v_primary THEN
      RAISE EXCEPTION 'center_manager_only_for_primary_owner';
    END IF;
  ELSIF p_canonical_code = ANY (v_allowed) THEN
    IF p_target_user_id = v_primary THEN
      RAISE EXCEPTION 'primary_owner_uses_center_manager_template';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_canonical_code';
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.role r
  WHERE r.organization_id = v_org_id
    AND r.is_canonical_template
    AND r.canonical_code = p_canonical_code
    AND r.status = 'active';

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'canonical_role_missing';
  END IF;

  UPDATE public.user_role ur
  SET
    status = 'ended',
    effective_to = CURRENT_DATE,
    updated_at = now()
  FROM public.role r
  WHERE ur.role_id = r.id
    AND ur.organization_id = v_org_id
    AND ur.user_id = p_target_user_id
    AND ur.status = 'active'
    AND r.is_canonical_template;

  INSERT INTO public.user_role (
    organization_id,
    user_id,
    role_id,
    effective_from,
    status
  ) VALUES (
    v_org_id,
    p_target_user_id,
    v_role_id,
    CURRENT_DATE,
    'active'
  );

  RETURN jsonb_build_object(
    'organization_id', v_org_id,
    'user_id', p_target_user_id,
    'canonical_code', p_canonical_code,
    'role_id', v_role_id
  );
END;
$$;

-- =============================================================================
-- SAFE IDENTITY PROJECTION (NO EMAIL LEAK)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fetch_app_user_identity_labels(p_user_ids uuid[])
RETURNS TABLE (user_id uuid, display_name text, membership_status text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id, u.display_name, u.membership_status
  FROM public.app_user u
  WHERE u.organization_id = public.current_organization_id()
    AND u.id = ANY (p_user_ids)
    AND public.is_active_app_user()
    AND (
      u.id = public.current_app_user_id()
      OR public.has_permission('identity.read')
      OR public.is_primary_owner()
    );
$$;

-- =============================================================================
-- CANONICAL TEMPLATE / PRIMARY OWNER GUARDS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_trusted_schema_mutation_role()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT current_user IN ('postgres', 'supabase_admin');
$$;

CREATE OR REPLACE FUNCTION public.protect_canonical_role_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public.is_trusted_schema_mutation_role() THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'canonical_role_mutation_denied' USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER role_protect_canonical_template
  BEFORE UPDATE OR DELETE ON role
  FOR EACH ROW
  WHEN (OLD.is_canonical_template)
  EXECUTE FUNCTION public.protect_canonical_role_mutation();

CREATE TRIGGER role_protect_canonical_insert
  BEFORE INSERT ON role
  FOR EACH ROW
  WHEN (NEW.is_canonical_template)
  EXECUTE FUNCTION public.protect_canonical_role_mutation();

CREATE OR REPLACE FUNCTION public.protect_canonical_role_permission_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_role_id uuid := COALESCE(NEW.role_id, OLD.role_id);
  v_is_canonical boolean;
BEGIN
  SELECT is_canonical_template INTO v_is_canonical
  FROM public.role WHERE id = v_role_id;

  IF COALESCE(v_is_canonical, false) AND NOT public.is_trusted_schema_mutation_role() THEN
    RAISE EXCEPTION 'canonical_role_permission_mutation_denied' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER role_permission_protect_canonical
  BEFORE INSERT OR UPDATE OR DELETE ON role_permission
  FOR EACH ROW EXECUTE FUNCTION public.protect_canonical_role_permission_mutation();

CREATE OR REPLACE FUNCTION public.protect_primary_owner_app_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_primary uuid;
BEGIN
  IF public.is_trusted_schema_mutation_role() THEN
    RETURN NEW;
  END IF;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = OLD.organization_id;

  IF v_primary IS NULL OR OLD.id IS DISTINCT FROM v_primary THEN
    RETURN NEW;
  END IF;

  IF NEW.membership_status IS DISTINCT FROM OLD.membership_status
     AND NEW.membership_status = 'removed' THEN
    RAISE EXCEPTION 'primary_owner_removal_denied';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'active' THEN
    RAISE EXCEPTION 'primary_owner_suspend_denied';
  END IF;

  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'primary_owner_org_change_denied';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER app_user_protect_primary_owner
  BEFORE UPDATE ON app_user
  FOR EACH ROW EXECUTE FUNCTION public.protect_primary_owner_app_user();

CREATE OR REPLACE FUNCTION public.protect_app_user_sensitive_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_trusted_schema_mutation_role() THEN
    RETURN NEW;
  END IF;

  IF public.is_primary_owner() THEN
    IF NEW.membership_status IS DISTINCT FROM OLD.membership_status THEN
      RAISE EXCEPTION 'membership_status_change_requires_trusted_path';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'Cannot change organization_id without user.manage permission';
  END IF;

  IF NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
    RAISE EXCEPTION 'Cannot change auth_user_id without user.manage permission';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Cannot change account status without user.manage permission';
  END IF;

  IF NEW.membership_status IS DISTINCT FROM OLD.membership_status THEN
    RAISE EXCEPTION 'Cannot change membership_status without trusted administration';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_one_active_canonical_user_role()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' AND EXISTS (
    SELECT 1 FROM public.role r
    WHERE r.id = NEW.role_id AND r.is_canonical_template
  ) THEN
    IF EXISTS (
      SELECT 1
      FROM public.user_role ur
      JOIN public.role r ON r.id = ur.role_id
      WHERE ur.organization_id = NEW.organization_id
        AND ur.user_id = NEW.user_id
        AND ur.status = 'active'
        AND r.is_canonical_template
        AND ur.id IS DISTINCT FROM NEW.id
    ) THEN
      RAISE EXCEPTION 'multiple_active_canonical_roles' USING ERRCODE = '23505';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER user_role_guard_one_active_canonical
  BEFORE INSERT OR UPDATE OF status, role_id ON user_role
  FOR EACH ROW EXECUTE FUNCTION public.guard_one_active_canonical_user_role();

-- =============================================================================
-- RLS: ORGANIZATION ENTITLEMENT
-- =============================================================================

ALTER TABLE organization_entitlement ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_entitlement FORCE ROW LEVEL SECURITY;

CREATE POLICY organization_entitlement_select_primary_owner
  ON organization_entitlement
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.is_primary_owner()
  );

-- =============================================================================
-- RLS: APP_USER SELECT HARDENING
-- =============================================================================

DROP POLICY IF EXISTS app_user_select ON app_user;

CREATE POLICY app_user_select ON app_user
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      id = public.current_app_user_id()
      OR public.is_primary_owner()
    )
  );

DROP POLICY IF EXISTS app_user_insert ON app_user;

-- No authenticated INSERT; membership creation is trusted-internal only.

-- =============================================================================
-- GRANTS: RESTRICT DIRECT ROLE GRAPH / APP_USER MUTATION
-- =============================================================================

REVOKE INSERT, UPDATE, DELETE ON public.role_permission FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.user_role FROM authenticated;
REVOKE INSERT ON public.app_user FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.role FROM authenticated;

GRANT SELECT ON public.organization_entitlement TO authenticated;

GRANT SELECT ON public.role_permission TO authenticated;
GRANT SELECT ON public.user_role TO authenticated;
GRANT SELECT, UPDATE ON public.app_user TO authenticated;
GRANT SELECT ON public.role TO authenticated;

-- =============================================================================
-- FUNCTION EXECUTE PRIVILEGES
-- =============================================================================

REVOKE ALL ON FUNCTION public.initialize_organization_access_foundation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.initialize_organization_access_foundation(uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public._m6_apply_canonical_role_permissions(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_apply_canonical_role_permissions(uuid, text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.set_primary_owner_for_organization(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_primary_owner_for_organization(uuid, uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.create_staff_membership_record(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_staff_membership_record(uuid, text, text, text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.is_primary_owner() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_primary_owner() TO authenticated;

REVOKE ALL ON FUNCTION public.is_owner_only_permission(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.count_member_staff_seats(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.count_member_staff_seats(uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.assign_canonical_staff_role(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_canonical_staff_role(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.fetch_app_user_identity_labels(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_app_user_identity_labels(uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION public.trg_initialize_organization_access_foundation() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_staff_membership_record(uuid, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.set_primary_owner_for_organization(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.initialize_organization_access_foundation(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.is_same_organization_app_user(p_app_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_user u
    WHERE u.id = p_app_user_id
      AND u.organization_id = public.current_organization_id()
      AND u.membership_status = 'member'
  );
$$;

REVOKE ALL ON FUNCTION public.is_same_organization_app_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_same_organization_app_user(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_staff_compensation_rule(
  p_app_user_id uuid,
  p_cost_domain_code text,
  p_compensation_basis_code text,
  p_amount bigint,
  p_effective_from date,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_rule_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('personnel_cost.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount' USING ERRCODE = 'P0001';
  END IF;

  IF p_compensation_basis_code NOT IN ('monthly_fixed', 'per_session') THEN
    RAISE EXCEPTION 'invalid_compensation_basis' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.validate_personnel_cost_domain(v_org, p_cost_domain_code);

  IF NOT public.is_same_organization_app_user(p_app_user_id) THEN
    RAISE EXCEPTION 'staff_not_found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO staff_compensation_rule (
    organization_id,
    app_user_id,
    cost_domain_code,
    compensation_basis_code,
    amount,
    effective_from,
    notes,
    created_by,
    updated_by
  ) VALUES (
    v_org,
    p_app_user_id,
    p_cost_domain_code,
    p_compensation_basis_code,
    p_amount,
    p_effective_from,
    p_notes,
    public.current_app_user_id(),
    public.current_app_user_id()
  )
  RETURNING id INTO v_rule_id;

  RETURN v_rule_id;
END;
$$;

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
      AND u.membership_status = 'member'
      AND ur.status = 'active'
      AND ur.effective_from <= CURRENT_DATE
      AND (ur.effective_to IS NULL OR ur.effective_to >= CURRENT_DATE)
      AND r.status = 'active'
      AND p.code = 'lead.read'
  );
$$;

-- =============================================================================
-- SQL test fixtures (psql as postgres only; not granted to authenticated/anon)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.test_fixture_insert_app_user(
  p_organization_id uuid,
  p_email text,
  p_display_name text,
  p_auth_user_id uuid DEFAULT NULL,
  p_status text DEFAULT 'active',
  p_membership_status text DEFAULT 'member'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'test_fixture_only' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.app_user (
    organization_id,
    email,
    display_name,
    auth_user_id,
    status,
    membership_status
  ) VALUES (
    p_organization_id,
    p_email,
    p_display_name,
    p_auth_user_id,
    p_status,
    p_membership_status
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.test_fixture_insert_app_user(uuid, text, text, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.test_fixture_insert_app_user(uuid, text, text, uuid, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.test_fixture_insert_app_user(uuid, text, text, uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.test_fixture_grant_all_permissions_role(
  p_organization_id uuid,
  p_admin_app_user_id uuid,
  p_role_code text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role uuid;
BEGIN
  IF session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'test_fixture_only' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.role (organization_id, code)
  VALUES (p_organization_id, p_role_code)
  RETURNING id INTO v_role;

  INSERT INTO public.role_permission (role_id, permission_id)
  SELECT v_role, p.id FROM public.permission p;

  INSERT INTO public.user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (p_organization_id, p_admin_app_user_id, v_role, CURRENT_DATE, 'active');
END;
$$;

REVOKE ALL ON FUNCTION public.test_fixture_grant_all_permissions_role(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.test_fixture_grant_all_permissions_role(uuid, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.test_fixture_grant_all_permissions_role(uuid, uuid, text) TO authenticated;
