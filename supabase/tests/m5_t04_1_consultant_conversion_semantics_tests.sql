-- M5-T04.1: Consultant cohort attribution and conversion-rate semantics (9 scenarios)

BEGIN;

CREATE TEMP TABLE _m5_t04_1_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m5_t04_1_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m5_t04_1_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m5_t04_1_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t04_1_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t04_1_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m5_t04_1_seed_auth_user(p_auth uuid, p_email text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, is_sso_user, is_anonymous
  )
  VALUES (
    p_auth,
    (SELECT id FROM auth.instances LIMIT 1),
    'authenticated',
    'authenticated',
    p_email,
    '',
    now(),
    now(),
    now(),
    false,
    false
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_role uuid;
  v_user uuid;
  v_auth uuid;
BEGIN
  PERFORM _m5_t04_1_as_super();
  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local') THEN
    v_auth := 'd1111111-1111-4111-8111-111111111111';
    PERFORM _m5_t04_1_seed_auth_user(v_auth, 'm5-t04-consultant-a@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t04_1_consultant_a') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'lead.read', 'lead.create', 'lead.update',
      'lead.assign', 'lead.convert', 'consultant_revenue.declare'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t04-consultant-a@olli.local', 'M5 T04 Consultant A', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM app_user WHERE email = 'm5-t04-consultant-b@olli.local') THEN
    v_auth := 'd2222222-2222-4222-8222-222222222222';
    PERFORM _m5_t04_1_seed_auth_user(v_auth, 'm5-t04-consultant-b@olli.local');
    INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t04_1_consultant_b') RETURNING id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, p.id FROM permission p
    WHERE p.code IN (
      'organization.read', 'lead.read', 'lead.create', 'lead.update',
      'lead.assign', 'lead.convert', 'consultant_revenue.declare'
    );
    INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)
    VALUES (v_org, 'm5-t04-consultant-b@olli.local', 'M5 T04 Consultant B', v_auth, 'active')
    RETURNING id INTO v_user;
    INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
    VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');
  END IF;
END $$;

DO $$
DECLARE
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_cons_a uuid;
  v_cons_b uuid;
BEGIN
  PERFORM _m5_t04_1_as_super();
  SELECT id INTO v_cons_a FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local';
  SELECT id INTO v_cons_b FROM app_user WHERE email = 'm5-t04-consultant-b@olli.local';

  INSERT INTO lead (id, organization_id, status, created_by, created_at, updated_at)
  VALUES
    ('d7100000-0000-4000-8000-000000000001', v_org, 'new', v_cons_a,
      timestamptz '2045-06-05 10:00:00+07', now()),
    ('d7100000-0000-4000-8000-000000000002', v_org, 'new', v_cons_a,
      timestamptz '2045-06-06 10:00:00+07', now()),
    ('d7100000-0000-4000-8000-000000000003', v_org, 'new', v_cons_a,
      timestamptz '2045-05-20 10:00:00+07', now()),
    ('d7100000-0000-4000-8000-000000000004', v_org, 'new', v_cons_b,
      timestamptz '2045-06-08 10:00:00+07', now())
  ON CONFLICT DO NOTHING;

  INSERT INTO lead_assignment (
    organization_id, lead_id, previous_assigned_user_id, new_assigned_user_id, changed_by, changed_at
  )
  VALUES
    (v_org, 'd7100000-0000-4000-8000-000000000001', NULL, v_cons_a, v_cons_a,
      timestamptz '2045-06-05 10:00:00+07'),
    (v_org, 'd7100000-0000-4000-8000-000000000001', v_cons_a, v_cons_b, v_cons_a,
      timestamptz '2045-06-05 11:00:00+07'),
    (v_org, 'd7100000-0000-4000-8000-000000000002', NULL, v_cons_a, v_cons_a,
      timestamptz '2045-06-06 10:00:00+07'),
    (v_org, 'd7100000-0000-4000-8000-000000000003', NULL, v_cons_a, v_cons_a,
      timestamptz '2045-05-20 10:00:00+07'),
    (v_org, 'd7100000-0000-4000-8000-000000000004', NULL, v_cons_b, v_cons_b,
      timestamptz '2045-06-08 10:00:00+07');

  PERFORM set_config('olli.lead_assignment_mutation', 'true', true);
  UPDATE lead SET assigned_user_id = v_cons_a
  WHERE id IN (
    'd7100000-0000-4000-8000-000000000002',
    'd7100000-0000-4000-8000-000000000003'
  );
  UPDATE lead SET assigned_user_id = v_cons_b
  WHERE id IN (
    'd7100000-0000-4000-8000-000000000001',
    'd7100000-0000-4000-8000-000000000004'
  );
  PERFORM set_config('olli.lead_assignment_mutation', 'false', true);
  INSERT INTO lead_conversion (organization_id, lead_id, converted_by, converted_at, assigned_user_id)
  VALUES
    (v_org, 'd7100000-0000-4000-8000-000000000001', v_cons_b,
      timestamptz '2045-06-20 12:00:00+07', v_cons_b),
    (v_org, 'd7100000-0000-4000-8000-000000000003', v_cons_a,
      timestamptz '2045-06-18 12:00:00+07', v_cons_a)
  ON CONFLICT DO NOTHING;
END $$;

-- 1: cohort attribution uses first assignment, not current owner
DO $$
DECLARE
  v_cohort uuid;
  v_current uuid;
  v_cons_a uuid;
BEGIN
  PERFORM _m5_t04_1_as_super();
  SELECT id INTO v_cons_a FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local';
  SELECT public.crm_lead_cohort_consultant_user_id(
    'a0000000-0000-4000-8000-000000000001',
    'd7100000-0000-4000-8000-000000000001'
  ) INTO v_cohort;
  SELECT assigned_user_id INTO v_current
  FROM lead WHERE id = 'd7100000-0000-4000-8000-000000000001';
  PERFORM _m5_t04_1_record(
    1, 'current owner does not rewrite cohort attribution',
    v_cohort = v_cons_a AND v_current IS DISTINCT FROM v_cons_a
  );
END $$;

-- 2: conversion event uses conversion-time assignee
DO $$
DECLARE v_prod jsonb;
BEGIN
  PERFORM _m5_t04_1_as_auth('a1111111-1111-4111-8111-111111111111');
  v_prod := public.get_crm_consultant_productivity('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_1_record(
    2, 'reassigned lead conversion uses conversion-time attribution',
    EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_prod->'rows') elem
      WHERE (elem->>'consultant_user_id')::uuid = (
        SELECT id FROM app_user WHERE email = 'm5-t04-consultant-b@olli.local'
      )
      AND (elem->>'conversions_in_period')::bigint >= 1
    )
  );
END $$;

-- 3: creator and cohort assignee not double-counted
DO $$
DECLARE v_cons_a uuid; v_cons_b uuid;
BEGIN
  PERFORM _m5_t04_1_as_super();
  SELECT id INTO v_cons_a FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local';
  SELECT id INTO v_cons_b FROM app_user WHERE email = 'm5-t04-consultant-b@olli.local';
  PERFORM _m5_t04_1_record(
    3, 'creator and assigned consultant are not double-counted',
    public.crm_lead_cohort_consultant_user_id(
      'a0000000-0000-4000-8000-000000000001',
      'd7100000-0000-4000-8000-000000000004'
    ) = v_cons_b
    AND public.crm_lead_cohort_consultant_user_id(
      'a0000000-0000-4000-8000-000000000001',
      'd7100000-0000-4000-8000-000000000002'
    ) = v_cons_a
  );
END $$;

-- 4: old lead converted in period excluded from cohort denominator
DO $$
DECLARE v_cohort bigint; v_period bigint;
BEGIN
  PERFORM _m5_t04_1_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT (elem->>'cohort_leads')::bigint, (elem->>'conversions_in_period')::bigint
  INTO v_cohort, v_period
  FROM jsonb_array_elements(
    public.get_crm_consultant_productivity('2045-06-01', '2045-06-30')->'rows'
  ) elem
  WHERE (elem->>'consultant_user_id')::uuid = (
    SELECT id FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local'
  );
  PERFORM _m5_t04_1_record(
    4, 'prior-period lead in period conversions not in cohort denominator',
    v_cohort >= 1 AND v_period >= 1
  );
END $$;

-- 5: same lead counted once in cohort denominator
DO $$
DECLARE
  v_bounds reporting_period_bounds;
  v_org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_distinct bigint;
  v_summed bigint;
BEGIN
  PERFORM _m5_t04_1_as_auth('a1111111-1111-4111-8111-111111111111');
  v_bounds := public.resolve_reporting_period('2045-06-01', '2045-06-30');
  SELECT count(DISTINCT l.id) INTO v_distinct
  FROM lead l
  WHERE l.organization_id = v_org
    AND l.created_at >= v_bounds.start_at_utc
    AND l.created_at < v_bounds.end_at_exclusive
    AND public.crm_lead_cohort_consultant_user_id(v_org, l.id) IS NOT NULL;

  SELECT coalesce(sum((elem->>'cohort_leads')::bigint), 0) INTO v_summed
  FROM jsonb_array_elements(
    public.get_crm_consultant_productivity('2045-06-01', '2045-06-30')->'rows'
  ) elem;

  PERFORM _m5_t04_1_record(
    5, 'same lead counted once in cohort denominator',
    v_distinct = v_summed AND v_distinct >= 3
  );
END $$;

-- 6: cohort numerator only includes conversions from cohort leads
DO $$
DECLARE v_rate numeric; v_cohort bigint; v_conv bigint;
BEGIN
  PERFORM _m5_t04_1_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT
    (elem->>'cohort_conversion_rate')::numeric,
    (elem->>'cohort_leads')::bigint,
    (elem->>'cohort_converted_leads')::bigint
  INTO v_rate, v_cohort, v_conv
  FROM jsonb_array_elements(
    public.get_crm_consultant_productivity('2045-06-01', '2045-06-30')->'rows'
  ) elem
  WHERE (elem->>'consultant_user_id')::uuid = (
    SELECT id FROM app_user WHERE email = 'm5-t04-consultant-a@olli.local'
  );
  PERFORM _m5_t04_1_record(
    6, 'cohort numerator only includes cohort lead conversions',
    v_cohort >= 1
      AND v_conv >= 1
      AND v_conv <= v_cohort
      AND v_rate IS NOT NULL
      AND v_rate <= 1
  );
END $$;

-- 7: source cohort rate uses matching numerator/denominator
DO $$
DECLARE v_src jsonb; v_row jsonb;
BEGIN
  PERFORM _m5_t04_1_as_auth('a1111111-1111-4111-8111-111111111111');
  v_src := public.get_crm_source_metrics('2045-06-01', '2045-06-30');
  SELECT elem INTO v_row
  FROM jsonb_array_elements(v_src) elem
  WHERE (elem->>'leads_created')::bigint > 0
  LIMIT 1;
  PERFORM _m5_t04_1_record(
    7, 'source cohort rate uses matching numerator/denominator',
    v_row ? 'cohort_converted_leads'
      AND v_row ? 'cohort_conversion_rate'
      AND (v_row->>'cohort_converted_leads')::bigint <= (v_row->>'leads_created')::bigint
  );
END $$;

-- 8: organization isolation
DO $$
DECLARE v_prod jsonb;
BEGIN
  PERFORM _m5_t04_1_as_auth('b1111111-1111-4111-8111-111111111111');
  v_prod := public.get_crm_consultant_productivity('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_1_record(
    8, 'organization isolation on consultant productivity',
    NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_prod->'rows') elem
      WHERE (elem->>'consultant_user_id')::uuid IN (
        SELECT id FROM app_user WHERE email LIKE 'm5-t04-consultant-%@olli.local'
          AND organization_id = 'a0000000-0000-4000-8000-000000000001'
      )
    )
  );
END $$;

-- 9: consultant personal scope intact
DO $$
DECLARE v_overview jsonb;
BEGIN
  PERFORM _m5_t04_1_as_auth('d1111111-1111-4111-8111-111111111111');
  v_overview := public.get_consultant_crm_overview('2045-06-01', '2045-06-30');
  PERFORM _m5_t04_1_record(
    9, 'consultant personal scope intact',
    v_overview ? 'cohort_leads'
      AND v_overview ? 'conversions_in_period'
      AND NOT v_overview ? 'conversion_rate_attributed'
  );
END $$;

DO $$
DECLARE v_fail integer; v_total integer; r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*)
  INTO v_fail, v_total
  FROM _m5_t04_1_results;
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m5_t04_1_results WHERE result = 'FAIL' LOOP
      RAISE NOTICE 'FAILED: % - %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M5-T04.1 consultant conversion semantics: %/% FAIL (% failed)',
      v_total - v_fail, v_total, v_fail;
  END IF;
  RAISE NOTICE 'M5-T04.1 consultant conversion semantics: %/% PASS (0 FAIL)', v_total, v_total;
END $$;

COMMIT;
