-- M6-T04: Owner center account administration read model

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

  RETURN jsonb_build_object(
    'staff_limit', v_staff_limit,
    'staff_seats_used', v_staff_seats_used,
    'primary_owner', v_primary_owner,
    'staff', v_staff
  );
END;
$$;

COMMENT ON FUNCTION public.fetch_center_account_administration() IS
  'Primary Owner only: entitlement, seat usage, primary owner summary, and member staff roster for /users.';

REVOKE ALL ON FUNCTION public.fetch_center_account_administration() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_center_account_administration() TO authenticated;
