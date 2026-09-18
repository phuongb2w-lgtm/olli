-- M5-T01: Management intelligence foundation — permissions, reporting period contract,
-- consultant revenue declaration lifecycle, executive reporting boundary.

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('report.executive.read'),
  ('consultant_revenue.declare'),
  ('consultant_revenue.review')
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE permission IS
  'Permission codes. report.executive.read gates center-wide executive intelligence (Center Manager only in product contract).';

-- =============================================================================
-- CONSULTANT REVENUE DECLARATION (non-canonical until accountant approval)
-- =============================================================================

CREATE TYPE consultant_revenue_declaration_status AS ENUM (
  'pending',
  'approved',
  'rejected',
  'returned'
);

COMMENT ON TYPE consultant_revenue_declaration_status IS
  'Consultant declarations are not canonical financial revenue until status = approved and linked bookkeeping exists.';

CREATE TABLE consultant_revenue_declaration (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL REFERENCES organization (id),
  consultant_user_id  uuid NOT NULL REFERENCES app_user (id),
  declaration_date    date NOT NULL,
  declared_amount     numeric(19, 4) NOT NULL CHECK (declared_amount > 0),
  currency_code       text NOT NULL DEFAULT 'VND',
  description         text,
  status              consultant_revenue_declaration_status NOT NULL DEFAULT 'pending',
  declared_at         timestamptz NOT NULL DEFAULT now(),
  reviewed_by         uuid REFERENCES app_user (id),
  reviewed_at         timestamptz,
  review_notes        text,
  approved_payment_id uuid REFERENCES payment (id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT consultant_revenue_declaration_org_consultant_fk
    FOREIGN KEY (organization_id, consultant_user_id)
    REFERENCES app_user (organization_id, id),
  CONSTRAINT consultant_revenue_declaration_org_reviewer_fk
    FOREIGN KEY (organization_id, reviewed_by)
    REFERENCES app_user (organization_id, id)
);

CREATE INDEX idx_consultant_revenue_declaration_org_status
  ON consultant_revenue_declaration (organization_id, status, declaration_date);

CREATE INDEX idx_consultant_revenue_declaration_consultant
  ON consultant_revenue_declaration (organization_id, consultant_user_id, declaration_date);

COMMENT ON TABLE consultant_revenue_declaration IS
  'Consultant-declared revenue pending accountant review. Never counted as canonical booked revenue while pending/returned/rejected.';

ALTER TABLE consultant_revenue_declaration ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultant_revenue_declaration FORCE ROW LEVEL SECURITY;

-- =============================================================================
-- REPORTING PERIOD CONTRACT
-- =============================================================================

CREATE TYPE reporting_period_bounds AS (
  organization_id    uuid,
  timezone           text,
  start_date         date,
  end_date           date,
  start_at_utc       timestamptz,
  end_at_exclusive   timestamptz
);

COMMENT ON TYPE reporting_period_bounds IS
  'Canonical local-date reporting window. start_date/end_date inclusive in organization timezone. end_at_exclusive is first instant after end_date local day.';

CREATE OR REPLACE FUNCTION public.resolve_reporting_period(
  p_start_date date,
  p_end_date date
)
RETURNS reporting_period_bounds
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_timezone text;
  v_bounds reporting_period_bounds;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RAISE EXCEPTION 'invalid_reporting_period' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT o.timezone INTO v_timezone
  FROM organization o
  WHERE o.id = v_org_id;

  v_bounds.organization_id := v_org_id;
  v_bounds.timezone := v_timezone;
  v_bounds.start_date := p_start_date;
  v_bounds.end_date := p_end_date;
  v_bounds.start_at_utc := (p_start_date::timestamp AT TIME ZONE v_timezone);
  v_bounds.end_at_exclusive := ((p_end_date + 1)::timestamp AT TIME ZONE v_timezone);

  RETURN v_bounds;
END;
$$;

COMMENT ON FUNCTION public.resolve_reporting_period(date, date) IS
  'Deterministic inclusive local-date period with UTC bounds for timestamptz filtering. All M5 read models must use this contract.';

-- =============================================================================
-- TEACHING SESSION OPERATIONAL DATE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.teaching_session_operational_date(
  p_scheduled_start_at timestamptz,
  p_timezone text
)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (p_scheduled_start_at AT TIME ZONE p_timezone)::date;
$$;

COMMENT ON FUNCTION public.teaching_session_operational_date(timestamptz, text) IS
  'Current operational local date for a materialized session. occurrence_date is identity/provenance only and must not drive operational placement after reschedule.';

-- =============================================================================
-- EFFECTIVE PERMISSIONS (navigation + UX authorization)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.list_my_permissions()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT p.code
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
  ORDER BY 1;
$$;

REVOKE ALL ON FUNCTION public.list_my_permissions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_my_permissions() TO authenticated;

-- =============================================================================
-- EXECUTIVE REPORTING BOUNDARY (stub read contract for later M5 tasks)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_executive_reporting_access()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('report.executive.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'organization_id', public.current_organization_id(),
    'executive_access', true
  );
END;
$$;

COMMENT ON FUNCTION public.get_executive_reporting_access() IS
  'Center Manager executive reporting gate. Cross-domain dashboards must require report.executive.read.';

GRANT EXECUTE ON FUNCTION public.resolve_reporting_period(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.teaching_session_operational_date(timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_executive_reporting_access() TO authenticated;

-- =============================================================================
-- CONSULTANT REVENUE RPCs (declaration lifecycle foundation)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.declare_consultant_revenue(
  p_declaration_date date,
  p_declared_amount numeric,
  p_description text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_user_id uuid;
  v_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.declare') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_user_id := public.current_app_user_id();

  IF p_declaration_date IS NULL OR p_declared_amount IS NULL OR p_declared_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_declaration' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO consultant_revenue_declaration (
    organization_id,
    consultant_user_id,
    declaration_date,
    declared_amount,
    description,
    status
  ) VALUES (
    v_org_id,
    v_user_id,
    p_declaration_date,
    p_declared_amount,
    NULLIF(trim(p_description), ''),
    'pending'
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_consultant_revenue_declaration(
  p_declaration_id uuid,
  p_action text,
  p_review_notes text DEFAULT NULL
)
RETURNS consultant_revenue_declaration
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_row consultant_revenue_declaration;
  v_new_status consultant_revenue_declaration_status;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('consultant_revenue.review') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  IF p_action NOT IN ('approve', 'reject', 'return') THEN
    RAISE EXCEPTION 'invalid_review_action' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM consultant_revenue_declaration
  WHERE id = p_declaration_id
    AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'declaration_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_row.status NOT IN ('pending', 'returned') THEN
    RAISE EXCEPTION 'declaration_not_reviewable' USING ERRCODE = 'P0001';
  END IF;

  v_new_status := CASE p_action
    WHEN 'approve' THEN 'approved'::consultant_revenue_declaration_status
    WHEN 'reject' THEN 'rejected'::consultant_revenue_declaration_status
    WHEN 'return' THEN 'returned'::consultant_revenue_declaration_status
  END;

  UPDATE consultant_revenue_declaration
  SET
    status = v_new_status,
    reviewed_by = public.current_app_user_id(),
    reviewed_at = now(),
    review_notes = NULLIF(trim(p_review_notes), ''),
    updated_at = now()
  WHERE id = p_declaration_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.count_canonical_financial_revenue(
  p_start_date date,
  p_end_date date
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_bounds reporting_period_bounds;
  v_total numeric;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('payment.read')
    OR public.has_permission('revenue.read')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_bounds := public.resolve_reporting_period(p_start_date, p_end_date);
  v_org_id := v_bounds.organization_id;

  SELECT COALESCE(sum(rre.amount), 0) INTO v_total
  FROM revenue_recognition_event rre
  WHERE rre.organization_id = v_org_id
    AND rre.status = 'posted'
    AND rre.recognized_at >= v_bounds.start_at_utc
    AND rre.recognized_at < v_bounds.end_at_exclusive;

  RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION public.sum_pending_consultant_declarations(
  p_start_date date,
  p_end_date date
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_total numeric;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT (
    public.has_permission('consultant_revenue.declare')
    OR public.has_permission('consultant_revenue.review')
    OR public.has_permission('report.executive.read')
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT COALESCE(sum(crd.declared_amount), 0) INTO v_total
  FROM consultant_revenue_declaration crd
  WHERE crd.organization_id = v_org_id
    AND crd.status IN ('pending', 'returned')
    AND crd.declaration_date BETWEEN p_start_date AND p_end_date;

  RETURN v_total;
END;
$$;

GRANT EXECUTE ON FUNCTION public.declare_consultant_revenue(date, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_consultant_revenue_declaration(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_canonical_financial_revenue(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sum_pending_consultant_declarations(date, date) TO authenticated;

-- =============================================================================
-- RLS: CONSULTANT REVENUE DECLARATION
-- =============================================================================

CREATE POLICY consultant_revenue_declaration_select ON consultant_revenue_declaration
  FOR SELECT
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      public.has_permission('consultant_revenue.review')
      OR public.has_permission('report.executive.read')
      OR (
        public.has_permission('consultant_revenue.declare')
        AND consultant_user_id = public.current_app_user_id()
      )
    )
  );

CREATE POLICY consultant_revenue_declaration_insert ON consultant_revenue_declaration
  FOR INSERT
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.declare')
    AND consultant_user_id = public.current_app_user_id()
    AND status = 'pending'
  );

CREATE POLICY consultant_revenue_declaration_update ON consultant_revenue_declaration
  FOR UPDATE
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.review')
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.review')
  );
