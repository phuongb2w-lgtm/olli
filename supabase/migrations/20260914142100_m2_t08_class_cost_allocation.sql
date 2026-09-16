-- M2-T08: Shared cost allocation and class economics.

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('class_economics.read'),
  ('cost_allocation.manage')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- ALLOCATION RULES
-- =============================================================================

CREATE TABLE cost_allocation_rule (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  source_scope_code     text NOT NULL,
  allocation_basis_code text NOT NULL,
  effective_from        date NOT NULL,
  effective_to          date,
  status                text NOT NULL DEFAULT 'active',
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  created_by            uuid,
  updated_by            uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT cost_allocation_rule_scope_check CHECK (
    source_scope_code IN ('operating_overhead', 'shared_personnel', 'marketing_sales', 'depreciation')
  ),
  CONSTRAINT cost_allocation_rule_basis_check CHECK (
    allocation_basis_code IN (
      'equal',
      'active_enrollment_count',
      'delivered_session_count',
      'recognized_revenue'
    )
  ),
  CONSTRAINT cost_allocation_rule_status_check CHECK (
    status IN ('active', 'superseded', 'void')
  ),
  CONSTRAINT cost_allocation_rule_dates_check CHECK (
    effective_to IS NULL OR effective_to >= effective_from
  ),
  FOREIGN KEY (organization_id, created_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_cost_allocation_rule_scope
  ON cost_allocation_rule (organization_id, source_scope_code, effective_from, effective_to);

ALTER TABLE cost_allocation_rule
  ADD CONSTRAINT cost_allocation_rule_no_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    source_scope_code WITH =,
    daterange(
      effective_from,
      COALESCE(effective_to, 'infinity'::date),
      '[]'
    ) WITH &&
  ) WHERE (status <> 'void');

CREATE TRIGGER cost_allocation_rule_updated_at
  BEFORE UPDATE ON cost_allocation_rule
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE cost_allocation_rule IS
  'Effective-dated shared-cost allocation policy by source scope.';

-- =============================================================================
-- ALLOCATION BATCH + FACTS
-- =============================================================================

CREATE TABLE class_cost_allocation_batch (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  accounting_period date NOT NULL,
  status            text NOT NULL DEFAULT 'posted',
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        uuid,
  voided_at         timestamptz,
  voided_by         uuid,
  void_notes        text,
  UNIQUE (organization_id, id),
  CONSTRAINT class_cost_allocation_batch_status_check CHECK (
    status IN ('posted', 'void')
  ),
  CONSTRAINT class_cost_allocation_batch_period_check CHECK (
    accounting_period = date_trunc('month', accounting_period)::date
  ),
  FOREIGN KEY (organization_id, created_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, voided_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX idx_class_cost_allocation_batch_org_period
  ON class_cost_allocation_batch (organization_id, accounting_period)
  WHERE status = 'posted';

CREATE TABLE class_cost_allocation (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  allocation_batch_id      uuid NOT NULL,
  accounting_period        date NOT NULL,
  class_id                 uuid NOT NULL,
  source_type              text NOT NULL,
  source_record_id         uuid NOT NULL,
  cost_domain_code         text NOT NULL,
  source_scope_code        text NOT NULL,
  cost_allocation_rule_id  uuid NOT NULL,
  allocation_basis_code    text NOT NULL,
  source_amount_snapshot   bigint NOT NULL,
  weight_value             bigint NOT NULL DEFAULT 0,
  weight_total             bigint NOT NULL DEFAULT 0,
  sequence_number          integer NOT NULL,
  allocated_amount         bigint NOT NULL,
  status                   text NOT NULL DEFAULT 'posted',
  created_at               timestamptz NOT NULL DEFAULT now(),
  created_by               uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT class_cost_allocation_amount_check CHECK (allocated_amount >= 0),
  CONSTRAINT class_cost_allocation_source_amount_check CHECK (source_amount_snapshot > 0),
  CONSTRAINT class_cost_allocation_status_check CHECK (status IN ('posted', 'void')),
  CONSTRAINT class_cost_allocation_source_type_check CHECK (
    source_type IN ('expense', 'personnel_cost_entry', 'depreciation_entry')
  ),
  CONSTRAINT class_cost_allocation_domain_check CHECK (
    cost_domain_code IN ('operating_overhead', 'personnel', 'marketing_sales', 'capital')
  ),
  CONSTRAINT class_cost_allocation_period_check CHECK (
    accounting_period = date_trunc('month', accounting_period)::date
  ),
  FOREIGN KEY (organization_id, allocation_batch_id)
    REFERENCES class_cost_allocation_batch (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id)
    REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, cost_allocation_rule_id)
    REFERENCES cost_allocation_rule (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX idx_class_cost_allocation_source_class
  ON class_cost_allocation (
    organization_id,
    accounting_period,
    source_type,
    source_record_id,
    class_id
  )
  WHERE status = 'posted';

CREATE INDEX idx_class_cost_allocation_class_period
  ON class_cost_allocation (organization_id, class_id, accounting_period, status);

COMMENT ON TABLE class_cost_allocation IS
  'Auditable shared-cost allocation facts. Source rows are never rewritten.';

-- =============================================================================
-- HELPERS: PERIOD + ELIGIBILITY + WEIGHTS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.allocation_period_end(p_period_month date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (date_trunc('month', p_period_month) + interval '1 month - 1 day')::date;
$$;

CREATE OR REPLACE FUNCTION public.is_class_eligible_for_allocation(
  p_class_id uuid,
  p_period_month date
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM class c
    WHERE c.id = p_class_id
      AND c.status IN ('planned', 'trial', 'active', 'closed')
      AND (c.term_start_date IS NULL OR c.term_start_date <= public.allocation_period_end(p_period_month))
      AND (c.term_end_date IS NULL OR c.term_end_date >= p_period_month)
  );
$$;

CREATE OR REPLACE FUNCTION public.class_active_enrollment_count(
  p_class_id uuid,
  p_period_month date
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT count(*)::bigint
  FROM enrollment e
  WHERE e.class_id = p_class_id
    AND e.status IN ('active', 'completed')
    AND e.start_date <= public.allocation_period_end(p_period_month)
    AND (e.end_date IS NULL OR e.end_date >= p_period_month);
$$;

CREATE OR REPLACE FUNCTION public.class_delivered_session_count(
  p_class_id uuid,
  p_period_month date
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT count(*)::bigint
  FROM teaching_session ts
  WHERE ts.class_id = p_class_id
    AND ts.status = 'completed'
    AND date_trunc('month', ts.scheduled_start_at)::date = p_period_month;
$$;

CREATE OR REPLACE FUNCTION public.class_recognized_revenue_amount(
  p_class_id uuid,
  p_period_month date
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(r.amount), 0)::bigint
  FROM revenue_recognition_event r
  JOIN enrollment e ON e.id = r.enrollment_id
  LEFT JOIN teaching_session ts ON ts.id = r.teaching_session_id
  WHERE e.class_id = p_class_id
    AND r.status = 'posted'
    AND date_trunc(
      'month',
      COALESCE(ts.scheduled_start_at, r.recognized_at)
    )::date = p_period_month;
$$;

CREATE OR REPLACE FUNCTION public.class_allocation_weight(
  p_class_id uuid,
  p_period_month date,
  p_basis text
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF NOT public.is_class_eligible_for_allocation(p_class_id, p_period_month) THEN
    RETURN 0;
  END IF;

  CASE p_basis
    WHEN 'equal' THEN
      RETURN 1;
    WHEN 'active_enrollment_count' THEN
      RETURN public.class_active_enrollment_count(p_class_id, p_period_month);
    WHEN 'delivered_session_count' THEN
      RETURN public.class_delivered_session_count(p_class_id, p_period_month);
    WHEN 'recognized_revenue' THEN
      RETURN public.class_recognized_revenue_amount(p_class_id, p_period_month);
    ELSE
      RAISE EXCEPTION 'invalid_allocation_basis';
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_allocation_rule(
  p_organization_id uuid,
  p_source_scope_code text,
  p_period_month date
)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT r.id
  FROM cost_allocation_rule r
  WHERE r.organization_id = p_organization_id
    AND r.source_scope_code = p_source_scope_code
    AND r.status <> 'void'
    AND public.is_compensation_rule_applicable_to_month(
      r.effective_from, r.effective_to, p_period_month
    )
  ORDER BY r.effective_from DESC
  LIMIT 1;
$$;

-- =============================================================================
-- DEFAULT RULES
-- =============================================================================

CREATE OR REPLACE FUNCTION public.ensure_default_allocation_rules(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cost_allocation_rule
    WHERE organization_id = p_organization_id
      AND source_scope_code = 'operating_overhead'
  ) THEN
    INSERT INTO cost_allocation_rule (
      organization_id, source_scope_code, allocation_basis_code, effective_from
    ) VALUES
      (p_organization_id, 'operating_overhead', 'active_enrollment_count', '2000-01-01'),
      (p_organization_id, 'shared_personnel', 'active_enrollment_count', '2000-01-01'),
      (p_organization_id, 'marketing_sales', 'recognized_revenue', '2000-01-01'),
      (p_organization_id, 'depreciation', 'equal', '2000-01-01');
  END IF;
END;
$$;

-- =============================================================================
-- CORE ALLOCATION
-- =============================================================================

CREATE OR REPLACE FUNCTION public._allocate_shared_source(
  p_organization_id uuid,
  p_period_month date,
  p_batch_id uuid,
  p_source_type text,
  p_source_record_id uuid,
  p_source_amount bigint,
  p_cost_domain_code text,
  p_source_scope_code text,
  p_rule_id uuid,
  p_basis text,
  p_created_by uuid
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_class record;
  v_classes uuid[] := ARRAY[]::uuid[];
  v_weights bigint[] := ARRAY[]::bigint[];
  v_raw_amounts bigint[] := ARRAY[]::bigint[];
  v_weight_total bigint := 0;
  v_class_count integer := 0;
  v_seq integer := 0;
  v_allocated bigint := 0;
  v_total_allocated bigint := 0;
  v_remainder bigint := 0;
  v_positive_count integer := 0;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM class_cost_allocation a
    WHERE a.organization_id = p_organization_id
      AND a.accounting_period = p_period_month
      AND a.source_type = p_source_type
      AND a.source_record_id = p_source_record_id
      AND a.status = 'posted'
  ) THEN
    SELECT COALESCE(SUM(allocated_amount), 0) INTO v_total_allocated
    FROM class_cost_allocation
    WHERE organization_id = p_organization_id
      AND accounting_period = p_period_month
      AND source_type = p_source_type
      AND source_record_id = p_source_record_id
      AND status = 'posted';

    RETURN jsonb_build_object(
      'allocated_total', v_total_allocated,
      'unallocated_total', GREATEST(p_source_amount - v_total_allocated, 0),
      'skipped', true
    );
  END IF;

  FOR v_class IN
    SELECT c.id
    FROM class c
    WHERE c.organization_id = p_organization_id
      AND public.is_class_eligible_for_allocation(c.id, p_period_month)
    ORDER BY c.id
  LOOP
    v_class_count := v_class_count + 1;
    v_classes := array_append(v_classes, v_class.id);
    v_weights := array_append(
      v_weights,
      public.class_allocation_weight(v_class.id, p_period_month, p_basis)
    );
  END LOOP;

  IF v_class_count = 0 THEN
    RETURN jsonb_build_object(
      'allocated_total', 0,
      'unallocated_total', p_source_amount,
      'skipped', false
    );
  END IF;

  SELECT COALESCE(SUM(w), 0) INTO v_weight_total FROM unnest(v_weights) AS w;

  IF p_basis <> 'equal' AND v_weight_total = 0 THEN
    RETURN jsonb_build_object(
      'allocated_total', 0,
      'unallocated_total', p_source_amount,
      'skipped', false
    );
  END IF;

  IF p_basis = 'equal' THEN
    FOR v_seq IN 1..v_class_count LOOP
      v_allocated := public.installment_schedule_amount(p_source_amount, v_class_count, v_seq);
      INSERT INTO class_cost_allocation (
        organization_id, allocation_batch_id, accounting_period, class_id,
        source_type, source_record_id, cost_domain_code, source_scope_code,
        cost_allocation_rule_id, allocation_basis_code, source_amount_snapshot,
        weight_value, weight_total, sequence_number, allocated_amount, created_by
      ) VALUES (
        p_organization_id, p_batch_id, p_period_month, v_classes[v_seq],
        p_source_type, p_source_record_id, p_cost_domain_code, p_source_scope_code,
        p_rule_id, p_basis, p_source_amount, 1, v_class_count, v_seq, v_allocated, p_created_by
      );
      v_total_allocated := v_total_allocated + v_allocated;
    END LOOP;
  ELSE
    FOR v_seq IN 1..v_class_count LOOP
      v_raw_amounts := array_append(v_raw_amounts, (p_source_amount * v_weights[v_seq]) / v_weight_total);
    END LOOP;

    v_total_allocated := 0;
    v_positive_count := 0;
    FOR v_seq IN 1..v_class_count LOOP
      IF v_weights[v_seq] > 0 THEN
        v_positive_count := v_positive_count + 1;
      END IF;
      v_total_allocated := v_total_allocated + v_raw_amounts[v_seq];
    END LOOP;

    v_remainder := p_source_amount - v_total_allocated;
    v_seq := 0;

    FOR v_seq IN 1..v_class_count LOOP
      v_allocated := v_raw_amounts[v_seq];
      IF v_weights[v_seq] > 0 AND v_remainder > 0 THEN
        v_allocated := v_allocated + 1;
        v_remainder := v_remainder - 1;
      END IF;

      IF v_allocated > 0 THEN
        INSERT INTO class_cost_allocation (
          organization_id, allocation_batch_id, accounting_period, class_id,
          source_type, source_record_id, cost_domain_code, source_scope_code,
          cost_allocation_rule_id, allocation_basis_code, source_amount_snapshot,
          weight_value, weight_total, sequence_number, allocated_amount, created_by
        ) VALUES (
          p_organization_id, p_batch_id, p_period_month, v_classes[v_seq],
          p_source_type, p_source_record_id, p_cost_domain_code, p_source_scope_code,
          p_rule_id, p_basis, p_source_amount, v_weights[v_seq], v_weight_total, v_seq, v_allocated, p_created_by
        );
      END IF;
    END LOOP;

    v_total_allocated := p_source_amount - v_remainder;
  END IF;

  RETURN jsonb_build_object(
    'allocated_total', (
      SELECT COALESCE(SUM(allocated_amount), 0)
      FROM class_cost_allocation
      WHERE organization_id = p_organization_id
        AND accounting_period = p_period_month
        AND source_type = p_source_type
        AND source_record_id = p_source_record_id
        AND status = 'posted'
    ),
    'unallocated_total', GREATEST(
      p_source_amount - COALESCE((
        SELECT SUM(allocated_amount)
        FROM class_cost_allocation
        WHERE organization_id = p_organization_id
          AND accounting_period = p_period_month
          AND source_type = p_source_type
          AND source_record_id = p_source_record_id
          AND status = 'posted'
      ), 0),
      0
    ),
    'skipped', false
  );
END;
$$;

-- =============================================================================
-- IMMUTABILITY
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_class_cost_allocation_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'posted' THEN
    IF NEW.allocated_amount IS DISTINCT FROM OLD.allocated_amount
      OR NEW.class_id IS DISTINCT FROM OLD.class_id
      OR NEW.source_type IS DISTINCT FROM OLD.source_type
      OR NEW.source_record_id IS DISTINCT FROM OLD.source_record_id
      OR NEW.cost_domain_code IS DISTINCT FROM OLD.cost_domain_code
      OR NEW.source_amount_snapshot IS DISTINCT FROM OLD.source_amount_snapshot
      OR NEW.weight_value IS DISTINCT FROM OLD.weight_value
      OR NEW.weight_total IS DISTINCT FROM OLD.weight_total
      OR NEW.allocation_basis_code IS DISTINCT FROM OLD.allocation_basis_code
    THEN
      RAISE EXCEPTION 'class_cost_allocation_immutable';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER class_cost_allocation_protect_immutability
  BEFORE UPDATE ON class_cost_allocation
  FOR EACH ROW EXECUTE FUNCTION protect_class_cost_allocation_immutability();

-- =============================================================================
-- RPC: CREATE / END ALLOCATION RULE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_cost_allocation_rule(
  p_source_scope_code text,
  p_allocation_basis_code text,
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
  IF NOT public.is_active_app_user() OR NOT public.has_permission('cost_allocation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO cost_allocation_rule (
    organization_id,
    source_scope_code,
    allocation_basis_code,
    effective_from,
    notes,
    created_by,
    updated_by
  ) VALUES (
    v_org,
    p_source_scope_code,
    p_allocation_basis_code,
    p_effective_from,
    p_notes,
    public.current_app_user_id(),
    public.current_app_user_id()
  )
  RETURNING id INTO v_rule_id;

  RETURN v_rule_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.end_cost_allocation_rule(
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
  v_rule cost_allocation_rule%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('cost_allocation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rule
  FROM cost_allocation_rule
  WHERE id = p_rule_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'rule_not_found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE cost_allocation_rule
  SET
    effective_to = p_effective_to,
    status = 'superseded',
    updated_by = public.current_app_user_id()
  WHERE id = p_rule_id;

  RETURN p_rule_id;
END;
$$;

-- =============================================================================
-- RPC: RUN ALLOCATION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.run_class_cost_allocation(p_period_month date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_period date;
  v_batch_id uuid;
  v_actor uuid;
  v_source record;
  v_rule_id uuid;
  v_basis text;
  v_result jsonb;
  v_shared_total bigint := 0;
  v_allocated_total bigint := 0;
  v_unallocated_total bigint := 0;
  v_sources_processed integer := 0;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('cost_allocation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_period := public.normalize_accounting_period(p_period_month);
  v_actor := public.current_app_user_id();
  PERFORM public.ensure_default_allocation_rules(v_org);

  SELECT id INTO v_batch_id
  FROM class_cost_allocation_batch
  WHERE organization_id = v_org
    AND accounting_period = v_period
    AND status = 'posted';

  IF NOT FOUND THEN
    INSERT INTO class_cost_allocation_batch (
      organization_id, accounting_period, created_by
    ) VALUES (v_org, v_period, v_actor)
    RETURNING id INTO v_batch_id;
  END IF;

  -- Operating overhead expenses (exclude personnel domain to avoid T07 double count)
  v_rule_id := public.resolve_allocation_rule(v_org, 'operating_overhead', v_period);
  IF v_rule_id IS NULL THEN
    RAISE EXCEPTION 'allocation_rule_not_found' USING ERRCODE = 'P0002';
  END IF;
  SELECT allocation_basis_code INTO v_basis FROM cost_allocation_rule WHERE id = v_rule_id;

  FOR v_source IN
    SELECT e.id, e.amount
    FROM expense e
    JOIN cost_group cg ON cg.id = e.cost_group_id
    WHERE e.organization_id = v_org
      AND e.status = 'posted'
      AND cg.cost_domain_code = 'operating_overhead'
      AND public.normalize_accounting_period(e.incurred_date) = v_period
  LOOP
    v_shared_total := v_shared_total + v_source.amount;
    v_result := public._allocate_shared_source(
      v_org, v_period, v_batch_id, 'expense', v_source.id, v_source.amount,
      'operating_overhead', 'operating_overhead', v_rule_id, v_basis, v_actor
    );
    v_allocated_total := v_allocated_total + (v_result->>'allocated_total')::bigint;
    v_unallocated_total := v_unallocated_total + (v_result->>'unallocated_total')::bigint;
    v_sources_processed := v_sources_processed + 1;
  END LOOP;

  -- Shared personnel (T07 authoritative; exclude direct session costs)
  v_rule_id := public.resolve_allocation_rule(v_org, 'shared_personnel', v_period);
  SELECT allocation_basis_code INTO v_basis FROM cost_allocation_rule WHERE id = v_rule_id;

  FOR v_source IN
    SELECT p.id, p.amount
    FROM personnel_cost_entry p
    WHERE p.organization_id = v_org
      AND p.status = 'posted'
      AND p.cost_domain_code = 'personnel'
      AND p.teaching_session_id IS NULL
      AND p.accounting_period = v_period
  LOOP
    v_shared_total := v_shared_total + v_source.amount;
    v_result := public._allocate_shared_source(
      v_org, v_period, v_batch_id, 'personnel_cost_entry', v_source.id, v_source.amount,
      'personnel', 'shared_personnel', v_rule_id, v_basis, v_actor
    );
    v_allocated_total := v_allocated_total + (v_result->>'allocated_total')::bigint;
    v_unallocated_total := v_unallocated_total + (v_result->>'unallocated_total')::bigint;
    v_sources_processed := v_sources_processed + 1;
  END LOOP;

  -- Marketing & sales: expense + shared personnel classified as marketing_sales
  v_rule_id := public.resolve_allocation_rule(v_org, 'marketing_sales', v_period);
  SELECT allocation_basis_code INTO v_basis FROM cost_allocation_rule WHERE id = v_rule_id;

  FOR v_source IN
    SELECT e.id, e.amount
    FROM expense e
    JOIN cost_group cg ON cg.id = e.cost_group_id
    WHERE e.organization_id = v_org
      AND e.status = 'posted'
      AND cg.cost_domain_code = 'marketing_sales'
      AND public.normalize_accounting_period(e.incurred_date) = v_period
  LOOP
    v_shared_total := v_shared_total + v_source.amount;
    v_result := public._allocate_shared_source(
      v_org, v_period, v_batch_id, 'expense', v_source.id, v_source.amount,
      'marketing_sales', 'marketing_sales', v_rule_id, v_basis, v_actor
    );
    v_allocated_total := v_allocated_total + (v_result->>'allocated_total')::bigint;
    v_unallocated_total := v_unallocated_total + (v_result->>'unallocated_total')::bigint;
    v_sources_processed := v_sources_processed + 1;
  END LOOP;

  FOR v_source IN
    SELECT p.id, p.amount
    FROM personnel_cost_entry p
    WHERE p.organization_id = v_org
      AND p.status = 'posted'
      AND p.cost_domain_code = 'marketing_sales'
      AND p.teaching_session_id IS NULL
      AND p.accounting_period = v_period
  LOOP
    v_shared_total := v_shared_total + v_source.amount;
    v_result := public._allocate_shared_source(
      v_org, v_period, v_batch_id, 'personnel_cost_entry', v_source.id, v_source.amount,
      'marketing_sales', 'marketing_sales', v_rule_id, v_basis, v_actor
    );
    v_allocated_total := v_allocated_total + (v_result->>'allocated_total')::bigint;
    v_unallocated_total := v_unallocated_total + (v_result->>'unallocated_total')::bigint;
    v_sources_processed := v_sources_processed + 1;
  END LOOP;

  -- Posted depreciation only (Cost A monthly facts)
  v_rule_id := public.resolve_allocation_rule(v_org, 'depreciation', v_period);
  SELECT allocation_basis_code INTO v_basis FROM cost_allocation_rule WHERE id = v_rule_id;

  FOR v_source IN
    SELECT d.id, d.amount
    FROM depreciation_entry d
    WHERE d.organization_id = v_org
      AND d.status = 'posted'
      AND d.period_month = v_period
  LOOP
    v_shared_total := v_shared_total + v_source.amount;
    v_result := public._allocate_shared_source(
      v_org, v_period, v_batch_id, 'depreciation_entry', v_source.id, v_source.amount,
      'capital', 'depreciation', v_rule_id, v_basis, v_actor
    );
    v_allocated_total := v_allocated_total + (v_result->>'allocated_total')::bigint;
    v_unallocated_total := v_unallocated_total + (v_result->>'unallocated_total')::bigint;
    v_sources_processed := v_sources_processed + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'period_month', v_period,
    'batch_id', v_batch_id,
    'sources_processed', v_sources_processed,
    'shared_source_total', v_shared_total,
    'allocated_total', v_allocated_total,
    'unallocated_total', v_unallocated_total
  );
END;
$$;

-- =============================================================================
-- RPC: VOID ALLOCATION BATCH
-- =============================================================================

CREATE OR REPLACE FUNCTION public.void_class_cost_allocation_batch(
  p_batch_id uuid,
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
  IF NOT public.is_active_app_user() OR NOT public.has_permission('cost_allocation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  UPDATE class_cost_allocation
  SET status = 'void'
  WHERE allocation_batch_id = p_batch_id
    AND organization_id = v_org
    AND status = 'posted';

  UPDATE class_cost_allocation_batch
  SET
    status = 'void',
    voided_at = now(),
    voided_by = public.current_app_user_id(),
    void_notes = p_notes
  WHERE id = p_batch_id
    AND organization_id = v_org
    AND status = 'posted';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'batch_not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN p_batch_id;
END;
$$;

-- =============================================================================
-- READ MODELS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_class_economics(
  p_class_id uuid,
  p_period_from date,
  p_period_to date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_from date;
  v_to date;
  v_revenue bigint := 0;
  v_direct_personnel bigint := 0;
  v_allocated_personnel bigint := 0;
  v_allocated_overhead bigint := 0;
  v_allocated_marketing bigint := 0;
  v_allocated_depreciation bigint := 0;
  v_total_cost bigint := 0;
  v_contribution bigint := 0;
  v_margin numeric;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_economics.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM class c
    WHERE c.id = p_class_id AND c.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'class_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_from := public.normalize_accounting_period(p_period_from);
  v_to := public.normalize_accounting_period(p_period_to);

  SELECT COALESCE(SUM(r.amount), 0) INTO v_revenue
  FROM revenue_recognition_event r
  JOIN enrollment e ON e.id = r.enrollment_id
  LEFT JOIN teaching_session ts ON ts.id = r.teaching_session_id
  WHERE e.class_id = p_class_id
    AND e.organization_id = v_org
    AND r.status = 'posted'
    AND date_trunc(
      'month',
      COALESCE(ts.scheduled_start_at, r.recognized_at)
    )::date BETWEEN v_from AND v_to;

  SELECT COALESCE(SUM(p.amount), 0) INTO v_direct_personnel
  FROM personnel_cost_entry p
  WHERE p.class_id = p_class_id
    AND p.organization_id = v_org
    AND p.status = 'posted'
    AND p.teaching_session_id IS NOT NULL
    AND p.accounting_period BETWEEN v_from AND v_to;

  SELECT COALESCE(SUM(a.allocated_amount), 0) INTO v_allocated_personnel
  FROM class_cost_allocation a
  WHERE a.class_id = p_class_id
    AND a.organization_id = v_org
    AND a.status = 'posted'
    AND a.source_scope_code = 'shared_personnel'
    AND a.accounting_period BETWEEN v_from AND v_to;

  SELECT COALESCE(SUM(a.allocated_amount), 0) INTO v_allocated_overhead
  FROM class_cost_allocation a
  WHERE a.class_id = p_class_id
    AND a.organization_id = v_org
    AND a.status = 'posted'
    AND a.source_scope_code = 'operating_overhead'
    AND a.accounting_period BETWEEN v_from AND v_to;

  SELECT COALESCE(SUM(a.allocated_amount), 0) INTO v_allocated_marketing
  FROM class_cost_allocation a
  WHERE a.class_id = p_class_id
    AND a.organization_id = v_org
    AND a.status = 'posted'
    AND a.source_scope_code = 'marketing_sales'
    AND a.accounting_period BETWEEN v_from AND v_to;

  SELECT COALESCE(SUM(a.allocated_amount), 0) INTO v_allocated_depreciation
  FROM class_cost_allocation a
  WHERE a.class_id = p_class_id
    AND a.organization_id = v_org
    AND a.status = 'posted'
    AND a.source_scope_code = 'depreciation'
    AND a.accounting_period BETWEEN v_from AND v_to;

  v_total_cost := v_direct_personnel
    + v_allocated_personnel
    + v_allocated_overhead
    + v_allocated_marketing
    + v_allocated_depreciation;
  v_contribution := v_revenue - v_total_cost;

  IF v_revenue > 0 THEN
    v_margin := round((v_contribution::numeric / v_revenue::numeric) * 100, 2);
  ELSE
    v_margin := NULL;
  END IF;

  RETURN jsonb_build_object(
    'class_id', p_class_id,
    'period_from', v_from,
    'period_to', v_to,
    'recognized_revenue', v_revenue,
    'direct_personnel_cost', v_direct_personnel,
    'allocated_personnel_cost', v_allocated_personnel,
    'allocated_operating_overhead', v_allocated_overhead,
    'allocated_marketing_sales', v_allocated_marketing,
    'allocated_depreciation', v_allocated_depreciation,
    'total_cost', v_total_cost,
    'contribution', v_contribution,
    'margin_percentage', v_margin
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_organization_cost_reconciliation(
  p_period_month date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_period date;
  v_shared_total bigint := 0;
  v_allocated_total bigint := 0;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_economics.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_period := public.normalize_accounting_period(p_period_month);

  SELECT COALESCE(SUM(x.amount), 0) INTO v_shared_total
  FROM (
    SELECT e.amount
    FROM expense e
    JOIN cost_group cg ON cg.id = e.cost_group_id
    WHERE e.organization_id = v_org
      AND e.status = 'posted'
      AND cg.cost_domain_code IN ('operating_overhead', 'marketing_sales')
      AND public.normalize_accounting_period(e.incurred_date) = v_period
    UNION ALL
    SELECT p.amount
    FROM personnel_cost_entry p
    WHERE p.organization_id = v_org
      AND p.status = 'posted'
      AND p.teaching_session_id IS NULL
      AND p.cost_domain_code IN ('personnel', 'marketing_sales')
      AND p.accounting_period = v_period
    UNION ALL
    SELECT d.amount
    FROM depreciation_entry d
    WHERE d.organization_id = v_org
      AND d.status = 'posted'
      AND d.period_month = v_period
  ) x;

  SELECT COALESCE(SUM(a.allocated_amount), 0) INTO v_allocated_total
  FROM class_cost_allocation a
  WHERE a.organization_id = v_org
    AND a.accounting_period = v_period
    AND a.status = 'posted';

  RETURN jsonb_build_object(
    'period_month', v_period,
    'shared_source_total', v_shared_total,
    'allocated_total', v_allocated_total,
    'unallocated_total', GREATEST(v_shared_total - v_allocated_total, 0)
  );
END;
$$;

CREATE OR REPLACE VIEW class_cost_allocation_detail
WITH (security_invoker = true) AS
SELECT
  a.*,
  c.name AS class_name
FROM class_cost_allocation a
JOIN class c ON c.id = a.class_id AND c.organization_id = a.organization_id;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE cost_allocation_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_allocation_rule FORCE ROW LEVEL SECURITY;
ALTER TABLE class_cost_allocation_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_cost_allocation_batch FORCE ROW LEVEL SECURITY;
ALTER TABLE class_cost_allocation ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_cost_allocation FORCE ROW LEVEL SECURITY;

CREATE POLICY cost_allocation_rule_select ON cost_allocation_rule FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('class_economics.read'));

CREATE POLICY cost_allocation_rule_insert ON cost_allocation_rule FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('cost_allocation.manage'));

CREATE POLICY cost_allocation_rule_update ON cost_allocation_rule FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('cost_allocation.manage'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY class_cost_allocation_batch_select ON class_cost_allocation_batch FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('class_economics.read'));

CREATE POLICY class_cost_allocation_batch_insert ON class_cost_allocation_batch FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('cost_allocation.manage'));

CREATE POLICY class_cost_allocation_batch_update ON class_cost_allocation_batch FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('cost_allocation.manage'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY class_cost_allocation_select ON class_cost_allocation FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('class_economics.read'));

CREATE POLICY class_cost_allocation_insert ON class_cost_allocation FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('cost_allocation.manage'));

CREATE POLICY class_cost_allocation_update ON class_cost_allocation FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('cost_allocation.manage'))
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON cost_allocation_rule, class_cost_allocation_batch, class_cost_allocation TO authenticated;
GRANT SELECT ON class_cost_allocation_detail TO authenticated;

GRANT EXECUTE ON FUNCTION public.allocation_period_end(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_class_eligible_for_allocation(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.class_active_enrollment_count(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.class_delivered_session_count(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.class_recognized_revenue_amount(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.class_allocation_weight(uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_allocation_rule(uuid, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_cost_allocation_rule(text, text, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_cost_allocation_rule(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.run_class_cost_allocation(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.void_class_cost_allocation_batch(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_economics(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_organization_cost_reconciliation(date) TO authenticated;
