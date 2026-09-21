-- M6-T02: test SQL fixtures are psql/postgres-only; not invokable via PostgREST authenticated role.

REVOKE EXECUTE ON FUNCTION public.test_fixture_insert_app_user(uuid, text, text, uuid, text, text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.test_fixture_grant_all_permissions_role(uuid, uuid, text) FROM authenticated;

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
  -- PostgREST uses login role `authenticator`; direct psql uses `postgres`.
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

REVOKE ALL ON FUNCTION public.test_fixture_insert_app_user(uuid, text, text, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.test_fixture_insert_app_user(uuid, text, text, uuid, text, text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.test_fixture_grant_all_permissions_role(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.test_fixture_grant_all_permissions_role(uuid, uuid, text) FROM anon, authenticated;
