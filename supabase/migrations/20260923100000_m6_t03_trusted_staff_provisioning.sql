-- M6-T03: Trusted staff provisioning — durable requests, execution claims, finalize pipeline.

-- =============================================================================
-- STAFF PROVISIONING REQUEST
-- =============================================================================

CREATE TABLE public.staff_provisioning_request (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                 uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  requesting_owner_app_user_id    uuid NOT NULL,
  idempotency_key                 text NOT NULL,
  payload_fingerprint             text NOT NULL,
  normalized_email                text NOT NULL,
  display_name                    text NOT NULL,
  canonical_role                  text NOT NULL,
  preferred_locale                text NOT NULL DEFAULT 'vi',
  status                          text NOT NULL,
  auth_user_id                    uuid,
  app_user_id                     uuid,
  auth_created_by_this_request    boolean NOT NULL DEFAULT false,
  processing_token                uuid,
  processing_started_at           timestamptz,
  lease_expires_at                timestamptz,
  result_code                     text,
  created_at                      timestamptz NOT NULL DEFAULT now(),
  updated_at                      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT staff_provisioning_request_idempotency_unique
    UNIQUE (organization_id, idempotency_key),
  CONSTRAINT staff_provisioning_request_status_check
    CHECK (status IN (
      'requested',
      'auth_pending',
      'auth_created',
      'membership_pending',
      'completed',
      'failed',
      'compensation_pending',
      'compensated',
      'reconciliation_required'
    )),
  CONSTRAINT staff_provisioning_request_canonical_role_check
    CHECK (canonical_role IN ('accountant', 'consultant', 'academic_operations', 'teacher')),
  CONSTRAINT staff_provisioning_request_locale_check
    CHECK (preferred_locale IN ('vi', 'en')),
  CONSTRAINT staff_provisioning_request_org_owner_fk
    FOREIGN KEY (organization_id, requesting_owner_app_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_staff_provisioning_request_org_status
  ON public.staff_provisioning_request (organization_id, status);

CREATE INDEX idx_staff_provisioning_request_auth_user
  ON public.staff_provisioning_request (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

CREATE TRIGGER staff_provisioning_request_updated_at
  BEFORE UPDATE ON public.staff_provisioning_request
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.staff_provisioning_request IS
  'Durable cross-system staff provisioning state. Authoritative intent for org, role, and Owner. No secrets stored.';

ALTER TABLE public.staff_provisioning_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_provisioning_request FORCE ROW LEVEL SECURITY;

CREATE POLICY staff_provisioning_request_select_primary_owner
  ON public.staff_provisioning_request
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.is_primary_owner()
  );

-- No direct authenticated INSERT/UPDATE; RPCs only.

-- =============================================================================
-- HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._m6_provisioning_lease_interval()
RETURNS interval
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT interval '5 minutes';
$$;

CREATE OR REPLACE FUNCTION public._m6_provisioning_payload_fingerprint(
  p_normalized_email text,
  p_display_name text,
  p_canonical_role text,
  p_preferred_locale text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT md5(
    coalesce(p_normalized_email, '') || '|'
    || coalesce(btrim(p_display_name), '') || '|'
    || coalesce(p_canonical_role, '') || '|'
    || coalesce(p_preferred_locale, 'vi')
  );
$$;

CREATE OR REPLACE FUNCTION public._m6_provisioning_staff_roles()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT ARRAY['accountant', 'consultant', 'academic_operations', 'teacher']::text[];
$$;

CREATE OR REPLACE FUNCTION public._m6_provisioning_assert_owner_for_org(
  p_organization_id uuid,
  p_owner_app_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.organization o
    JOIN public.organization_entitlement oe ON oe.organization_id = o.id
    JOIN public.app_user u
      ON u.organization_id = oe.organization_id
     AND u.id = oe.primary_app_user_id
    WHERE o.id = p_organization_id
      AND o.status = 'active'
      AND oe.primary_app_user_id = p_owner_app_user_id
      AND oe.primary_app_user_id = p_owner_app_user_id
      AND u.id = p_owner_app_user_id
      AND u.status = 'active'
      AND u.membership_status = 'member'
  ) THEN
    RAISE EXCEPTION 'not_primary_owner';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_assign_canonical_staff_role_internal(
  p_organization_id uuid,
  p_target_user_id uuid,
  p_canonical_code text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_id uuid;
  v_primary uuid;
  v_allowed text[] := public._m6_provisioning_staff_roles();
BEGIN
  IF p_canonical_code = ANY (v_allowed) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'invalid_canonical_code';
  END IF;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = p_organization_id;

  IF p_target_user_id = v_primary THEN
    RAISE EXCEPTION 'primary_owner_uses_center_manager_template';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.id = p_target_user_id
      AND u.organization_id = p_organization_id
      AND u.membership_status = 'member'
  ) THEN
    RAISE EXCEPTION 'invalid_target_user';
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.role r
  WHERE r.organization_id = p_organization_id
    AND r.is_canonical_template
    AND r.canonical_code = p_canonical_code
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
    AND ur.user_id = p_target_user_id
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
    p_target_user_id,
    v_role_id,
    CURRENT_DATE,
    'active'
  );

  RETURN v_role_id;
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_provisioning_check_duplicate_member(
  p_organization_id uuid,
  p_normalized_email text,
  p_exclude_app_user_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.app_user%ROWTYPE;
BEGIN
  SELECT * INTO v_existing
  FROM public.app_user u
  WHERE u.organization_id = p_organization_id
    AND lower(btrim(u.email)) = p_normalized_email
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF p_exclude_app_user_id IS NOT NULL AND v_existing.id = p_exclude_app_user_id THEN
    RETURN;
  END IF;

  IF v_existing.membership_status = 'removed' THEN
    RAISE EXCEPTION 'member_already_exists';
  END IF;

  IF v_existing.membership_status = 'member' THEN
    RAISE EXCEPTION 'member_already_exists';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._m6_provisioning_request_to_json(p_row public.staff_provisioning_request)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'request_id', p_row.id,
    'status', p_row.status,
    'organization_id', p_row.organization_id,
    'normalized_email', p_row.normalized_email,
    'display_name', p_row.display_name,
    'canonical_role', p_row.canonical_role,
    'preferred_locale', p_row.preferred_locale,
    'auth_user_id', p_row.auth_user_id,
    'app_user_id', p_row.app_user_id,
    'auth_created_by_this_request', p_row.auth_created_by_this_request,
    'result_code', p_row.result_code
  );
$$;

-- =============================================================================
-- BEGIN (AUTHENTICATED)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.begin_staff_provisioning(
  p_idempotency_key text,
  p_email text,
  p_display_name text,
  p_canonical_role text,
  p_preferred_locale text DEFAULT 'vi'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_owner_id uuid;
  v_normalized_email text;
  v_fingerprint text;
  v_row public.staff_provisioning_request%ROWTYPE;
  v_key text;
BEGIN
  IF NOT public.is_primary_owner() THEN
    RAISE EXCEPTION 'not_primary_owner';
  END IF;

  v_org_id := public.current_organization_id();
  v_owner_id := public.current_app_user_id();
  v_key := NULLIF(btrim(p_idempotency_key), '');

  IF v_key IS NULL OR NULLIF(btrim(p_email), '') IS NULL OR NULLIF(btrim(p_display_name), '') IS NULL THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  IF NOT (p_canonical_role = ANY (public._m6_provisioning_staff_roles())) THEN
    RAISE EXCEPTION 'invalid_role';
  END IF;

  IF p_preferred_locale IS NOT NULL AND p_preferred_locale NOT IN ('vi', 'en') THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  v_normalized_email := public.normalize_email_key(p_email);
  IF v_normalized_email IS NULL OR v_normalized_email = '' THEN
    RAISE EXCEPTION 'invalid_email';
  END IF;

  v_fingerprint := public._m6_provisioning_payload_fingerprint(
    v_normalized_email,
    p_display_name,
    p_canonical_role,
    COALESCE(p_preferred_locale, 'vi')
  );

  SELECT * INTO v_row
  FROM public.staff_provisioning_request spr
  WHERE spr.organization_id = v_org_id
    AND spr.idempotency_key = v_key;

  IF FOUND THEN
    IF v_row.payload_fingerprint IS DISTINCT FROM v_fingerprint THEN
      RAISE EXCEPTION 'idempotency_conflict';
    END IF;
    IF v_row.status = 'completed' THEN
      RETURN public._m6_provisioning_request_to_json(v_row)
        || jsonb_build_object('outcome', 'completed');
    END IF;
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object('outcome', 'resume');
  END IF;

  PERFORM public._m6_provisioning_check_duplicate_member(v_org_id, v_normalized_email);

  IF EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.auth_user_id IS NOT NULL
      AND lower(btrim(u.email)) = v_normalized_email
      AND u.organization_id <> v_org_id
      AND u.membership_status = 'member'
  ) THEN
    RAISE EXCEPTION 'identity_conflict';
  END IF;

  INSERT INTO public.staff_provisioning_request (
    organization_id,
    requesting_owner_app_user_id,
    idempotency_key,
    payload_fingerprint,
    normalized_email,
    display_name,
    canonical_role,
    preferred_locale,
    status
  ) VALUES (
    v_org_id,
    v_owner_id,
    v_key,
    v_fingerprint,
    v_normalized_email,
    btrim(p_display_name),
    p_canonical_role,
    COALESCE(p_preferred_locale, 'vi'),
    'requested'
  )
  RETURNING * INTO v_row;

  RETURN public._m6_provisioning_request_to_json(v_row)
    || jsonb_build_object('outcome', 'created');
END;
$$;

-- =============================================================================
-- CLAIM AUTH EXECUTION (AUTHENTICATED)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.claim_provisioning_auth_execution(
  p_request_id uuid,
  p_processing_token uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.staff_provisioning_request%ROWTYPE;
  v_new_token uuid;
  v_now timestamptz := now();
  v_lease interval := public._m6_provisioning_lease_interval();
BEGIN
  IF NOT public.is_primary_owner() THEN
    RAISE EXCEPTION 'not_primary_owner';
  END IF;

  SELECT * INTO v_row
  FROM public.staff_provisioning_request spr
  WHERE spr.id = p_request_id
    AND spr.organization_id = public.current_organization_id()
    AND spr.requesting_owner_app_user_id = public.current_app_user_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF v_row.status = 'completed' THEN
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object(
        'outcome', 'completed',
        'processing_token', v_row.processing_token,
        'lease_expires_at', v_row.lease_expires_at
      );
  END IF;

  IF v_row.status IN ('failed', 'compensated', 'reconciliation_required') THEN
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object('outcome', 'terminal', 'processing_token', NULL, 'lease_expires_at', NULL);
  END IF;

  IF v_row.processing_token IS NOT NULL
     AND v_row.lease_expires_at IS NOT NULL
     AND v_row.lease_expires_at > v_now
     AND (p_processing_token IS NULL OR p_processing_token IS DISTINCT FROM v_row.processing_token)
     AND NOT (
       v_row.auth_user_id IS NULL
       AND v_row.processing_started_at IS NOT NULL
       AND v_row.processing_started_at < v_now - interval '30 seconds'
     ) THEN
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object('outcome', 'provisioning_pending', 'processing_token', NULL, 'lease_expires_at', v_row.lease_expires_at);
  END IF;

  IF v_row.processing_token IS NOT NULL
     AND p_processing_token IS NOT NULL
     AND v_row.processing_token = p_processing_token
     AND v_row.lease_expires_at IS NOT NULL
     AND v_row.lease_expires_at > v_now THEN
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object(
        'outcome', 'claimed',
        'processing_token', v_row.processing_token,
        'lease_expires_at', v_row.lease_expires_at
      );
  END IF;

  v_new_token := gen_random_uuid();

  UPDATE public.staff_provisioning_request spr
  SET
    status = CASE
      WHEN spr.status = 'requested' THEN 'auth_pending'
      WHEN spr.status IN ('auth_pending', 'auth_created', 'membership_pending') THEN spr.status
      ELSE spr.status
    END,
    processing_token = v_new_token,
    processing_started_at = v_now,
    lease_expires_at = v_now + v_lease
  WHERE spr.id = p_request_id
  RETURNING * INTO v_row;

  RETURN public._m6_provisioning_request_to_json(v_row)
    || jsonb_build_object(
      'outcome', 'claimed',
      'processing_token', v_row.processing_token,
      'lease_expires_at', v_row.lease_expires_at
    );
END;
$$;

-- =============================================================================
-- RECORD AUTH CREATED (SERVICE ROLE)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.record_provisioning_auth_created(
  p_request_id uuid,
  p_auth_user_id uuid,
  p_processing_token uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.staff_provisioning_request%ROWTYPE;
BEGIN
  IF p_request_id IS NULL OR p_auth_user_id IS NULL OR p_processing_token IS NULL THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  SELECT * INTO v_row
  FROM public.staff_provisioning_request spr
  WHERE spr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF v_row.processing_token IS DISTINCT FROM p_processing_token THEN
    RAISE EXCEPTION 'invalid_processing_token';
  END IF;

  IF v_row.lease_expires_at IS NULL OR v_row.lease_expires_at <= now() THEN
    RAISE EXCEPTION 'lease_expired';
  END IF;

  IF v_row.status NOT IN ('auth_pending', 'auth_created') THEN
    RAISE EXCEPTION 'invalid_request_state';
  END IF;

  IF v_row.auth_user_id IS NOT NULL AND v_row.auth_user_id IS DISTINCT FROM p_auth_user_id THEN
    RAISE EXCEPTION 'identity_conflict';
  END IF;

  IF v_row.status = 'auth_created'
     AND v_row.auth_user_id = p_auth_user_id
     AND v_row.auth_created_by_this_request THEN
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object('outcome', 'auth_created');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.auth_user_id = p_auth_user_id
      AND (v_row.app_user_id IS NULL OR u.id IS DISTINCT FROM v_row.app_user_id)
  ) THEN
    RAISE EXCEPTION 'identity_conflict';
  END IF;

  UPDATE public.staff_provisioning_request spr
  SET
    auth_user_id = p_auth_user_id,
    auth_created_by_this_request = true,
    status = 'auth_created'
  WHERE spr.id = p_request_id
  RETURNING * INTO v_row;

  RETURN public._m6_provisioning_request_to_json(v_row)
    || jsonb_build_object('outcome', 'auth_created');
END;
$$;

-- =============================================================================
-- FINALIZE (SERVICE ROLE) — request_id only
-- =============================================================================

CREATE OR REPLACE FUNCTION public.finalize_staff_provisioning(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.staff_provisioning_request%ROWTYPE;
  v_limit integer;
  v_primary uuid;
  v_count integer;
  v_user_id uuid;
  v_auth uuid;
BEGIN
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'invalid_input';
  END IF;

  SELECT * INTO v_row
  FROM public.staff_provisioning_request spr
  WHERE spr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF v_row.status = 'completed' AND v_row.app_user_id IS NOT NULL THEN
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object('outcome', 'completed');
  END IF;

  IF v_row.status NOT IN ('auth_created', 'membership_pending') THEN
    RAISE EXCEPTION 'invalid_request_state';
  END IF;

  IF v_row.auth_user_id IS NULL OR NOT v_row.auth_created_by_this_request THEN
    RAISE EXCEPTION 'invalid_request_state';
  END IF;

  v_auth := v_row.auth_user_id;

  BEGIN
    PERFORM public._m6_provisioning_assert_owner_for_org(
      v_row.organization_id,
      v_row.requesting_owner_app_user_id
    );
  EXCEPTION
    WHEN OTHERS THEN
      UPDATE public.staff_provisioning_request spr
      SET status = 'compensation_pending', result_code = 'not_primary_owner'
      WHERE spr.id = p_request_id;
      RAISE EXCEPTION 'not_primary_owner';
  END;

  IF EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE u.auth_user_id = v_auth
      AND (v_row.app_user_id IS NULL OR u.id IS DISTINCT FROM v_row.app_user_id)
  ) THEN
    UPDATE public.staff_provisioning_request spr
    SET status = 'compensation_pending', result_code = 'identity_conflict'
    WHERE spr.id = p_request_id;
    RAISE EXCEPTION 'identity_conflict';
  END IF;

  PERFORM public._m6_provisioning_check_duplicate_member(
    v_row.organization_id,
    v_row.normalized_email,
    v_row.app_user_id
  );

  UPDATE public.staff_provisioning_request spr
  SET status = 'membership_pending'
  WHERE spr.id = p_request_id;

  SELECT oe.staff_limit, oe.primary_app_user_id
    INTO v_limit, v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_row.organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entitlement_missing';
  END IF;

  SELECT public.count_member_staff_seats(v_row.organization_id) INTO v_count;

  IF v_count >= v_limit THEN
    UPDATE public.staff_provisioning_request spr
    SET status = 'compensation_pending', result_code = 'staff_seat_limit_exceeded'
    WHERE spr.id = p_request_id
    RETURNING * INTO v_row;
    RETURN public._m6_provisioning_request_to_json(v_row)
      || jsonb_build_object('outcome', 'staff_seat_limit_exceeded');
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
    v_row.organization_id,
    v_row.normalized_email,
    v_row.display_name,
    v_row.preferred_locale,
    'active',
    'member',
    v_auth
  )
  RETURNING id INTO v_user_id;

  PERFORM public._m6_assign_canonical_staff_role_internal(
    v_row.organization_id,
    v_user_id,
    v_row.canonical_role
  );

  UPDATE public.staff_provisioning_request spr
  SET
    app_user_id = v_user_id,
    status = 'completed',
    result_code = 'completed',
    processing_token = NULL,
    lease_expires_at = NULL
  WHERE spr.id = p_request_id
  RETURNING * INTO v_row;

  RETURN public._m6_provisioning_request_to_json(v_row)
    || jsonb_build_object('outcome', 'completed');
EXCEPTION
  WHEN unique_violation THEN
    UPDATE public.staff_provisioning_request spr
    SET status = 'compensation_pending', result_code = 'member_already_exists'
    WHERE spr.id = p_request_id;
    RAISE EXCEPTION 'member_already_exists';
  WHEN OTHERS THEN
    IF SQLERRM LIKE '%staff_seat_limit_exceeded%'
       OR SQLERRM LIKE '%not_primary_owner%'
       OR SQLERRM LIKE '%identity_conflict%'
       OR SQLERRM LIKE '%member_already_exists%' THEN
      RAISE;
    END IF;
    UPDATE public.staff_provisioning_request spr
    SET status = 'compensation_pending', result_code = 'membership_provisioning_failed'
    WHERE spr.id = p_request_id;
    RAISE EXCEPTION 'membership_provisioning_failed';
END;
$$;

-- =============================================================================
-- COMPENSATION / RECOVERY MARKERS (SERVICE ROLE)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.mark_provisioning_compensated(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.staff_provisioning_request%ROWTYPE;
BEGIN
  SELECT * INTO v_row
  FROM public.staff_provisioning_request spr
  WHERE spr.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF NOT v_row.auth_created_by_this_request THEN
    RAISE EXCEPTION 'reconciliation_required';
  END IF;

  UPDATE public.staff_provisioning_request spr
  SET status = 'compensated', result_code = 'compensated'
  WHERE spr.id = p_request_id
  RETURNING * INTO v_row;

  RETURN public._m6_provisioning_request_to_json(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_provisioning_reconciliation_required(
  p_request_id uuid,
  p_result_code text DEFAULT 'reconciliation_required'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.staff_provisioning_request%ROWTYPE;
BEGIN
  UPDATE public.staff_provisioning_request spr
  SET status = 'reconciliation_required', result_code = COALESCE(p_result_code, 'reconciliation_required')
  WHERE spr.id = p_request_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  RETURN public._m6_provisioning_request_to_json(v_row);
END;
$$;

-- =============================================================================
-- GRANTS
-- =============================================================================

REVOKE ALL ON TABLE public.staff_provisioning_request FROM PUBLIC;
GRANT SELECT ON TABLE public.staff_provisioning_request TO authenticated;
GRANT ALL ON TABLE public.staff_provisioning_request TO service_role;

REVOKE ALL ON FUNCTION public.begin_staff_provisioning(text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_staff_provisioning(text, text, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.claim_provisioning_auth_execution(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_provisioning_auth_execution(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.record_provisioning_auth_created(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_provisioning_auth_created(uuid, uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_provisioning_auth_created(uuid, uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.finalize_staff_provisioning(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finalize_staff_provisioning(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_staff_provisioning(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.mark_provisioning_compensated(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_provisioning_compensated(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_provisioning_compensated(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.mark_provisioning_reconciliation_required(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_provisioning_reconciliation_required(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_provisioning_reconciliation_required(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public._m6_provisioning_assert_owner_for_org(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_assign_canonical_staff_role_internal(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._m6_provisioning_check_duplicate_member(uuid, text, uuid) FROM PUBLIC;
