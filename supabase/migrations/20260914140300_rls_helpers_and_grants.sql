-- M0-T04: Security helper functions and table grants.

-- =============================================================================
-- SECURITY HELPER FUNCTIONS (SECURITY DEFINER, fixed search_path)
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
  WHERE u.auth_user_id = auth.uid()
    AND u.status = 'active'
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
  WHERE u.auth_user_id = auth.uid()
    AND u.status = 'active'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.has_permission(p_code text)
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
    WHERE u.auth_user_id = auth.uid()
      AND u.status = 'active'
      AND ur.status = 'active'
      AND ur.effective_from <= CURRENT_DATE
      AND (ur.effective_to IS NULL OR ur.effective_to >= CURRENT_DATE)
      AND r.status = 'active'
      AND p.code = p_code
  );
$$;

CREATE OR REPLACE FUNCTION public.is_active_app_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.current_app_user_id() IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION public.current_app_user_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_organization_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.has_permission(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_active_app_user() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.current_app_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_organization_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_permission(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_app_user() TO authenticated;

-- Defense in depth for app_user sensitive field changes.
CREATE OR REPLACE FUNCTION public.protect_app_user_sensitive_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('olli.bypass_app_user_guard', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF public.has_permission('user.manage') THEN
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

  RETURN NEW;
END;
$$;

CREATE TRIGGER app_user_protect_sensitive_fields
  BEFORE UPDATE ON app_user
  FOR EACH ROW EXECUTE FUNCTION public.protect_app_user_sensitive_fields();

-- =============================================================================
-- GRANTS: deny anon; authenticated receives DML gated by RLS
-- =============================================================================

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM authenticated;

GRANT SELECT, INSERT, UPDATE ON
  organization,
  app_user,
  role,
  role_permission,
  user_role,
  permission,
  observation_indicator,
  student,
  guardian,
  student_guardian,
  teacher,
  course,
  class,
  class_schedule,
  enrollment,
  class_teacher_assignment,
  teaching_session,
  attendance,
  assessment,
  assessment_result,
  teacher_observation,
  observation_rating,
  progress_evaluation,
  tuition_plan,
  charge,
  financial_adjustment,
  payment,
  payment_allocation,
  cost_group,
  expense_category,
  expense
TO authenticated;

GRANT SELECT ON charge_balance TO authenticated;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
