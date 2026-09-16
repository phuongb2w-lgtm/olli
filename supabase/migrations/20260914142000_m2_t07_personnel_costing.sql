-- M2-T07: Personnel costing foundation (compensation rules + personnel cost entries).

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('personnel_cost.read'),
  ('personnel_cost.manage')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- COMPENSATION RULES
-- =============================================================================

CREATE TABLE staff_compensation_rule (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  app_user_id             uuid NOT NULL,
  cost_domain_code        text NOT NULL,
  compensation_basis_code text NOT NULL,
  amount                  bigint NOT NULL,
  effective_from          date NOT NULL,
  effective_to            date,
  status                  text NOT NULL DEFAULT 'active',
  notes                   text,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  created_by              uuid,
  updated_by              uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT staff_compensation_rule_domain_check CHECK (
    cost_domain_code IN ('personnel', 'marketing_sales')
  ),
  CONSTRAINT staff_compensation_rule_basis_check CHECK (
    compensation_basis_code IN ('monthly_fixed', 'per_session')
  ),
  CONSTRAINT staff_compensation_rule_amount_check CHECK (amount > 0),
  CONSTRAINT staff_compensation_rule_status_check CHECK (
    status IN ('active', 'superseded', 'void')
  ),
  CONSTRAINT staff_compensation_rule_dates_check CHECK (
    effective_to IS NULL OR effective_to >= effective_from
  ),
  FOREIGN KEY (organization_id, app_user_id)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_staff_compensation_rule_staff
  ON staff_compensation_rule (organization_id, app_user_id, compensation_basis_code, cost_domain_code);

CREATE INDEX idx_staff_compensation_rule_effective
  ON staff_compensation_rule (organization_id, effective_from, effective_to);

ALTER TABLE staff_compensation_rule
  ADD CONSTRAINT staff_compensation_rule_no_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    app_user_id WITH =,
    compensation_basis_code WITH =,
    cost_domain_code WITH =,
    daterange(
      effective_from,
      COALESCE(effective_to, 'infinity'::date),
      '[]'
    ) WITH &&
  ) WHERE (status <> 'void');

CREATE TRIGGER staff_compensation_rule_updated_at
  BEFORE UPDATE ON staff_compensation_rule
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE staff_compensation_rule IS
  'Effective-dated staff compensation configuration. Classification is on the rule, not auth roles.';

-- =============================================================================
-- WELFARE FUND BASELINE
-- =============================================================================

CREATE TABLE welfare_fund_baseline_config (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  monthly_amount  bigint NOT NULL,
  effective_from  date NOT NULL,
  effective_to    date,
  status          text NOT NULL DEFAULT 'active',
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT welfare_fund_baseline_amount_check CHECK (monthly_amount > 0),
  CONSTRAINT welfare_fund_baseline_status_check CHECK (
    status IN ('active', 'superseded', 'void')
  ),
  CONSTRAINT welfare_fund_baseline_dates_check CHECK (
    effective_to IS NULL OR effective_to >= effective_from
  ),
  FOREIGN KEY (organization_id, created_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_welfare_fund_baseline_org
  ON welfare_fund_baseline_config (organization_id, effective_from, effective_to);

ALTER TABLE welfare_fund_baseline_config
  ADD CONSTRAINT welfare_fund_baseline_no_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    daterange(
      effective_from,
      COALESCE(effective_to, 'infinity'::date),
      '[]'
    ) WITH &&
  ) WHERE (status <> 'void');

CREATE TRIGGER welfare_fund_baseline_config_updated_at
  BEFORE UPDATE ON welfare_fund_baseline_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE welfare_fund_baseline_config IS
  'Organization-level welfare fund monthly baseline (Cost B2 personnel). No staff identity required.';

-- =============================================================================
-- PERSONNEL COST ENTRIES
-- =============================================================================

CREATE TABLE personnel_cost_entry (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                 uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  app_user_id                     uuid,
  staff_compensation_rule_id      uuid,
  welfare_fund_baseline_config_id uuid,
  cost_domain_code                text NOT NULL,
  compensation_basis_code         text,
  amount                          bigint NOT NULL,
  accounting_period               date NOT NULL,
  incurred_date                   date NOT NULL,
  source_type                     text NOT NULL,
  teaching_session_id             uuid,
  class_id                        uuid,
  teacher_id                      uuid,
  status                          text NOT NULL DEFAULT 'posted',
  voided_at                       timestamptz,
  voided_by                       uuid,
  void_notes                      text,
  created_at                      timestamptz NOT NULL DEFAULT now(),
  created_by                      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT personnel_cost_entry_amount_check CHECK (amount > 0),
  CONSTRAINT personnel_cost_entry_status_check CHECK (status IN ('posted', 'void')),
  CONSTRAINT personnel_cost_entry_domain_check CHECK (
    cost_domain_code IN ('personnel', 'marketing_sales')
  ),
  CONSTRAINT personnel_cost_entry_basis_check CHECK (
    compensation_basis_code IS NULL
    OR compensation_basis_code IN ('monthly_fixed', 'per_session')
  ),
  CONSTRAINT personnel_cost_entry_source_check CHECK (
    source_type IN ('monthly_fixed', 'per_session', 'welfare_baseline')
  ),
  CONSTRAINT personnel_cost_entry_period_check CHECK (
    accounting_period = date_trunc('month', accounting_period)::date
  ),
  CONSTRAINT personnel_cost_entry_shape_check CHECK (
    (source_type = 'welfare_baseline' AND welfare_fund_baseline_config_id IS NOT NULL AND app_user_id IS NULL)
    OR (source_type <> 'welfare_baseline' AND staff_compensation_rule_id IS NOT NULL AND app_user_id IS NOT NULL)
  ),
  FOREIGN KEY (organization_id, app_user_id)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, staff_compensation_rule_id)
    REFERENCES staff_compensation_rule (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, welfare_fund_baseline_config_id)
    REFERENCES welfare_fund_baseline_config (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teaching_session_id)
    REFERENCES teaching_session (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id)
    REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teacher_id)
    REFERENCES teacher (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, voided_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX idx_personnel_cost_monthly_rule_period
  ON personnel_cost_entry (staff_compensation_rule_id, accounting_period)
  WHERE status = 'posted'
    AND source_type = 'monthly_fixed'
    AND staff_compensation_rule_id IS NOT NULL;

CREATE UNIQUE INDEX idx_personnel_cost_session_rule
  ON personnel_cost_entry (staff_compensation_rule_id, teaching_session_id)
  WHERE status = 'posted'
    AND source_type = 'per_session'
    AND teaching_session_id IS NOT NULL;

CREATE UNIQUE INDEX idx_personnel_cost_welfare_period
  ON personnel_cost_entry (organization_id, accounting_period)
  WHERE status = 'posted'
    AND source_type = 'welfare_baseline';

CREATE INDEX idx_personnel_cost_entry_org_period
  ON personnel_cost_entry (organization_id, accounting_period, status);

CREATE INDEX idx_personnel_cost_entry_class
  ON personnel_cost_entry (organization_id, class_id, status)
  WHERE class_id IS NOT NULL;

CREATE INDEX idx_personnel_cost_entry_domain
  ON personnel_cost_entry (organization_id, cost_domain_code, status);

COMMENT ON TABLE personnel_cost_entry IS
  'Immutable personnel management-cost facts. Distinct from ordinary expense rows.';

-- =============================================================================
-- HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.normalize_accounting_period(p_date date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT date_trunc('month', p_date)::date;
$$;

CREATE OR REPLACE FUNCTION public.is_compensation_rule_effective_on(
  p_effective_from date,
  p_effective_to date,
  p_on date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_effective_from <= p_on
    AND (p_effective_to IS NULL OR p_effective_to >= p_on);
$$;

CREATE OR REPLACE FUNCTION public.is_compensation_rule_applicable_to_month(
  p_effective_from date,
  p_effective_to date,
  p_period_month date
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_effective_from <= (p_period_month + interval '1 month - 1 day')::date
    AND (p_effective_to IS NULL OR p_effective_to >= p_period_month);
$$;

CREATE OR REPLACE FUNCTION public.validate_personnel_cost_domain(
  p_organization_id uuid,
  p_cost_domain_code text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_cost_domain_code NOT IN ('personnel', 'marketing_sales') THEN
    RAISE EXCEPTION 'invalid_personnel_cost_domain' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM cost_group cg
    WHERE cg.organization_id = p_organization_id
      AND cg.cost_domain_code = p_cost_domain_code
  ) THEN
    RAISE EXCEPTION 'cost_domain_not_configured' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.protect_personnel_cost_entry_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'posted' THEN
    IF NEW.amount IS DISTINCT FROM OLD.amount
      OR NEW.app_user_id IS DISTINCT FROM OLD.app_user_id
      OR NEW.staff_compensation_rule_id IS DISTINCT FROM OLD.staff_compensation_rule_id
      OR NEW.welfare_fund_baseline_config_id IS DISTINCT FROM OLD.welfare_fund_baseline_config_id
      OR NEW.cost_domain_code IS DISTINCT FROM OLD.cost_domain_code
      OR NEW.compensation_basis_code IS DISTINCT FROM OLD.compensation_basis_code
      OR NEW.accounting_period IS DISTINCT FROM OLD.accounting_period
      OR NEW.incurred_date IS DISTINCT FROM OLD.incurred_date
      OR NEW.source_type IS DISTINCT FROM OLD.source_type
      OR NEW.teaching_session_id IS DISTINCT FROM OLD.teaching_session_id
      OR NEW.class_id IS DISTINCT FROM OLD.class_id
      OR NEW.teacher_id IS DISTINCT FROM OLD.teacher_id
    THEN
      RAISE EXCEPTION 'personnel_cost_entry_immutable';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER personnel_cost_entry_protect_immutability
  BEFORE UPDATE ON personnel_cost_entry
  FOR EACH ROW EXECUTE FUNCTION protect_personnel_cost_entry_immutability();

-- =============================================================================
-- RPC: CREATE COMPENSATION RULE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_staff_compensation_rule(
  p_app_user_id uuid,
  p_cost_domain_code text,
  p_compensation_basis_code text,
  p_amount bigint,
  p_effective_from date,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_rule_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('personnel_cost.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount' USING ERRCODE = 'P0001';
  END IF;

  IF p_compensation_basis_code NOT IN ('monthly_fixed', 'per_session') THEN
    RAISE EXCEPTION 'invalid_compensation_basis' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.validate_personnel_cost_domain(v_org, p_cost_domain_code);

  IF NOT EXISTS (
    SELECT 1 FROM app_user u
    WHERE u.id = p_app_user_id AND u.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'staff_not_found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO staff_compensation_rule (
    organization_id,
    app_user_id,
    cost_domain_code,
    compensation_basis_code,
    amount,
    effective_from,
    notes,
    created_by,
    updated_by
  ) VALUES (
    v_org,
    p_app_user_id,
    p_cost_domain_code,
    p_compensation_basis_code,
    p_amount,
    p_effective_from,
    p_notes,
    public.current_app_user_id(),
    public.current_app_user_id()
  )
  RETURNING id INTO v_rule_id;

  RETURN v_rule_id;
END;
$$;

-- =============================================================================
-- RPC: END / SUPERSEDE COMPENSATION RULE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.end_staff_compensation_rule(
  p_rule_id uuid,
  p_effective_to date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_rule staff_compensation_rule%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('personnel_cost.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rule
  FROM staff_compensation_rule
  WHERE id = p_rule_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'rule_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_rule.status = 'void' THEN
    RAISE EXCEPTION 'rule_already_void' USING ERRCODE = 'P0001';
  END IF;

  IF p_effective_to < v_rule.effective_from THEN
    RAISE EXCEPTION 'invalid_effective_to' USING ERRCODE = 'P0001';
  END IF;

  UPDATE staff_compensation_rule
  SET
    effective_to = p_effective_to,
    status = 'superseded',
    updated_by = public.current_app_user_id()
  WHERE id = p_rule_id;

  RETURN p_rule_id;
END;
$$;

-- =============================================================================
-- RPC: CONFIGURE WELFARE BASELINE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.configure_welfare_fund_baseline(
  p_monthly_amount bigint,
  p_effective_from date,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_config_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('personnel_cost.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_monthly_amount IS NULL OR p_monthly_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount' USING ERRCODE = 'P0001';
  END IF;

  UPDATE welfare_fund_baseline_config
  SET
    effective_to = p_effective_from - 1,
    status = 'superseded',
    updated_by = public.current_app_user_id()
  WHERE organization_id = v_org
    AND status = 'active'
    AND effective_to IS NULL
    AND effective_from < p_effective_from;

  INSERT INTO welfare_fund_baseline_config (
    organization_id,
    monthly_amount,
    effective_from,
    notes,
    created_by,
    updated_by
  ) VALUES (
    v_org,
    p_monthly_amount,
    p_effective_from,
    p_notes,
    public.current_app_user_id(),
    public.current_app_user_id()
  )
  RETURNING id INTO v_config_id;

  RETURN v_config_id;
END;
$$;

-- =============================================================================
-- RPC: GENERATE MONTHLY PERSONNEL COSTS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.generate_personnel_costs(p_period_month date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_period date;
  v_rule staff_compensation_rule%ROWTYPE;
  v_welfare welfare_fund_baseline_config%ROWTYPE;
  v_monthly_created integer := 0;
  v_welfare_created integer := 0;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('personnel_cost.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_period := public.normalize_accounting_period(p_period_month);

  FOR v_rule IN
    SELECT *
    FROM staff_compensation_rule r
    WHERE r.organization_id = v_org
      AND r.status <> 'void'
      AND r.compensation_basis_code = 'monthly_fixed'
      AND public.is_compensation_rule_applicable_to_month(
        r.effective_from, r.effective_to, v_period
      )
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM personnel_cost_entry e
      WHERE e.staff_compensation_rule_id = v_rule.id
        AND e.accounting_period = v_period
        AND e.status = 'posted'
        AND e.source_type = 'monthly_fixed'
    ) THEN
      INSERT INTO personnel_cost_entry (
        organization_id,
        app_user_id,
        staff_compensation_rule_id,
        cost_domain_code,
        compensation_basis_code,
        amount,
        accounting_period,
        incurred_date,
        source_type,
        created_by
      ) VALUES (
        v_org,
        v_rule.app_user_id,
        v_rule.id,
        v_rule.cost_domain_code,
        v_rule.compensation_basis_code,
        v_rule.amount,
        v_period,
        v_period,
        'monthly_fixed',
        public.current_app_user_id()
      );
      v_monthly_created := v_monthly_created + 1;
    END IF;
  END LOOP;

  SELECT * INTO v_welfare
  FROM welfare_fund_baseline_config w
  WHERE w.organization_id = v_org
    AND w.status <> 'void'
    AND public.is_compensation_rule_applicable_to_month(
      w.effective_from, w.effective_to, v_period
    )
  ORDER BY w.effective_from DESC
  LIMIT 1;

  IF FOUND AND NOT EXISTS (
    SELECT 1
    FROM personnel_cost_entry e
    WHERE e.organization_id = v_org
      AND e.accounting_period = v_period
      AND e.status = 'posted'
      AND e.source_type = 'welfare_baseline'
  ) THEN
    INSERT INTO personnel_cost_entry (
      organization_id,
      welfare_fund_baseline_config_id,
      cost_domain_code,
      amount,
      accounting_period,
      incurred_date,
      source_type,
      created_by
    ) VALUES (
      v_org,
      v_welfare.id,
      'personnel',
      v_welfare.monthly_amount,
      v_period,
      v_period,
      'welfare_baseline',
      public.current_app_user_id()
    );
    v_welfare_created := 1;
  END IF;

  RETURN jsonb_build_object(
    'period_month', v_period,
    'monthly_entries_created', v_monthly_created,
    'welfare_entries_created', v_welfare_created
  );
END;
$$;

-- =============================================================================
-- RPC: GENERATE DIRECT SESSION PERSONNEL COST
-- =============================================================================

CREATE OR REPLACE FUNCTION public.generate_teaching_session_personnel_cost(
  p_teaching_session_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_session teaching_session%ROWTYPE;
  v_teacher teacher%ROWTYPE;
  v_rule staff_compensation_rule%ROWTYPE;
  v_session_date date;
  v_period date;
  v_created integer := 0;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('personnel_cost.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_session
  FROM teaching_session ts
  WHERE ts.id = p_teaching_session_id AND ts.organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_session.status <> 'completed' THEN
    RETURN jsonb_build_object('entries_created', 0, 'reason', 'session_not_completed');
  END IF;

  SELECT * INTO v_teacher
  FROM teacher t
  WHERE t.id = v_session.teacher_id AND t.organization_id = v_org;

  IF v_teacher.user_id IS NULL THEN
    RETURN jsonb_build_object('entries_created', 0, 'reason', 'teacher_has_no_app_user');
  END IF;

  v_session_date := v_session.scheduled_start_at::date;
  v_period := public.normalize_accounting_period(v_session_date);

  FOR v_rule IN
    SELECT *
    FROM staff_compensation_rule r
    WHERE r.organization_id = v_org
      AND r.app_user_id = v_teacher.user_id
      AND r.status <> 'void'
      AND r.compensation_basis_code = 'per_session'
      AND public.is_compensation_rule_effective_on(
        r.effective_from, r.effective_to, v_session_date
      )
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM personnel_cost_entry e
      WHERE e.staff_compensation_rule_id = v_rule.id
        AND e.teaching_session_id = v_session.id
        AND e.status = 'posted'
        AND e.source_type = 'per_session'
    ) THEN
      INSERT INTO personnel_cost_entry (
        organization_id,
        app_user_id,
        staff_compensation_rule_id,
        cost_domain_code,
        compensation_basis_code,
        amount,
        accounting_period,
        incurred_date,
        source_type,
        teaching_session_id,
        class_id,
        teacher_id,
        created_by
      ) VALUES (
        v_org,
        v_rule.app_user_id,
        v_rule.id,
        v_rule.cost_domain_code,
        v_rule.compensation_basis_code,
        v_rule.amount,
        v_period,
        v_session_date,
        'per_session',
        v_session.id,
        v_session.class_id,
        v_session.teacher_id,
        public.current_app_user_id()
      );
      v_created := v_created + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('entries_created', v_created);
END;
$$;

-- =============================================================================
-- RPC: VOID PERSONNEL COST ENTRY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.void_personnel_cost_entry(
  p_entry_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('personnel_cost.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  UPDATE personnel_cost_entry
  SET
    status = 'void',
    voided_at = now(),
    voided_by = public.current_app_user_id(),
    void_notes = p_notes
  WHERE id = p_entry_id
    AND organization_id = v_org
    AND status = 'posted';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entry_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN p_entry_id;
END;
$$;

-- =============================================================================
-- READ MODEL (T08 handoff)
-- =============================================================================

CREATE OR REPLACE VIEW personnel_cost_entry_detail
WITH (security_invoker = true) AS
SELECT
  e.id,
  e.organization_id,
  e.app_user_id,
  e.staff_compensation_rule_id,
  e.welfare_fund_baseline_config_id,
  e.cost_domain_code,
  e.compensation_basis_code,
  e.amount,
  e.accounting_period,
  e.incurred_date,
  e.source_type,
  e.teaching_session_id,
  e.class_id,
  e.teacher_id,
  e.status,
  e.created_at,
  CASE
    WHEN e.teaching_session_id IS NOT NULL THEN 'direct'
    ELSE 'shared'
  END AS attribution_type
FROM personnel_cost_entry e;

COMMENT ON VIEW personnel_cost_entry_detail IS
  'Derived personnel cost read model: direct (session-linked) vs shared (monthly/welfare).';

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE staff_compensation_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_compensation_rule FORCE ROW LEVEL SECURITY;
ALTER TABLE welfare_fund_baseline_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE welfare_fund_baseline_config FORCE ROW LEVEL SECURITY;
ALTER TABLE personnel_cost_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE personnel_cost_entry FORCE ROW LEVEL SECURITY;

CREATE POLICY staff_compensation_rule_select ON staff_compensation_rule FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.read'));

CREATE POLICY staff_compensation_rule_insert ON staff_compensation_rule FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.manage'));

CREATE POLICY staff_compensation_rule_update ON staff_compensation_rule FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.manage'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY welfare_fund_baseline_config_select ON welfare_fund_baseline_config FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.read'));

CREATE POLICY welfare_fund_baseline_config_insert ON welfare_fund_baseline_config FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.manage'));

CREATE POLICY welfare_fund_baseline_config_update ON welfare_fund_baseline_config FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.manage'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY personnel_cost_entry_select ON personnel_cost_entry FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.read'));

CREATE POLICY personnel_cost_entry_insert ON personnel_cost_entry FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.manage'));

CREATE POLICY personnel_cost_entry_update ON personnel_cost_entry FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('personnel_cost.manage'))
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON staff_compensation_rule, welfare_fund_baseline_config, personnel_cost_entry TO authenticated;
GRANT SELECT ON personnel_cost_entry_detail TO authenticated;

GRANT EXECUTE ON FUNCTION public.normalize_accounting_period(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_compensation_rule_effective_on(date, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_compensation_rule_applicable_to_month(date, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_staff_compensation_rule(uuid, text, text, bigint, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_staff_compensation_rule(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.configure_welfare_fund_baseline(bigint, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_personnel_costs(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_teaching_session_personnel_cost(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.void_personnel_cost_entry(uuid, text) TO authenticated;
