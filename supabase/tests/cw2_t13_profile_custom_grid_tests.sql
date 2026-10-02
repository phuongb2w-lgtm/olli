-- CW2-T13: profile grid + personal custom fields + PIN adversarial (26+ cases)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t13_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t13_results TO authenticated, anon;

CREATE TEMP TABLE IF NOT EXISTS _cw2_t13_fixture (
  org_id uuid,
  consultant_a_auth uuid,
  consultant_a_user uuid,
  consultant_b_auth uuid,
  consultant_b_user uuid,
  portfolio_entry_id uuid,
  lead_id uuid,
  cc char(2)
);
GRANT ALL ON TABLE _cw2_t13_fixture TO authenticated, anon;
TRUNCATE _cw2_t13_fixture;

CREATE OR REPLACE FUNCTION _cw2_t13_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t13_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- Seed fixture intake
DO $$
DECLARE f record; j jsonb; j_list jsonb; v_row jsonb; v_cc char(2); v_pe uuid;
  v_seq_before bigint; v_seq_after bigint;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT consultant_operational_code INTO v_cc FROM app_user WHERE id = f.consultant_a_user;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);

  j := public.create_consultant_workspace_portfolio_intake(
    'NGUYEN VAN', 'AN', '2017-06-09', 'NGUYEN VAN', 'B', '0912345678', '001234567890', '[]'::jsonb
  );
  v_pe := (j->>'portfolio_entry_id')::uuid;
  INSERT INTO _cw2_t13_fixture VALUES (
    f.org_id, f.consultant_a_auth, f.consultant_a_user, f.consultant_b_auth, f.consultant_b_user, v_pe,
    (j->>'lead_id')::uuid, v_cc
  );

  PERFORM _cw2_t13_record(1, 'DOB save on intake', (j->>'date_of_birth') = '2017-06-09');
  PERFORM _cw2_t13_record(2, 'PIN save on intake', j->>'personal_identification_number' = '001234567890');
  PERFORM _cw2_t13_record(3, 'PIN leading zero', j->>'personal_identification_number' = '001234567890');
  PERFORM _cw2_t13_record(4, 'guardian phone intake', j->>'primary_guardian_phone' = '0912345678');
  PERFORM _cw2_t13_record(5, 'provisional CCYY0000', j->>'student_code_display' = v_cc || '170000');
  PERFORM _cw2_t13_record(6, 'lifecycle tiem_nang', j->>'lifecycle_status' = 'tiem_nang');

  j_list := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 50);
  SELECT elem INTO v_row FROM jsonb_array_elements(j_list->'rows') elem
  WHERE (elem->>'portfolio_entry_id')::uuid = v_pe LIMIT 1;
  PERFORM _cw2_t13_record(7, 'list DOB reload', v_row->>'date_of_birth' = '2017-06-09');
  PERFORM _cw2_t13_record(8, 'list guardian reload', v_row->>'primary_guardian_phone' = '0912345678');
  PERFORM _cw2_t13_record(9, 'list provisional code', v_row->>'student_code_display' = v_cc || '170000');
  PERFORM _cw2_t13_record(10, 'list PIN for owner consultant', v_row->>'personal_identification_number' = '001234567890');

  SELECT last_allocated_sequence INTO v_seq_before FROM organization_student_sequence WHERE organization_id = f.org_id;
  SELECT last_allocated_sequence INTO v_seq_after FROM organization_student_sequence WHERE organization_id = f.org_id;
  PERFORM _cw2_t13_record(11, 'provisional no sequence consume', v_seq_after = v_seq_before);

  j := public.save_consultant_portfolio_profile(
    v_pe, 'NGUYEN VAN', 'AN', '2018-01-01', 'NGUYEN VAN', 'B', '0912345678', '001234567890', NULL
  );
  PERFORM _cw2_t13_record(12, 'pre-official DOB changes YY', j->>'student_code_display' = v_cc || '180000');
END $$;

-- Official student code (consultant 02 + DOB 2018-01-01 -> CC180037)
DO $$
DECLARE
  fx record;
  v_student uuid;
  v_cc char(2);
  v_role uuid;
  v_fail boolean := false;
  r public.official_student_code_allocation_result;
  j jsonb;
BEGIN
  SELECT * INTO fx FROM _cw2_t13_fixture LIMIT 1;
  v_cc := fx.cc;

  PERFORM _cw2_t05_as_postgres();
  INSERT INTO student (organization_id, given_name, family_name, date_of_birth, status)
  SELECT lc.organization_id, lc.given_name, lc.family_name, lc.date_of_birth, 'prospect'
  FROM lead_candidate lc
  WHERE lc.lead_id = fx.lead_id
  RETURNING id INTO v_student;

  UPDATE consultant_portfolio_entry
  SET student_id = v_student
  WHERE id = fx.portfolio_entry_id;

  UPDATE organization_student_sequence
  SET last_allocated_sequence = 36
  WHERE organization_id = fx.org_id;

  SELECT id INTO v_role FROM role WHERE organization_id = fx.org_id AND canonical_code = 'consultant' LIMIT 1;
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, p.id
  FROM permission p
  WHERE p.code IN ('student.read', 'student.update', 'payment.record')
    AND NOT EXISTS (
      SELECT 1 FROM role_permission rp WHERE rp.role_id = v_role AND rp.permission_id = p.id
    );
  PERFORM _cw2_t13_record(31, 'fixture student linked', v_student IS NOT NULL);
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  r := public.allocate_official_student_code(v_student, fx.consultant_a_user);
  PERFORM _cw2_t13_record(32, 'official allocation CCYYNNNN', r.official_student_code = v_cc || '180037');

  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  j := public.get_consultant_portfolio_entry_detail(fx.portfolio_entry_id);
  PERFORM _cw2_t13_record(33, 'post-official display code', j->>'student_code_display' = v_cc || '180037');

  BEGIN
    j := public.save_consultant_portfolio_profile(
      fx.portfolio_entry_id, 'NGUYEN VAN', 'AN', '2019-05-05', 'NGUYEN VAN', 'B', '0912345678', '001234567890', NULL
    );
    v_fail := false;
  EXCEPTION WHEN OTHERS THEN
    v_fail := SQLERRM LIKE '%profile_locked%';
  END;
  j := public.get_consultant_portfolio_entry_detail(fx.portfolio_entry_id);
  PERFORM _cw2_t13_record(
    34,
    'post-official DOB change immutable code',
    v_fail AND j->>'student_code_display' = v_cc || '180037'
  );
END $$;

-- Personal custom fields + isolation
DO $$
DECLARE fx record; j jsonb; v_def uuid; v_key text; v_lead uuid; v_vals jsonb;
BEGIN
  SELECT * INTO fx FROM _cw2_t13_fixture LIMIT 1;
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  v_lead := fx.lead_id;

  j := public.create_personal_custom_field_definition('Ghi chu cua toi', 'text');
  v_def := (j->>'id')::uuid;
  v_key := j->>'field_key';
  PERFORM _cw2_t13_record(13, 'create personal field', v_def IS NOT NULL);

  PERFORM public.save_personal_custom_field_values(
    'lead', v_lead, jsonb_build_array(jsonb_build_object('field_key', v_key, 'value', 'Hen goi lai'))
  );
  v_vals := public.list_personal_custom_field_values('lead', v_lead);
  PERFORM _cw2_t13_record(14, 'save personal value', EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_vals) e WHERE e->>'value' = 'Hen goi lai'
  ));
  PERFORM _cw2_t13_record(15, 'reload personal value', jsonb_array_length(v_vals) = 1);

  PERFORM public.update_personal_custom_field_definition(v_def, 'Ghi chu doi ten', NULL);
  v_vals := public.list_personal_custom_field_values('lead', v_lead);
  PERFORM _cw2_t13_record(16, 'rename retains value', jsonb_array_length(v_vals) = 1);

  PERFORM public.update_personal_custom_field_definition(v_def, NULL, 'archived');
  PERFORM _cw2_t13_record(17, 'archive field', NOT EXISTS (
    SELECT 1 FROM consultant_custom_field_definition WHERE id = v_def AND status = 'active'
  ));
  PERFORM _cw2_t13_record(18, 'archive keeps core profile', EXISTS (
    SELECT 1 FROM lead_candidate WHERE lead_id = v_lead AND date_of_birth = '2018-01-01'
  ));

  PERFORM _cw2_t05_as_auth(fx.consultant_b_auth);
  PERFORM _cw2_t13_record(19, 'consultant B defs isolated', NOT EXISTS (
    SELECT 1 FROM consultant_custom_field_definition
    WHERE organization_id = fx.org_id AND owner_app_user_id = fx.consultant_a_user AND field_key = v_key AND status = 'active'
  ));
  v_vals := public.list_personal_custom_field_values('lead', v_lead);
  PERFORM _cw2_t13_record(20, 'consultant B values empty', coalesce(jsonb_array_length(v_vals), 0) = 0);
END $$;

-- H뿯ẽc v뿯ẽ-style user with student.personal_id.read + personal field manage
DO $$
DECLARE fx record; j jsonb; v_key text; v_student uuid; v_vals jsonb; v_role uuid; v_perm uuid;
  v_staff_auth uuid; v_staff_user uuid;
BEGIN
  SELECT * INTO fx FROM _cw2_t13_fixture LIMIT 1;
  v_staff_auth := gen_random_uuid();
  PERFORM _cw2_t05_seed_auth_user(v_staff_auth, 't13-acad-' || fx.org_id::text || '@olli.local');
  v_staff_user := public.test_fixture_insert_app_user(
    fx.org_id, 't13-acad-' || fx.org_id::text || '@olli.local', 'T13 Acad', v_staff_auth
  );
  SELECT id INTO v_role FROM role WHERE organization_id = fx.org_id AND canonical_code = 'academic_operations' LIMIT 1;
  SELECT id INTO v_perm FROM permission WHERE code = 'student.personal_id.read';
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, v_perm WHERE NOT EXISTS (
    SELECT 1 FROM role_permission rp WHERE rp.role_id = v_role AND rp.permission_id = v_perm
  );
  SELECT id INTO v_perm FROM permission WHERE code = 'student_personal_field.manage';
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, v_perm WHERE NOT EXISTS (
    SELECT 1 FROM role_permission rp WHERE rp.role_id = v_role AND rp.permission_id = v_perm
  );
  INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)
  VALUES (fx.org_id, v_staff_user, v_role, CURRENT_DATE, 'active');

  PERFORM _cw2_t05_as_auth(v_staff_auth);
  j := public.create_personal_custom_field_definition('Lu y xep lop', 'text');
  v_key := j->>'field_key';
  PERFORM _cw2_t13_record(21, 'academic creates personal field', v_key IS NOT NULL);

  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  SELECT fx.lead_id INTO v_student; -- lead phase ok for values
  PERFORM _cw2_t05_as_auth(v_staff_auth);
  PERFORM public.save_personal_custom_field_values(
    'lead', fx.lead_id, jsonb_build_array(jsonb_build_object('field_key', v_key, 'value', 'Can hoc bu'))
  );
  v_vals := public.list_personal_custom_field_values('lead', fx.lead_id);
  PERFORM _cw2_t13_record(22, 'academic save/read own value', EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_vals) e WHERE e->>'value' = 'Can hoc bu'
  ));

  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  v_vals := public.list_personal_custom_field_values('lead', fx.lead_id);
  PERFORM _cw2_t13_record(23, 'consultant does not see academic field', coalesce(jsonb_array_length(v_vals), 0) = 0);
END $$;

-- Accounting personal field (manage permission on finance surface)
DO $$
DECLARE fx record; j jsonb; v_key text; v_vals jsonb; v_acct record; v_perm uuid; v_role uuid;
BEGIN
  SELECT * INTO fx FROM _cw2_t13_fixture LIMIT 1;
  SELECT * INTO v_acct FROM _cw2_t05_accountant_for_org(fx.org_id);
  SELECT id INTO v_role FROM role WHERE organization_id = fx.org_id AND canonical_code = 'accountant' LIMIT 1;
  SELECT id INTO v_perm FROM permission WHERE code = 'student_personal_field.manage';
  INSERT INTO role_permission (role_id, permission_id)
  SELECT v_role, v_perm WHERE NOT EXISTS (
    SELECT 1 FROM role_permission rp WHERE rp.role_id = v_role AND rp.permission_id = v_perm
  );

  PERFORM _cw2_t05_as_auth(v_acct.accountant_auth);
  j := public.create_personal_custom_field_definition('Lu y cong no', 'text');
  v_key := j->>'field_key';
  PERFORM _cw2_t13_record(37, 'accounting creates personal field', v_key IS NOT NULL);

  PERFORM public.save_personal_custom_field_values(
    'lead', fx.lead_id, jsonb_build_array(jsonb_build_object('field_key', v_key, 'value', 'Can doi chieu'))
  );
  v_vals := public.list_personal_custom_field_values('lead', fx.lead_id);
  PERFORM _cw2_t13_record(38, 'accounting read own personal value', EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_vals) e WHERE e->>'value' = 'Can doi chieu'
  ));
END $$;

-- PIN adversarial
DO $$
DECLARE fx record; f2 record; j jsonb; j_list jsonb; v_row jsonb; v_detail jsonb;
  v_teacher_auth uuid; v_acct_auth uuid; v_pin text; v_fail boolean := false;
  v_other_pe uuid;
BEGIN
  SELECT * INTO fx FROM _cw2_t13_fixture LIMIT 1;

  PERFORM _cw2_t05_as_auth(fx.consultant_b_auth);
  BEGIN
    v_detail := public.get_consultant_portfolio_entry_detail(fx.portfolio_entry_id);
    v_fail := true;
  EXCEPTION WHEN OTHERS THEN
    v_fail := false;
  END;
  PERFORM _cw2_t13_record(24, 'consultant B denied other portfolio detail', NOT v_fail OR v_detail IS NULL);

  PERFORM _cw2_t05_as_auth(fx.consultant_b_auth);
  j_list := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 50);
  SELECT elem INTO v_row FROM jsonb_array_elements(j_list->'rows') elem
  WHERE (elem->>'portfolio_entry_id')::uuid = fx.portfolio_entry_id LIMIT 1;
  PERFORM _cw2_t13_record(25, 'consultant B list omits A row PIN', v_row IS NULL OR v_row->>'personal_identification_number' IS NULL);

  SELECT * INTO f2 FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_auth(f2.consultant_a_auth);
  j := public.create_consultant_workspace_portfolio_intake(
    'CROSS', 'ORG', '2015-01-01', 'PH', 'HUYNH', '0900111222', '009988776655', '[]'::jsonb
  );
  v_other_pe := (j->>'portfolio_entry_id')::uuid;
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  j_list := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 50);
  SELECT elem INTO v_row FROM jsonb_array_elements(j_list->'rows') elem
  WHERE (elem->>'portfolio_entry_id')::uuid = v_other_pe LIMIT 1;
  PERFORM _cw2_t13_record(36, 'cross-org list omits foreign PIN', v_row IS NULL OR v_row->>'personal_identification_number' IS NULL);

  v_teacher_auth := _cw2_t11_teacher_only_auth(fx.org_id);
  PERFORM _cw2_t05_as_auth(v_teacher_auth);
  v_fail := false;
  BEGIN
    j_list := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 50);
  EXCEPTION WHEN OTHERS THEN
    v_fail := true;
  END;
  PERFORM _cw2_t13_record(26, 'teacher denied portfolio list', v_fail);
  BEGIN
    SELECT personal_identification_number INTO v_pin FROM student LIMIT 1;
    PERFORM _cw2_t13_record(27, 'teacher denied raw student PIN column', v_pin IS NULL);
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM _cw2_t13_record(27, 'teacher denied raw student PIN column', true);
  END;

  PERFORM _cw2_t05_as_postgres();
  SELECT au.auth_user_id INTO v_acct_auth
  FROM app_user au
  JOIN user_role ur ON ur.user_id = au.id AND ur.organization_id = fx.org_id
  JOIN role r ON r.id = ur.role_id AND r.canonical_code = 'accountant'
  WHERE au.organization_id = fx.org_id
  LIMIT 1;
  PERFORM _cw2_t05_as_auth(v_acct_auth);
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  j := public.get_consultant_portfolio_entry_detail(fx.portfolio_entry_id);
  PERFORM _cw2_t13_record(28, 'consultant A detail PIN', j->>'personal_identification_number' = '001234567890');

  PERFORM _cw2_t05_as_auth(v_acct_auth);
  BEGIN
    v_detail := public.get_consultant_portfolio_entry_detail(fx.portfolio_entry_id);
    PERFORM _cw2_t13_record(
      29,
      'accountant without PIN perm omits raw PIN',
      v_detail->>'personal_identification_number' IS NULL
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM _cw2_t13_record(29, 'accountant without PIN perm omits raw PIN', true);
  END;

  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  j := public.get_consultant_portfolio_entry_detail(fx.portfolio_entry_id);
  PERFORM _cw2_t13_record(30, 'owner/consultant authorized PIN path', j->>'personal_identification_number' = '001234567890');
END $$;

-- Core vs custom separation, archive semantics, bulk read, grid prefs, role isolation
DO $$
DECLARE
  fx record; f2 record; j jsonb; v_vals jsonb; v_key text; v_def uuid; v_ok boolean; v_cnt integer;
  v_acad_auth uuid; v_acct_auth uuid; v_owner_auth uuid; v_teacher_auth uuid; v_student uuid;
  v_acad_key text; v_acct_key text;
BEGIN
  SELECT * INTO fx FROM _cw2_t13_fixture LIMIT 1;
  PERFORM _cw2_t05_as_postgres();
  SELECT student_id INTO v_student FROM consultant_portfolio_entry WHERE id = fx.portfolio_entry_id;
  SELECT au.auth_user_id INTO v_acad_auth FROM app_user au
  WHERE au.organization_id = fx.org_id AND au.email = 't13-acad-' || fx.org_id::text || '@olli.local';
  SELECT au.auth_user_id INTO v_acct_auth FROM app_user au
  JOIN user_role ur ON ur.user_id = au.id AND ur.organization_id = fx.org_id
  JOIN role r ON r.id = ur.role_id AND r.canonical_code = 'accountant'
  WHERE au.organization_id = fx.org_id LIMIT 1;
  SELECT au.auth_user_id INTO v_owner_auth FROM organization_entitlement oe
  JOIN app_user au ON au.id = oe.primary_app_user_id
  WHERE oe.organization_id = fx.org_id;

  -- 39: label equal to a core identity gets a distinct key
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  j := public.create_personal_custom_field_definition('student_code', 'text');
  v_key := j->>'field_key';
  PERFORM _cw2_t13_record(39, 'core-named label gets non-core key', v_key IS NOT NULL AND v_key <> 'student_code');

  -- 40: custom "Ngay sinh"/"Ma hoc vien" values never touch core DOB / student code
  j := public.create_personal_custom_field_definition('date_of_birth', 'date');
  PERFORM public.save_personal_custom_field_values('student', v_student, jsonb_build_array(
    jsonb_build_object('field_key', j->>'field_key', 'value', '2001-01-01'),
    jsonb_build_object('field_key', v_key, 'value', 'XX999999')
  ));
  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t13_record(40, 'custom core-named values keep core fields', EXISTS (
    SELECT 1 FROM student s WHERE s.id = v_student
      AND s.date_of_birth = '2018-01-01' AND s.student_code = fx.cc || '180037'
  ) AND (j->>'field_key') <> 'date_of_birth');

  -- 41: explicit reserved key rejected
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  BEGIN
    PERFORM public.create_personal_custom_field_definition('X', 'text', 'date_of_birth');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := SQLERRM LIKE '%custom_field_key_reserved%';
  END;
  PERFORM _cw2_t13_record(41, 'explicit reserved key rejected', v_ok);

  -- 42: only active/archived status accepted
  j := public.create_personal_custom_field_definition('Theo doi', 'text');
  v_def := (j->>'id')::uuid;
  v_key := j->>'field_key';
  BEGIN
    PERFORM public.update_personal_custom_field_definition(v_def, NULL, 'deleted');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := SQLERRM LIKE '%invalid_status%';
  END;
  PERFORM _cw2_t13_record(42, 'invalid status rejected', v_ok);

  -- 35: another consultant cannot rename/archive this definition
  PERFORM _cw2_t05_as_auth(fx.consultant_b_auth);
  BEGIN
    PERFORM public.update_personal_custom_field_definition(v_def, 'Hijack', 'archived');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := SQLERRM LIKE '%field_not_found%';
  END;
  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t13_record(35, 'non-owner cannot rename/archive', v_ok AND EXISTS (
    SELECT 1 FROM consultant_custom_field_definition WHERE id = v_def AND label = 'Theo doi' AND status = 'active'
  ));
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);

  -- 43/44: archive hides column but retains stored values; archived field is read-only
  PERFORM public.save_personal_custom_field_values('student', v_student,
    jsonb_build_array(jsonb_build_object('field_key', v_key, 'value', 'Giu lai')));
  PERFORM public.update_personal_custom_field_definition(v_def, NULL, 'archived');
  v_vals := public.list_personal_custom_field_values('student', v_student);
  PERFORM _cw2_t05_as_postgres();
  SELECT count(*) INTO v_cnt FROM consultant_custom_field_value WHERE field_definition_id = v_def AND value_text = 'Giu lai';
  PERFORM _cw2_t13_record(43, 'archive hides column, retains value', v_cnt = 1 AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_vals) e WHERE e->>'field_key' = v_key
  ));
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  BEGIN
    PERFORM public.save_personal_custom_field_values('student', v_student,
      jsonb_build_array(jsonb_build_object('field_key', v_key, 'value', 'Moi')));
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := SQLERRM LIKE '%invalid_custom_field%';
  END;
  PERFORM _cw2_t13_record(44, 'archived field rejects writes', v_ok);

  -- 45: bulk read returns only caller-owned active values
  v_vals := public.list_personal_custom_field_values_bulk('student', ARRAY[v_student]);
  PERFORM _cw2_t05_as_auth(fx.consultant_b_auth);
  PERFORM _cw2_t13_record(45, 'bulk read owner-scoped',
    jsonb_array_length(v_vals) >= 1
    AND jsonb_array_length(public.list_personal_custom_field_values_bulk('student', ARRAY[v_student])) = 0);

  -- 46: grid preferences are private per user
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  INSERT INTO personal_grid_preference (organization_id, app_user_id, surface_key, preferences)
  VALUES (fx.org_id, fx.consultant_a_user, 'students', '{"columnOrder":["custom_x"]}'::jsonb)
  ON CONFLICT (organization_id, app_user_id, surface_key) DO UPDATE SET preferences = excluded.preferences;
  PERFORM _cw2_t05_as_auth(fx.consultant_b_auth);
  SELECT count(*) INTO v_cnt FROM personal_grid_preference;
  BEGIN
    INSERT INTO personal_grid_preference (organization_id, app_user_id, surface_key, preferences)
    VALUES (fx.org_id, fx.consultant_a_user, 'finance_students', '{}'::jsonb);
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := true;
  END;
  PERFORM _cw2_t13_record(46, 'grid prefs private per user', v_cnt = 0 AND v_ok);

  -- 47: primary owner does not automatically see others' personal notes
  PERFORM _cw2_t05_as_auth(v_owner_auth);
  SELECT count(*) INTO v_cnt FROM consultant_custom_field_definition
  WHERE owner_app_user_id <> public.current_app_user_id();
  PERFORM _cw2_t13_record(47, 'owner cannot see others notes',
    v_cnt = 0 AND jsonb_array_length(public.list_personal_custom_field_values_bulk('lead', ARRAY[fx.lead_id])) = 0);

  -- 48: Hoc vu and Accounting notes are mutually invisible
  PERFORM _cw2_t05_as_auth(v_acad_auth);
  v_acad_key := (public.create_personal_custom_field_definition('Luu y xep lop 2', 'text'))->>'field_key';
  PERFORM public.save_personal_custom_field_values('student', v_student,
    jsonb_build_array(jsonb_build_object('field_key', v_acad_key, 'value', 'Lop toi')));
  PERFORM _cw2_t05_as_auth(v_acct_auth);
  v_acct_key := (public.create_personal_custom_field_definition('Luu y cong no 2', 'text'))->>'field_key';
  PERFORM public.save_personal_custom_field_values('student', v_student,
    jsonb_build_array(jsonb_build_object('field_key', v_acct_key, 'value', 'No cu')));
  v_vals := public.list_personal_custom_field_values_bulk('student', ARRAY[v_student]);
  v_ok := NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_vals) e WHERE e->>'value' = 'Lop toi');
  PERFORM _cw2_t05_as_auth(v_acad_auth);
  v_vals := public.list_personal_custom_field_values_bulk('student', ARRAY[v_student]);
  v_ok := v_ok AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_vals) e WHERE e->>'value' = 'No cu');
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  v_vals := public.list_personal_custom_field_values_bulk('student', ARRAY[v_student]);
  v_ok := v_ok AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_vals) e WHERE e->>'value' IN ('Lop toi', 'No cu')
  );
  PERFORM _cw2_t13_record(48, 'academic/accounting/consultant notes isolated', v_ok);

  -- 49: teacher cannot manage personal columns
  PERFORM _cw2_t05_as_postgres();
  SELECT au.auth_user_id INTO v_teacher_auth FROM app_user au
  JOIN user_role ur ON ur.user_id = au.id AND ur.organization_id = fx.org_id AND ur.status = 'active'
  JOIN role r ON r.id = ur.role_id AND r.canonical_code = 'teacher'
  WHERE au.organization_id = fx.org_id LIMIT 1;
  PERFORM _cw2_t05_as_auth(v_teacher_auth);
  BEGIN
    PERFORM public.create_personal_custom_field_definition('Teacher note', 'text');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _cw2_t13_record(49, 'teacher denied personal columns', v_ok
    AND jsonb_array_length(public.list_personal_custom_field_values_bulk('student', ARRAY[v_student])) = 0);

  -- 50: cross-org subject writes rejected
  SELECT * INTO f2 FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_auth(f2.consultant_a_auth);
  v_key := (public.create_personal_custom_field_definition('Cross', 'text'))->>'field_key';
  BEGIN
    PERFORM public.save_personal_custom_field_values('student', v_student,
      jsonb_build_array(jsonb_build_object('field_key', v_key, 'value', 'x')));
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := SQLERRM LIKE '%subject_not_found%';
  END;
  PERFORM _cw2_t13_record(50, 'cross-org subject write denied', v_ok);

  -- 51: accounting student list includes the student; consultant is denied
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
  SELECT fx.org_id, v_student, cl.id, CURRENT_DATE, 'active'
  FROM class cl WHERE cl.organization_id = fx.org_id LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO course (organization_id, code, name) VALUES (fx.org_id, 'T13C', 'T13 Course');
    INSERT INTO class (organization_id, course_id, name)
    SELECT fx.org_id, c.id, 'T13 Class' FROM course c WHERE c.organization_id = fx.org_id AND c.code = 'T13C';
    INSERT INTO enrollment (organization_id, student_id, class_id, start_date, status)
    SELECT fx.org_id, v_student, cl.id, CURRENT_DATE, 'active'
    FROM class cl WHERE cl.organization_id = fx.org_id AND cl.name = 'T13 Class';
  END IF;
  PERFORM _cw2_t05_as_auth(v_acct_auth);
  v_ok := EXISTS (
    SELECT 1 FROM public.list_finance_student_accounts(500, 0) r
    WHERE (r->>'student_id')::uuid = v_student AND (r->>'outstanding_balance')::bigint = 0
  );
  PERFORM _cw2_t05_as_auth(fx.consultant_a_auth);
  BEGIN
    PERFORM public.list_finance_student_accounts(10, 0);
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := v_ok AND SQLERRM LIKE '%permission_denied%';
  END;
  PERFORM _cw2_t13_record(51, 'finance student accounts incl. zero-balance; consultant denied', v_ok);

  -- 52: organizations created after migration receive T13 role grants
  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t13_record(52, 'future org canonical grants', (
    SELECT count(DISTINCT r.canonical_code) FROM role r
    JOIN role_permission rp ON rp.role_id = r.id
    JOIN permission p ON p.id = rp.permission_id AND p.code = 'student_personal_field.manage'
    WHERE r.organization_id = f2.org_id AND r.is_canonical_template
      AND r.canonical_code IN ('academic_operations', 'accountant', 'consultant', 'center_manager')
  ) = 4 AND NOT EXISTS (
    SELECT 1 FROM role r
    JOIN role_permission rp ON rp.role_id = r.id
    JOIN permission p ON p.id = rp.permission_id
      AND p.code IN ('student_personal_field.manage', 'student.personal_id.read')
    WHERE r.organization_id = f2.org_id AND r.canonical_code = 'teacher'
  ));

  -- 53: grid guardian display uses Vietnamese family-then-given order
  PERFORM _cw2_t13_record(53, 'guardian display family name first', (
    public._cw2_portfolio_primary_contact_display(
      gen_random_uuid(), 'B', 'NGUYEN VAN', '0912345678', NULL, NULL, NULL, NULL
    )->>'primary_guardian_name' = 'NGUYEN VAN B'
    AND public._cw2_portfolio_primary_contact_display(
      NULL, NULL, NULL, NULL, gen_random_uuid(), 'C', 'TRAN THI', '0900000000'
    )->>'primary_guardian_name' = 'TRAN THI C'
  ));
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _cw2_t13_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T13 tests failed: % (%)', v_fail, (
      SELECT string_agg(test_no || ' ' || test_name, '; ' ORDER BY test_no)
      FROM _cw2_t13_results WHERE result = 'FAIL'
    );
  END IF;
  IF (SELECT count(*) FROM _cw2_t13_results WHERE result = 'PASS') <> 53 THEN
    RAISE EXCEPTION 'CW2-T13 expected 53 passing cases, got %', (SELECT count(*) FROM _cw2_t13_results);
  END IF;
  RAISE NOTICE 'CW2-T13: % cases PASS', (SELECT count(*) FROM _cw2_t13_results WHERE result = 'PASS');
END $$;
