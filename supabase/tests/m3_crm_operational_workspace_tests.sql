-- M3-T09: CRM operational workspace — intake, edits, catalogs, and guards.

BEGIN;

CREATE TEMP TABLE _m3_ow_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_ow_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_ow_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_ow_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_ow_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m3_ow_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m3_ow_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_ow_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_ow_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1: create_lead_with_people requires lead.create
DO $$
BEGIN
  PERFORM _m3_ow_as_auth('a2222222-2222-4222-8222-222222222222');
  PERFORM _m3_ow_expect_fail(
    1,
    'create_lead_with_people requires lead.create',
    $sql$SELECT public.create_lead_with_people(
      '{"notes_summary":"x"}'::jsonb,
      '[{"given_name":"A","family_name":"B"}]'::jsonb,
      '[{"given_name":"C","family_name":"D","phone":"0900123456"}]'::jsonb
    )$sql$
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 2: admin can create lead with people same org
DO $$
DECLARE
  result jsonb;
  v_lead uuid;
  cand_cnt integer;
  contact_cnt integer;
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_lead_with_people(
    jsonb_build_object('notes_summary', 'OW test intake'),
    jsonb_build_array(
      jsonb_build_object('given_name', 'An', 'family_name', 'Nguyen'),
      jsonb_build_object('given_name', 'Binh', 'family_name', 'Nguyen', 'is_primary_candidate', true)
    ),
    jsonb_build_array(
      jsonb_build_object('given_name', 'Chi', 'family_name', 'Nguyen', 'phone', '0900999888', 'email', 'chi@example.com')
    )
  ) INTO result;
  v_lead := (result->>'lead_id')::uuid;
  SELECT count(*) INTO cand_cnt FROM lead_candidate WHERE lead_id = v_lead;
  SELECT count(*) INTO contact_cnt FROM lead_contact WHERE lead_id = v_lead;
  PERFORM _m3_ow_record(2, 'create lead with people same org', cand_cnt = 2 AND contact_cnt = 1);
  PERFORM _m3_ow_as_super();
END $$;

-- 3: invalid contact rejected atomically
DO $$
DECLARE
  ok boolean := false;
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.create_lead_with_people(
      '{}'::jsonb,
      '[{"given_name":"Only","family_name":"Candidate"}]'::jsonb,
      '[{"given_name":"","family_name":"Bad"}]'::jsonb
    );
  EXCEPTION WHEN OTHERS THEN
    ok := true;
  END;
  PERFORM _m3_ow_record(3, 'invalid contact rejected on intake', ok);
  PERFORM _m3_ow_as_super();
END $$;

-- 4: invalid source rejected
DO $$
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    4,
    'invalid source rejected',
    $sql$SELECT public.create_lead_with_people(
      jsonb_build_object('lead_source_id', gen_random_uuid()::text),
      '[{"given_name":"A","family_name":"B"}]'::jsonb,
      '[{"given_name":"C","family_name":"D"}]'::jsonb
    )$sql$
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 5: invalid campaign rejected
DO $$
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    5,
    'invalid campaign rejected',
    $sql$SELECT public.create_lead_with_people(
      jsonb_build_object('lead_campaign_id', gen_random_uuid()::text),
      '[{"given_name":"A","family_name":"B"}]'::jsonb,
      '[{"given_name":"C","family_name":"D"}]'::jsonb
    )$sql$
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 6: cross-org source rejected
DO $$
DECLARE
  org_b_source uuid;
BEGIN
  PERFORM _m3_ow_as_super();
  SELECT id INTO org_b_source FROM lead_source
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    6,
    'cross-org source rejected',
    format(
      $sql$SELECT public.create_lead_with_people(
        jsonb_build_object('lead_source_id', %L),
        '[{"given_name":"A","family_name":"B"}]'::jsonb,
        '[{"given_name":"C","family_name":"D"}]'::jsonb
      )$sql$,
      org_b_source
    )
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 7: cross-org campaign rejected
DO $$
DECLARE
  org_b_campaign uuid;
BEGIN
  PERFORM _m3_ow_as_super();
  SELECT id INTO org_b_campaign FROM lead_campaign
  WHERE organization_id = 'b0000000-0000-4000-8000-000000000001' LIMIT 1;
  IF org_b_campaign IS NULL THEN
    INSERT INTO lead_campaign (organization_id, code, name, status)
    VALUES ('b0000000-0000-4000-8000-000000000001', 'ow_b_only', 'Org B only', 'active')
    RETURNING id INTO org_b_campaign;
  END IF;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    7,
    'cross-org campaign rejected',
    format(
      $sql$SELECT public.create_lead_with_people(
        jsonb_build_object('lead_campaign_id', %L),
        '[{"given_name":"A","family_name":"B"}]'::jsonb,
        '[{"given_name":"C","family_name":"D"}]'::jsonb
      )$sql$,
      org_b_campaign
    )
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 8: initial assignment remains null
DO $$
DECLARE
  result jsonb;
  v_owner uuid;
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_lead_with_people(
    '{}'::jsonb,
    '[{"given_name":"No","family_name":"Assign"}]'::jsonb,
    '[{"given_name":"Parent","family_name":"Assign"}]'::jsonb
  ) INTO result;
  SELECT assigned_user_id INTO v_owner FROM lead WHERE id = (result->>'lead_id')::uuid;
  PERFORM _m3_ow_record(8, 'initial assignment remains null', v_owner IS NULL);
  PERFORM _m3_ow_as_super();
END $$;

-- 9: lead.create cannot set assigned_user_id on insert
DO $$
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    9,
    'lead.create cannot bypass assign on insert',
    $sql$INSERT INTO lead (organization_id, status, assigned_user_id)
       VALUES ('a0000000-0000-4000-8000-000000000001', 'new', 'a1000000-0000-4000-8000-000000000001')$sql$
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 10: primary candidate auto-set when omitted
DO $$
DECLARE
  result jsonb;
  primary_cnt integer;
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_lead_with_people(
    '{}'::jsonb,
    '[{"given_name":"Solo","family_name":"Kid"}]'::jsonb,
    '[{"given_name":"Parent","family_name":"Kid"}]'::jsonb
  ) INTO result;
  SELECT count(*) INTO primary_cnt FROM lead_candidate
  WHERE lead_id = (result->>'lead_id')::uuid AND is_primary_candidate;
  PERFORM _m3_ow_record(10, 'primary candidate uniqueness enforced', primary_cnt = 1);
  PERFORM _m3_ow_as_super();
END $$;

-- 11: normalized contact fields populated
DO $$
DECLARE
  result jsonb;
  phone_norm text;
  email_norm text;
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_lead_with_people(
    '{}'::jsonb,
    '[{"given_name":"Norm","family_name":"Test"}]'::jsonb,
    '[{"given_name":"P","family_name":"T","phone":"0900-111-222","email":"Test@Example.COM"}]'::jsonb
  ) INTO result;
  SELECT phone_normalized, email_normalized INTO phone_norm, email_norm
  FROM lead_contact WHERE lead_id = (result->>'lead_id')::uuid LIMIT 1;
  PERFORM _m3_ow_record(
    11,
    'normalized contact fields populated',
    phone_norm IS NOT NULL AND email_norm IS NOT NULL
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 12: no student created on intake
DO $$
DECLARE
  result jsonb;
  before_cnt integer;
  after_cnt integer;
BEGIN
  PERFORM _m3_ow_as_super();
  SELECT count(*) INTO before_cnt FROM student WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.create_lead_with_people(
    '{}'::jsonb,
    '[{"given_name":"No","family_name":"Student"}]'::jsonb,
    '[{"given_name":"No","family_name":"Guardian"}]'::jsonb
  ) INTO result;
  PERFORM _m3_ow_as_super();
  SELECT count(*) INTO after_cnt FROM student WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m3_ow_record(12, 'no student created on intake', after_cnt = before_cnt);
END $$;

-- 13: no guardian created on intake
DO $$
DECLARE
  result jsonb;
  before_cnt integer;
  after_cnt integer;
BEGIN
  PERFORM _m3_ow_as_super();
  SELECT count(*) INTO before_cnt FROM guardian WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.create_lead_with_people(
    '{}'::jsonb,
    '[{"given_name":"No","family_name":"Student2"}]'::jsonb,
    '[{"given_name":"No","family_name":"Guardian2"}]'::jsonb
  );
  PERFORM _m3_ow_as_super();
  SELECT count(*) INTO after_cnt FROM guardian WHERE organization_id = 'a0000000-0000-4000-8000-000000000001';
  PERFORM _m3_ow_record(13, 'no guardian created on intake', after_cnt = before_cnt);
END $$;

-- 14: update_lead_operational works with lead.update
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_source uuid;
  notes text;
BEGIN
  PERFORM _m3_ow_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'new') RETURNING id INTO v_lead;
  SELECT id INTO v_source FROM lead_source WHERE organization_id = org AND status = 'active' LIMIT 1;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.update_lead_operational(v_lead, 'Updated notes', v_source, NULL, false, false);
  SELECT notes_summary INTO notes FROM lead WHERE id = v_lead;
  PERFORM _m3_ow_record(14, 'update_lead_operational works', notes = 'Updated notes');
  PERFORM _m3_ow_as_super();
END $$;

-- 15: lifecycle status protected from direct update
DO $$
DECLARE
  v_lead uuid := 'a6100000-0000-4000-8000-000000000001';
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    15,
    'lifecycle status protected from generic update',
    format($sql$UPDATE lead SET status = 'contacted' WHERE id = %L$sql$, v_lead)
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 16: assignment protected from generic update
DO $$
DECLARE
  v_lead uuid := 'a6100000-0000-4000-8000-000000000002';
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    16,
    'assignment protected from generic update',
    format(
      $sql$UPDATE lead SET assigned_user_id = 'a1000000-0000-4000-8000-000000000001' WHERE id = %L$sql$,
      v_lead
    )
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 17: candidate identity edit marks resolution stale
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student uuid;
  stale boolean;
BEGIN
  PERFORM _m3_ow_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Stale', 'Candidate', true) RETURNING id INTO v_candidate;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Parent', 'Stale', true, true);
  SELECT id INTO v_student FROM student WHERE organization_id = org LIMIT 1;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'use_existing', v_student, true, NULL);
  UPDATE lead_candidate SET given_name = 'StaleEdited' WHERE id = v_candidate;
  SELECT is_stale INTO stale FROM lead_candidate_identity_resolution WHERE lead_candidate_id = v_candidate;
  PERFORM _m3_ow_record(17, 'candidate identity edit marks stale', stale IS TRUE);
  PERFORM _m3_ow_as_super();
END $$;

-- 18: contact identity edit marks resolution stale
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_contact uuid;
  v_guardian uuid;
  stale boolean;
BEGIN
  PERFORM _m3_ow_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Kid', 'ContactStale', true);
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Parent', 'ContactStale', '0900123123', true, true) RETURNING id INTO v_contact;
  SELECT id INTO v_guardian FROM guardian WHERE organization_id = org LIMIT 1;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_contact_identity(v_contact, 'use_existing', v_guardian, true, NULL);
  UPDATE lead_contact SET phone = '0900999111' WHERE id = v_contact;
  SELECT is_stale INTO stale FROM lead_contact_identity_resolution WHERE lead_contact_id = v_contact;
  PERFORM _m3_ow_record(18, 'contact identity edit marks stale', stale IS TRUE);
  PERFORM _m3_ow_as_super();
END $$;

-- 19: unrelated lead notes edit does not mark identity stale
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student uuid;
  stale boolean;
BEGIN
  PERFORM _m3_ow_as_super();
  INSERT INTO lead (organization_id, status, notes_summary) VALUES (org, 'qualified', 'before') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Stable', 'Candidate', true) RETURNING id INTO v_candidate;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Stable', 'Contact', true, true);
  SELECT id INTO v_student FROM student WHERE organization_id = org LIMIT 1;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'use_existing', v_student, true, NULL);
  PERFORM public.update_lead_operational(v_lead, 'after notes only', NULL, NULL, false, false);
  SELECT is_stale INTO stale FROM lead_candidate_identity_resolution WHERE lead_candidate_id = v_candidate;
  PERFORM _m3_ow_record(19, 'unrelated lead edit does not mark stale', stale IS FALSE);
  PERFORM _m3_ow_as_super();
END $$;

-- 20: converted lead blocks candidate identity edit
DO $$
DECLARE
  v_lead uuid;
  v_candidate uuid;
BEGIN
  PERFORM _m3_ow_as_super();
  SELECT l.id INTO v_lead FROM lead l WHERE l.status = 'converted' AND l.organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  IF v_lead IS NULL THEN
    PERFORM _m3_ow_record(20, 'converted lead blocks candidate edit', true);
    RETURN;
  END IF;
  SELECT id INTO v_candidate FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    20,
    'converted lead blocks candidate edit',
    format($sql$UPDATE lead_candidate SET given_name = 'Blocked' WHERE id = %L$sql$, v_candidate)
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 21: converted lead blocks operational source change
DO $$
DECLARE
  v_lead uuid;
  v_source uuid;
BEGIN
  PERFORM _m3_ow_as_super();
  SELECT l.id INTO v_lead FROM lead l WHERE l.status = 'converted' AND l.organization_id = 'a0000000-0000-4000-8000-000000000001' LIMIT 1;
  SELECT id INTO v_source FROM lead_source WHERE organization_id = 'a0000000-0000-4000-8000-000000000001' AND status = 'active' LIMIT 1;
  IF v_lead IS NULL THEN
    PERFORM _m3_ow_record(21, 'converted lead blocks source change', true);
    RETURN;
  END IF;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    21,
    'converted lead blocks source change',
    format($sql$SELECT public.update_lead_operational(%L, NULL, %L, NULL, false, false)$sql$, v_lead, v_source)
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 22: inactive source rejected for intake
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  inactive_source uuid;
BEGIN
  PERFORM _m3_ow_as_super();
  INSERT INTO lead_source (organization_id, code, display_name, status)
  VALUES (org, 'ow_inactive_src', 'Inactive OW', 'inactive')
  RETURNING id INTO inactive_source;
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    22,
    'inactive source rejected for intake',
    format(
      $sql$SELECT public.create_lead_with_people(
        jsonb_build_object('lead_source_id', %L),
        '[{"given_name":"A","family_name":"B"}]'::jsonb,
        '[{"given_name":"C","family_name":"D"}]'::jsonb
      )$sql$,
      inactive_source
    )
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 23: upsert source catalog requires manage_sources
DO $$
BEGIN
  PERFORM _m3_ow_as_auth('a2222222-2222-4222-8222-222222222222');
  PERFORM _m3_ow_expect_fail(
    23,
    'catalog upsert requires lead.manage_sources',
    $sql$SELECT public.upsert_lead_source_catalog(NULL, 'denied_src', 'Denied', 'active')$sql$
  );
  PERFORM _m3_ow_as_super();
END $$;

-- 24: admin can create and deactivate source catalog entry
DO $$
DECLARE
  new_id uuid;
  new_status text;
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.upsert_lead_source_catalog(NULL, 'ow_new_src', 'OW New Source', 'active') INTO new_id;
  PERFORM public.upsert_lead_source_catalog(new_id, 'ow_new_src', 'OW New Source', 'inactive');
  SELECT status INTO new_status FROM lead_source WHERE id = new_id;
  PERFORM _m3_ow_record(24, 'admin can deactivate source catalog', new_status = 'inactive');
  PERFORM _m3_ow_as_super();
END $$;

-- 25: intake requires at least one candidate and contact
DO $$
BEGIN
  PERFORM _m3_ow_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM _m3_ow_expect_fail(
    25,
    'intake requires people',
    $sql$SELECT public.create_lead_with_people('{}'::jsonb, '[]'::jsonb, '[]'::jsonb)$sql$
  );
  PERFORM _m3_ow_as_super();
END $$;

DO $$
DECLARE
  fail_cnt integer;
  r record;
BEGIN
  SELECT count(*) INTO fail_cnt FROM _m3_ow_results WHERE result = 'FAIL';
  IF fail_cnt > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m3_ow_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAIL test %: %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M3-T09 operational workspace tests failed: % failing assertions', fail_cnt;
  END IF;
END $$;

COMMIT;
