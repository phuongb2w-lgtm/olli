-- M0-T06: narrowly scoped locale self-persistence for authenticated app users.

CREATE OR REPLACE FUNCTION public.set_own_preferred_locale(p_locale text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF p_locale NOT IN ('vi', 'en') THEN
    RAISE EXCEPTION 'Invalid locale: %', p_locale USING ERRCODE = '22023';
  END IF;

  v_user_id := public.current_app_user_id();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated as active app user';
  END IF;

  UPDATE public.app_user
  SET preferred_locale = p_locale,
      updated_at = now()
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'App user not found';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_own_preferred_locale(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_own_preferred_locale(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_own_preferred_locale(text) TO authenticated;

COMMENT ON FUNCTION public.set_own_preferred_locale(text) IS
  'Authenticated users may persist only their own preferred_locale (vi|en). No arbitrary user ID.';
