-- M2-T09: Class financial simulator (planning scenarios, not accounting facts).

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('class_simulation.read'),
  ('class_simulation.manage')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- SCENARIO MODEL
-- =============================================================================

CREATE TABLE class_financial_scenario (
  id                                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                     uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  class_id                            uuid,
  scenario_name                       text NOT NULL,
  status                              text NOT NULL DEFAULT 'draft',
  planned_learner_count                 integer NOT NULL,
  tuition_assumption_mode             text NOT NULL DEFAULT 'uniform_tuition',
  assumed_net_tuition_per_learner     bigint NOT NULL DEFAULT 0,
  planned_months                      integer NOT NULL,
  planned_session_count               integer NOT NULL,
  per_session_teacher_rate            bigint,
  staff_compensation_rule_id          uuid,
  per_session_rate_snapshot           bigint,
  monthly_shared_personnel_assumption bigint NOT NULL DEFAULT 0,
  monthly_operating_overhead_assumption bigint NOT NULL DEFAULT 0,
  marketing_sales_assumption          bigint NOT NULL DEFAULT 0,
  marketing_assumption_basis          text NOT NULL DEFAULT 'one_time',
  monthly_depreciation_assumption     bigint NOT NULL DEFAULT 0,
  capacity_snapshot                   integer,
  economics_snapshot                  jsonb,
  finalized_at                        timestamptz,
  finalized_by                        uuid,
  created_at                          timestamptz NOT NULL DEFAULT now(),
  updated_at                          timestamptz NOT NULL DEFAULT now(),
  created_by                          uuid,
  updated_by                          uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT class_financial_scenario_status_check CHECK (
    status IN ('draft', 'finalized')
  ),
  CONSTRAINT class_financial_scenario_tuition_mode_check CHECK (
    tuition_assumption_mode IN ('uniform_tuition')
  ),
  CONSTRAINT class_financial_scenario_marketing_basis_check CHECK (
    marketing_assumption_basis IN ('one_time', 'monthly')
  ),
  CONSTRAINT class_financial_scenario_learners_check CHECK (planned_learner_count >= 0),
  CONSTRAINT class_financial_scenario_months_check CHECK (planned_months > 0),
  CONSTRAINT class_financial_scenario_sessions_check CHECK (planned_session_count >= 0),
  CONSTRAINT class_financial_scenario_tuition_check CHECK (assumed_net_tuition_per_learner >= 0),
  CONSTRAINT class_financial_scenario_assumption_amounts_check CHECK (
    monthly_shared_personnel_assumption >= 0
    AND monthly_operating_overhead_assumption >= 0
    AND marketing_sales_assumption >= 0
    AND monthly_depreciation_assumption >= 0
  ),
  CONSTRAINT class_financial_scenario_teacher_rate_check CHECK (
    per_session_teacher_rate IS NULL OR per_session_teacher_rate >= 0
  ),
  FOREIGN KEY (organization_id, class_id)
    REFERENCES class (organization_id, id) ON DELETE SET NULL,
  FOREIGN KEY (organization_id, staff_compensation_rule_id)
    REFERENCES staff_compensation_rule (organization_id, id) ON DELETE SET NULL,
  FOREIGN KEY (organization_id, created_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, finalized_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_class_financial_scenario_org
  ON class_financial_scenario (organization_id, status);

CREATE INDEX idx_class_financial_scenario_class
  ON class_financial_scenario (organization_id, class_id)
  WHERE class_id IS NOT NULL;

CREATE TRIGGER class_financial_scenario_updated_at
  BEFORE UPDATE ON class_financial_scenario
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE class_financial_scenario IS
  'Hypothetical class economics planning scenario. Never creates accounting facts.';

-- =============================================================================
-- PURE ECONOMICS HELPERS (aligned with T08 semantics)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.compute_projected_class_total_cost(
  p_direct_personnel bigint,
  p_shared_personnel bigint,
  p_operating_overhead bigint,
  p_marketing_sales bigint,
  p_depreciation bigint
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_direct_personnel, 0)
    + COALESCE(p_shared_personnel, 0)
    + COALESCE(p_operating_overhead, 0)
    + COALESCE(p_marketing_sales, 0)
    + COALESCE(p_depreciation, 0);
$$;

CREATE OR REPLACE FUNCTION public.compute_projected_contribution(
  p_revenue bigint,
  p_total_cost bigint
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_revenue, 0) - COALESCE(p_total_cost, 0);
$$;

CREATE OR REPLACE FUNCTION public.compute_projected_margin_percentage(
  p_revenue bigint,
  p_contribution bigint
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN COALESCE(p_revenue, 0) > 0 THEN
      round((p_contribution::numeric / p_revenue::numeric) * 100, 2)
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.compute_break_even_learner_count(
  p_total_cost bigint,
  p_tuition_per_learner bigint
)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_tuition_per_learner IS NULL OR p_tuition_per_learner <= 0 THEN
    RETURN NULL;
  END IF;

  IF COALESCE(p_total_cost, 0) <= 0 THEN
    RETURN 0;
  END IF;

  RETURN ((p_total_cost + p_tuition_per_learner - 1) / p_tuition_per_learner)::integer;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_scenario_per_session_rate(p_scenario class_financial_scenario)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_rate bigint;
BEGIN
  IF p_scenario.status = 'finalized' AND p_scenario.per_session_rate_snapshot IS NOT NULL THEN
    RETURN p_scenario.per_session_rate_snapshot;
  END IF;

  IF p_scenario.per_session_teacher_rate IS NOT NULL THEN
    RETURN p_scenario.per_session_teacher_rate;
  END IF;

  IF p_scenario.staff_compensation_rule_id IS NOT NULL THEN
    SELECT amount INTO v_rate
    FROM staff_compensation_rule
    WHERE id = p_scenario.staff_compensation_rule_id
      AND organization_id = p_scenario.organization_id
      AND compensation_basis_code = 'per_session';

    RETURN COALESCE(v_rate, 0);
  END IF;

  RETURN 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_scenario_economics(p_scenario_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_scenario class_financial_scenario%ROWTYPE;
  v_rate bigint;
  v_revenue bigint;
  v_direct bigint;
  v_shared bigint;
  v_overhead bigint;
  v_marketing bigint;
  v_depreciation bigint;
  v_total bigint;
  v_contribution bigint;
  v_margin numeric;
  v_break_even integer;
  v_capacity integer;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_scenario
  FROM class_financial_scenario
  WHERE id = p_scenario_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_scenario.status = 'finalized' AND v_scenario.economics_snapshot IS NOT NULL THEN
    RETURN v_scenario.economics_snapshot;
  END IF;

  v_rate := public.resolve_scenario_per_session_rate(v_scenario);
  v_revenue := v_scenario.planned_learner_count * v_scenario.assumed_net_tuition_per_learner;
  v_direct := v_rate * v_scenario.planned_session_count;
  v_shared := v_scenario.monthly_shared_personnel_assumption * v_scenario.planned_months;
  v_overhead := v_scenario.monthly_operating_overhead_assumption * v_scenario.planned_months;
  v_marketing := CASE
    WHEN v_scenario.marketing_assumption_basis = 'monthly'
      THEN v_scenario.marketing_sales_assumption * v_scenario.planned_months
    ELSE v_scenario.marketing_sales_assumption
  END;
  v_depreciation := v_scenario.monthly_depreciation_assumption * v_scenario.planned_months;
  v_total := public.compute_projected_class_total_cost(
    v_direct, v_shared, v_overhead, v_marketing, v_depreciation
  );
  v_contribution := public.compute_projected_contribution(v_revenue, v_total);
  v_margin := public.compute_projected_margin_percentage(v_revenue, v_contribution);
  v_break_even := public.compute_break_even_learner_count(
    v_total, v_scenario.assumed_net_tuition_per_learner
  );

  IF v_scenario.class_id IS NOT NULL THEN
    SELECT capacity INTO v_capacity
    FROM class
    WHERE id = v_scenario.class_id AND organization_id = v_org;
  ELSE
    v_capacity := v_scenario.capacity_snapshot;
  END IF;

  RETURN jsonb_build_object(
    'projected_revenue', v_revenue,
    'projected_direct_personnel', v_direct,
    'projected_shared_personnel', v_shared,
    'projected_operating_overhead', v_overhead,
    'projected_marketing_sales', v_marketing,
    'projected_depreciation', v_depreciation,
    'projected_total_cost', v_total,
    'projected_contribution', v_contribution,
    'projected_margin_percentage', v_margin,
    'break_even_learner_count', v_break_even,
    'capacity', v_capacity,
    'break_even_within_capacity', CASE
      WHEN v_break_even IS NULL OR v_capacity IS NULL THEN NULL
      ELSE v_break_even <= v_capacity
    END,
    'per_session_rate_used', v_rate
  );
END;
$$;

-- =============================================================================
-- IMMUTABILITY FOR FINALIZED SCENARIOS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_finalized_scenario()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'finalized' THEN
    IF NEW.scenario_name IS DISTINCT FROM OLD.scenario_name
      OR NEW.planned_learner_count IS DISTINCT FROM OLD.planned_learner_count
      OR NEW.assumed_net_tuition_per_learner IS DISTINCT FROM OLD.assumed_net_tuition_per_learner
      OR NEW.planned_months IS DISTINCT FROM OLD.planned_months
      OR NEW.planned_session_count IS DISTINCT FROM OLD.planned_session_count
      OR NEW.per_session_teacher_rate IS DISTINCT FROM OLD.per_session_teacher_rate
      OR NEW.staff_compensation_rule_id IS DISTINCT FROM OLD.staff_compensation_rule_id
      OR NEW.monthly_shared_personnel_assumption IS DISTINCT FROM OLD.monthly_shared_personnel_assumption
      OR NEW.monthly_operating_overhead_assumption IS DISTINCT FROM OLD.monthly_operating_overhead_assumption
      OR NEW.marketing_sales_assumption IS DISTINCT FROM OLD.marketing_sales_assumption
      OR NEW.marketing_assumption_basis IS DISTINCT FROM OLD.marketing_assumption_basis
      OR NEW.monthly_depreciation_assumption IS DISTINCT FROM OLD.monthly_depreciation_assumption
      OR NEW.economics_snapshot IS DISTINCT FROM OLD.economics_snapshot
      OR NEW.per_session_rate_snapshot IS DISTINCT FROM OLD.per_session_rate_snapshot
    THEN
      RAISE EXCEPTION 'finalized_scenario_immutable';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER class_financial_scenario_protect_finalized
  BEFORE UPDATE ON class_financial_scenario
  FOR EACH ROW EXECUTE FUNCTION protect_finalized_scenario();

-- =============================================================================
-- RPC: CREATE SCENARIO
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_class_financial_scenario(
  p_scenario_name text,
  p_planned_learner_count integer,
  p_assumed_net_tuition_per_learner bigint,
  p_planned_months integer,
  p_planned_session_count integer,
  p_class_id uuid DEFAULT NULL,
  p_per_session_teacher_rate bigint DEFAULT NULL,
  p_staff_compensation_rule_id uuid DEFAULT NULL,
  p_monthly_shared_personnel_assumption bigint DEFAULT 0,
  p_monthly_operating_overhead_assumption bigint DEFAULT 0,
  p_marketing_sales_assumption bigint DEFAULT 0,
  p_marketing_assumption_basis text DEFAULT 'one_time',
  p_monthly_depreciation_assumption bigint DEFAULT 0,
  p_capacity_snapshot integer DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_id uuid;
  v_capacity integer;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_planned_months IS NULL OR p_planned_months <= 0 THEN
    RAISE EXCEPTION 'invalid_planned_months' USING ERRCODE = 'P0001';
  END IF;

  IF p_class_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM class c WHERE c.id = p_class_id AND c.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'class_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_staff_compensation_rule_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM staff_compensation_rule r
    WHERE r.id = p_staff_compensation_rule_id AND r.organization_id = v_org
  ) THEN
    RAISE EXCEPTION 'compensation_rule_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_capacity := p_capacity_snapshot;
  IF p_class_id IS NOT NULL THEN
    SELECT capacity INTO v_capacity FROM class WHERE id = p_class_id AND organization_id = v_org;
  END IF;

  INSERT INTO class_financial_scenario (
    organization_id,
    class_id,
    scenario_name,
    planned_learner_count,
    assumed_net_tuition_per_learner,
    planned_months,
    planned_session_count,
    per_session_teacher_rate,
    staff_compensation_rule_id,
    monthly_shared_personnel_assumption,
    monthly_operating_overhead_assumption,
    marketing_sales_assumption,
    marketing_assumption_basis,
    monthly_depreciation_assumption,
    capacity_snapshot,
    created_by,
    updated_by
  ) VALUES (
    v_org,
    p_class_id,
    p_scenario_name,
    COALESCE(p_planned_learner_count, 0),
    COALESCE(p_assumed_net_tuition_per_learner, 0),
    p_planned_months,
    COALESCE(p_planned_session_count, 0),
    p_per_session_teacher_rate,
    p_staff_compensation_rule_id,
    COALESCE(p_monthly_shared_personnel_assumption, 0),
    COALESCE(p_monthly_operating_overhead_assumption, 0),
    COALESCE(p_marketing_sales_assumption, 0),
    COALESCE(p_marketing_assumption_basis, 'one_time'),
    COALESCE(p_monthly_depreciation_assumption, 0),
    v_capacity,
    public.current_app_user_id(),
    public.current_app_user_id()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- =============================================================================
-- RPC: UPDATE SCENARIO
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_class_financial_scenario(
  p_scenario_id uuid,
  p_scenario_name text DEFAULT NULL,
  p_planned_learner_count integer DEFAULT NULL,
  p_assumed_net_tuition_per_learner bigint DEFAULT NULL,
  p_planned_months integer DEFAULT NULL,
  p_planned_session_count integer DEFAULT NULL,
  p_per_session_teacher_rate bigint DEFAULT NULL,
  p_staff_compensation_rule_id uuid DEFAULT NULL,
  p_monthly_shared_personnel_assumption bigint DEFAULT NULL,
  p_monthly_operating_overhead_assumption bigint DEFAULT NULL,
  p_marketing_sales_assumption bigint DEFAULT NULL,
  p_marketing_assumption_basis text DEFAULT NULL,
  p_monthly_depreciation_assumption bigint DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_scenario class_financial_scenario%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_scenario
  FROM class_financial_scenario
  WHERE id = p_scenario_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_scenario.status <> 'draft' THEN
    RAISE EXCEPTION 'scenario_not_editable' USING ERRCODE = 'P0001';
  END IF;

  UPDATE class_financial_scenario
  SET
    scenario_name = COALESCE(p_scenario_name, scenario_name),
    planned_learner_count = COALESCE(p_planned_learner_count, planned_learner_count),
    assumed_net_tuition_per_learner = COALESCE(p_assumed_net_tuition_per_learner, assumed_net_tuition_per_learner),
    planned_months = COALESCE(p_planned_months, planned_months),
    planned_session_count = COALESCE(p_planned_session_count, planned_session_count),
    per_session_teacher_rate = COALESCE(p_per_session_teacher_rate, per_session_teacher_rate),
    staff_compensation_rule_id = COALESCE(p_staff_compensation_rule_id, staff_compensation_rule_id),
    monthly_shared_personnel_assumption = COALESCE(p_monthly_shared_personnel_assumption, monthly_shared_personnel_assumption),
    monthly_operating_overhead_assumption = COALESCE(p_monthly_operating_overhead_assumption, monthly_operating_overhead_assumption),
    marketing_sales_assumption = COALESCE(p_marketing_sales_assumption, marketing_sales_assumption),
    marketing_assumption_basis = COALESCE(p_marketing_assumption_basis, marketing_assumption_basis),
    monthly_depreciation_assumption = COALESCE(p_monthly_depreciation_assumption, monthly_depreciation_assumption),
    updated_by = public.current_app_user_id()
  WHERE id = p_scenario_id;

  RETURN p_scenario_id;
END;
$$;

-- =============================================================================
-- RPC: FINALIZE SCENARIO
-- =============================================================================

CREATE OR REPLACE FUNCTION public.finalize_class_financial_scenario(p_scenario_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_scenario class_financial_scenario%ROWTYPE;
  v_rate bigint;
  v_economics jsonb;
  v_capacity integer;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_scenario
  FROM class_financial_scenario
  WHERE id = p_scenario_id AND organization_id = v_org
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_scenario.status = 'finalized' THEN
    RETURN v_scenario.economics_snapshot;
  END IF;

  v_rate := public.resolve_scenario_per_session_rate(v_scenario);

  IF v_scenario.class_id IS NOT NULL THEN
    SELECT capacity INTO v_capacity
    FROM class WHERE id = v_scenario.class_id AND organization_id = v_org;
  ELSE
    v_capacity := v_scenario.capacity_snapshot;
  END IF;

  v_economics := public.calculate_scenario_economics(p_scenario_id);

  UPDATE class_financial_scenario
  SET
    status = 'finalized',
    per_session_rate_snapshot = v_rate,
    capacity_snapshot = v_capacity,
    economics_snapshot = v_economics,
    finalized_at = now(),
    finalized_by = public.current_app_user_id(),
    updated_by = public.current_app_user_id()
  WHERE id = p_scenario_id;

  RETURN v_economics;
END;
$$;

-- =============================================================================
-- RPC: CLONE SCENARIO
-- =============================================================================

CREATE OR REPLACE FUNCTION public.clone_class_financial_scenario(p_scenario_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_src class_financial_scenario%ROWTYPE;
  v_new_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.manage') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_src
  FROM class_financial_scenario
  WHERE id = p_scenario_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario_not_found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO class_financial_scenario (
    organization_id, class_id, scenario_name, status,
    planned_learner_count, tuition_assumption_mode, assumed_net_tuition_per_learner,
    planned_months, planned_session_count, per_session_teacher_rate,
    staff_compensation_rule_id, monthly_shared_personnel_assumption,
    monthly_operating_overhead_assumption, marketing_sales_assumption,
    marketing_assumption_basis, monthly_depreciation_assumption, capacity_snapshot,
    created_by, updated_by
  ) VALUES (
    v_src.organization_id, v_src.class_id, v_src.scenario_name || ' (copy)', 'draft',
    v_src.planned_learner_count, v_src.tuition_assumption_mode, v_src.assumed_net_tuition_per_learner,
    v_src.planned_months, v_src.planned_session_count, v_src.per_session_teacher_rate,
    v_src.staff_compensation_rule_id, v_src.monthly_shared_personnel_assumption,
    v_src.monthly_operating_overhead_assumption, v_src.marketing_sales_assumption,
    v_src.marketing_assumption_basis, v_src.monthly_depreciation_assumption, v_src.capacity_snapshot,
    public.current_app_user_id(), public.current_app_user_id()
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

-- =============================================================================
-- RPC: GET SCENARIO
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_class_financial_scenario(p_scenario_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_row class_financial_scenario%ROWTYPE;
  v_economics jsonb;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM class_financial_scenario
  WHERE id = p_scenario_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_economics := public.calculate_scenario_economics(p_scenario_id);

  RETURN jsonb_build_object(
    'scenario', to_jsonb(v_row),
    'economics', v_economics
  );
END;
$$;

-- =============================================================================
-- RPC: COMPARE SCENARIOS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.compare_class_financial_scenarios(
  p_class_id uuid DEFAULT NULL,
  p_scenario_ids uuid[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_result jsonb := '[]'::jsonb;
  v_rec record;
  v_economics jsonb;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  FOR v_rec IN
    SELECT s.*
    FROM class_financial_scenario s
    WHERE s.organization_id = v_org
      AND (
        (p_scenario_ids IS NOT NULL AND s.id = ANY(p_scenario_ids))
        OR (p_scenario_ids IS NULL AND p_class_id IS NOT NULL AND s.class_id = p_class_id)
      )
    ORDER BY s.created_at, s.id
  LOOP
    v_economics := public.calculate_scenario_economics(v_rec.id);
    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'scenario_id', v_rec.id,
      'scenario_name', v_rec.scenario_name,
      'status', v_rec.status,
      'planned_learner_count', v_rec.planned_learner_count,
      'assumed_net_tuition_per_learner', v_rec.assumed_net_tuition_per_learner,
      'projected_revenue', v_economics->'projected_revenue',
      'projected_total_cost', v_economics->'projected_total_cost',
      'projected_contribution', v_economics->'projected_contribution',
      'projected_margin_percentage', v_economics->'projected_margin_percentage',
      'break_even_learner_count', v_economics->'break_even_learner_count'
    ));
  END LOOP;

  RETURN jsonb_build_object('scenarios', v_result);
END;
$$;

-- =============================================================================
-- RPC: PROJECTED VS ACTUAL
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_projected_vs_actual_class_economics(
  p_scenario_id uuid,
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
  v_scenario class_financial_scenario%ROWTYPE;
  v_projected jsonb;
  v_actual jsonb;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('class_simulation.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_scenario
  FROM class_financial_scenario
  WHERE id = p_scenario_id AND organization_id = v_org;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_scenario.class_id IS NULL THEN
    RAISE EXCEPTION 'scenario_not_linked_to_class' USING ERRCODE = 'P0001';
  END IF;

  v_projected := public.calculate_scenario_economics(p_scenario_id);
  v_actual := public.get_class_economics(v_scenario.class_id, p_period_from, p_period_to);

  RETURN jsonb_build_object(
    'scenario_id', p_scenario_id,
    'class_id', v_scenario.class_id,
    'projected', v_projected,
    'actual', v_actual,
    'variance', jsonb_build_object(
      'revenue', COALESCE((v_actual->>'recognized_revenue')::bigint, 0)
        - COALESCE((v_projected->>'projected_revenue')::bigint, 0),
      'total_cost', COALESCE((v_actual->>'total_cost')::bigint, 0)
        - COALESCE((v_projected->>'projected_total_cost')::bigint, 0),
      'contribution', COALESCE((v_actual->>'contribution')::bigint, 0)
        - COALESCE((v_projected->>'projected_contribution')::bigint, 0)
    )
  );
END;
$$;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE class_financial_scenario ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_financial_scenario FORCE ROW LEVEL SECURITY;

CREATE POLICY class_financial_scenario_select ON class_financial_scenario FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('class_simulation.read'));

CREATE POLICY class_financial_scenario_insert ON class_financial_scenario FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('class_simulation.manage'));

CREATE POLICY class_financial_scenario_update ON class_financial_scenario FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('class_simulation.manage'))
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON class_financial_scenario TO authenticated;

GRANT EXECUTE ON FUNCTION public.compute_projected_class_total_cost(bigint, bigint, bigint, bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compute_projected_contribution(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compute_projected_margin_percentage(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compute_break_even_learner_count(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_scenario_economics(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_class_financial_scenario(text, integer, bigint, integer, integer, uuid, bigint, uuid, bigint, bigint, bigint, text, bigint, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_class_financial_scenario(uuid, text, integer, bigint, integer, integer, bigint, uuid, bigint, bigint, bigint, text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_class_financial_scenario(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clone_class_financial_scenario(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_financial_scenario(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compare_class_financial_scenarios(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_projected_vs_actual_class_economics(uuid, date, date) TO authenticated;
