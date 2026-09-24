-- M7-T06: Primary Owner first-use center setup (authoritative setup_completed_at).

ALTER TABLE public.organization
  ADD COLUMN IF NOT EXISTS setup_completed_at timestamptz NULL;

COMMENT ON COLUMN public.organization.setup_completed_at IS
  'Set when the primary Owner completes first-use center setup via complete_center_setup().';

UPDATE public.organization
SET setup_completed_at = COALESCE(updated_at, created_at, now())
WHERE setup_completed_at IS NULL;

-- =============================================================================
-- SETUP STATE (authoritative)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.organization_center_setup_complete(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization o
    WHERE o.id = p_organization_id
      AND o.setup_completed_at IS NOT NULL
  );
$$;

COMMENT ON FUNCTION public.organization_center_setup_complete(uuid) IS
  'True when the center has a recorded Owner onboarding completion timestamp.';

CREATE OR REPLACE FUNCTION public.organization_subscription_allows_owner_setup(p_organization_id uuid)
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
      AND os.status IN ('provisioning', 'active')
  );
$$;

COMMENT ON FUNCTION public.organization_subscription_allows_owner_setup(uuid) IS
  'Owner may complete first-use setup only while subscription is provisioning or active.';

CREATE OR REPLACE FUNCTION public.requires_center_setup()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_operational_primary_owner()
    AND public.current_organization_id() IS NOT NULL
    AND NOT public.organization_center_setup_complete(public.current_organization_id())
    AND public.organization_subscription_allows_owner_setup(public.current_organization_id());
$$;

COMMENT ON FUNCTION public.requires_center_setup() IS
  'Primary Owner with incomplete setup while commercial state still permits onboarding.';

-- =============================================================================
-- SESSION COMMERCIAL ACCESS (extend for onboarding routing)
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
    'is_primary_owner', public.is_operational_primary_owner(),
    'requires_center_setup', public.requires_center_setup(),
    'setup_completed', public.organization_center_setup_complete(v_org_id)
  );
END;
$$;

-- =============================================================================
-- OWNER SETUP READ / COMPLETE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fetch_owner_center_setup()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_row public.organization%ROWTYPE;
  v_preferred text;
BEGIN
  IF NOT public.is_operationally_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_operational_primary_owner() THEN
    RAISE EXCEPTION 'not_primary_owner' USING ERRCODE = '42501';
  END IF;

  IF NOT public.requires_center_setup() THEN
    IF NOT public.organization_subscription_allows_owner_setup(public.current_organization_id()) THEN
      RAISE EXCEPTION 'commercial_access_restricted' USING ERRCODE = '42501';
    END IF;
    RAISE EXCEPTION 'setup_already_complete' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT * INTO v_row
  FROM public.organization o
  WHERE o.id = v_org_id;

  SELECT u.preferred_locale INTO v_preferred
  FROM public.app_user u
  WHERE u.id = public.current_app_user_id();

  RETURN jsonb_build_object(
    'organization_id', v_org_id,
    'name', v_row.name,
    'default_locale', v_row.default_locale,
    'timezone', v_row.timezone,
    'preferred_locale', v_preferred,
    'subscription_status', (
      SELECT os.status
      FROM public.organization_subscription os
      WHERE os.organization_id = v_org_id
    )
  );
END;
$$;

COMMENT ON FUNCTION public.fetch_owner_center_setup() IS
  'Primary Owner read for /onboarding while setup is required and commercial state permits it.';

CREATE OR REPLACE FUNCTION public.complete_center_setup(
  p_name text,
  p_default_locale text,
  p_timezone text,
  p_preferred_locale text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_name text;
  v_locale text;
  v_tz text;
  v_pref text;
BEGIN
  IF NOT public.is_operationally_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_operational_primary_owner() THEN
    RAISE EXCEPTION 'not_primary_owner' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  IF public.organization_center_setup_complete(v_org_id) THEN
    RAISE EXCEPTION 'setup_already_complete' USING ERRCODE = '42501';
  END IF;

  IF NOT public.organization_subscription_allows_owner_setup(v_org_id) THEN
    RAISE EXCEPTION 'commercial_access_restricted' USING ERRCODE = '42501';
  END IF;

  v_name := btrim(COALESCE(p_name, ''));
  IF char_length(v_name) < 2 OR char_length(v_name) > 200 THEN
    RAISE EXCEPTION 'invalid_organization_name' USING ERRCODE = '22023';
  END IF;

  v_locale := btrim(COALESCE(p_default_locale, ''));
  IF v_locale NOT IN ('vi', 'en') THEN
    RAISE EXCEPTION 'invalid_default_locale' USING ERRCODE = '22023';
  END IF;

  v_tz := btrim(COALESCE(p_timezone, ''));
  IF v_tz = '' OR char_length(v_tz) > 100 THEN
    RAISE EXCEPTION 'invalid_timezone' USING ERRCODE = '22023';
  END IF;

  IF p_preferred_locale IS NOT NULL AND btrim(p_preferred_locale) <> '' THEN
    v_pref := btrim(p_preferred_locale);
    IF v_pref NOT IN ('vi', 'en') THEN
      RAISE EXCEPTION 'invalid_preferred_locale' USING ERRCODE = '22023';
    END IF;
    UPDATE public.app_user u
    SET preferred_locale = v_pref
    WHERE u.id = public.current_app_user_id()
      AND u.organization_id = v_org_id;
  END IF;

  UPDATE public.organization o
  SET
    name = v_name,
    default_locale = v_locale,
    timezone = v_tz,
    setup_completed_at = now()
  WHERE o.id = v_org_id;

  RETURN jsonb_build_object(
    'organization_id', v_org_id,
    'setup_completed_at', (SELECT setup_completed_at FROM public.organization WHERE id = v_org_id),
    'allows_normal_use', public.organization_subscription_allows_normal_use(v_org_id)
  );
END;
$$;

COMMENT ON FUNCTION public.complete_center_setup(text, text, text, text) IS
  'Primary Owner completes first-use center profile; bypasses commercial RBAC gate during provisioning.';

REVOKE ALL ON FUNCTION public.organization_center_setup_complete(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.organization_center_setup_complete(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.organization_subscription_allows_owner_setup(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.organization_subscription_allows_owner_setup(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.requires_center_setup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.requires_center_setup() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.fetch_owner_center_setup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_owner_center_setup() TO authenticated;

REVOKE ALL ON FUNCTION public.complete_center_setup(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_center_setup(text, text, text, text) TO authenticated;
