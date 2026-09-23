-- M7-T02: Trusted center + primary Owner provisioning (operator/service_role only).

-- =============================================================================
-- CENTER PROVISIONING REQUEST (durable idempotency; no org until finalize)
-- =============================================================================

CREATE TABLE public.center_provisioning_request (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key                 text NOT NULL,
  payload_fingerprint             text NOT NULL,
  organization_name               text NOT NULL,
  default_locale                  text NOT NULL DEFAULT 'vi',
  timezone                        text NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
  currency_code                   text NOT NULL DEFAULT 'VND',
  owner_normalized_email          text NOT NULL,
  owner_display_name              text NOT NULL,
  owner_preferred_locale          text NOT NULL DEFAULT 'vi',
  status                          text NOT NULL,
  auth_user_id                    uuid,
  auth_created_by_this_request    boolean NOT NULL DEFAULT false,
  organization_id                 uuid REFERENCES public.organization (id) ON DELETE RESTRICT,
  owner_app_user_id               uuid,
  result_code                     text,
  created_at                      timestamptz NOT NULL DEFAULT now(),
  updated_at                      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT center_provisioning_request_idempotency_unique UNIQUE (idempotency_key),
  CONSTRAINT center_provisioning_request_status_check CHECK (
    status IN (
      'pending_auth',
      'auth_created',
      'completed',
      'failed',
      'compensation_pending',
      'compensated',
      'reconciliation_required'
    )
  ),
  CONSTRAINT center_provisioning_request_locale_check CHECK (
    default_locale IN ('vi', 'en')
    AND owner_preferred_locale IN ('vi', 'en')
  ),
  CONSTRAINT center_provisioning_request_org_owner_fk
    FOREIGN KEY (organization_id, owner_app_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_center_provisioning_request_status
  ON public.center_provisioning_request (status);

CREATE INDEX idx_center_provisioning_request_owner_email
  ON public.center_provisioning_request (owner_normalized_email);

CREATE TRIGGER center_provisioning_request_updated_at
  BEFORE UPDATE ON public.center_provisioning_request
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE public.center_provisioning_request IS
  'Trusted center provisioning state. Organization row is created only on successful finalize after Auth identity exists.';

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._m7_center_provisioning_payload_fingerprint(
  p_organization_name text,
  p_owner_email text,
  p_owner_display_name text,
  p_owner_preferred_locale text,
  p_default_locale text,
  p_timezone text,
  p_currency_code text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT md5(
    concat_ws(
      '|',
      btrim(p_organization_name),
      public.normalize_email_key(p_owner_email),
      btrim(p_owner_display_name),
      COALESCE(p_owner_preferred_locale, 'vi'),
      COALESCE(p_default_locale, 'vi'),
      COALESCE(btrim(p_timezone), 'Asia/Ho_Chi_Minh'),
      COALESCE(btrim(p_currency_code), 'VND')
    )
  );
$$;

CREATE OR REPLACE FUNCTION public._m7_center_provisioning_to_json(
  p_row public.center_provisioning_request
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'request_id', p_row.id,
    'status', p_row.status,
    'idempotency_key', p_row.idempotency_key,
    'organization_name', p_row.organization_name,
    'owner_normalized_email', p_row.owner_normalized_email,
    'auth_user_id', p_row.auth_user_id,
    'organization_id', p_row.organization_id,
    'owner_app_user_id', p_row.owner_app_user_id,
    'result_code', p_row.result_code
  );
$$;

CREATE OR REPLACE FUNCTION public._m7_assign_center_manager_to_primary_owner(
  p_organization_id uuid,
  p_app_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_primary uuid;
  v_role_id uuid;
BEGIN
  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = p_organization_id;

  IF v_primary IS NULL OR v_primary IS DISTINCT FROM p_app_user_id THEN
    RAISE EXCEPTION 'primary_owner_mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.id = p_app_user_id
      AND u.organization_id = p_organization_id
      AND u.membership_status = 'member'
  ) THEN
    RAISE EXCEPTION 'invalid_target_user';
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.role r
  WHERE r.organization_id = p_organization_id
    AND r.is_canonical_template
    AND r.canonical_code = 'center_manager'
    AND r.status = 'active';

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'canonical_role_missing';
  END IF;

  UPDATE public.user_role ur
  SET
    status = 'ended',
    effective_to = CURRENT_DATE,
    updated_at = now()
  FROM public.role r
  WHERE ur.role_id = r.id
    AND ur.organization_id = p_organization_id
    AND ur.user_id = p_app_user_id
    AND ur.status = 'active'
    AND r.is_canonical_template;

  INSERT INTO public.user_role (
    organization_id,
    user_id,
    role_id,
    effective_from,
    status
  ) VALUES (
    p_organization_id,
    p_app_user_id,
    v_role_id,
    CURRENT_DATE,
    'active'
  );

  RETURN v_role_id;
END;
$$;

-- =============================================================================
-- BEGIN (service_role)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.begin_center_provisioning(
  p_idempotency_key text,
  p_organization_name text,
  p_owner_email text,
  p_owner_display_name text,
  p_owner_preferred_locale text DEFAULT 'vi',
  p_default_locale text DEFAULT 'vi',
  p_timezone text DEFAULT 'Asia/Ho_Chi_Minh',
  p_currency_code text DEFAULT 'VND'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
  v_name text;
  v_email text;
  v_display text;
  v_fingerprint text;
  v_row public.center_provisioning_request%ROWTYPE;
BEGIN
  v_key := NULLIF(btrim(p_idempotency_key), '');
  v_name := NULLIF(btrim(p_organization_name), '');
  v_email := public.normalize_email_key(p_owner_email);
  v_display := NULLIF(btrim(p_owner_display_name), '');

  IF v_key IS NULL OR v_name IS NULL OR v_email IS NULL OR v_display IS NULL THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  IF p_owner_preferred_locale IS NOT NULL AND p_owner_preferred_locale NOT IN ('vi', 'en') THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  IF p_default_locale IS NOT NULL AND p_default_locale NOT IN ('vi', 'en') THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  v_fingerprint := public._m7_center_provisioning_payload_fingerprint(
    v_name,
    v_email,
    v_display,
    COALESCE(p_owner_preferred_locale, 'vi'),
    COALESCE(p_default_locale, 'vi'),
    COALESCE(p_timezone, 'Asia/Ho_Chi_Minh'),
    COALESCE(p_currency_code, 'VND')
  );

  SELECT * INTO v_row
  FROM public.center_provisioning_request cpr
  WHERE cpr.idempotency_key = v_key;

  IF FOUND THEN
    IF v_row.payload_fingerprint IS DISTINCT FROM v_fingerprint THEN
      RAISE EXCEPTION 'idempotency_conflict';
    END IF;
    IF v_row.status = 'completed' THEN
      RETURN public._m7_center_provisioning_to_json(v_row)
        || jsonb_build_object('outcome', 'completed');
    END IF;
    RETURN public._m7_center_provisioning_to_json(v_row)
      || jsonb_build_object('outcome', 'resume');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.center_provisioning_request cpr
    WHERE cpr.owner_normalized_email = v_email
      AND cpr.status = 'completed'
      AND cpr.idempotency_key <> v_key
  ) THEN
    RAISE EXCEPTION 'owner_email_already_provisioned';
  END IF;

  INSERT INTO public.center_provisioning_request (
    idempotency_key,
    payload_fingerprint,
    organization_name,
    default_locale,
    timezone,
    currency_code,
    owner_normalized_email,
    owner_display_name,
    owner_preferred_locale,
    status
  ) VALUES (
    v_key,
    v_fingerprint,
    v_name,
    COALESCE(p_default_locale, 'vi'),
    COALESCE(p_timezone, 'Asia/Ho_Chi_Minh'),
    COALESCE(p_currency_code, 'VND'),
    v_email,
    v_display,
    COALESCE(p_owner_preferred_locale, 'vi'),
    'pending_auth'
  )
  RETURNING * INTO v_row;

  RETURN public._m7_center_provisioning_to_json(v_row)
    || jsonb_build_object('outcome', 'started');
END;
$$;

-- =============================================================================
-- RECORD AUTH (service_role)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.record_center_provisioning_auth_created(
  p_request_id uuid,
  p_auth_user_id uuid,
  p_auth_created_by_this_request boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.center_provisioning_request%ROWTYPE;
BEGIN
  IF p_request_id IS NULL OR p_auth_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  SELECT * INTO v_row
  FROM public.center_provisioning_request cpr
  WHERE cpr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF v_row.status = 'completed' THEN
    RETURN public._m7_center_provisioning_to_json(v_row)
      || jsonb_build_object('outcome', 'completed');
  END IF;

  IF v_row.status NOT IN ('pending_auth', 'auth_created') THEN
    RAISE EXCEPTION 'invalid_request_state';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.auth_user_id = p_auth_user_id
      AND (
        v_row.owner_app_user_id IS NULL
        OR u.id IS DISTINCT FROM v_row.owner_app_user_id
      )
  ) THEN
    UPDATE public.center_provisioning_request cpr
    SET status = 'compensation_pending', result_code = 'identity_conflict'
    WHERE cpr.id = p_request_id;
    RAISE EXCEPTION 'identity_conflict';
  END IF;

  UPDATE public.center_provisioning_request cpr
  SET
    auth_user_id = p_auth_user_id,
    auth_created_by_this_request = COALESCE(p_auth_created_by_this_request, true),
    status = 'auth_created',
    result_code = NULL
  WHERE cpr.id = p_request_id
  RETURNING * INTO v_row;

  RETURN public._m7_center_provisioning_to_json(v_row)
    || jsonb_build_object('outcome', 'auth_created');
END;
$$;

-- =============================================================================
-- FINALIZE (service_role) — creates organization graph in one transaction
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

CREATE OR REPLACE FUNCTION public.mark_center_provisioning_compensated(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.center_provisioning_request cpr
  SET status = 'compensated', result_code = 'compensated'
  WHERE cpr.id = p_request_id
    AND cpr.status IN ('compensation_pending', 'failed', 'pending_auth', 'auth_created');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_center_provisioning_reconciliation_required(
  p_request_id uuid,
  p_result_code text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.center_provisioning_request cpr
  SET status = 'reconciliation_required', result_code = COALESCE(p_result_code, 'reconciliation_required')
  WHERE cpr.id = p_request_id;
END;
$$;

-- =============================================================================
-- RLS: operator tables not exposed to authenticated
-- =============================================================================

ALTER TABLE public.center_provisioning_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.center_provisioning_request FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.center_provisioning_request FROM PUBLIC;
REVOKE ALL ON TABLE public.center_provisioning_request FROM anon, authenticated;
GRANT ALL ON TABLE public.center_provisioning_request TO service_role;

REVOKE ALL ON FUNCTION public.begin_center_provisioning(text, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.begin_center_provisioning(text, text, text, text, text, text, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.begin_center_provisioning(text, text, text, text, text, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.record_center_provisioning_auth_created(uuid, uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_center_provisioning_auth_created(uuid, uuid, boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_center_provisioning_auth_created(uuid, uuid, boolean) TO service_role;

REVOKE ALL ON FUNCTION public.finalize_center_provisioning(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finalize_center_provisioning(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_center_provisioning(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.mark_center_provisioning_compensated(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_center_provisioning_compensated(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_center_provisioning_compensated(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.mark_center_provisioning_reconciliation_required(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_center_provisioning_reconciliation_required(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_center_provisioning_reconciliation_required(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public._m7_assign_center_manager_to_primary_owner(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m7_assign_center_manager_to_primary_owner(uuid, uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public._m7_center_provisioning_payload_fingerprint(text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m7_center_provisioning_to_json(public.center_provisioning_request) FROM PUBLIC;
