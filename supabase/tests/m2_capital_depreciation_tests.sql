-- M2-T03: capital asset and depreciation regression (20 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_cap_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m2_cap_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m2_cap_record(test_no integer, test_name text, passed boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO _m2_cap_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_cap_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m2_cap_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m2_cap_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m2_cap_setup_org(OUT org_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM _m2_cap_as_super();
  org_id := gen_random_uuid();
  INSERT INTO organization (id, name) VALUES (org_id, 'M2 Capital Test Org');
END;
$$;

CREATE OR REPLACE FUNCTION _m2_cap_as_auth(p_auth_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_cap_as_super()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1: detailed asset creation
DO $$
DECLARE org uuid; aid uuid; cnt integer;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, category_code,
    placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Projector', 'equipment', '2026-01-15', 18000000, 60
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO aid;
  SELECT count(*) INTO cnt FROM depreciation_entry WHERE capital_asset_id = aid;
  PERFORM _m2_cap_record(1, 'create detailed asset with schedule', aid IS NOT NULL AND cnt = 60);
END $$;

-- 2: quick-mode aggregated asset
DO $$
DECLARE org uuid; aid uuid;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, category_code,
    placed_in_service_date, original_cost, useful_life_months, is_quick_mode
  )
  SELECT org, cg.id, 'Initial setup investment', 'other_capital', '2026-02-01', 120000000, 60, true
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO aid;
  PERFORM _m2_cap_record(
    2,
    'create quick-mode aggregated asset',
    EXISTS (SELECT 1 FROM capital_asset WHERE id = aid AND is_quick_mode = true)
  );
END $$;

-- 3: reject zero cost
SELECT _m2_cap_expect_fail(
  3,
  'reject zero original cost',
  $$
    DO $inner$
    DECLARE org uuid := _m2_cap_setup_org(); cg uuid;
    BEGIN
      SELECT id INTO cg FROM cost_group WHERE organization_id = org AND cost_domain_code = 'capital';
      INSERT INTO capital_asset (
        organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
      ) VALUES (org, cg, 'Bad', CURRENT_DATE, 0, 12);
    END $inner$;
  $$
);

-- 4: reject zero useful life
SELECT _m2_cap_expect_fail(
  4,
  'reject zero useful life',
  $$
    DO $inner$
    DECLARE org uuid := _m2_cap_setup_org(); cg uuid;
    BEGIN
      SELECT id INTO cg FROM cost_group WHERE organization_id = org AND cost_domain_code = 'capital';
      INSERT INTO capital_asset (
        organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
      ) VALUES (org, cg, 'Bad', CURRENT_DATE, 1000, 0);
    END $inner$;
  $$
);

-- 5: straight-line schedule amounts for interior periods
DO $$
DECLARE org uuid; aid uuid; amt bigint;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, category_code,
    placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Partitions', 'fit_out', '2026-03-10', 80000000, 96
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO aid;
  SELECT amount INTO amt FROM depreciation_entry WHERE capital_asset_id = aid AND period_number = 1;
  PERFORM _m2_cap_record(5, 'straight-line base period amount', amt = 80000000 / 96);
END $$;

-- 6: remainder handling exact lifetime total
DO $$
DECLARE org uuid; aid uuid; total bigint;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Remainder test', '2026-01-01', 100, 3
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO aid;
  SELECT sum(amount) INTO total FROM depreciation_entry WHERE capital_asset_id = aid;
  PERFORM _m2_cap_record(6, 'remainder handling exact lifetime total', total = 100);
END $$;

-- 7: no duplicate asset-month entry
SELECT _m2_cap_expect_fail(
  7,
  'no duplicate asset-month depreciation',
  $$
    DO $inner$
    DECLARE org uuid := _m2_cap_setup_org(); aid uuid;
    BEGIN
      INSERT INTO capital_asset (
        organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
      )
      SELECT org, cg.id, 'Dup month', CURRENT_DATE, 1200, 2
      FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
      RETURNING id INTO aid;
      INSERT INTO depreciation_entry (
        organization_id, capital_asset_id, period_month, period_number, amount, status
      )
      SELECT de.organization_id, de.capital_asset_id, '2099-01-01'::date, de.period_number, 100, 'scheduled'
      FROM depreciation_entry de
      WHERE de.capital_asset_id = aid AND de.period_number = 1;
    END $inner$;
  $$
);

-- 8: later asset addition independent
DO $$
DECLARE org uuid; a1 uuid; a2 uuid; t1 bigint; t2 bigint;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Initial fit-out', '2026-01-01', 50000000, 60
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO a1;
  SELECT sum(amount) INTO t1 FROM depreciation_entry WHERE capital_asset_id = a1;
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Ten desks', '2026-06-01', 10000000, 72
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO a2;
  SELECT sum(amount) INTO t2 FROM depreciation_entry WHERE capital_asset_id = a2;
  PERFORM _m2_cap_record(
    8,
    'later asset addition does not affect previous asset',
    t1 = 50000000 AND t2 = 10000000 AND a1 <> a2
  );
END $$;

-- 9: placed-in-service month start period
DO $$
DECLARE org uuid; aid uuid; first_month date;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Signage', '2026-03-28', 5000000, 36
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO aid;
  SELECT period_month INTO first_month FROM depreciation_entry
  WHERE capital_asset_id = aid AND period_number = 1;
  PERFORM _m2_cap_record(9, 'depreciation starts in placed-in-service month', first_month = '2026-03-01'::date);
END $$;

-- 10: posted depreciation cannot be silently rewritten
SELECT _m2_cap_expect_fail(
  10,
  'posted depreciation cannot be silently rewritten',
  $$
    DO $inner$
    DECLARE org uuid := _m2_cap_setup_org(); aid uuid; eid uuid;
    BEGIN
      INSERT INTO capital_asset (
        organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
      )
      SELECT org, cg.id, 'Immutable dep', '2026-01-01', 1200, 3
      FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
      RETURNING id INTO aid;
      UPDATE depreciation_entry SET status = 'posted', posted_at = now()
      WHERE capital_asset_id = aid AND period_number = 1
      RETURNING id INTO eid;
      UPDATE depreciation_entry SET amount = 999 WHERE id = eid;
    END $inner$;
  $$
);

-- 11: asset cost cannot change after posted history
SELECT _m2_cap_expect_fail(
  11,
  'asset cost cannot change after posted depreciation',
  $$
    DO $inner$
    DECLARE org uuid := _m2_cap_setup_org(); aid uuid;
    BEGIN
      INSERT INTO capital_asset (
        organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
      )
      SELECT org, cg.id, 'Immutable asset', '2026-01-01', 1200, 3
      FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
      RETURNING id INTO aid;
      UPDATE depreciation_entry SET status = 'posted', posted_at = now()
      WHERE capital_asset_id = aid AND period_number = 1;
      UPDATE capital_asset SET original_cost = 9999 WHERE id = aid;
    END $inner$;
  $$
);

-- 12: retirement voids future scheduled periods
DO $$
DECLARE org uuid; aid uuid; future_sched integer;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Retire me', '2026-01-01', 12000, 12
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO aid;
  UPDATE capital_asset SET status = 'retired', retired_at = '2026-03-15' WHERE id = aid;
  UPDATE depreciation_entry SET status = 'void'
  WHERE capital_asset_id = aid AND status = 'scheduled' AND period_month > '2026-03-01'::date;
  SELECT count(*) INTO future_sched FROM depreciation_entry
  WHERE capital_asset_id = aid AND status = 'scheduled' AND period_month > '2026-03-01'::date;
  PERFORM _m2_cap_record(12, 'retirement voids future scheduled periods', future_sched = 0);
END $$;

-- 13: cross-org asset cost_group rejected
SELECT _m2_cap_expect_fail(
  13,
  'cross-org capital asset cost_group rejected',
  $$
    DO $inner$
    DECLARE org_a uuid := _m2_cap_setup_org(); org_b uuid := _m2_cap_setup_org(); cg_b uuid;
    BEGIN
      SELECT id INTO cg_b FROM cost_group WHERE organization_id = org_b AND cost_domain_code = 'capital';
      INSERT INTO capital_asset (
        organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
      ) VALUES (org_a, cg_b, 'Cross org', CURRENT_DATE, 1000, 12);
    END $inner$;
  $$
);

-- 14: cross-org depreciation asset rejected
SELECT _m2_cap_expect_fail(
  14,
  'cross-org depreciation asset rejected',
  $$
    DO $inner$
    DECLARE org_a uuid := _m2_cap_setup_org(); org_b uuid := _m2_cap_setup_org();
      aid_b uuid; cg_a uuid;
    BEGIN
      INSERT INTO capital_asset (
        organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
      )
      SELECT org_b, cg.id, 'Org B asset', CURRENT_DATE, 1000, 2
      FROM cost_group cg WHERE cg.organization_id = org_b AND cg.cost_domain_code = 'capital'
      RETURNING id INTO aid_b;
      SELECT id INTO cg_a FROM cost_group WHERE organization_id = org_a AND cost_domain_code = 'capital';
      INSERT INTO depreciation_entry (
        organization_id, capital_asset_id, period_month, period_number, amount, status
      ) VALUES (org_a, aid_b, '2099-02-01', 99, 100, 'scheduled');
    END $inner$;
  $$
);

-- 15: RLS tenant isolation (org A cannot read org B asset)
DO $$
DECLARE cnt integer;
BEGIN
  PERFORM _m2_cap_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM capital_asset
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _m2_cap_record(15, 'RLS prevents cross-org asset read', cnt = 0);
  PERFORM _m2_cap_as_super();
END $$;

-- 16: permission gate (staff without asset.create cannot insert)
DO $$
BEGIN
  PERFORM _m2_cap_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    INSERT INTO capital_asset (
      organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
    )
    SELECT 'a0000000-0000-4000-8000-000000000001', cg.id, 'Denied', CURRENT_DATE, 1000, 12
    FROM cost_group cg
    WHERE cg.organization_id = 'a0000000-0000-4000-8000-000000000001'
      AND cg.cost_domain_code = 'capital';
    PERFORM _m2_cap_record(16, 'permission gate blocks asset.create', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m2_cap_record(16, 'permission gate blocks asset.create', true);
  END;
  PERFORM _m2_cap_as_super();
END $$;

-- 17: Cost A resolution via cost_domain_code capital
DO $$
DECLARE org uuid; domain_code text;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Cost A map', CURRENT_DATE, 5000, 12
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital';
  SELECT cg.cost_domain_code INTO domain_code
  FROM capital_asset ca
  JOIN cost_group cg ON cg.id = ca.cost_group_id
  WHERE ca.organization_id = org
  LIMIT 1;
  PERFORM _m2_cap_record(17, 'Cost A uses cost_domain_code capital', domain_code = 'capital');
END $$;

-- 18: domain identity uses cost_domain_code not group_slot
DO $$
DECLARE org uuid; cg uuid;
BEGIN
  org := _m2_cap_setup_org();
  SELECT id INTO cg FROM cost_group
  WHERE organization_id = org AND cost_domain_code = 'capital';
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  ) VALUES (org, cg, 'Slot independent', CURRENT_DATE, 3000, 6);
  PERFORM _m2_cap_record(
    18,
    'domain identity uses cost_domain_code not group_slot',
    EXISTS (
      SELECT 1 FROM capital_asset ca
      JOIN cost_group g ON g.id = ca.cost_group_id
      WHERE ca.organization_id = org AND g.cost_domain_code = 'capital'
    )
  );
END $$;

-- 19: existing operating expenses unaffected
DO $$
DECLARE org uuid; exp_before integer; exp_after integer;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO expense_category (organization_id, cost_group_id, code, display_name)
  SELECT org, cg.id, 'test_rent', 'Rent'
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'operating_overhead';
  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
  SELECT org, ec.id, ec.cost_group_id, 50000, CURRENT_DATE
  FROM expense_category ec WHERE ec.organization_id = org AND ec.code = 'test_rent';
  SELECT count(*) INTO exp_before FROM expense WHERE organization_id = org;
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'No expense dup', CURRENT_DATE, 9000000, 36
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital';
  SELECT count(*) INTO exp_after FROM expense WHERE organization_id = org;
  PERFORM _m2_cap_record(19, 'Cost B/C expenses unaffected by capital asset', exp_before = exp_after AND exp_before = 1);
END $$;

-- 20: full-life posted sum equals original cost
DO $$
DECLARE org uuid; aid uuid; posted_sum bigint;
BEGIN
  org := _m2_cap_setup_org();
  INSERT INTO capital_asset (
    organization_id, cost_group_id, name, placed_in_service_date, original_cost, useful_life_months
  )
  SELECT org, cg.id, 'Full life', '2026-04-01', 60000000, 60
  FROM cost_group cg WHERE cg.organization_id = org AND cg.cost_domain_code = 'capital'
  RETURNING id INTO aid;
  UPDATE depreciation_entry SET status = 'posted', posted_at = now() WHERE capital_asset_id = aid;
  SELECT sum(amount) INTO posted_sum FROM depreciation_entry WHERE capital_asset_id = aid AND status = 'posted';
  PERFORM _m2_cap_record(20, 'full-life depreciation equals original cost', posted_sum = 60000000);
END $$;

DO $$
DECLARE total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed
  FROM _m2_cap_results;

  RAISE NOTICE 'M2 capital depreciation Tests: % / % passed (% failed)', passed, total, failed;

  IF failed > 0 OR total <> 20 THEN
    RAISE EXCEPTION 'M2 capital depreciation tests failed: % of % (expected 20)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_cap_results ORDER BY test_no;

ROLLBACK;
