-- M7-T03: Provider-neutral commercial plan, organization subscription, entitlement sync.

-- =============================================================================
-- COMMERCIAL PLAN (global catalog)
-- =============================================================================

CREATE TABLE public.commercial_plan (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL,
  name         text NOT NULL,
  staff_limit  integer NOT NULL,
  status       text NOT NULL DEFAULT 'active',
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT commercial_plan_code_unique UNIQUE (code),
  CONSTRAINT commercial_plan_staff_limit_check CHECK (staff_limit >= 0),
  CONSTRAINT commercial_plan_status_check CHECK (status IN ('active', 'archived'))
);

CREATE TRIGGER commercial_plan_updated_at
  BEFORE UPDATE ON public.commercial_plan
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.commercial_plan IS
  'Operator-managed commercial package definitions. No pricing or billing-provider fields.';

INSERT INTO public.commercial_plan (code, name, staff_limit, status)
VALUES ('base', 'Base center', 5, 'active')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- ORGANIZATION SUBSCRIPTION (one row per organization)
-- =============================================================================

CREATE TABLE public.organization_subscription (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  commercial_plan_id  uuid NOT NULL REFERENCES public.commercial_plan (id) ON DELETE RESTRICT,
  status              text NOT NULL,
  activated_at        timestamptz,
  suspended_at        timestamptz,
  cancelled_at        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organization_subscription_organization_unique UNIQUE (organization_id),
  CONSTRAINT organization_subscription_status_check CHECK (
    status IN ('provisioning', 'active', 'suspended', 'cancelled')
  )
);

CREATE INDEX idx_organization_subscription_plan
  ON public.organization_subscription (commercial_plan_id);

CREATE INDEX idx_organization_subscription_status
  ON public.organization_subscription (status);

CREATE TRIGGER organization_subscription_updated_at
  BEFORE UPDATE ON public.organization_subscription
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.organization_subscription IS
  'Center commercial lifecycle. Independent from organization.status operational kill switch.';

-- =============================================================================
-- ENTITLEMENT LINKAGE (runtime authority remains organization_entitlement)
-- =============================================================================

ALTER TABLE public.organization_entitlement
  ADD COLUMN commercial_plan_id uuid REFERENCES public.commercial_plan (id) ON DELETE RESTRICT,
  ADD COLUMN organization_subscription_id uuid REFERENCES public.organization_subscription (id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.protect_entitlement_commercial_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('olli.trusted_entitlement_sync', true) = 'true' THEN
    RETURN NEW;
  END IF;

  -- Local SQL tests and dev seed fixtures run as postgres superuser.
  IF current_user = 'postgres' THEN
    RETURN NEW;
  END IF;

  IF NEW.staff_limit IS DISTINCT FROM OLD.staff_limit
     OR NEW.commercial_plan_id IS DISTINCT FROM OLD.commercial_plan_id
     OR NEW.organization_subscription_id IS DISTINCT FROM OLD.organization_subscription_id THEN
    RAISE EXCEPTION 'entitlement_commercial_fields_managed_by_subscription';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER organization_entitlement_protect_commercial_fields
  BEFORE UPDATE ON public.organization_entitlement
  FOR EACH ROW EXECUTE FUNCTION public.protect_entitlement_commercial_fields();

-- =============================================================================
-- INTERNAL: ENTITLEMENT SYNC
-- =============================================================================

CREATE OR REPLACE FUNCTION public._m7_get_base_commercial_plan_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.commercial_plan WHERE code = 'base' AND status = 'active' LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._m7_sync_entitlement_from_subscription(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.organization_subscription%ROWTYPE;
  v_plan public.commercial_plan%ROWTYPE;
BEGIN
  SELECT os.* INTO v_sub
  FROM public.organization_subscription os
  WHERE os.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription_missing';
  END IF;

  SELECT cp.* INTO v_plan
  FROM public.commercial_plan cp
  WHERE cp.id = v_sub.commercial_plan_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_missing';
  END IF;

  PERFORM set_config('olli.trusted_entitlement_sync', 'true', true);

  UPDATE public.organization_entitlement oe
  SET
    commercial_plan_id = v_plan.id,
    organization_subscription_id = v_sub.id,
    staff_limit = CASE
      WHEN v_sub.status = 'cancelled' THEN oe.staff_limit
      ELSE v_plan.staff_limit
    END
  WHERE oe.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entitlement_missing';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._m7_assert_subscription_transition(
  p_from text,
  p_to text
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_from = p_to THEN
    RETURN;
  END IF;

  IF p_from = 'provisioning' AND p_to IN ('active', 'cancelled') THEN
    RETURN;
  END IF;

  IF p_from = 'active' AND p_to IN ('suspended', 'cancelled') THEN
    RETURN;
  END IF;

  IF p_from = 'suspended' AND p_to IN ('active', 'cancelled') THEN
    RETURN;
  END IF;

  RAISE EXCEPTION 'invalid_subscription_transition';
END;
$$;

CREATE OR REPLACE FUNCTION public._m7_initialize_organization_subscription(
  p_organization_id uuid,
  p_initial_status text DEFAULT 'provisioning'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan_id uuid;
  v_sub_id uuid;
  v_now timestamptz := now();
BEGIN
  IF p_initial_status NOT IN ('provisioning', 'active') THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  v_plan_id := public._m7_get_base_commercial_plan_id();
  IF v_plan_id IS NULL THEN
    RAISE EXCEPTION 'base_plan_missing';
  END IF;

  INSERT INTO public.organization_subscription (
    organization_id,
    commercial_plan_id,
    status,
    activated_at
  ) VALUES (
    p_organization_id,
    v_plan_id,
    p_initial_status,
    CASE WHEN p_initial_status = 'active' THEN v_now ELSE NULL END
  )
  ON CONFLICT (organization_id) DO NOTHING
  RETURNING id INTO v_sub_id;

  IF v_sub_id IS NULL THEN
    SELECT os.id INTO v_sub_id
    FROM public.organization_subscription os
    WHERE os.organization_id = p_organization_id;
  END IF;

  PERFORM public._m7_sync_entitlement_from_subscription(p_organization_id);
  RETURN v_sub_id;
END;
$$;

-- =============================================================================
-- OPERATOR RPCs (service_role)
-- =============================================================================

CREATE OR REPLACE FUNCTION public._m7_operator_load_subscription(
  p_organization_id uuid
)
RETURNS public.organization_subscription
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.organization_subscription%ROWTYPE;
BEGIN
  IF p_organization_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.organization o WHERE o.id = p_organization_id) THEN
    RAISE EXCEPTION 'organization_not_found';
  END IF;

  SELECT os.* INTO v_sub
  FROM public.organization_subscription os
  WHERE os.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription_missing';
  END IF;

  RETURN v_sub;
END;
$$;

CREATE OR REPLACE FUNCTION public._m7_operator_resolve_plan(p_plan_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan_id uuid;
BEGIN
  SELECT cp.id INTO v_plan_id
  FROM public.commercial_plan cp
  WHERE cp.code = NULLIF(btrim(p_plan_code), '')
    AND cp.status = 'active';

  IF v_plan_id IS NULL THEN
    RAISE EXCEPTION 'plan_not_found';
  END IF;

  RETURN v_plan_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_organization_subscription(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.organization_subscription%ROWTYPE;
BEGIN
  v_sub := public._m7_operator_load_subscription(p_organization_id);
  PERFORM public._m7_assert_subscription_transition(v_sub.status, 'active');

  UPDATE public.organization_subscription os
  SET
    status = 'active',
    activated_at = COALESCE(os.activated_at, now()),
    suspended_at = NULL
  WHERE os.id = v_sub.id
  RETURNING * INTO v_sub;

  PERFORM public._m7_sync_entitlement_from_subscription(p_organization_id);

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'subscription_id', v_sub.id,
    'status', v_sub.status,
    'commercial_plan_id', v_sub.commercial_plan_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.suspend_organization_subscription(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.organization_subscription%ROWTYPE;
BEGIN
  v_sub := public._m7_operator_load_subscription(p_organization_id);
  PERFORM public._m7_assert_subscription_transition(v_sub.status, 'suspended');

  UPDATE public.organization_subscription os
  SET status = 'suspended', suspended_at = now()
  WHERE os.id = v_sub.id
  RETURNING * INTO v_sub;

  PERFORM public._m7_sync_entitlement_from_subscription(p_organization_id);

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'subscription_id', v_sub.id,
    'status', v_sub.status
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reactivate_organization_subscription(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.organization_subscription%ROWTYPE;
BEGIN
  v_sub := public._m7_operator_load_subscription(p_organization_id);
  PERFORM public._m7_assert_subscription_transition(v_sub.status, 'active');

  UPDATE public.organization_subscription os
  SET status = 'active', suspended_at = NULL
  WHERE os.id = v_sub.id
  RETURNING * INTO v_sub;

  PERFORM public._m7_sync_entitlement_from_subscription(p_organization_id);

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'subscription_id', v_sub.id,
    'status', v_sub.status
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_organization_subscription(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.organization_subscription%ROWTYPE;
BEGIN
  v_sub := public._m7_operator_load_subscription(p_organization_id);
  PERFORM public._m7_assert_subscription_transition(v_sub.status, 'cancelled');

  UPDATE public.organization_subscription os
  SET status = 'cancelled', cancelled_at = now()
  WHERE os.id = v_sub.id
  RETURNING * INTO v_sub;

  PERFORM public._m7_sync_entitlement_from_subscription(p_organization_id);

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'subscription_id', v_sub.id,
    'status', v_sub.status
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.change_organization_commercial_plan(
  p_organization_id uuid,
  p_plan_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub public.organization_subscription%ROWTYPE;
  v_plan_id uuid;
  v_staff_limit integer;
BEGIN
  v_sub := public._m7_operator_load_subscription(p_organization_id);
  v_plan_id := public._m7_operator_resolve_plan(p_plan_code);

  IF v_sub.status = 'cancelled' THEN
    RAISE EXCEPTION 'subscription_cancelled';
  END IF;

  UPDATE public.organization_subscription os
  SET commercial_plan_id = v_plan_id
  WHERE os.id = v_sub.id
  RETURNING * INTO v_sub;

  PERFORM public._m7_sync_entitlement_from_subscription(p_organization_id);

  SELECT oe.staff_limit INTO v_staff_limit
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = p_organization_id;

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'subscription_id', v_sub.id,
    'status', v_sub.status,
    'commercial_plan_id', v_sub.commercial_plan_id,
    'staff_limit', v_staff_limit
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.resync_organization_entitlement(p_organization_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff_limit integer;
BEGIN
  PERFORM public._m7_sync_entitlement_from_subscription(p_organization_id);

  SELECT oe.staff_limit INTO v_staff_limit
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = p_organization_id;

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'staff_limit', v_staff_limit
  );
END;
$$;

-- =============================================================================
-- OWNER READ (authenticated primary Owner)
-- =============================================================================

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
  IF NOT public.is_primary_owner() THEN
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

-- =============================================================================
-- BACKFILL EXISTING ORGANIZATIONS (active commercial state, staff_limit unchanged)
-- =============================================================================

DO $$
DECLARE
  org_record record;
BEGIN
  FOR org_record IN SELECT id FROM public.organization LOOP
    PERFORM public._m7_initialize_organization_subscription(org_record.id, 'active');
  END LOOP;
END;
$$;

-- =============================================================================
-- T02 FINALIZE: initialize commercial subscription (provisioning)
-- =============================================================================

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
-- RLS / GRANTS
-- =============================================================================

ALTER TABLE public.commercial_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commercial_plan FORCE ROW LEVEL SECURITY;

ALTER TABLE public.organization_subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_subscription FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.commercial_plan FROM PUBLIC;
REVOKE ALL ON TABLE public.commercial_plan FROM anon, authenticated;
GRANT SELECT ON TABLE public.commercial_plan TO service_role;

REVOKE ALL ON TABLE public.organization_subscription FROM PUBLIC;
REVOKE ALL ON TABLE public.organization_subscription FROM anon, authenticated;
GRANT ALL ON TABLE public.organization_subscription TO service_role;

REVOKE ALL ON FUNCTION public._m7_sync_entitlement_from_subscription(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m7_initialize_organization_subscription(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m7_assert_subscription_transition(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m7_operator_load_subscription(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m7_operator_resolve_plan(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m7_get_base_commercial_plan_id() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.activate_organization_subscription(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.activate_organization_subscription(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_organization_subscription(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.suspend_organization_subscription(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.suspend_organization_subscription(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.suspend_organization_subscription(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.reactivate_organization_subscription(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reactivate_organization_subscription(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reactivate_organization_subscription(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.cancel_organization_subscription(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_organization_subscription(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_organization_subscription(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.change_organization_commercial_plan(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.change_organization_commercial_plan(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.change_organization_commercial_plan(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.resync_organization_entitlement(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resync_organization_entitlement(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resync_organization_entitlement(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.fetch_owner_commercial_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_owner_commercial_status() TO authenticated;
