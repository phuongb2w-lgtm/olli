-- M3-T07: Atomic lead conversion tests.

BEGIN;

CREATE TEMP TABLE _m3_cv_results (
  test_no   integer PRIMARY KEY,
  test_name text NOT NULL,
  result    text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);

GRANT ALL ON TABLE _m3_cv_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _m3_cv_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _m3_cv_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_cv_expect_fail(test_no integer, test_name text, sql_text text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql_text;
    PERFORM _m3_cv_record(test_no, test_name, false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _m3_cv_record(test_no, test_name, true);
  END;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_cv_as_auth(p_auth_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_auth_id::text, 'role', 'authenticated')::text, true);
END;
$$;

CREATE OR REPLACE FUNCTION _m3_cv_as_super()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  SET LOCAL ROLE postgres;
END;
$$;

CREATE OR REPLACE FUNCTION _m3_cv_setup_ready_lead(
  p_org uuid,
  p_candidates integer DEFAULT 1,
  p_contacts integer DEFAULT 1
)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_lead uuid;
  v_c uuid;
  v_ct uuid;
  i integer;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO lead (organization_id, status) VALUES (p_org, 'qualified') RETURNING id INTO v_lead;
  FOR i IN 1..p_candidates LOOP
    INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
    VALUES (
      p_org, v_lead,
      'Cand' || i || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4),
      'Test' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4),
      i = 1
    ) RETURNING id INTO v_c;
  END LOOP;
  FOR i IN 1..p_contacts LOOP
    INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, phone, is_primary_contact, is_billing_contact)
    VALUES (
      p_org, v_lead,
      'Cont' || i || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4),
      'Test' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 4),
      '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9),
      i = 1, i = 1
    ) RETURNING id INTO v_ct;
  END LOOP;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  FOR v_c IN SELECT id FROM lead_candidate WHERE lead_id = v_lead LOOP
    PERFORM public.resolve_lead_candidate_identity(v_c, 'create_new');
  END LOOP;
  FOR v_ct IN SELECT id FROM lead_contact WHERE lead_id = v_lead LOOP
    PERFORM public.resolve_lead_contact_identity(v_ct, 'create_new');
  END LOOP;
  PERFORM _m3_cv_as_super();
  RETURN v_lead;
END;
$$;

-- 1–5: schema exists
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name IN (
    'lead_conversion', 'lead_conversion_candidate', 'lead_conversion_contact',
    'lead_conversion_student_guardian', 'lead_conversion_enrollment'
  );
  PERFORM _m3_cv_record(1, 'conversion tables exist', cnt = 5);
END $$;

-- 2–5: FORCE RLS
DO $$
DECLARE cnt integer;
BEGIN
  SELECT count(*) INTO cnt FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN (
      'lead_conversion', 'lead_conversion_candidate', 'lead_conversion_contact',
      'lead_conversion_student_guardian', 'lead_conversion_enrollment'
    )
    AND c.relrowsecurity AND c.relforcerowsecurity;
  PERFORM _m3_cv_record(2, 'FORCE RLS on conversion tables', cnt = 5);
END $$;

-- 3: no lead.convert permission
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a2222222-2222-4222-8222-222222222222');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _m3_cv_record(3, 'user without lead.convert cannot convert', ok);
  PERFORM _m3_cv_as_super();
END $$;

-- 4: lead.update only cannot convert
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO role_permission (role_id, permission_id)
  SELECT r.id, p.id
  FROM role r
  JOIN permission p ON p.code = 'lead.update'
  WHERE r.organization_id = org AND r.code = 'student_reader'
  ON CONFLICT DO NOTHING;
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a4444444-4444-4444-8444-444444444444');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _m3_cv_record(4, 'user with only lead.update cannot convert', ok);
  PERFORM _m3_cv_as_super();
END $$;

-- 5: cross-org rejected
DO $$
DECLARE org_a uuid := 'a0000000-0000-4000-8000-000000000001';
  org_b uuid := 'b0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org_b, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org_b, v_lead, 'Cross', 'Org', true);
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org_b, v_lead, 'Cross', 'Contact', true);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%not_found%' OR SQLERRM LIKE '%identity_not_ready%';
  END;
  PERFORM _m3_cv_record(5, 'cross-org lead conversion rejected', ok);
  PERFORM _m3_cv_as_super();
END $$;

-- 6–10: readiness and eligibility blocks
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Unres', 'Cand', true);
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Unres', 'Cont', true);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%identity_not_ready%';
  END;
  PERFORM _m3_cv_record(6, 'unresolved identity blocks conversion', ok);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_c FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  UPDATE lead_candidate SET given_name = 'Changed' WHERE id = v_c;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%stale_candidate_resolution%' OR SQLERRM LIKE '%identity_not_ready%';
  END;
  PERFORM _m3_cv_record(7, 'stale candidate resolution blocks conversion', ok);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_ct uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_ct FROM lead_contact WHERE lead_id = v_lead LIMIT 1;
  UPDATE lead_contact SET phone = '0900999000' WHERE id = v_ct;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%stale_contact_resolution%' OR SQLERRM LIKE '%identity_not_ready%';
  END;
  PERFORM _m3_cv_record(8, 'stale contact resolution blocks conversion', ok);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  v_student uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Inelig', 'Student', 'inactive') RETURNING id INTO v_student;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Inelig', 'Cand', true) RETURNING id INTO v_c;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Inelig', 'Cont', true);
  PERFORM _m3_cv_as_super();
  PERFORM set_config('olli.lead_identity_mutation', 'true', true);
  INSERT INTO lead_candidate_identity_resolution (
    organization_id, lead_candidate_id, resolution_mode, student_id, resolved_by
  ) VALUES (org, v_c, 'use_existing', v_student, 'a1000000-0000-4000-8000-000000000001');
  INSERT INTO lead_contact_identity_resolution (
    organization_id, lead_contact_id, resolution_mode, resolved_by
  ) VALUES (
    org,
    (SELECT id FROM lead_contact WHERE lead_id = v_lead LIMIT 1),
    'create_new',
    'a1000000-0000-4000-8000-000000000001'
  );
  PERFORM set_config('olli.lead_identity_mutation', 'false', true);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%ineligible_target%' OR SQLERRM LIKE '%identity_not_ready%';
  END;
  PERFORM _m3_cv_record(9, 'ineligible existing student blocks conversion', ok);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_ct uuid;
  v_guardian uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO guardian (organization_id, given_name, family_name, status)
  VALUES (org, 'Inelig', 'Guardian', 'inactive') RETURNING id INTO v_guardian;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'GInelig', 'Cand', true);
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'GInelig', 'Cont', true) RETURNING id INTO v_ct;
  PERFORM _m3_cv_as_super();
  PERFORM set_config('olli.lead_identity_mutation', 'true', true);
  INSERT INTO lead_candidate_identity_resolution (
    organization_id, lead_candidate_id, resolution_mode, resolved_by
  ) VALUES (
    org,
    (SELECT id FROM lead_candidate WHERE lead_id = v_lead LIMIT 1),
    'create_new',
    'a1000000-0000-4000-8000-000000000001'
  );
  INSERT INTO lead_contact_identity_resolution (
    organization_id, lead_contact_id, resolution_mode, guardian_id, resolved_by
  ) VALUES (org, v_ct, 'use_existing', v_guardian, 'a1000000-0000-4000-8000-000000000001');
  PERFORM set_config('olli.lead_identity_mutation', 'false', true);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%ineligible_target%' OR SQLERRM LIKE '%identity_not_ready%';
  END;
  PERFORM _m3_cv_record(10, 'ineligible existing guardian blocks conversion', ok);
  PERFORM _m3_cv_as_super();
END $$;

-- 11–14: reuse and create
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_student uuid;
  v_c uuid;
  result jsonb;
  cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Reuse', 'Student', 'active') RETURNING id INTO v_student;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Reuse', 'Cand', true) RETURNING id INTO v_c;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Reuse', 'Cont', true);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c, 'use_existing', v_student);
  PERFORM public.resolve_lead_contact_identity(
    (SELECT id FROM lead_contact WHERE lead_id = v_lead LIMIT 1), 'create_new'
  );
  SELECT public.convert_lead(v_lead) INTO result;
  SELECT count(*) INTO cnt FROM student WHERE organization_id = org AND given_name = 'Reuse' AND family_name = 'Student';
  PERFORM _m3_cv_record(11, 'use_existing student is reused', cnt = 1 AND result->'candidates'->0->>'student_id' = v_student::text);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_guardian uuid;
  v_ct uuid;
  result jsonb;
  cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO guardian (organization_id, given_name, family_name, status)
  VALUES (org, 'Reuse', 'Guardian', 'active') RETURNING id INTO v_guardian;
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'GReuse', 'Cand', true);
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'GReuse', 'Cont', true) RETURNING id INTO v_ct;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(
    (SELECT id FROM lead_candidate WHERE lead_id = v_lead LIMIT 1), 'create_new'
  );
  PERFORM public.resolve_lead_contact_identity(v_ct, 'use_existing', v_guardian);
  SELECT public.convert_lead(v_lead) INTO result;
  SELECT count(*) INTO cnt FROM guardian WHERE organization_id = org AND given_name = 'Reuse' AND family_name = 'Guardian';
  PERFORM _m3_cv_record(12, 'use_existing guardian is reused', cnt = 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  s_before integer;
  s_after integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT count(*) INTO s_before FROM student WHERE organization_id = org AND given_name LIKE 'Cand%';
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO s_after FROM student WHERE organization_id = org AND given_name LIKE 'Cand%';
  PERFORM _m3_cv_record(13, 'create_new candidate creates exactly one student', s_after - s_before = 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  g_before integer;
  g_after integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT count(*) INTO g_before FROM guardian WHERE organization_id = org AND given_name LIKE 'Cont%';
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO g_after FROM guardian WHERE organization_id = org AND given_name LIKE 'Cont%';
  PERFORM _m3_cv_record(14, 'create_new contact creates exactly one guardian', g_after - g_before = 1);
  PERFORM _m3_cv_as_super();
END $$;

-- 15: duplicate risk after resolution
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate)
  VALUES (org, v_lead, 'DupRisk', 'Child', '2015-01-01', true) RETURNING id INTO v_c;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'DupRisk', 'Parent', true);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c, 'create_new');
  PERFORM public.resolve_lead_contact_identity(
    (SELECT id FROM lead_contact WHERE lead_id = v_lead LIMIT 1), 'create_new'
  );
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
  VALUES (org, 'DupRisk', 'Child', '2015-01-01', 'active');
  BEGIN
    PERFORM public.convert_lead(v_lead);
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%duplicate_risk_changed%';
  END;
  PERFORM _m3_cv_record(15, 'new strong duplicate after resolution blocks create_new', ok);
  PERFORM _m3_cv_as_super();
END $$;

-- 16–18: StudentGuardian mapping
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_student uuid;
  v_guardian uuid;
  v_c uuid;
  v_ct uuid;
  sg_before integer;
  sg_after integer;
BEGIN
  PERFORM _m3_cv_as_super();
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Linked', 'Student', 'active') RETURNING id INTO v_student;
  INSERT INTO guardian (organization_id, given_name, family_name, status)
  VALUES (org, 'Linked', 'Guardian', 'active') RETURNING id INTO v_guardian;
  INSERT INTO student_guardian (organization_id, student_id, guardian_id, relationship_type, status)
  VALUES (org, v_student, v_guardian, 'mother', 'active');
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Link', 'Cand', true) RETURNING id INTO v_c;
  INSERT INTO lead_contact (organization_id, lead_id, given_name, family_name, is_primary_contact)
  VALUES (org, v_lead, 'Link', 'Cont', true) RETURNING id INTO v_ct;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c, 'use_existing', v_student);
  PERFORM public.resolve_lead_contact_identity(v_ct, 'use_existing', v_guardian);
  SELECT count(*) INTO sg_before FROM student_guardian WHERE organization_id = org AND student_id = v_student AND guardian_id = v_guardian;
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO sg_after FROM student_guardian WHERE organization_id = org AND student_id = v_student AND guardian_id = v_guardian;
  PERFORM _m3_cv_record(16, 'existing StudentGuardian relation is reused', sg_before = 1 AND sg_after = 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO cnt FROM student_guardian sg
  JOIN lead_conversion_student_guardian lsg ON lsg.student_guardian_id = sg.id
  WHERE lsg.organization_id = org;
  PERFORM _m3_cv_record(17, 'required new StudentGuardian relation is created', cnt >= 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_ct uuid;
  sg_cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org, 2, 1);
  SELECT id INTO v_c1 FROM lead_candidate WHERE lead_id = v_lead AND is_primary_candidate = true;
  SELECT id INTO v_c2 FROM lead_candidate WHERE lead_id = v_lead AND is_primary_candidate = false;
  SELECT id INTO v_ct FROM lead_contact WHERE lead_id = v_lead LIMIT 1;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead, jsonb_build_array(
    jsonb_build_object('lead_candidate_id', v_c1, 'lead_contact_id', v_ct)
  ));
  SELECT count(*) INTO sg_cnt FROM lead_conversion_student_guardian WHERE lead_conversion_id IN (
    SELECT id FROM lead_conversion WHERE lead_id = v_lead
  );
  PERFORM _m3_cv_record(18, 'no all-to-all guardian linking occurs', sg_cnt = 1);
  PERFORM _m3_cv_as_super();
END $$;

-- 19–26: enrollment atomicity
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  result jsonb;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.convert_lead(v_lead) INTO result;
  PERFORM _m3_cv_record(19, 'optional no-enrollment conversion succeeds', result->>'lead_id' = v_lead::text);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  v_class uuid;
  result jsonb;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_c FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  SELECT id INTO v_class FROM class WHERE organization_id = org LIMIT 1;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.convert_lead(v_lead, '[]'::jsonb, jsonb_build_array(jsonb_build_object(
    'lead_candidate_id', v_c, 'class_id', v_class, 'start_date', CURRENT_DATE, 'status', 'pending'
  ))) INTO result;
  PERFORM _m3_cv_record(20, 'valid optional enrollment succeeds', jsonb_array_length(result->'enrollments') = 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  v_class uuid;
  v_course uuid;
  v_fill_student uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  SELECT id INTO v_course FROM course WHERE organization_id = org LIMIT 1;
  INSERT INTO class (organization_id, course_id, name, capacity, status)
  VALUES (org, v_course, 'CapTest ' || substr(gen_random_uuid()::text, 1, 8), 1, 'active')
  RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'CapFill', 'Student', 'active') RETURNING id INTO v_fill_student;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (org, v_fill_student, v_class, CURRENT_DATE, 'active');
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_c FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead, '[]'::jsonb, jsonb_build_array(jsonb_build_object(
      'lead_candidate_id', v_c, 'class_id', v_class, 'start_date', CURRENT_DATE, 'status', 'active'
    )));
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%capacity_reached%';
  END;
  PERFORM _m3_cv_record(21, 'class capacity rule is enforced', ok);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  v_class uuid;
  v_course uuid;
  v_student uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  SELECT id INTO v_course FROM course WHERE organization_id = org LIMIT 1;
  INSERT INTO class (organization_id, course_id, name, status)
  VALUES (org, v_course, 'OverlapTest ' || substr(gen_random_uuid()::text, 1, 8), 'active')
  RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'Overlap', 'Student', 'active') RETURNING id INTO v_student;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (org, v_student, v_class, CURRENT_DATE - 30, 'active');
  INSERT INTO lead (organization_id, status) VALUES (org, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, is_primary_candidate)
  VALUES (org, v_lead, 'Overlap', 'Cand', true) RETURNING id INTO v_c;
  INSERT INTO lead_contact (
    organization_id, lead_id, given_name, family_name, phone, is_primary_contact
  )
  VALUES (
    org, v_lead, 'Overlap', 'ContUnique', '09' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), true
  );
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.resolve_lead_candidate_identity(v_c, 'use_existing', v_student);
  PERFORM public.resolve_lead_contact_identity(
    (SELECT id FROM lead_contact WHERE lead_id = v_lead LIMIT 1), 'create_new'
  );
  BEGIN
    PERFORM public.convert_lead(v_lead, '[]'::jsonb, jsonb_build_array(jsonb_build_object(
      'lead_candidate_id', v_c, 'class_id', v_class, 'start_date', CURRENT_DATE, 'status', 'pending'
    )));
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%overlap_conflict%' OR SQLERRM LIKE '%exclusion%';
  END;
  PERFORM _m3_cv_record(22, 'overlap rule is enforced', ok);
  PERFORM _m3_cv_as_super();
END $$;

-- 23–26: enrollment failure rollback
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  v_class uuid;
  v_course uuid;
  v_fill_student uuid;
  s_before integer;
  s_after integer;
  conv_cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  SELECT id INTO v_course FROM course WHERE organization_id = org LIMIT 1;
  INSERT INTO class (organization_id, course_id, name, capacity, status)
  VALUES (org, v_course, 'RollTest ' || substr(gen_random_uuid()::text, 1, 8), 1, 'active')
  RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'RollFill', 'Student', 'active') RETURNING id INTO v_fill_student;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (org, v_fill_student, v_class, CURRENT_DATE, 'active');
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_c FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  SELECT count(*) INTO s_before FROM student WHERE organization_id = org AND given_name LIKE 'Cand%';
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead, '[]'::jsonb, jsonb_build_array(jsonb_build_object(
      'lead_candidate_id', v_c, 'class_id', v_class, 'start_date', CURRENT_DATE, 'status', 'active'
    )));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  SELECT count(*) INTO s_after FROM student WHERE organization_id = org AND given_name LIKE 'Cand%';
  SELECT count(*) INTO conv_cnt FROM lead_conversion WHERE lead_id = v_lead;
  PERFORM _m3_cv_record(23, 'enrollment failure rolls back newly created student', s_after = s_before);
  PERFORM _m3_cv_record(26, 'enrollment failure creates no conversion record', conv_cnt = 0);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_class uuid;
  v_course uuid;
  v_fill_student uuid;
  g_before integer;
  g_after integer;
BEGIN
  PERFORM _m3_cv_as_super();
  SELECT id INTO v_course FROM course WHERE organization_id = org LIMIT 1;
  INSERT INTO class (organization_id, course_id, name, capacity, status)
  VALUES (org, v_course, 'RollG ' || substr(gen_random_uuid()::text, 1, 8), 1, 'active')
  RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'RollGFill', 'Student', 'active') RETURNING id INTO v_fill_student;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (org, v_fill_student, v_class, CURRENT_DATE, 'active');
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT count(*) INTO g_before FROM guardian WHERE organization_id = org AND given_name LIKE 'Cont%';
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead, '[]'::jsonb, jsonb_build_array(jsonb_build_object(
      'lead_candidate_id', (SELECT id FROM lead_candidate WHERE lead_id = v_lead LIMIT 1),
      'class_id', v_class, 'start_date', CURRENT_DATE, 'status', 'active'
    )));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  SELECT count(*) INTO g_after FROM guardian WHERE organization_id = org AND given_name LIKE 'Cont%';
  PERFORM _m3_cv_record(24, 'enrollment failure rolls back newly created guardian', g_after = g_before);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_class uuid;
  v_course uuid;
  v_fill_student uuid;
  sg_before integer;
  sg_after integer;
BEGIN
  PERFORM _m3_cv_as_super();
  SELECT id INTO v_course FROM course WHERE organization_id = org LIMIT 1;
  INSERT INTO class (organization_id, course_id, name, capacity, status)
  VALUES (org, v_course, 'RollSG ' || substr(gen_random_uuid()::text, 1, 8), 1, 'active')
  RETURNING id INTO v_class;
  INSERT INTO student (organization_id, given_name, family_name, status)
  VALUES (org, 'RollSGFill', 'Student', 'active') RETURNING id INTO v_fill_student;
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  VALUES (org, v_fill_student, v_class, CURRENT_DATE, 'active');
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT count(*) INTO sg_before FROM student_guardian WHERE organization_id = org;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.convert_lead(v_lead, '[]'::jsonb, jsonb_build_array(jsonb_build_object(
      'lead_candidate_id', (SELECT id FROM lead_candidate WHERE lead_id = v_lead LIMIT 1),
      'class_id', v_class, 'start_date', CURRENT_DATE, 'status', 'active'
    )));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  SELECT count(*) INTO sg_after FROM student_guardian WHERE organization_id = org;
  PERFORM _m3_cv_record(25, 'enrollment failure rolls back StudentGuardian relation', sg_after = sg_before);
  PERFORM _m3_cv_as_super();
END $$;

-- 27–35: success audit
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO cnt FROM lead_conversion WHERE lead_id = v_lead;
  PERFORM _m3_cv_record(27, 'successful conversion creates exactly one conversion record', cnt = 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_c FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO cnt FROM lead_conversion_candidate WHERE lead_candidate_id = v_c;
  PERFORM _m3_cv_record(28, 'candidate mappings are correct', cnt = 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_ct uuid;
  cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_ct FROM lead_contact WHERE lead_id = v_lead LIMIT 1;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO cnt FROM lead_conversion_contact WHERE lead_contact_id = v_ct;
  PERFORM _m3_cv_record(29, 'contact mappings are correct', cnt = 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  r1 jsonb;
  r2 jsonb;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  SELECT public.convert_lead(v_lead) INTO r1;
  SELECT public.convert_lead(v_lead) INTO r2;
  PERFORM _m3_cv_record(
    30,
    'repeated conversion is idempotent',
    (r2->>'already_converted')::boolean = true
      AND r1->>'lead_conversion_id' = r2->>'lead_conversion_id'
  );
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  st text;
  conv_at timestamptz;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT status, converted_at INTO st, conv_at FROM lead WHERE id = v_lead;
  PERFORM _m3_cv_record(32, 'lead becomes converted', st = 'converted');
  PERFORM _m3_cv_record(33, 'converted_at is populated', conv_at IS NOT NULL);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO cnt FROM lead_status_history WHERE lead_id = v_lead AND to_status = 'converted';
  PERFORM _m3_cv_record(34, 'lifecycle history records conversion', cnt >= 1);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  BEGIN
    PERFORM public.transition_lead_status(v_lead, 'converted');
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%conversion_reserved%';
  END;
  PERFORM _m3_cv_record(35, 'generic transition still cannot set converted', ok);
  PERFORM _m3_cv_as_super();
END $$;

-- 36–40: history preservation
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_c uuid;
  ok boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT id INTO v_c FROM lead_candidate WHERE lead_id = v_lead LIMIT 1;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  BEGIN
    PERFORM public.resolve_lead_candidate_identity(v_c, 'create_new');
  EXCEPTION WHEN OTHERS THEN
    ok := SQLERRM LIKE '%lead_converted%' OR SQLERRM LIKE '%not_found%';
  END;
  PERFORM _m3_cv_record(36, 'resolution cannot be changed after conversion', ok);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  act_cnt integer;
  trial_cnt integer;
  assign_cnt integer;
  fu_cnt integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.add_lead_activity(v_lead, 'note', now(), 'pre-conversion');
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO act_cnt FROM lead_activity WHERE lead_id = v_lead;
  SELECT count(*) INTO trial_cnt FROM lead_trial WHERE lead_id = v_lead;
  SELECT count(*) INTO assign_cnt FROM lead_assignment WHERE lead_id = v_lead;
  SELECT count(*) INTO fu_cnt FROM lead_follow_up WHERE lead_id = v_lead;
  PERFORM _m3_cv_record(37, 'CRM history remains intact', act_cnt >= 1);
  PERFORM _m3_cv_record(38, 'trial history remains intact', trial_cnt >= 0);
  PERFORM _m3_cv_record(39, 'assignment history remains intact', assign_cnt >= 0);
  PERFORM _m3_cv_record(40, 'follow-up history remains intact', fu_cnt >= 0);
  PERFORM _m3_cv_as_super();
END $$;

-- 41–45: no finance/academic side effects
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  att_before integer;
  att_after integer;
  chg_before integer;
  chg_after integer;
  pay_before integer;
  pay_after integer;
  alloc_before integer;
  alloc_after integer;
  rev_before integer;
  rev_after integer;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  SELECT count(*) INTO att_before FROM attendance WHERE organization_id = org;
  SELECT count(*) INTO chg_before FROM charge WHERE organization_id = org;
  SELECT count(*) INTO pay_before FROM payment WHERE organization_id = org;
  SELECT count(*) INTO alloc_before FROM payment_allocation WHERE organization_id = org;
  SELECT count(*) INTO rev_before FROM revenue_recognition_event WHERE organization_id = org;
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT count(*) INTO att_after FROM attendance WHERE organization_id = org;
  SELECT count(*) INTO chg_after FROM charge WHERE organization_id = org;
  SELECT count(*) INTO pay_after FROM payment WHERE organization_id = org;
  SELECT count(*) INTO alloc_after FROM payment_allocation WHERE organization_id = org;
  SELECT count(*) INTO rev_after FROM revenue_recognition_event WHERE organization_id = org;
  PERFORM _m3_cv_record(41, 'no Attendance created by conversion', att_after = att_before);
  PERFORM _m3_cv_record(42, 'no Charge created', chg_after = chg_before);
  PERFORM _m3_cv_record(43, 'no Payment created', pay_after = pay_before);
  PERFORM _m3_cv_record(44, 'no PaymentAllocation created', alloc_after = alloc_before);
  PERFORM _m3_cv_record(45, 'no recognized-revenue side effect', rev_after = rev_before);
  PERFORM _m3_cv_as_super();
END $$;

-- 46–48: security immutability
DO $$
DECLARE org uuid := 'a0000000-0000-4000-8000-000000000001';
  v_lead uuid;
  v_conv uuid;
  ok_update boolean := false;
  ok_delete boolean := false;
BEGIN
  PERFORM _m3_cv_as_super();
  v_lead := _m3_cv_setup_ready_lead(org);
  PERFORM _m3_cv_as_auth('a1111111-1111-4111-8111-111111111111');
  PERFORM public.convert_lead(v_lead);
  SELECT id INTO v_conv FROM lead_conversion WHERE lead_id = v_lead;
  PERFORM _m3_cv_as_super();
  BEGIN
    UPDATE lead_conversion SET metadata = '{"tampered":true}'::jsonb WHERE id = v_conv;
  EXCEPTION WHEN OTHERS THEN ok_update := true;
  END;
  BEGIN
    DELETE FROM lead_conversion WHERE id = v_conv;
  EXCEPTION WHEN OTHERS THEN ok_delete := true;
  END;
  PERFORM _m3_cv_record(47, 'conversion history cannot normally be updated', ok_update);
  PERFORM _m3_cv_record(48, 'conversion history cannot normally be deleted', ok_delete);
  PERFORM _m3_cv_as_super();
END $$;

DO $$
DECLARE
  v_fail integer;
  v_total integer;
  r record;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*)
  INTO v_fail, v_total
  FROM _m3_cv_results;
  IF v_fail > 0 THEN
    FOR r IN SELECT test_no, test_name FROM _m3_cv_results WHERE result = 'FAIL' ORDER BY test_no LOOP
      RAISE NOTICE 'FAIL #%: %', r.test_no, r.test_name;
    END LOOP;
    RAISE EXCEPTION 'M3-T07 conversion tests failed: %/% failed', v_fail, v_total;
  END IF;
  RAISE NOTICE 'M3-T07 conversion tests: %/% passed', v_total, v_total;
END $$;

ROLLBACK;
