-- M2-T03: Capital assets and straight-line monthly depreciation (Cost A).

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('asset.read'),
  ('asset.create'),
  ('asset.update')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- CAPITAL ASSET
-- =============================================================================

CREATE TABLE capital_asset (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  cost_group_id            uuid NOT NULL,
  name                     text NOT NULL,
  category_code            text,
  placed_in_service_date   date NOT NULL,
  original_cost            bigint NOT NULL,
  useful_life_months       integer NOT NULL,
  depreciation_method_code text NOT NULL DEFAULT 'straight_line',
  is_quick_mode            boolean NOT NULL DEFAULT false,
  status                   text NOT NULL DEFAULT 'active',
  retired_at               date,
  notes                    text,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  created_by               uuid,
  updated_by               uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT capital_asset_original_cost_check CHECK (original_cost > 0),
  CONSTRAINT capital_asset_useful_life_check CHECK (useful_life_months > 0),
  CONSTRAINT capital_asset_method_check CHECK (depreciation_method_code = 'straight_line'),
  CONSTRAINT capital_asset_status_check CHECK (status IN ('active', 'retired')),
  CONSTRAINT capital_asset_category_check CHECK (
    category_code IS NULL OR category_code IN (
      'fit_out', 'signage', 'furniture', 'equipment', 'technology', 'other_capital'
    )
  ),
  CONSTRAINT capital_asset_retired_date_check CHECK (
    retired_at IS NULL OR status = 'retired'
  ),
  FOREIGN KEY (organization_id, cost_group_id) REFERENCES cost_group (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_capital_asset_organization ON capital_asset (organization_id);
CREATE INDEX idx_capital_asset_status ON capital_asset (organization_id, status);
CREATE INDEX idx_capital_asset_cost_group ON capital_asset (organization_id, cost_group_id);

CREATE TRIGGER capital_asset_updated_at
  BEFORE UPDATE ON capital_asset
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE capital_asset IS
  'Cost A long-lived capital investment. Independent from operating expense. Quick and detailed modes converge here.';

COMMENT ON COLUMN capital_asset.cost_group_id IS
  'Snapshot of capital cost_group at acquisition; resolves to cost_domain_code = capital for reporting.';

-- =============================================================================
-- DEPRECIATION ENTRY
-- =============================================================================

CREATE TABLE depreciation_entry (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL,
  capital_asset_id uuid NOT NULL,
  period_month     date NOT NULL,
  period_number    integer NOT NULL,
  amount           bigint NOT NULL,
  status           text NOT NULL DEFAULT 'scheduled',
  posted_at        timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (capital_asset_id, period_number),
  UNIQUE (capital_asset_id, period_month),
  CONSTRAINT depreciation_entry_amount_check CHECK (amount > 0),
  CONSTRAINT depreciation_entry_period_check CHECK (period_number > 0),
  CONSTRAINT depreciation_entry_status_check CHECK (status IN ('scheduled', 'posted', 'void')),
  CONSTRAINT depreciation_entry_period_month_check CHECK (
    period_month = date_trunc('month', period_month)::date
  ),
  FOREIGN KEY (organization_id, capital_asset_id) REFERENCES capital_asset (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_depreciation_entry_asset ON depreciation_entry (organization_id, capital_asset_id, period_number);
CREATE INDEX idx_depreciation_entry_month ON depreciation_entry (organization_id, period_month, status);

COMMENT ON TABLE depreciation_entry IS
  'Monthly straight-line allocation of capital_asset.original_cost. Posted rows are immutable.';

-- =============================================================================
-- SCHEDULE GENERATION (Option A: persist full schedule at asset creation)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.capital_asset_period_month(
  p_placed_in_service date,
  p_period_number integer
)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT (date_trunc('month', p_placed_in_service)::date
    + make_interval(months => p_period_number - 1))::date;
$$;

CREATE OR REPLACE FUNCTION public.straight_line_depreciation_amount(
  p_original_cost bigint,
  p_useful_life_months integer,
  p_period_number integer
)
RETURNS bigint
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_base bigint;
BEGIN
  IF p_period_number < 1 OR p_period_number > p_useful_life_months THEN
    RAISE EXCEPTION 'period_number out of range';
  END IF;

  v_base := p_original_cost / p_useful_life_months;

  IF p_period_number < p_useful_life_months THEN
    RETURN v_base;
  END IF;

  RETURN p_original_cost - v_base * (p_useful_life_months - 1);
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_depreciation_schedule(p_capital_asset_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_asset capital_asset%ROWTYPE;
  v_amount bigint;
  v_month date;
BEGIN
  SELECT * INTO v_asset FROM capital_asset WHERE id = p_capital_asset_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'capital_asset not found';
  END IF;

  IF v_asset.status <> 'active' THEN
    RAISE EXCEPTION 'cannot generate schedule for non-active asset';
  END IF;

  IF EXISTS (
    SELECT 1 FROM depreciation_entry
    WHERE capital_asset_id = p_capital_asset_id AND status = 'posted'
  ) THEN
    RAISE EXCEPTION 'cannot regenerate schedule after posted depreciation exists';
  END IF;

  DELETE FROM depreciation_entry
  WHERE capital_asset_id = p_capital_asset_id AND status = 'scheduled';

  FOR v_period_num IN 1..v_asset.useful_life_months LOOP
    v_amount := public.straight_line_depreciation_amount(
      v_asset.original_cost,
      v_asset.useful_life_months,
      v_period_num
    );
    v_month := public.capital_asset_period_month(v_asset.placed_in_service_date, v_period_num);

    INSERT INTO depreciation_entry (
      organization_id,
      capital_asset_id,
      period_month,
      period_number,
      amount,
      status
    ) VALUES (
      v_asset.organization_id,
      v_asset.id,
      v_month,
      v_period_num,
      v_amount,
      'scheduled'
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_capital_asset_generate_schedule()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM public.generate_depreciation_schedule(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER capital_asset_generate_schedule
  AFTER INSERT ON capital_asset
  FOR EACH ROW EXECUTE FUNCTION public.trg_capital_asset_generate_schedule();

-- =============================================================================
-- IMMUTABILITY GUARDS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_capital_asset_after_posted_depreciation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM depreciation_entry
    WHERE capital_asset_id = OLD.id AND status = 'posted'
  ) THEN
    IF NEW.original_cost IS DISTINCT FROM OLD.original_cost
       OR NEW.useful_life_months IS DISTINCT FROM OLD.useful_life_months
       OR NEW.placed_in_service_date IS DISTINCT FROM OLD.placed_in_service_date
       OR NEW.depreciation_method_code IS DISTINCT FROM OLD.depreciation_method_code
       OR NEW.cost_group_id IS DISTINCT FROM OLD.cost_group_id
    THEN
      RAISE EXCEPTION 'Cannot modify core capital asset fields after posted depreciation exists';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER capital_asset_protect_after_posted
  BEFORE UPDATE ON capital_asset
  FOR EACH ROW EXECUTE FUNCTION public.protect_capital_asset_after_posted_depreciation();

CREATE OR REPLACE FUNCTION public.protect_posted_depreciation_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'posted' THEN
    IF NEW.amount IS DISTINCT FROM OLD.amount
       OR NEW.period_month IS DISTINCT FROM OLD.period_month
       OR NEW.period_number IS DISTINCT FROM OLD.period_number
       OR NEW.capital_asset_id IS DISTINCT FROM OLD.capital_asset_id
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR (NEW.status = 'scheduled')
    THEN
      RAISE EXCEPTION 'Posted depreciation entries are immutable; void and repost explicitly if needed';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER depreciation_entry_protect_posted
  BEFORE UPDATE ON depreciation_entry
  FOR EACH ROW EXECUTE FUNCTION public.protect_posted_depreciation_entry();

-- =============================================================================
-- RPC: RESOLVE CAPITAL COST GROUP
-- =============================================================================

CREATE OR REPLACE FUNCTION public.resolve_capital_cost_group_id(p_organization_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT id
  FROM cost_group
  WHERE organization_id = p_organization_id
    AND cost_domain_code = 'capital'
  LIMIT 1;
$$;

-- =============================================================================
-- RPC: CREATE CAPITAL ASSET (detailed + quick converge here)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_capital_asset(
  p_name text,
  p_original_cost bigint,
  p_useful_life_months integer,
  p_placed_in_service_date date,
  p_category_code text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_is_quick_mode boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_cost_group uuid;
  v_asset_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('asset.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'invalid_name' USING ERRCODE = 'P0001';
  END IF;

  IF p_original_cost IS NULL OR p_original_cost <= 0 THEN
    RAISE EXCEPTION 'invalid_cost' USING ERRCODE = 'P0001';
  END IF;

  IF p_useful_life_months IS NULL OR p_useful_life_months <= 0 THEN
    RAISE EXCEPTION 'invalid_useful_life' USING ERRCODE = 'P0001';
  END IF;

  IF p_placed_in_service_date IS NULL THEN
    RAISE EXCEPTION 'invalid_placed_in_service_date' USING ERRCODE = 'P0001';
  END IF;

  v_cost_group := public.resolve_capital_cost_group_id(v_org_id);

  IF v_cost_group IS NULL THEN
    RAISE EXCEPTION 'capital_cost_group_missing' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO capital_asset (
    organization_id,
    cost_group_id,
    name,
    category_code,
    placed_in_service_date,
    original_cost,
    useful_life_months,
    is_quick_mode,
    notes,
    created_by,
    updated_by
  ) VALUES (
    v_org_id,
    v_cost_group,
    btrim(p_name),
    p_category_code,
    p_placed_in_service_date,
    p_original_cost,
    p_useful_life_months,
    COALESCE(p_is_quick_mode, false),
    p_notes,
    v_actor,
    v_actor
  )
  RETURNING id INTO v_asset_id;

  RETURN v_asset_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_quick_capital_asset(
  p_total_investment bigint,
  p_useful_life_months integer,
  p_placed_in_service_date date,
  p_name text DEFAULT 'Initial setup investment'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  RETURN public.create_capital_asset(
    p_name,
    p_total_investment,
    p_useful_life_months,
    p_placed_in_service_date,
    'other_capital',
    NULL,
    true
  );
END;
$$;

-- =============================================================================
-- RPC: POST DEPRECIATION THROUGH MONTH
-- =============================================================================

CREATE OR REPLACE FUNCTION public.post_depreciation_through(
  p_capital_asset_id uuid,
  p_through_month date
)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_asset capital_asset%ROWTYPE;
  v_through date;
  v_count integer;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('asset.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_through := date_trunc('month', p_through_month)::date;

  SELECT * INTO v_asset
  FROM capital_asset
  WHERE id = p_capital_asset_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_asset.status = 'retired' AND v_asset.retired_at IS NOT NULL THEN
    v_through := LEAST(v_through, date_trunc('month', v_asset.retired_at)::date);
  END IF;

  UPDATE depreciation_entry
  SET status = 'posted', posted_at = now()
  WHERE capital_asset_id = p_capital_asset_id
    AND organization_id = v_org_id
    AND status = 'scheduled'
    AND period_month <= v_through;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- =============================================================================
-- RPC: RETIRE CAPITAL ASSET
-- =============================================================================

CREATE OR REPLACE FUNCTION public.retire_capital_asset(
  p_capital_asset_id uuid,
  p_retired_at date DEFAULT CURRENT_DATE
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_retire_month date;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('asset.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();
  v_retire_month := date_trunc('month', p_retired_at)::date;

  UPDATE capital_asset
  SET status = 'retired',
      retired_at = p_retired_at,
      updated_by = v_actor
  WHERE id = p_capital_asset_id
    AND organization_id = v_org_id
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE depreciation_entry
  SET status = 'void'
  WHERE capital_asset_id = p_capital_asset_id
    AND organization_id = v_org_id
    AND status = 'scheduled'
    AND period_month > v_retire_month;
END;
$$;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE capital_asset ENABLE ROW LEVEL SECURITY;
ALTER TABLE capital_asset FORCE ROW LEVEL SECURITY;
ALTER TABLE depreciation_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE depreciation_entry FORCE ROW LEVEL SECURITY;

CREATE POLICY capital_asset_select ON capital_asset FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('asset.read'));

CREATE POLICY capital_asset_insert ON capital_asset FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('asset.create'));

CREATE POLICY capital_asset_update ON capital_asset FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('asset.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY depreciation_entry_select ON depreciation_entry FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('asset.read'));

CREATE POLICY depreciation_entry_insert ON depreciation_entry FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('asset.create')
    AND EXISTS (
      SELECT 1 FROM capital_asset ca
      WHERE ca.id = depreciation_entry.capital_asset_id
        AND ca.organization_id = public.current_organization_id()
    )
  );

CREATE POLICY depreciation_entry_update ON depreciation_entry FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('asset.update'))
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON capital_asset, depreciation_entry TO authenticated;

GRANT EXECUTE ON FUNCTION public.capital_asset_period_month(date, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.straight_line_depreciation_amount(bigint, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_capital_asset(text, bigint, integer, date, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_quick_capital_asset(bigint, integer, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_depreciation_through(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.retire_capital_asset(uuid, date) TO authenticated;
