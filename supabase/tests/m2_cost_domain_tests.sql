-- M2-T02: cost domain taxonomy regression (12 scenarios)

BEGIN;

CREATE TEMP TABLE _m2_cd_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

CREATE OR REPLACE FUNCTION _m2_cd_record(test_no integer, test_name text, passed boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO _m2_cd_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m2_cd_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m2_cd_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m2_cd_record(test_no, test_name, true);
  END;
END;
$$;

-- 1: new org receives four cost groups
DO $$
DECLARE
  org uuid := gen_random_uuid();
  cnt integer;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Cost Domains');
  SELECT count(*) INTO cnt FROM cost_group WHERE organization_id = org;
  PERFORM _m2_cd_record(1, 'new org has four cost groups', cnt = 4);
END $$;

-- 2: canonical domain codes are deterministic
DO $$
DECLARE
  org uuid := gen_random_uuid();
  codes text[];
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Domain Codes');
  SELECT array_agg(cost_domain_code ORDER BY cost_domain_code)
    INTO codes
  FROM cost_group
  WHERE organization_id = org;
  PERFORM _m2_cd_record(
    2,
    'canonical management codes are deterministic',
    codes = ARRAY['capital', 'marketing_sales', 'operating_overhead', 'personnel']::text[]
  );
END $$;

-- 3: B1 distinguishable from B2
DO $$
DECLARE
  org uuid := gen_random_uuid();
  b1 uuid; b2 uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 B1 B2');
  SELECT id INTO b1 FROM cost_group WHERE organization_id = org AND cost_domain_code = 'operating_overhead';
  SELECT id INTO b2 FROM cost_group WHERE organization_id = org AND cost_domain_code = 'personnel';
  PERFORM _m2_cd_record(3, 'B1 operating_overhead distinct from B2 personnel', b1 IS NOT NULL AND b2 IS NOT NULL AND b1 <> b2);
END $$;

-- 4: C distinct from B1 and B2
DO $$
DECLARE
  org uuid := gen_random_uuid();
  c uuid; b1 uuid; b2 uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Cost C');
  SELECT id INTO c FROM cost_group WHERE organization_id = org AND cost_domain_code = 'marketing_sales';
  SELECT id INTO b1 FROM cost_group WHERE organization_id = org AND cost_domain_code = 'operating_overhead';
  SELECT id INTO b2 FROM cost_group WHERE organization_id = org AND cost_domain_code = 'personnel';
  PERFORM _m2_cd_record(
    4,
    'C marketing_sales distinct from B1 and B2',
    c IS NOT NULL AND c <> b1 AND c <> b2
  );
END $$;

-- 5: Cost A exists
DO $$
DECLARE
  org uuid := gen_random_uuid();
  a uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Cost A');
  SELECT id INTO a FROM cost_group WHERE organization_id = org AND cost_domain_code = 'capital';
  PERFORM _m2_cd_record(5, 'Cost A capital domain exists', a IS NOT NULL);
END $$;

-- 6: category classification under correct domain
DO $$
DECLARE
  org uuid := gen_random_uuid();
  domain_code text;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Category Class');
  SELECT cg.cost_domain_code INTO domain_code
  FROM expense_category ec
  JOIN cost_group cg ON cg.id = ec.cost_group_id
  WHERE ec.organization_id = org AND ec.code = 'rent';
  PERFORM _m2_cd_record(6, 'rent category under operating_overhead', domain_code = 'operating_overhead');
END $$;

-- 7: expense snapshots cost_group_id at post time
DO $$
DECLARE
  org uuid := gen_random_uuid();
  cat uuid;
  g_overhead uuid;
  exp_group uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Snapshot');
  SELECT id INTO g_overhead FROM cost_group WHERE organization_id = org AND cost_domain_code = 'operating_overhead';
  SELECT id INTO cat FROM expense_category WHERE organization_id = org AND code = 'internet';
  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
    VALUES (org, cat, g_overhead, 10000, CURRENT_DATE);
  SELECT cost_group_id INTO exp_group FROM expense WHERE organization_id = org LIMIT 1;
  PERFORM _m2_cd_record(7, 'expense snapshots cost_group_id at post', exp_group = g_overhead);
END $$;

-- 8: reparenting category does not rewrite historical expense classification
DO $$
DECLARE
  org uuid := gen_random_uuid();
  g_overhead uuid;
  g_personnel uuid;
  cat uuid;
  snap uuid;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Reparent Snap');
  SELECT id INTO g_overhead FROM cost_group WHERE organization_id = org AND cost_domain_code = 'operating_overhead';
  SELECT id INTO g_personnel FROM cost_group WHERE organization_id = org AND cost_domain_code = 'personnel';
  SELECT id INTO cat FROM expense_category WHERE organization_id = org AND code = 'water';
  INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
    VALUES (org, cat, g_overhead, 20000, CURRENT_DATE);
  SELECT cost_group_id INTO snap FROM expense WHERE organization_id = org LIMIT 1;
  BEGIN
    UPDATE expense_category SET cost_group_id = g_personnel WHERE id = cat;
    PERFORM _m2_cd_record(8, 'reparent blocked preserves expense snapshot', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m2_cd_record(
      8,
      'reparent blocked preserves expense snapshot',
      snap = g_overhead AND (SELECT cost_group_id FROM expense WHERE organization_id = org LIMIT 1) = g_overhead
    );
  END;
END $$;

-- 9: cross-organization cost_group reference rejected
SELECT _m2_cd_expect_fail(
  9,
  'cross-org expense category group rejected',
  $$
    DO $inner$
    DECLARE
      org_a uuid := gen_random_uuid();
      org_b uuid := gen_random_uuid();
      g_b uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org_a, 'Org A'), (org_b, 'Org B');
      SELECT id INTO g_b FROM cost_group WHERE organization_id = org_b AND cost_domain_code = 'operating_overhead';
      INSERT INTO expense_category (organization_id, cost_group_id, code, display_name)
        VALUES (org_a, g_b, 'bad_cross_org', 'Bad');
    END $inner$;
  $$
);

-- 10: duplicate canonical domain per org rejected
SELECT _m2_cd_expect_fail(
  10,
  'duplicate cost_domain_code per org rejected',
  $$
    INSERT INTO cost_group (organization_id, group_slot, cost_domain_code, code)
    SELECT id, 3, 'operating_overhead', 'dup'
    FROM organization
    LIMIT 1;
  $$
);

-- 11: domain identity independent of translated display_name
DO $$
DECLARE
  org uuid := gen_random_uuid();
  domain_before text;
  domain_after text;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M2 Label Independence');
  SELECT cg.cost_domain_code INTO domain_before
  FROM expense_category ec
  JOIN cost_group cg ON cg.id = ec.cost_group_id
  WHERE ec.organization_id = org AND ec.code = 'welfare_fund';
  UPDATE expense_category SET display_name = 'Quỹ phúc lợi' WHERE organization_id = org AND code = 'welfare_fund';
  SELECT cg.cost_domain_code INTO domain_after
  FROM expense_category ec
  JOIN cost_group cg ON cg.id = ec.cost_group_id
  WHERE ec.organization_id = org AND ec.code = 'welfare_fund';
  PERFORM _m2_cd_record(
    11,
    'domain identity not derived from display_name',
    domain_before = 'personnel' AND domain_after = 'personnel'
  );
END $$;

-- 12: expense group/category mismatch still rejected
SELECT _m2_cd_expect_fail(
  12,
  'expense group category mismatch rejected',
  $$
    DO $inner$
    DECLARE
      org uuid := gen_random_uuid();
      cat uuid;
      g_personnel uuid;
    BEGIN
      INSERT INTO organization (id, name) VALUES (org, 'M2 Mismatch');
      SELECT id INTO cat FROM expense_category WHERE organization_id = org AND code = 'rent';
      SELECT id INTO g_personnel FROM cost_group WHERE organization_id = org AND cost_domain_code = 'personnel';
      INSERT INTO expense (organization_id, expense_category_id, cost_group_id, amount, incurred_date)
        VALUES (org, cat, g_personnel, 5000, CURRENT_DATE);
    END $inner$;
  $$
);

DO $$
DECLARE
  total integer; passed integer; failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
    INTO total, passed, failed
  FROM _m2_cd_results;

  RAISE NOTICE 'M2 cost domain Tests: % / % passed (% failed)', passed, total, failed;

  IF failed > 0 OR total <> 12 THEN
    RAISE EXCEPTION 'M2 cost domain tests failed: % of % (expected 12)', failed, total;
  END IF;
END $$;

SELECT test_no, test_name, result FROM _m2_cd_results ORDER BY test_no;

ROLLBACK;
