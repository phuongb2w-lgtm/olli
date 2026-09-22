-- M6-T05: Staff lifecycle (suspend, reactivate, remove, restore), role-change
-- tightening, identity-gate hardening, and append-only lifecycle events.

-- =============================================================================
-- IDENTITY GATE: usable identity requires active org + active member
-- =============================================================================

CREATE OR REPLACE FUNCTION public.current_app_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.id
  FROM public.app_user u
  JOIN public.organization o ON o.id = u.organization_id
  WHERE u.auth_user_id = auth.uid()
    AND u.status = 'active'
    AND u.membership_status = 'member'
    AND o.status = 'active'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_organization_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.organization_id
  FROM public.app_user u
  JOIN public.organization o ON o.id = u.organization_id
  WHERE u.auth_user_id = auth.uid()
    AND u.status = 'active'
    AND u.membership_status = 'member'
    AND o.status = 'active'
  LIMIT 1;
$$;

COMMENT ON FUNCTION public.current_app_user_id() IS
  'Active application identity only: org active, app_user.status=active, membership_status=member.';

COMMENT ON FUNCTION public.current_organization_id() IS
  'Organization of the current usable identity. Removed or inactive users resolve to NULL.';

-- =============================================================================
-- LIFECYCLE EVENT HISTORY (append-only)
-- =============================================================================

CREATE TABLE public.staff_lifecycle_event (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  target_app_user_id  uuid NOT NULL,
  actor_app_user_id   uuid NOT NULL,
  event_type          text NOT NULL,
  from_status         text NOT NULL,
  to_status           text NOT NULL,
  from_membership     text NOT NULL,
  to_membership       text NOT NULL,
  canonical_role      text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT staff_lifecycle_event_type_check CHECK (
    event_type IN ('suspended', 'reactivated', 'removed', 'restored')
  ),
  CONSTRAINT staff_lifecycle_event_target_fk
    FOREIGN KEY (organization_id, target_app_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT,
  CONSTRAINT staff_lifecycle_event_actor_fk
    FOREIGN KEY (organization_id, actor_app_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_staff_lifecycle_event_target
  ON public.staff_lifecycle_event (organization_id, target_app_user_id, created_at DESC);

COMMENT ON TABLE public.staff_lifecycle_event IS
  'Append-only Owner staff lifecycle events. Role history remains on user_role.';

ALTER TABLE public.staff_lifecycle_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_lifecycle_event FORCE ROW LEVEL SECURITY;

CREATE POLICY staff_lifecycle_event_select_primary_owner
  ON public.staff_lifecycle_event
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.is_primary_owner()
  );

REVOKE ALL ON TABLE public.staff_lifecycle_event FROM PUBLIC;
REVOKE ALL ON TABLE public.staff_lifecycle_event FROM anon, authenticated;
GRANT SELECT ON TABLE public.staff_lifecycle_event TO authenticated;

-- =============================================================================
-- DIRECT-DML GUARDS: lifecycle RPCs are the only mutation path
-- Triggers are INVOKER so current_user is the executing role.
-- SECURITY DEFINER RPCs owned by postgres therefore pass the trusted-path check.
-- Authenticated PostgREST UPDATEs do not.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_primary_owner_app_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
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

CREATE OR REPLACE FUNCTION public.protect_app_user_sensitive_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF public.is_trusted_schema_mutation_role() THEN
    RETURN NEW;
  END IF;

  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'Cannot change organization_id without trusted administration';
  END IF;

  IF NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
    RAISE EXCEPTION 'Cannot change auth_user_id without trusted administration';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'Cannot change account status without trusted administration';
  END IF;

  IF NEW.membership_status IS DISTINCT FROM OLD.membership_status THEN
    RAISE EXCEPTION 'Cannot change membership_status without trusted administration';
  END IF;

  RETURN NEW;
END;
$$;

-- =============================================================================
-- INTERNAL LIFECYCLE HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._m6_staff_lifecycle_roles()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT ARRAY['accountant', 'consultant', 'academic_operations', 'teacher']::text[];
$$;

CREATE OR REPLACE FUNCTION public._m6_lifecycle_require_owner()
RETURNS TABLE (org_id uuid, actor_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
  v_actor uuid;
  v_org_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  v_actor := public.current_app_user_id();
  v_org := public.current_organization_id();

  IF v_actor IS NULL OR v_org IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT o.status INTO v_org_status
  FROM public.organization o
  WHERE o.id = v_org;

  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'organization_inactive';
  END IF;

  IF NOT public.is_primary_owner() THEN
    RAISE EXCEPTION 'not_primary_owner';
  END IF;

  org_id := v_org;
  actor_id := v_actor;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_lifecycle_lock_target(
  p_org_id uuid,
  p_target_user_id uuid,
  p_lock_entitlement boolean
)
RETURNS public.app_user
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target public.app_user%ROWTYPE;
BEGIN
  IF p_lock_entitlement THEN
    PERFORM 1
    FROM public.organization_entitlement oe
    WHERE oe.organization_id = p_org_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'target_not_found';
    END IF;
  END IF;

  SELECT u.* INTO v_target
  FROM public.app_user u
  WHERE u.id = p_target_user_id
    AND u.organization_id = p_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'target_not_found';
  END IF;

  RETURN v_target;
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_active_canonical_staff_role_code(
  p_org_id uuid,
  p_user_id uuid
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.canonical_code
  FROM public.user_role ur
  JOIN public.role r ON r.id = ur.role_id
  WHERE ur.organization_id = p_org_id
    AND ur.user_id = p_user_id
    AND ur.status = 'active'
    AND r.is_canonical_template
    AND r.canonical_code = ANY (public._m6_staff_lifecycle_roles())
  ORDER BY r.canonical_code
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._m6_end_active_canonical_staff_roles(
  p_org_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.user_role ur
  SET
    status = 'ended',
    effective_to = CURRENT_DATE,
    updated_at = now()
  FROM public.role r
  WHERE ur.role_id = r.id
    AND ur.organization_id = p_org_id
    AND ur.user_id = p_user_id
    AND ur.status = 'active'
    AND r.is_canonical_template;
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_assign_canonical_staff_role_on_member(
  p_org_id uuid,
  p_user_id uuid,
  p_canonical_code text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
  v_current text;
BEGIN
  IF p_canonical_code IS NULL OR NOT (p_canonical_code = ANY (public._m6_staff_lifecycle_roles())) THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;

  v_current := public._m6_active_canonical_staff_role_code(p_org_id, p_user_id);
  IF v_current IS NOT DISTINCT FROM p_canonical_code THEN
    SELECT r.id INTO v_role_id
    FROM public.role r
    WHERE r.organization_id = p_org_id
      AND r.is_canonical_template
      AND r.canonical_code = p_canonical_code
      AND r.status = 'active';
    RETURN v_role_id;
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.role r
  WHERE r.organization_id = p_org_id
    AND r.is_canonical_template
    AND r.canonical_code = p_canonical_code
    AND r.status = 'active';

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;

  PERFORM public._m6_end_active_canonical_staff_roles(p_org_id, p_user_id);

  INSERT INTO public.user_role (
    organization_id,
    user_id,
    role_id,
    effective_from,
    status
  ) VALUES (
    p_org_id,
    p_user_id,
    v_role_id,
    CURRENT_DATE,
    'active'
  );

  RETURN v_role_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_append_staff_lifecycle_event(
  p_org_id uuid,
  p_target_id uuid,
  p_actor_id uuid,
  p_event_type text,
  p_from_status text,
  p_to_status text,
  p_from_membership text,
  p_to_membership text,
  p_canonical_role text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.staff_lifecycle_event (
    organization_id,
    target_app_user_id,
    actor_app_user_id,
    event_type,
    from_status,
    to_status,
    from_membership,
    to_membership,
    canonical_role
  ) VALUES (
    p_org_id,
    p_target_id,
    p_actor_id,
    p_event_type,
    p_from_status,
    p_to_status,
    p_from_membership,
    p_to_membership,
    p_canonical_role
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_lifecycle_result(
  p_target public.app_user,
  p_canonical_role text,
  p_noop boolean
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'ok', true,
    'app_user_id', p_target.id,
    'status', p_target.status,
    'membership_status', p_target.membership_status,
    'canonical_role', p_canonical_role,
    'noop', p_noop
  );
$$;

-- =============================================================================
-- ASSIGN CANONICAL STAFF ROLE (tightened)
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
  v_primary uuid;
  v_target public.app_user%ROWTYPE;
  v_role_id uuid;
  v_current text;
BEGIN
  SELECT r.org_id, r.actor_id INTO v_org_id, v_actor
  FROM public._m6_lifecycle_require_owner() r;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  IF v_primary IS NULL THEN
    RAISE EXCEPTION 'primary_owner_unassigned';
  END IF;

  v_target := public._m6_lifecycle_lock_target(v_org_id, p_target_user_id, false);

  IF v_target.id = v_primary THEN
    RAISE EXCEPTION 'target_is_primary_owner';
  END IF;

  IF v_target.membership_status = 'removed' THEN
    RAISE EXCEPTION 'target_already_removed';
  END IF;

  IF v_target.membership_status IS DISTINCT FROM 'member' THEN
    RAISE EXCEPTION 'target_not_member';
  END IF;

  IF v_target.status = 'locked' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  IF p_canonical_code IS NULL OR p_canonical_code = 'center_manager'
     OR NOT (p_canonical_code = ANY (public._m6_staff_lifecycle_roles())) THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;

  v_current := public._m6_active_canonical_staff_role_code(v_org_id, v_target.id);
  IF v_current IS NOT DISTINCT FROM p_canonical_code THEN
    RETURN jsonb_build_object(
      'organization_id', v_org_id,
      'user_id', v_target.id,
      'canonical_code', p_canonical_code,
      'role_id', (
        SELECT r.id FROM public.role r
        WHERE r.organization_id = v_org_id
          AND r.is_canonical_template
          AND r.canonical_code = p_canonical_code
        LIMIT 1
      ),
      'noop', true
    );
  END IF;

  v_role_id := public._m6_assign_canonical_staff_role_on_member(
    v_org_id,
    v_target.id,
    p_canonical_code
  );

  RETURN jsonb_build_object(
    'organization_id', v_org_id,
    'user_id', v_target.id,
    'canonical_code', p_canonical_code,
    'role_id', v_role_id,
    'noop', false
  );
END;
$$;

-- =============================================================================
-- SUSPEND / REACTIVATE / REMOVE / RESTORE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.suspend_staff_member(p_target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_primary uuid;
  v_target public.app_user%ROWTYPE;
  v_role text;
BEGIN
  SELECT r.org_id, r.actor_id INTO v_org_id, v_actor
  FROM public._m6_lifecycle_require_owner() r;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  v_target := public._m6_lifecycle_lock_target(v_org_id, p_target_user_id, false);

  IF v_target.id = v_primary THEN
    RAISE EXCEPTION 'target_is_primary_owner';
  END IF;

  IF v_target.membership_status = 'removed' THEN
    RAISE EXCEPTION 'target_already_removed';
  END IF;

  IF v_target.membership_status IS DISTINCT FROM 'member' THEN
    RAISE EXCEPTION 'target_not_member';
  END IF;

  IF v_target.status = 'locked' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  v_role := public._m6_active_canonical_staff_role_code(v_org_id, v_target.id);

  IF v_target.status = 'inactive' THEN
    RETURN public._m6_lifecycle_result(v_target, v_role, true);
  END IF;

  IF v_target.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  UPDATE public.app_user
  SET status = 'inactive'
  WHERE id = v_target.id
    AND organization_id = v_org_id
  RETURNING * INTO v_target;

  PERFORM public._m6_append_staff_lifecycle_event(
    v_org_id,
    v_target.id,
    v_actor,
    'suspended',
    'active',
    'inactive',
    'member',
    'member',
    v_role
  );

  RETURN public._m6_lifecycle_result(v_target, v_role, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.reactivate_staff_member(p_target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_primary uuid;
  v_target public.app_user%ROWTYPE;
  v_role text;
BEGIN
  SELECT r.org_id, r.actor_id INTO v_org_id, v_actor
  FROM public._m6_lifecycle_require_owner() r;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  v_target := public._m6_lifecycle_lock_target(v_org_id, p_target_user_id, false);

  IF v_target.id = v_primary THEN
    RAISE EXCEPTION 'target_is_primary_owner';
  END IF;

  IF v_target.membership_status = 'removed' THEN
    RAISE EXCEPTION 'target_already_removed';
  END IF;

  IF v_target.membership_status IS DISTINCT FROM 'member' THEN
    RAISE EXCEPTION 'target_not_member';
  END IF;

  IF v_target.status = 'locked' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  v_role := public._m6_active_canonical_staff_role_code(v_org_id, v_target.id);

  IF v_target.status = 'active' THEN
    RETURN public._m6_lifecycle_result(v_target, v_role, true);
  END IF;

  IF v_target.status IS DISTINCT FROM 'inactive' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  UPDATE public.app_user
  SET status = 'active'
  WHERE id = v_target.id
    AND organization_id = v_org_id
  RETURNING * INTO v_target;

  PERFORM public._m6_append_staff_lifecycle_event(
    v_org_id,
    v_target.id,
    v_actor,
    'reactivated',
    'inactive',
    'active',
    'member',
    'member',
    v_role
  );

  RETURN public._m6_lifecycle_result(v_target, v_role, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_staff_from_center(p_target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_primary uuid;
  v_target public.app_user%ROWTYPE;
  v_role text;
  v_from_status text;
BEGIN
  SELECT r.org_id, r.actor_id INTO v_org_id, v_actor
  FROM public._m6_lifecycle_require_owner() r;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  v_target := public._m6_lifecycle_lock_target(v_org_id, p_target_user_id, true);

  IF v_target.id = v_primary THEN
    RAISE EXCEPTION 'target_is_primary_owner';
  END IF;

  IF v_target.status = 'locked' AND v_target.membership_status = 'member' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  v_role := public._m6_active_canonical_staff_role_code(v_org_id, v_target.id);

  IF v_target.membership_status = 'removed' THEN
    RETURN public._m6_lifecycle_result(v_target, v_role, true);
  END IF;

  IF v_target.membership_status IS DISTINCT FROM 'member' THEN
    RAISE EXCEPTION 'target_not_member';
  END IF;

  v_from_status := v_target.status;

  PERFORM public._m6_end_active_canonical_staff_roles(v_org_id, v_target.id);

  UPDATE public.app_user
  SET
    status = 'inactive',
    membership_status = 'removed'
  WHERE id = v_target.id
    AND organization_id = v_org_id
    AND membership_status = 'member'
  RETURNING * INTO v_target;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  PERFORM public._m6_append_staff_lifecycle_event(
    v_org_id,
    v_target.id,
    v_actor,
    'removed',
    v_from_status,
    'inactive',
    'member',
    'removed',
    v_role
  );

  RETURN public._m6_lifecycle_result(v_target, NULL, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_removed_staff(
  p_target_user_id uuid,
  p_canonical_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_primary uuid;
  v_limit integer;
  v_count integer;
  v_target public.app_user%ROWTYPE;
  v_current_role text;
  v_role_id uuid;
BEGIN
  SELECT r.org_id, r.actor_id INTO v_org_id, v_actor
  FROM public._m6_lifecycle_require_owner() r;

  IF p_canonical_role IS NULL OR p_canonical_role = 'center_manager'
     OR NOT (p_canonical_role = ANY (public._m6_staff_lifecycle_roles())) THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;

  SELECT oe.primary_app_user_id, oe.staff_limit
    INTO v_primary, v_limit
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND OR v_primary IS NULL THEN
    RAISE EXCEPTION 'target_not_found';
  END IF;

  v_target := public._m6_lifecycle_lock_target(v_org_id, p_target_user_id, false);

  IF v_target.id = v_primary THEN
    RAISE EXCEPTION 'target_is_primary_owner';
  END IF;

  v_current_role := public._m6_active_canonical_staff_role_code(v_org_id, v_target.id);

  IF v_target.membership_status = 'member' THEN
    IF v_target.status = 'active'
       AND v_current_role IS NOT DISTINCT FROM p_canonical_role THEN
      RETURN public._m6_lifecycle_result(v_target, v_current_role, true);
    END IF;
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  IF v_target.membership_status IS DISTINCT FROM 'removed' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  IF v_target.status = 'locked' THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  SELECT public.count_member_staff_seats(v_org_id) INTO v_count;
  IF v_count >= v_limit THEN
    RAISE EXCEPTION 'staff_seat_limit_exceeded';
  END IF;

  UPDATE public.app_user
  SET
    membership_status = 'member',
    status = 'active'
  WHERE id = v_target.id
    AND organization_id = v_org_id
    AND membership_status = 'removed'
  RETURNING * INTO v_target;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'lifecycle_conflict';
  END IF;

  v_role_id := public._m6_assign_canonical_staff_role_on_member(
    v_org_id,
    v_target.id,
    p_canonical_role
  );

  PERFORM public._m6_append_staff_lifecycle_event(
    v_org_id,
    v_target.id,
    v_actor,
    'restored',
    'inactive',
    'active',
    'removed',
    'member',
    p_canonical_role
  );

  RETURN public._m6_lifecycle_result(v_target, p_canonical_role, false);
END;
$$;

-- =============================================================================
-- T03: distinguish removed same-email identity
-- =============================================================================

CREATE OR REPLACE FUNCTION public._m6_provisioning_check_duplicate_member(
  p_organization_id uuid,
  p_normalized_email text,
  p_exclude_app_user_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.app_user%ROWTYPE;
BEGIN
  SELECT * INTO v_existing
  FROM public.app_user u
  WHERE u.organization_id = p_organization_id
    AND lower(btrim(u.email)) = p_normalized_email
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF p_exclude_app_user_id IS NOT NULL AND v_existing.id = p_exclude_app_user_id THEN
    RETURN;
  END IF;

  IF v_existing.membership_status = 'removed' THEN
    RAISE EXCEPTION 'removed_member_exists';
  END IF;

  IF v_existing.membership_status = 'member' THEN
    RAISE EXCEPTION 'member_already_exists';
  END IF;
END;
$$;

-- =============================================================================
-- /users READ MODEL: include removed staff (separate from current roster)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fetch_center_account_administration()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_primary uuid;
  v_staff_limit integer;
  v_staff_seats_used integer;
  v_primary_owner jsonb;
  v_staff jsonb;
  v_removed jsonb;
BEGIN
  IF NOT public.is_primary_owner() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT oe.primary_app_user_id, oe.staff_limit
  INTO v_primary, v_staff_limit
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  IF v_primary IS NULL THEN
    RAISE EXCEPTION 'primary_owner_unassigned';
  END IF;

  v_staff_seats_used := public.count_member_staff_seats(v_org_id);

  SELECT jsonb_build_object(
    'app_user_id', u.id,
    'display_name', u.display_name,
    'email', u.email,
    'access_status', u.status,
    'membership_status', u.membership_status,
    'preferred_locale', u.preferred_locale
  )
  INTO v_primary_owner
  FROM public.app_user u
  WHERE u.id = v_primary
    AND u.organization_id = v_org_id;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'app_user_id', s.app_user_id,
        'display_name', s.display_name,
        'email', s.email,
        'canonical_role', s.canonical_role,
        'access_status', s.access_status,
        'membership_status', s.membership_status,
        'preferred_locale', s.preferred_locale,
        'created_at', s.created_at
      )
      ORDER BY s.created_at ASC, s.display_name ASC
    ),
    '[]'::jsonb
  )
  INTO v_staff
  FROM (
    SELECT
      u.id AS app_user_id,
      u.display_name,
      u.email,
      (
        SELECT r.canonical_code
        FROM public.user_role ur
        JOIN public.role r ON r.id = ur.role_id
        WHERE ur.user_id = u.id
          AND ur.organization_id = v_org_id
          AND ur.status = 'active'
          AND r.is_canonical_template
        ORDER BY r.canonical_code
        LIMIT 1
      ) AS canonical_role,
      u.status AS access_status,
      u.membership_status,
      u.preferred_locale,
      u.created_at
    FROM public.app_user u
    WHERE u.organization_id = v_org_id
      AND u.membership_status = 'member'
      AND u.id IS DISTINCT FROM v_primary
  ) s;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'app_user_id', s.app_user_id,
        'display_name', s.display_name,
        'email', s.email,
        'canonical_role', s.canonical_role,
        'access_status', s.access_status,
        'membership_status', s.membership_status,
        'preferred_locale', s.preferred_locale,
        'created_at', s.created_at
      )
      ORDER BY s.created_at ASC, s.display_name ASC
    ),
    '[]'::jsonb
  )
  INTO v_removed
  FROM (
    SELECT
      u.id AS app_user_id,
      u.display_name,
      u.email,
      (
        SELECT r.canonical_code
        FROM public.user_role ur
        JOIN public.role r ON r.id = ur.role_id
        WHERE ur.user_id = u.id
          AND ur.organization_id = v_org_id
          AND r.is_canonical_template
        ORDER BY
          CASE WHEN ur.status = 'active' THEN 0 ELSE 1 END,
          ur.effective_to DESC NULLS LAST,
          ur.updated_at DESC
        LIMIT 1
      ) AS canonical_role,
      u.status AS access_status,
      u.membership_status,
      u.preferred_locale,
      u.created_at
    FROM public.app_user u
    WHERE u.organization_id = v_org_id
      AND u.membership_status = 'removed'
      AND u.id IS DISTINCT FROM v_primary
  ) s;

  RETURN jsonb_build_object(
    'staff_limit', v_staff_limit,
    'staff_seats_used', v_staff_seats_used,
    'primary_owner', v_primary_owner,
    'staff', v_staff,
    'removed_staff', v_removed
  );
END;
$$;

COMMENT ON FUNCTION public.fetch_center_account_administration() IS
  'Primary Owner only: entitlement, seat usage, current staff, and removed staff for /users.';

-- =============================================================================
-- GRANTS
-- =============================================================================

REVOKE ALL ON FUNCTION public._m6_staff_lifecycle_roles() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_lifecycle_require_owner() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_lifecycle_require_owner() FROM anon, authenticated;
REVOKE ALL ON FUNCTION public._m6_lifecycle_lock_target(uuid, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_lifecycle_lock_target(uuid, uuid, boolean) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public._m6_active_canonical_staff_role_code(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_active_canonical_staff_role_code(uuid, uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public._m6_end_active_canonical_staff_roles(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_end_active_canonical_staff_roles(uuid, uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public._m6_assign_canonical_staff_role_on_member(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_assign_canonical_staff_role_on_member(uuid, uuid, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public._m6_append_staff_lifecycle_event(uuid, uuid, uuid, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_append_staff_lifecycle_event(uuid, uuid, uuid, text, text, text, text, text, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public._m6_lifecycle_result(public.app_user, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_lifecycle_result(public.app_user, text, boolean) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.suspend_staff_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.suspend_staff_member(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.reactivate_staff_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reactivate_staff_member(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.remove_staff_from_center(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.remove_staff_from_center(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.restore_removed_staff(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restore_removed_staff(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.assign_canonical_staff_role(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_canonical_staff_role(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.fetch_center_account_administration() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_center_account_administration() TO authenticated;

-- Authenticated PostgREST may update locale/display only. Lifecycle columns
-- cannot be written except through trusted SECURITY DEFINER RPCs.
REVOKE UPDATE ON public.app_user FROM authenticated;
GRANT UPDATE (
  preferred_locale,
  display_name,
  updated_at,
  updated_by
) ON public.app_user TO authenticated;
