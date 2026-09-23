-- M7-T04: Enforce organization_subscription.status for normal application use.

-- =============================================================================
-- COMMERCIAL ENTITLEMENT (authoritative)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.organization_subscription_allows_normal_use(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_subscription os
    WHERE os.organization_id = p_organization_id
      AND os.status = 'active'
  );
$$;

COMMENT ON FUNCTION public.organization_subscription_allows_normal_use(uuid) IS
  'True only when the center has an active commercial subscription. Missing row fails closed.';

CREATE OR REPLACE FUNCTION public.is_organization_commercially_entitled()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.current_organization_id() IS NOT NULL
    AND public.organization_subscription_allows_normal_use(public.current_organization_id());
$$;

CREATE OR REPLACE FUNCTION public.assert_organization_commercially_entitled()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.current_app_user_id() IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organization_commercially_entitled() THEN
    RAISE EXCEPTION 'commercial_access_restricted' USING ERRCODE = '42501';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_organization_commercially_entitled() IS
  'Raises commercial_access_restricted when the current center subscription is not active.';

-- Operational identity (org active, member) without commercial gate.
CREATE OR REPLACE FUNCTION public.is_operationally_active_app_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.current_app_user_id() IS NOT NULL;
$$;

COMMENT ON FUNCTION public.is_operationally_active_app_user() IS
  'Usable M6 identity: active org, active member. Ignores commercial subscription.';

-- Primary Owner identity for commercial-status reads (no subscription gate).
CREATE OR REPLACE FUNCTION public.is_operational_primary_owner()
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
      AND public.is_operationally_active_app_user()
  );
$$;

COMMENT ON FUNCTION public.is_operational_primary_owner() IS
  'Primary Owner with operational identity only. Used for restricted commercial status reads.';

-- =============================================================================
-- IDENTITY + RBAC (commercial gate on normal use)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_active_app_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_operationally_active_app_user()
    AND public.is_organization_commercially_entitled();
$$;

COMMENT ON FUNCTION public.is_active_app_user() IS
  'Normal application identity: operational M6 identity plus active commercial subscription.';

CREATE OR REPLACE FUNCTION public.is_primary_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_operational_primary_owner()
    AND public.is_organization_commercially_entitled();
$$;

COMMENT ON FUNCTION public.is_primary_owner() IS
  'Commercially entitled primary Owner. Executive and account administration derive from this identity.';

CREATE OR REPLACE FUNCTION public.has_permission(p_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN NOT public.is_organization_commercially_entitled() THEN false
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
  WHERE public.is_organization_commercially_entitled()
  ORDER BY 1;
$$;

-- =============================================================================
-- SESSION COMMERCIAL ACCESS (authenticated routing)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fetch_session_commercial_access()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_status text;
BEGIN
  IF NOT public.is_operationally_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT os.status INTO v_status
  FROM public.organization_subscription os
  WHERE os.organization_id = v_org_id;

  RETURN jsonb_build_object(
    'organization_id', v_org_id,
    'allows_normal_use', public.organization_subscription_allows_normal_use(v_org_id),
    'subscription_status', v_status,
    'is_primary_owner', public.is_operational_primary_owner()
  );
END;
$$;

-- Owner commercial read while commercially restricted.
CREATE OR REPLACE FUNCTION public.fetch_owner_commercial_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_sub public.organization_subscription%ROWTYPE;
  v_plan public.commercial_plan%ROWTYPE;
  v_staff_limit integer;
  v_staff_used integer;
BEGIN
  IF NOT public.is_operational_primary_owner() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT os.* INTO v_sub
  FROM public.organization_subscription os
  WHERE os.organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription_missing';
  END IF;

  SELECT cp.* INTO v_plan
  FROM public.commercial_plan cp
  WHERE cp.id = v_sub.commercial_plan_id;

  SELECT oe.staff_limit INTO v_staff_limit
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  v_staff_used := public.count_member_staff_seats(v_org_id);

  RETURN jsonb_build_object(
    'plan_code', v_plan.code,
    'plan_name', v_plan.name,
    'subscription_status', v_sub.status,
    'staff_limit', v_staff_limit,
    'staff_seats_used', v_staff_used,
    'activated_at', v_sub.activated_at,
    'suspended_at', v_sub.suspended_at,
    'cancelled_at', v_sub.cancelled_at,
    'organization_status', (
      SELECT o.status FROM public.organization o WHERE o.id = v_org_id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.organization_subscription_allows_normal_use(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.organization_subscription_allows_normal_use(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_organization_commercially_entitled() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_organization_commercially_entitled() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.assert_organization_commercially_entitled() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_organization_commercially_entitled() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_operationally_active_app_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_operationally_active_app_user() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_operational_primary_owner() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_operational_primary_owner() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.fetch_session_commercial_access() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_session_commercial_access() TO authenticated;

-- =============================================================================
-- ORG BOOTSTRAP: subscription row for legacy SQL test orgs (fail-closed otherwise)
-- =============================================================================

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

  IF NOT EXISTS (
    SELECT 1
    FROM public.organization_subscription os
    WHERE os.organization_id = p_organization_id
  ) THEN
    IF current_setting('olli.center_provisioning_finalize', true) = 'true' THEN
      PERFORM public._m7_initialize_organization_subscription(p_organization_id, 'provisioning');
    ELSIF public.is_trusted_schema_mutation_role() THEN
      PERFORM public._m7_initialize_organization_subscription(p_organization_id, 'active');
    ELSE
      PERFORM public._m7_initialize_organization_subscription(p_organization_id, 'provisioning');
    END IF;
  END IF;

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

CREATE OR REPLACE FUNCTION public.finalize_center_provisioning(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.center_provisioning_request%ROWTYPE;
  v_org_id uuid;
  v_app_user_id uuid;
  v_role_id uuid;
  v_staff_limit integer;
  v_primary uuid;
  v_canonical_roles integer;
  v_cost_groups integer;
BEGIN
  SELECT * INTO v_row
  FROM public.center_provisioning_request cpr
  WHERE cpr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF v_row.status = 'completed'
     AND v_row.organization_id IS NOT NULL
     AND v_row.owner_app_user_id IS NOT NULL THEN
    RETURN public._m7_center_provisioning_to_json(v_row)
      || jsonb_build_object('outcome', 'completed');
  END IF;

  IF v_row.status <> 'auth_created' OR v_row.auth_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_request_state';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.auth_user_id = v_row.auth_user_id
      AND (v_row.owner_app_user_id IS NULL OR u.id IS DISTINCT FROM v_row.owner_app_user_id)
  ) THEN
    UPDATE public.center_provisioning_request cpr
    SET status = 'compensation_pending', result_code = 'identity_conflict'
    WHERE cpr.id = p_request_id;
    RAISE EXCEPTION 'identity_conflict';
  END IF;

  PERFORM set_config('olli.center_provisioning_finalize', 'true', true);

  INSERT INTO public.organization (
    name,
    default_locale,
    timezone,
    currency_code,
    status
  ) VALUES (
    v_row.organization_name,
    v_row.default_locale,
    v_row.timezone,
    v_row.currency_code,
    'active'
  )
  RETURNING id INTO v_org_id;

  PERFORM set_config('olli.center_provisioning_finalize', '', true);

  PERFORM public._m7_initialize_organization_subscription(v_org_id, 'provisioning');

  SELECT oe.staff_limit, oe.primary_app_user_id
    INTO v_staff_limit, v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  IF v_staff_limit IS DISTINCT FROM 5 OR v_primary IS NOT NULL THEN
    RAISE EXCEPTION 'entitlement_bootstrap_invalid';
  END IF;

  SELECT count(*)::integer INTO v_canonical_roles
  FROM public.role r
  WHERE r.organization_id = v_org_id
    AND r.is_canonical_template
    AND r.status = 'active';

  IF v_canonical_roles <> 5 THEN
    RAISE EXCEPTION 'canonical_roles_bootstrap_invalid';
  END IF;

  SELECT count(*)::integer INTO v_cost_groups
  FROM public.cost_group cg
  WHERE cg.organization_id = v_org_id;

  IF v_cost_groups < 2 THEN
    RAISE EXCEPTION 'organization_bootstrap_invalid';
  END IF;

  INSERT INTO public.app_user (
    organization_id,
    email,
    display_name,
    preferred_locale,
    status,
    membership_status,
    auth_user_id
  ) VALUES (
    v_org_id,
    v_row.owner_normalized_email,
    v_row.owner_display_name,
    v_row.owner_preferred_locale,
    'active',
    'member',
    v_row.auth_user_id
  )
  RETURNING id INTO v_app_user_id;

  PERFORM public.set_primary_owner_for_organization(v_org_id, v_app_user_id);

  SELECT public._m7_assign_center_manager_to_primary_owner(v_org_id, v_app_user_id)
    INTO v_role_id;

  UPDATE public.center_provisioning_request cpr
  SET
    organization_id = v_org_id,
    owner_app_user_id = v_app_user_id,
    status = 'completed',
    result_code = 'completed'
  WHERE cpr.id = p_request_id
  RETURNING * INTO v_row;

  RETURN public._m7_center_provisioning_to_json(v_row)
    || jsonb_build_object(
      'outcome', 'completed',
      'staff_limit', v_staff_limit,
      'center_manager_role_id', v_role_id
    );
EXCEPTION
  WHEN unique_violation THEN
    UPDATE public.center_provisioning_request cpr
    SET status = 'compensation_pending', result_code = 'identity_conflict'
    WHERE cpr.id = p_request_id;
    RAISE EXCEPTION 'identity_conflict';
  WHEN OTHERS THEN
    IF SQLERRM LIKE '%identity_conflict%' OR SQLERRM LIKE '%owner_email_already_provisioned%' THEN
      RAISE;
    END IF;
    UPDATE public.center_provisioning_request cpr
    SET status = 'failed', result_code = left(SQLERRM, 120)
    WHERE cpr.id = p_request_id
      AND cpr.status <> 'completed';
    RAISE;
END;
$$;

-- =============================================================================
-- RLS: allow operational identity self-read for commercial routing (not domain data)
-- =============================================================================

DROP POLICY IF EXISTS app_user_select ON app_user;

CREATE POLICY app_user_select ON app_user
  FOR SELECT TO authenticated
  USING (
    public.is_operationally_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      id = public.current_app_user_id()
      OR public.is_primary_owner()
    )
  );

CREATE POLICY organization_select_operational_self ON organization
  FOR SELECT TO authenticated
  USING (
    public.is_operationally_active_app_user()
    AND id = public.current_organization_id()
  );
