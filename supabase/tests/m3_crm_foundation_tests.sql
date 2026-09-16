-- M3-T02: CRM foundation integrity, tenant isolation, and security tests.

BEGIN;

CREATE TEMP TABLE _m3_crm_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_crm_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_crm_record(test_no integer, test_name text, passed boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO _m3_crm_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_crm_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m3_crm_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m3_crm_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_crm_as_auth(p_auth_id uuid)
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

CREATE OR REPLACE FUNCTION _m3_crm_as_super()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- Fixture UUIDs (must match supabase/seed.sql)
-- Org A: a0000000-0000-4000-8000-000000000001
-- Org B: b0000000-0000-4000-8000-000000000001
-- Org A admin auth: a1111111-1111-4111-8111-111111111111
-- Org B admin auth: b1111111-1111-4111-8111-111111111111
-- Org A admin app_user: a1000000-0000-4000-8000-000000000001

-- 1: CRM tables exist after fresh reset
DO $$
DECLARE
  cnt integer;
BEGIN
  SELECT count(*) INTO cnt
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN (
      'lead', 'lead_candidate', 'lead_contact',
      'lead_source', 'lead_campaign', 'lead_lost_reason'
    );
  PERFORM _m3_crm_record(1, 'CRM tables exist', cnt = 6);
END $$;

-- 2: FORCE RLS active on CRM tables
DO $$
DECLARE
  cnt integer;
BEGIN
  SELECT count(*) INTO cnt
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN (
      'lead', 'lead_candidate', 'lead_contact',
      'lead_source', 'lead_campaign', 'lead_lost_reason'
    )
    AND c.relrowsecurity = true
    AND c.relforcerowsecurity = true;
  PERFORM _m3_crm_record(2, 'FORCE RLS active on CRM tables', cnt = 6);
END $$;

-- 3: six CRM permissions exist exactly once
DO $$
DECLARE
  cnt integer;
BEGIN
  SELECT count(*) INTO cnt
  FROM permission
  WHERE code IN (
    'lead.read', 'lead.create', 'lead.update',
    'lead.assign', 'lead.convert', 'lead.manage_sources'
  );
  PERFORM _m3_crm_record(3, 'six CRM permissions exist', cnt = 6);
END $$;

-- 4: new org receives seeded lead sources
DO $$
DECLARE
  org uuid := gen_random_uuid();
  cnt integer;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M3 CRM Seed Org');
  SELECT count(*) INTO cnt FROM lead_source WHERE organization_id = org;
  PERFORM _m3_crm_record(4, 'new org receives seeded lead sources', cnt >= 7);
END $$;

-- 5: new org receives seeded lost reasons
DO $$
DECLARE
  org uuid := gen_random_uuid();
  cnt integer;
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M3 Lost Reason Seed');
  SELECT count(*) INTO cnt FROM lead_lost_reason WHERE organization_id = org;
  PERFORM _m3_crm_record(5, 'new org receives seeded lost reasons', cnt >= 7);
END $$;

-- 6: lead source code unique per organization
DO $$
DECLARE
  org uuid := gen_random_uuid();
BEGIN
  INSERT INTO organization (id, name) VALUES (org, 'M3 Source Unique');
  PERFORM _m3_crm_expect_fail(
    6,
    'lead source code unique per org',
    format(
      $sql$INSERT INTO lead_source (organization_id, code, display_name)
         SELECT %L, code, display_name FROM lead_source WHERE organization_id = %L LIMIT 1$sql$,
      org,
      org
    )
  );
END $$;

-- 7: invalid pipeline status rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_crm_expect_fail(
    7,
    'invalid pipeline status rejected',
    format(
      $sql$INSERT INTO lead (organization_id, status) VALUES (%L, 'invalid_status')$sql$,
      org
    )
  );
END $$;

-- 8: lost lead requires lost reason
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_crm_expect_fail(
    8,
    'lost lead requires lost reason',
    format(
      $sql$INSERT INTO lead (organization_id, status) VALUES (%L, 'lost')$sql$,
      org
    )
  );
END $$;

-- 9: valid multi-candidate lead
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES
    (org, v_lead, 'An', 'Nguyễn', true),
    (org, v_lead, 'Bình', 'Nguyễn', false);
  SELECT count(*) INTO cnt FROM lead_candidate WHERE lead_id = v_lead;
  PERFORM _m3_crm_record(9, 'valid multi-candidate lead', cnt = 2);
END $$;

-- 10: valid multi-contact lead
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact)
  VALUES
    (org, v_lead, 'Lan', 'Nguyễn', '0901 111 111', true),
    (org, v_lead, 'Hùng', 'Nguyễn', '0901 111 111', false);
  SELECT count(*) INTO cnt FROM lead_contact WHERE lead_id = v_lead;
  PERFORM _m3_crm_record(10, 'valid multi-contact lead', cnt = 2);
END $$;

-- 11: shared family phone does not violate uniqueness
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead1 uuid;
  v_lead2 uuid;
  ok boolean := true;
BEGIN
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead1;
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead2;
  BEGIN
    INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact)
    VALUES (org, v_lead1, 'Mai', 'Trần', '0909-888-777', true);
    INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact)
    VALUES (org, v_lead2, 'Nam', 'Trần', '0909-888-777', true);
  EXCEPTION WHEN OTHERS THEN
    ok := false;
  END;
  PERFORM _m3_crm_record(11, 'shared phone allowed across leads', ok);
END $$;

-- 12: phone normalization is deterministic
DO $$
DECLARE
  norm text;
BEGIN
  norm := public.normalize_phone_digits('(+84) 901-234-567');
  PERFORM _m3_crm_record(12, 'phone normalization deterministic', norm = '84901234567');
END $$;

-- 13: email normalization is deterministic
DO $$
DECLARE
  norm text;
BEGIN
  norm := public.normalize_email_key('  Admin@Example.COM ');
  PERFORM _m3_crm_record(13, 'email normalization deterministic', norm = 'admin@example.com');
END $$;

-- 14: cross-org lead source linkage rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  src_b uuid;
BEGIN
  SELECT id INTO src_b FROM lead_source WHERE organization_id = org_b LIMIT 1;
  PERFORM _m3_crm_expect_fail(
    14,
    'cross-org lead source linkage rejected',
    format(
      $sql$INSERT INTO lead (organization_id, status, lead_source_id)
         VALUES (%L, 'new', %L)$sql$,
      org_a,
      src_b
    )
  );
END $$;

-- 15: cross-org campaign linkage rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  src_b uuid;
  camp_b uuid;
BEGIN
  INSERT INTO lead_campaign (organization_id, code, name, lead_source_id)
  SELECT org_b, 'summer_2026', 'Summer 2026', id
  FROM lead_source WHERE organization_id = org_b LIMIT 1
  RETURNING id INTO camp_b;

  PERFORM _m3_crm_expect_fail(
    15,
    'cross-org campaign linkage rejected',
    format(
      $sql$INSERT INTO lead (organization_id, status, lead_campaign_id)
         VALUES (%L, 'new', %L)$sql$,
      org_a,
      camp_b
    )
  );
END $$;

-- 16: cross-org lost reason linkage rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  reason_b uuid;
BEGIN
  SELECT id INTO reason_b FROM lead_lost_reason WHERE organization_id = org_b LIMIT 1;
  PERFORM _m3_crm_expect_fail(
    16,
    'cross-org lost reason linkage rejected',
    format(
      $sql$INSERT INTO lead (organization_id, status, lost_reason_id)
         VALUES (%L, 'lost', %L)$sql$,
      org_a,
      reason_b
    )
  );
END $$;

-- 17: candidate cannot attach to another org lead
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  lead_b uuid;
BEGIN
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO lead_b;
  PERFORM _m3_crm_expect_fail(
    17,
    'candidate cannot attach to other org lead',
    format(
      $sql$INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name)
         VALUES (%L, %L, 'Test', 'User')$sql$,
      org_a,
      lead_b
    )
  );
END $$;

-- 18: contact cannot attach to another org lead
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  lead_b uuid;
BEGIN
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO lead_b;
  PERFORM _m3_crm_expect_fail(
    18,
    'contact cannot attach to other org lead',
    format(
      $sql$INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name)
         VALUES (%L, %L, 'Test', 'Contact')$sql$,
      org_a,
      lead_b
    )
  );
END $$;

-- 19: cross-org assignment rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  user_b uuid := 'b1000000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_crm_expect_fail(
    19,
    'cross-org assignment rejected',
    format(
      $sql$INSERT INTO lead (organization_id, status, assigned_user_id)
         VALUES (%L, 'new', %L)$sql$,
      org_a,
      user_b
    )
  );
END $$;

-- 20: nullable assignment works
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  INSERT INTO lead (organization_id, status, assigned_user_id)
  VALUES (org, 'new', NULL)
  RETURNING id INTO v_lead;
  PERFORM _m3_crm_record(20, 'nullable assignment works', v_lead IS NOT NULL);
END $$;

-- 21: referenced lead source cannot be deleted
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  src uuid;
  v_lead uuid;
BEGIN
  SELECT id INTO src FROM lead_source WHERE organization_id = org AND code = 'walk_in';
  INSERT INTO lead (organization_id, status, lead_source_id)
  VALUES (org, 'new', src)
  RETURNING id INTO v_lead;
  PERFORM _m3_crm_expect_fail(
    21,
    'referenced lead source delete blocked',
    format($sql$DELETE FROM lead_source WHERE id = %L$sql$, src)
  );
END $$;

-- 22: lead creation has no M1 side effects
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  before_students integer;
  before_guardians integer;
  before_enrollments integer;
  after_students integer;
  after_guardians integer;
  after_enrollments integer;
  v_lead uuid;
BEGIN
  SELECT count(*) INTO before_students FROM student WHERE organization_id = org;
  SELECT count(*) INTO before_guardians FROM guardian WHERE organization_id = org;
  SELECT count(*) INTO before_enrollments FROM enrollment WHERE organization_id = org;

  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'CRM', 'Only', true);
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact)
  VALUES (org, v_lead, 'Parent', 'Only', '0900000111', true);

  SELECT count(*) INTO after_students FROM student WHERE organization_id = org;
  SELECT count(*) INTO after_guardians FROM guardian WHERE organization_id = org;
  SELECT count(*) INTO after_enrollments FROM enrollment WHERE organization_id = org;

  PERFORM _m3_crm_record(
    22,
    'lead creation has no M1 side effects',
    before_students = after_students
      AND before_guardians = after_guardians
      AND before_enrollments = after_enrollments
  );
END $$;

-- 23: lead creation has no M2 side effects
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  before_charges integer;
  before_payments integer;
  after_charges integer;
  after_payments integer;
  v_lead uuid;
BEGIN
  SELECT count(*) INTO before_charges FROM charge WHERE organization_id = org;
  SELECT count(*) INTO before_payments FROM payment WHERE organization_id = org;

  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;

  SELECT count(*) INTO after_charges FROM charge WHERE organization_id = org;
  SELECT count(*) INTO after_payments FROM payment WHERE organization_id = org;

  PERFORM _m3_crm_record(
    23,
    'lead creation has no M2 side effects',
    before_charges = after_charges AND before_payments = after_payments
  );
END $$;

-- 24: org A admin reads org A leads via RLS
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_crm_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'new') RETURNING id INTO v_lead;

  PERFORM _m3_crm_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM lead WHERE id = v_lead;
  PERFORM _m3_crm_record(24, 'org A admin reads org A leads', cnt = 1);
  PERFORM _m3_crm_as_super();
END $$;

-- 25: org A cannot read org B leads
DO $$
DECLARE
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_crm_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO v_lead;

  PERFORM _m3_crm_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt FROM lead WHERE id = v_lead;
  PERFORM _m3_crm_record(25, 'org A cannot read org B leads', cnt = 0);
  PERFORM _m3_crm_as_super();
END $$;

-- 26: org A cannot mutate org B leads
DO $$
DECLARE
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  updated integer;
BEGIN
  PERFORM _m3_crm_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'new') RETURNING id INTO v_lead;

  PERFORM _m3_crm_as_auth('a1111111-1111-4111-8111-111111111111');
  UPDATE lead SET notes_summary = 'cross org hack' WHERE id = v_lead;
  GET DIAGNOSTICS updated = ROW_COUNT;
  PERFORM _m3_crm_record(26, 'org A cannot mutate org B leads', updated = 0);
  PERFORM _m3_crm_as_super();
END $$;

-- 27: org A cannot read org B lead sources
DO $$
DECLARE
  cnt integer;
BEGIN
  PERFORM _m3_crm_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt
  FROM lead_source
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001';
  PERFORM _m3_crm_record(27, 'org A cannot read org B lead sources', cnt = 0);
  PERFORM _m3_crm_as_super();
END $$;

-- 28: only one active primary contact per lead
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Primary', 'One', true);
  PERFORM _m3_crm_expect_fail(
    28,
    'one active primary contact per lead',
    format(
      $sql$INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
         VALUES (%L, %L, 'Primary', 'Two', true)$sql$,
      org,
      v_lead
    )
  );
END $$;

-- 29: only one active primary candidate per lead
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
BEGIN
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Primary', 'Candidate', true);
  PERFORM _m3_crm_expect_fail(
    29,
    'one active primary candidate per lead',
    format(
      $sql$INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
         VALUES (%L, %L, 'Second', 'Primary', true)$sql$,
      org,
      v_lead
    )
  );
END $$;

-- Report
DO $$
DECLARE
  total integer;
  passed integer;
  failed integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE result = 'PASS'), count(*) FILTER (WHERE result = 'FAIL')
  INTO total, passed, failed
  FROM _m3_crm_results;

  IF failed > 0 THEN
    RAISE EXCEPTION 'M3 CRM Foundation Tests: % / % passed (% failed)', passed, total, failed;
  END IF;

  RAISE NOTICE 'M3 CRM Foundation Tests: % / % passed (0 failed)', passed, total;
END $$;

COMMIT;
