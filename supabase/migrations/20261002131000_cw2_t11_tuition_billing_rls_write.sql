-- CW2-T11: Allow authoritative tuition billing writes (Accounting confirm + test fixtures).

CREATE POLICY enrollment_financial_terms_cw2_declare_select ON public.enrollment_financial_terms
  FOR SELECT
  TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.declare')
  );

CREATE OR REPLACE FUNCTION public.protect_enrollment_financial_terms_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('cw2.authoritative_tuition_establishment', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status = 'active' THEN
    IF NEW.agreed_tuition_amount IS DISTINCT FROM OLD.agreed_tuition_amount
       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.net_tuition_amount IS DISTINCT FROM OLD.net_tuition_amount
       OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
       OR NEW.payment_plan_mode IS DISTINCT FROM OLD.payment_plan_mode
       OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id
    THEN
      RAISE EXCEPTION 'Active enrollment financial terms cannot be silently rewritten; use financial_adjustment for corrections';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status IN ('superseded', 'cancelled') THEN
    IF NEW.agreed_tuition_amount IS DISTINCT FROM OLD.agreed_tuition_amount
       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.net_tuition_amount IS DISTINCT FROM OLD.net_tuition_amount
       OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
       OR NEW.payment_plan_mode IS DISTINCT FROM OLD.payment_plan_mode
       OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id
       OR NEW.status IS DISTINCT FROM OLD.status
    THEN
      RAISE EXCEPTION 'Historical enrollment financial terms are immutable';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_is_teacher_only_app_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role ur
    JOIN public.role r ON r.id = ur.role_id AND r.organization_id = ur.organization_id
    WHERE ur.organization_id = public.current_organization_id()
      AND ur.user_id = public.current_app_user_id()
      AND ur.status = 'active'
      AND r.canonical_code = 'teacher'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.user_role ur
    JOIN public.role r ON r.id = ur.role_id AND r.organization_id = ur.organization_id
    WHERE ur.organization_id = public.current_organization_id()
      AND ur.user_id = public.current_app_user_id()
      AND ur.status = 'active'
      AND r.canonical_code IN (
        'academic_operations', 'accountant', 'consultant', 'center_manager', 'owner'
      )
  );
$$;

CREATE OR REPLACE FUNCTION public._cw2_can_read_periodic_finance_tables()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT public.is_active_app_user()
    AND (
      public.has_permission('consultant_revenue.review')
      OR public.has_permission('consultant_revenue.declare')
      OR public.has_permission('charge.read')
      OR (
        public.has_permission('enrollment.read')
        AND EXISTS (
          SELECT 1
          FROM public.user_role ur
          JOIN public.role r ON r.id = ur.role_id AND r.organization_id = ur.organization_id
          WHERE ur.organization_id = public.current_organization_id()
            AND ur.user_id = public.current_app_user_id()
            AND ur.status = 'active'
            AND r.canonical_code IN (
              'academic_operations', 'accountant', 'consultant', 'center_manager', 'owner'
            )
        )
      )
    );
$$;

REVOKE ALL ON FUNCTION public._cw2_is_teacher_only_app_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_can_read_periodic_finance_tables() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cw2_is_teacher_only_app_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public._cw2_can_read_periodic_finance_tables() TO authenticated;

CREATE POLICY enrollment_tuition_billing_insert ON public.enrollment_tuition_billing
  FOR INSERT
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND (
      public.has_permission('consultant_revenue.review')
      OR public.has_permission('charge.create')
    )
  );

CREATE POLICY enrollment_tuition_billing_update ON public.enrollment_tuition_billing
  FOR UPDATE
  USING (organization_id = public.current_organization_id())
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.review')
  );

DROP POLICY IF EXISTS enrollment_tuition_billing_select ON public.enrollment_tuition_billing;
CREATE POLICY enrollment_tuition_billing_select ON public.enrollment_tuition_billing
  FOR SELECT
  USING (
    organization_id = public.current_organization_id()
    AND public._cw2_can_read_periodic_finance_tables()
  );

DROP POLICY IF EXISTS enrollment_periodic_balance_select ON public.enrollment_periodic_tuition_balance;
CREATE POLICY enrollment_periodic_balance_select ON public.enrollment_periodic_tuition_balance
  FOR SELECT
  USING (
    organization_id = public.current_organization_id()
    AND public._cw2_can_read_periodic_finance_tables()
  );

DROP POLICY IF EXISTS enrollment_periodic_obligation_select ON public.enrollment_periodic_period_obligation;
CREATE POLICY enrollment_periodic_obligation_select ON public.enrollment_periodic_period_obligation
  FOR SELECT
  USING (
    organization_id = public.current_organization_id()
    AND public._cw2_can_read_periodic_finance_tables()
  );

DROP POLICY IF EXISTS enrollment_periodic_consumption_select ON public.enrollment_periodic_session_consumption;
CREATE POLICY enrollment_periodic_consumption_select ON public.enrollment_periodic_session_consumption
  FOR SELECT
  USING (
    organization_id = public.current_organization_id()
    AND public._cw2_can_read_periodic_finance_tables()
  );

DROP POLICY IF EXISTS enrollment_periodic_balance_write ON public.enrollment_periodic_tuition_balance;
DROP POLICY IF EXISTS enrollment_periodic_obligation_write ON public.enrollment_periodic_period_obligation;
DROP POLICY IF EXISTS enrollment_periodic_consumption_write ON public.enrollment_periodic_session_consumption;
DROP POLICY IF EXISTS enrollment_periodic_consumption_update ON public.enrollment_periodic_session_consumption;

DROP FUNCTION IF EXISTS public._cw2_periodic_rls_allows_org(uuid);
DROP FUNCTION IF EXISTS public._cw2_periodic_internal_enter(uuid);
DROP FUNCTION IF EXISTS public._cw2_periodic_internal_leave();
DROP FUNCTION IF EXISTS public._cw2_periodic_internal_depth();
DROP FUNCTION IF EXISTS public._cw2_periodic_internal_org();

REVOKE ALL ON FUNCTION public._cw2_periodic_try_consume_session(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_reverse_session_consumption(uuid, uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_ensure_obligation(uuid, uuid, text, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_apply_confirmed_payment(uuid, uuid, bigint, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_periodic_activate_period_from_session(uuid, uuid, date, public.enrollment_tuition_billing) FROM PUBLIC;

CREATE POLICY organization_academic_year_write ON public.organization_academic_year
  FOR ALL
  USING (organization_id = public.current_organization_id())
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND public.has_permission('charge.create')
  );

CREATE OR REPLACE FUNCTION public.can_view_roster_operational_tuition()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT public.is_active_app_user()
    AND public.has_permission('enrollment.read')
    AND NOT (
      EXISTS (
        SELECT 1
        FROM public.user_role ur
        JOIN public.role r ON r.id = ur.role_id AND r.organization_id = ur.organization_id
        WHERE ur.organization_id = public.current_organization_id()
          AND ur.user_id = public.current_app_user_id()
          AND ur.status = 'active'
          AND r.canonical_code = 'teacher'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_role ur
        JOIN public.role r ON r.id = ur.role_id AND r.organization_id = ur.organization_id
        WHERE ur.organization_id = public.current_organization_id()
          AND ur.user_id = public.current_app_user_id()
          AND ur.status = 'active'
          AND r.canonical_code IN (
            'academic_operations', 'accountant', 'consultant', 'center_manager', 'owner'
          )
      )
    );
$$;

REVOKE ALL ON FUNCTION public.can_view_roster_operational_tuition() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_roster_operational_tuition() TO authenticated;
