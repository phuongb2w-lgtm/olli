-- CW2: fix plpgsql loop variable shadowing in consultant code allocator helper.

CREATE OR REPLACE FUNCTION public._cw2_next_consultant_operational_code(p_organization_id uuid)
RETURNS char(2)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_high integer;
  v_next integer;
  v_candidate char(2);
BEGIN
  SELECT COALESCE(max(consultant_operational_code::integer), 1) INTO v_high
  FROM public.app_user
  WHERE organization_id = p_organization_id
    AND consultant_operational_code IS NOT NULL;

  IF v_high < 2 THEN
    v_high := 1;
  END IF;

  FOR v_next IN v_high + 1 .. 99 LOOP
    v_candidate := lpad(v_next::text, 2, '0');
    IF NOT EXISTS (
      SELECT 1 FROM public.app_user u
      WHERE u.organization_id = p_organization_id
        AND u.consultant_operational_code = v_candidate
    ) THEN
      RETURN v_candidate;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'consultant_operational_code_exhausted' USING ERRCODE = 'P0001';
END;
$$;
