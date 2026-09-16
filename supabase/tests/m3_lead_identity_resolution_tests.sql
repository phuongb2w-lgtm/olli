-- M3-T06: Lead identity resolution and deduplication tests.

BEGIN;

CREATE TEMP TABLE _m3_ir_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_ir_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_ir_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_ir_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_ir_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m3_ir_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m3_ir_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_ir_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_ir_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

-- 1–3: schema exists
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_candidate_identity_resolution';
  PERFORM _m3_ir_record(1, 'lead_candidate_identity_resolution table exists', cnt = 1);

  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_contact_identity_resolution';
  PERFORM _m3_ir_record(2, 'lead_contact_identity_resolution table exists', cnt = 1);

  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'lead_identity_resolution_event';
  PERFORM _m3_ir_record(3, 'lead_identity_resolution_event table exists', cnt = 1);
END $$;

-- 4–6: FORCE RLS
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'lead_candidate_identity_resolution'
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_ir_record(4, 'FORCE RLS on lead_candidate_identity_resolution', cnt = 1);

  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'lead_contact_identity_resolution'
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_ir_record(5, 'FORCE RLS on lead_contact_identity_resolution', cnt = 1);

  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'lead_identity_resolution_event'
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_ir_record(6, 'FORCE RLS on lead_identity_resolution_event', cnt = 1);
END $$;

-- 7: same-org candidate matching
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student uuid;
  cnt integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
  VALUES (org, 'Match', 'Student', '2015-03-01', 'active') RETURNING id INTO v_student;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate)
  VALUES (org, v_lead, 'Match', 'Student', '2015-03-01', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt
  FROM public.find_student_matches_for_lead_candidate(v_candidate)
  WHERE student_id = v_student AND match_confidence = 'strong';
  PERFORM _m3_ir_record(7, 'same-org candidate strong match by name and DOB', cnt = 1);
  PERFORM _m3_ir_as_super();
END $$;

-- 8: cross-org student never in candidate matches
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student_b uuid;
  cnt integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
  VALUES (org_b, 'Cross', 'Org', '2014-01-01', 'active') RETURNING id INTO v_student_b;
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate)
  VALUES (org_a, v_lead, 'Cross', 'Org', '2014-01-01', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt
  FROM public.find_student_matches_for_lead_candidate(v_candidate)
  WHERE student_id = v_student_b;
  PERFORM _m3_ir_record(8, 'cross-org student excluded from candidate matches', cnt = 0);
  PERFORM _m3_ir_as_super();
END $$;

-- 9: normalized phone guardian match
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_contact uuid;
  v_guardian uuid;
  cnt integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO guardian (organization_id, given_name, family_name, phone, status)
  VALUES (org, 'Phone', 'Guardian', '0912-345-678', 'active') RETURNING id INTO v_guardian;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact)
  VALUES (org, v_lead, 'Other', 'Name', '0912 345 678', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt
  FROM public.find_guardian_matches_for_lead_contact(v_contact)
  WHERE guardian_id = v_guardian AND match_confidence = 'strong' AND 'same_phone' = ANY(match_reasons);
  PERFORM _m3_ir_record(9, 'normalized phone matching works for contact', cnt = 1);
  PERFORM _m3_ir_as_super();
END $$;

-- 10: normalized email guardian match
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_contact uuid;
  v_guardian uuid;
  cnt integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO guardian (organization_id, given_name, family_name, email, status)
  VALUES (org, 'Email', 'Guardian', 'Parent@Example.COM', 'active') RETURNING id INTO v_guardian;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, email, is_primary_contact)
  VALUES (org, v_lead, 'Other', 'Name', '  parent@example.com ', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt
  FROM public.find_guardian_matches_for_lead_contact(v_contact)
  WHERE guardian_id = v_guardian AND match_confidence = 'strong' AND 'same_email' = ANY(match_reasons);
  PERFORM _m3_ir_record(10, 'normalized email matching works for contact', cnt = 1);
  PERFORM _m3_ir_as_super();
END $$;

-- 11: name-only candidate match is possible not strong
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  conf text;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'NameOnly', 'Test', 'active');
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'NameOnly', 'Test', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT match_confidence INTO conf
  FROM public.find_student_matches_for_lead_candidate(v_candidate)
  LIMIT 1;
  PERFORM _m3_ir_record(11, 'name-only candidate match is possible', conf = 'possible');
  PERFORM _m3_ir_as_super();
END $$;

-- 12: resolve candidate to same-org existing student
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student uuid;
  res jsonb;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Resolve', 'Me', 'prospect') RETURNING id INTO v_student;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Resolve', 'Candidate', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.resolve_lead_candidate_identity(v_candidate, 'use_existing', v_student, false, 'pick existing')
  INTO res;
  PERFORM _m3_ir_record(
    12,
    'candidate resolves to same-org existing student',
    (res->>'resolution_mode') = 'use_existing' AND (res->>'student_id')::uuid = v_student
  );
  PERFORM _m3_ir_as_super();
END $$;

-- 13: cross-org student resolution rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student_b uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_ir_as_super();
  SELECT id INTO v_student_b FROM student WHERE organization_id = org_b LIMIT 1;
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org_a, v_lead, 'Cross', 'Resolve', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.resolve_lead_candidate_identity(v_candidate, 'use_existing', v_student_b);
  EXCEPTION WHEN OTHERS THEN
    ok := true;
  END;
  PERFORM _m3_ir_record(13, 'cross-org student resolution rejected', ok);
  PERFORM _m3_ir_as_super();
END $$;

-- 14: resolve contact to same-org guardian
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_contact uuid;
  v_guardian uuid;
  res jsonb;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO guardian (organization_id, given_name, family_name, status)
  VALUES (org, 'Pick', 'Guardian', 'active') RETURNING id INTO v_guardian;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Pick', 'Contact', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.resolve_lead_contact_identity(v_contact, 'use_existing', v_guardian)
  INTO res;
  PERFORM _m3_ir_record(
    14,
    'contact resolves to same-org existing guardian',
    (res->>'resolution_mode') = 'use_existing' AND (res->>'guardian_id')::uuid = v_guardian
  );
  PERFORM _m3_ir_as_super();
END $$;

-- 15: cross-org guardian resolution rejected
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_contact uuid;
  v_guardian_b uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_ir_as_super();
  SELECT id INTO v_guardian_b FROM guardian WHERE organization_id = org_b LIMIT 1;
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org_a, v_lead, 'Cross', 'Contact', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.resolve_lead_contact_identity(v_contact, 'use_existing', v_guardian_b);
  EXCEPTION WHEN OTHERS THEN
    ok := true;
  END;
  PERFORM _m3_ir_record(15, 'cross-org guardian resolution rejected', ok);
  PERFORM _m3_ir_as_super();
END $$;

-- 16–17: create_new choices
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_contact uuid;
  res_c jsonb;
  res_g jsonb;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Brand', 'NewStudent', true) RETURNING id INTO v_candidate;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Brand', 'NewGuardian', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.resolve_lead_candidate_identity(v_candidate, 'create_new', NULL, false) INTO res_c;
  SELECT public.resolve_lead_contact_identity(v_contact, 'create_new', NULL, false) INTO res_g;
  PERFORM _m3_ir_record(16, 'candidate can choose create_new', (res_c->>'resolution_mode') = 'create_new');
  PERFORM _m3_ir_record(17, 'contact can choose create_new', (res_g->>'resolution_mode') = 'create_new');
  PERFORM _m3_ir_as_super();
END $$;

-- 18: invalid resolution combinations rejected
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Invalid', 'Combo', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new', gen_random_uuid(), false);
  EXCEPTION WHEN OTHERS THEN
    ok := true;
  END;
  PERFORM _m3_ir_record(18, 'invalid resolution FK combinations rejected', ok);
  PERFORM _m3_ir_as_super();
END $$;

-- 19–20: actor server-derived; direct insert blocked
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student uuid;
  v_actor uuid;
  ok_direct boolean := false;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Actor', 'Test', 'active') RETURNING id INTO v_student;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Actor', 'Candidate', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'use_existing', v_student);
  SELECT resolved_by INTO v_actor
  FROM lead_candidate_identity_resolution
  WHERE lead_candidate_id = v_candidate;
  PERFORM _m3_ir_record(19, 'resolution actor is server-derived', v_actor = 'a1000000-0000-4000-8000-000000000001'::uuid);
  BEGIN
    INSERT INTO lead_candidate_identity_resolution (
      organization_id, lead_candidate_id, resolution_mode, student_id, resolved_by
    ) VALUES (org, v_candidate, 'use_existing', v_student, gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN
    ok_direct := true;
  END;
  PERFORM _m3_ir_record(20, 'direct resolution insert blocked (actor spoofing impossible)', ok_direct);
  PERFORM _m3_ir_as_super();
END $$;

-- 21–22: history append and immutability
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  cnt integer;
  ok_immutable boolean := false;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'History', 'Candidate', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new');
  SELECT count(*) INTO cnt FROM lead_identity_resolution_event
  WHERE subject_type = 'candidate' AND subject_id = v_candidate;
  PERFORM _m3_ir_record(21, 'first resolution appends history', cnt >= 1);
  PERFORM _m3_ir_record(22, 'no-op resolution does not append duplicate history', cnt = 1);
  PERFORM _m3_ir_as_super();
  BEGIN
    UPDATE lead_identity_resolution_event SET note = 'tampered' WHERE subject_id = v_candidate;
  EXCEPTION WHEN OTHERS THEN
    ok_immutable := true;
  END;
  PERFORM _m3_ir_record(23, 'resolution history is immutable', ok_immutable);
END $$;

-- 24: changing resolution preserves previous history
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_student uuid;
  cnt integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Switch', 'Student', 'active') RETURNING id INTO v_student;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Switch', 'Candidate', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'use_existing', v_student);
  SELECT count(*) INTO cnt FROM lead_identity_resolution_event
  WHERE subject_id = v_candidate AND previous_resolution_mode IS NOT NULL;
  PERFORM _m3_ir_record(24, 'changing resolution preserves previous history', cnt >= 1);
  PERFORM _m3_ir_as_super();
END $$;

-- 25–26: stale after material edits
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_contact uuid;
  stale_c boolean;
  stale_g boolean;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Stale', 'Candidate', true) RETURNING id INTO v_candidate;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact)
  VALUES (org, v_lead, 'Stale', 'Contact', '0900123456', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_contact, 'create_new');
  PERFORM _m3_ir_as_super();
  UPDATE lead_candidate SET given_name = 'Changed' WHERE id = v_candidate;
  UPDATE lead_contact SET phone = '0900999888' WHERE id = v_contact;
  SELECT is_stale INTO stale_c FROM lead_candidate_identity_resolution WHERE lead_candidate_id = v_candidate;
  SELECT is_stale INTO stale_g FROM lead_contact_identity_resolution WHERE lead_contact_id = v_contact;
  PERFORM _m3_ir_record(25, 'material candidate edit flags stale resolution', stale_c = true);
  PERFORM _m3_ir_record(26, 'material contact edit flags stale resolution', stale_g = true);
  PERFORM _m3_ir_as_super();
END $$;

-- 27: unrelated lead edit does not invalidate identity resolution
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  stale boolean;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status, notes_summary) VALUES (org, 'qualified', 'before') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Stable', 'Candidate', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new');
  PERFORM _m3_ir_as_super();
  UPDATE lead SET notes_summary = 'after unrelated edit' WHERE id = v_lead;
  SELECT is_stale INTO stale FROM lead_candidate_identity_resolution WHERE lead_candidate_id = v_candidate;
  PERFORM _m3_ir_record(27, 'unrelated lead edit does not invalidate identity resolution', stale = false);
  PERFORM _m3_ir_as_super();
END $$;

-- 28–29: ineligible targets make readiness false
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_contact uuid;
  v_student uuid;
  v_guardian uuid;
  status jsonb;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Inactive', 'Student', 'inactive') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name, status)
  VALUES (org, 'Inactive', 'Guardian', 'inactive') RETURNING id INTO v_guardian;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Inactive', 'Target', true) RETURNING id INTO v_candidate;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Inactive', 'Target', true) RETURNING id INTO v_contact;
  PERFORM set_config('olli.lead_identity_mutation', 'true', true);
  INSERT INTO lead_candidate_identity_resolution (
    organization_id, lead_candidate_id, resolution_mode, student_id, resolved_by
  ) VALUES (org, v_candidate, 'use_existing', v_student, 'a1000000-0000-4000-8000-000000000001');
  INSERT INTO lead_contact_identity_resolution (
    organization_id, lead_contact_id, resolution_mode, guardian_id, resolved_by
  ) VALUES (org, v_contact, 'use_existing', v_guardian, 'a1000000-0000-4000-8000-000000000001');
  PERFORM set_config('olli.lead_identity_mutation', 'false', true);
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.get_lead_identity_resolution_status(v_lead) INTO status;
  PERFORM _m3_ir_record(
    28,
    'inactive student target makes lead not ready',
    (status->>'ready')::boolean = false AND (status->>'ineligible_target_count')::integer >= 1
  );
  PERFORM _m3_ir_record(
    29,
    'inactive guardian target makes lead not ready',
    (status->>'ready')::boolean = false
  );
  PERFORM _m3_ir_as_super();
END $$;

-- 30: strong match create_new requires acknowledgement
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
  VALUES (org, 'Dup', 'Warn', '2012-05-05', 'active');
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate)
  VALUES (org, v_lead, 'Dup', 'Warn', '2012-05-05', true) RETURNING id INTO v_candidate;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new', NULL, false);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%strong_match_ack_required%';
  END;
  PERFORM _m3_ir_record(30, 'create_new with strong match requires acknowledgement', ok);
  PERFORM _m3_ir_as_super();
END $$;

-- 31–35: no M1 side effects from resolution
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_contact uuid;
  v_student uuid;
  v_guardian uuid;
  s_mid integer;
  s_after integer;
  g_mid integer;
  g_after integer;
  sg_mid integer;
  sg_after integer;
  e_mid integer;
  e_after integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'NoInsert', 'Student', 'active') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name, status)
  VALUES (org, 'NoInsert', 'Guardian', 'active') RETURNING id INTO v_guardian;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'NoInsert', 'Candidate', true) RETURNING id INTO v_candidate;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'NoInsert', 'Contact', true) RETURNING id INTO v_contact;
  SELECT count(*) INTO s_mid FROM student WHERE organization_id = org;
  SELECT count(*) INTO g_mid FROM guardian WHERE organization_id = org;
  SELECT count(*) INTO sg_mid FROM student_guardian WHERE organization_id = org;
  SELECT count(*) INTO e_mid FROM enrollment WHERE organization_id = org;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'use_existing', v_student);
  PERFORM public.resolve_lead_contact_identity(v_contact, 'use_existing', v_guardian);
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new', NULL, true);
  PERFORM _m3_ir_as_super();
  SELECT count(*) INTO s_after FROM student WHERE organization_id = org;
  SELECT count(*) INTO g_after FROM guardian WHERE organization_id = org;
  SELECT count(*) INTO sg_after FROM student_guardian WHERE organization_id = org;
  SELECT count(*) INTO e_after FROM enrollment WHERE organization_id = org;
  PERFORM _m3_ir_record(31, 'resolution causes no Student INSERT', s_after = s_mid);
  PERFORM _m3_ir_record(32, 'resolution causes no Guardian INSERT', g_after = g_mid);
  PERFORM _m3_ir_record(33, 'resolution causes no StudentGuardian INSERT', sg_after = sg_mid);
  PERFORM _m3_ir_record(34, 'resolution causes no Enrollment INSERT', e_after = e_mid);
  PERFORM _m3_ir_record(35, 'duplicate warning does not merge records', s_after = s_mid AND g_after = g_mid);
  PERFORM _m3_ir_as_super();
END $$;

-- 36–37: siblings and multiple contacts resolve independently
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_ct1 uuid;
  v_ct2 uuid;
  cnt integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Sibling', 'One', true) RETURNING id INTO v_c1;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Sibling', 'Two', false) RETURNING id INTO v_c2;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Contact', 'One', true) RETURNING id INTO v_ct1;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact, is_billing_contact)
  VALUES (org, v_lead, 'Contact', 'Two', false, true) RETURNING id INTO v_ct2;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c1, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_ct1, 'create_new');
  SELECT count(*) INTO cnt FROM lead_candidate_identity_resolution
  WHERE lead_candidate_id IN (v_c1, v_c2);
  PERFORM _m3_ir_record(36, 'sibling candidates resolve independently', cnt = 1);
  SELECT count(*) INTO cnt FROM lead_contact_identity_resolution
  WHERE lead_contact_id IN (v_ct1, v_ct2);
  PERFORM _m3_ir_record(37, 'multiple contacts resolve independently', cnt = 1);
  PERFORM _m3_ir_as_super();
END $$;

-- 38–40: readiness helper
DO $$
DECLARE
  org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_candidate uuid;
  v_contact uuid;
  status jsonb;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Ready', 'Candidate', true) RETURNING id INTO v_candidate;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Ready', 'Contact', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.get_lead_identity_resolution_status(v_lead) INTO status;
  PERFORM _m3_ir_record(
    38,
    'unresolved identities make lead not ready',
    (status->>'ready')::boolean = false AND (status->>'unresolved_candidates')::integer = 1
  );
  PERFORM public.resolve_lead_candidate_identity(v_candidate, 'create_new');
  PERFORM public.resolve_lead_contact_identity(v_contact, 'create_new');
  SELECT public.get_lead_identity_resolution_status(v_lead) INTO status;
  PERFORM _m3_ir_record(40, 'fully resolved identities report ready', (status->>'ready')::boolean = true);
  PERFORM _m3_ir_as_super();
END $$;

-- 39: cross-org guardian excluded from contact matches
DO $$
DECLARE
  org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_contact uuid;
  v_guardian_b uuid;
  cnt integer;
BEGIN
  PERFORM _m3_ir_as_super();
  INSERT INTO guardian (organization_id, given_name, family_name, phone, status)
  VALUES (org_b, 'Cross', 'Guardian', '0900777666', 'active') RETURNING id INTO v_guardian_b;
  INSERT INTO lead (organization_id, status) VALUES (org_a, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact)
  VALUES (org_a, v_lead, 'Cross', 'Contact', '0900777666', true) RETURNING id INTO v_contact;
  PERFORM _m3_ir_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT count(*) INTO cnt
  FROM public.find_guardian_matches_for_lead_contact(v_contact)
  WHERE guardian_id = v_guardian_b;
  PERFORM _m3_ir_record(39, 'cross-org guardian excluded from contact matches', cnt = 0);
  PERFORM _m3_ir_as_super();
END $$;

DO $$
DECLARE
  v_fail integer;
  v_total integer;
  r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*)
  INTO v_fail, v_total
  FROM _m3_ir_results;
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m3_ir_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAIL #%: %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M3-T06 identity resolution tests failed: %/% failed', v_fail, v_total;
  END IF;
  RAISE NOTICE 'M3-T06 identity resolution tests: %/% passed', v_total, v_total;
END $$;

ROLLBACK;
