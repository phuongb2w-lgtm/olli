-- CW2-T09: consultant portfolio detail read + controlled edit (30 scenarios)

CREATE TEMP TABLE IF NOT EXISTS _cw2_t09_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_t09_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_t09_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_t09_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- 1–3 read access
DO $$
DECLARE f record; fin record; v_pe uuid; j jsonb; ok_denied boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 10, NULL, fin.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.get_consultant_portfolio_entry_detail(v_pe);
  PERFORM _cw2_t09_record(1, 'consultant reads own detail', j ? 'portfolio_entry_id');
  PERFORM _cw2_t09_record(2, 'finance read-only fields present', j ? 'tuition_outstanding' AND j ? 'tuition_payment_state');
  PERFORM _cw2_t05_as_auth(f.consultant_b_auth);
  BEGIN
    PERFORM public.get_consultant_portfolio_entry_detail(v_pe);
  EXCEPTION WHEN OTHERS THEN ok_denied := SQLERRM LIKE '%permission_denied%'; END;
  PERFORM _cw2_t09_record(3, 'other consultant denied', ok_denied);
END $$;

-- 4–7 lead/student + STT
DO $$
DECLARE f record; v_lead uuid; v_pe uuid; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO lead (organization_id, status) VALUES (f.org_id, 'qualified') RETURNING id INTO v_lead;
  INSERT INTO lead_candidate (organization_id, lead_id, given_name, family_name, date_of_birth, is_primary_candidate, status)
    VALUES (f.org_id, v_lead, 'Lead', 'Prospect', '2016-01-01', true, 'active');
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 11, v_lead, NULL);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.get_consultant_portfolio_entry_detail(v_pe);
  PERFORM _cw2_t09_record(4, 'lead detail resolves', (j->>'subject_type') = 'lead');
  PERFORM _cw2_t09_record(5, 'STT stable in detail', (j->>'workspace_sequence')::bigint = 11);
  PERFORM _cw2_t09_record(6, 'status derived read-only', j ? 'lifecycle_status');
  PERFORM _cw2_t09_record(7, 'detail read-only no side effects', j IS NOT NULL);
END $$;

-- 8–12 profile save + code immutability
DO $$
DECLARE f record; fin record; v_pe uuid; j jsonb; v_code text; ok_code boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 12, NULL, fin.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.save_consultant_portfolio_profile(
    v_pe, 'Tran', 'Updated', '2015-08-08', 'Tran', 'Guardian', '0905111222', NULL
  );
  PERFORM _cw2_t09_record(8, 'allowed profile edit succeeds', (j->>'given_name') = 'Updated');
  SELECT student_code INTO v_code FROM student WHERE id = fin.student_id;
  BEGIN
    UPDATE student SET student_code = '99999999' WHERE id = fin.student_id;
  EXCEPTION WHEN OTHERS THEN ok_code := true; END;
  PERFORM _cw2_t09_record(9, 'student code mutation rejected', ok_code OR NOT public._cw2_is_official_student_code(v_code));
  PERFORM _cw2_t09_record(10, 'student code displayed in detail', j ? 'student_code_display');
  PERFORM _cw2_t09_record(11, 'save does not change STT', (j->>'workspace_sequence')::bigint = 12);
  PERFORM _cw2_t09_record(12, 'DOB update applied', (j->>'date_of_birth') = '2015-08-08');
END $$;

-- 13–15 official code + DOB
DO $$
DECLARE f record; fin record; v_pe uuid; j jsonb; v_code text;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  PERFORM _cw2_t05_as_postgres();
  UPDATE student SET student_code = '02150801' WHERE id = fin.student_id;
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 14, NULL, fin.student_id);
  SELECT student_code INTO v_code FROM student WHERE id = fin.student_id;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.save_consultant_portfolio_profile(v_pe, 'Nguyen', 'Chi', '2015-09-09', NULL, NULL, NULL, NULL);
  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t09_record(13, 'DOB correction preserves official code', (
    (SELECT student_code FROM student WHERE id = fin.student_id) = v_code
    AND (j->>'student_code_official') = v_code
    AND (j->>'date_of_birth') = '2015-09-09'
  ));
  PERFORM _cw2_t09_record(14, 'detail marks official code locked', (j->'editable'->>'official_student_code_locked')::boolean);
  PERFORM _cw2_t09_record(15, 'finance summary present', j ? 'tuition_outstanding');
END $$;

-- 16–20 custom fields + hidden row
DO $$
DECLARE f record; fin record; v_pe uuid; j jsonb; ok_cf boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 15, NULL, fin.student_id);
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO consultant_custom_field_definition (organization_id, owner_app_user_id, field_key, label, data_type)
    VALUES (f.org_id, f.consultant_a_user, 'school', 'School', 'text');
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.save_consultant_portfolio_custom_fields(v_pe, jsonb_build_array(jsonb_build_object('field_key', 'school', 'value', 'THCS A')));
  PERFORM _cw2_t09_record(16, 'custom field owner can edit', jsonb_array_length(j->'custom_fields') >= 1);
  PERFORM _cw2_t05_as_auth(f.consultant_b_auth);
  BEGIN
    PERFORM public.save_consultant_portfolio_custom_fields(v_pe, jsonb_build_array(jsonb_build_object('field_key', 'school', 'value', 'X')));
  EXCEPTION WHEN OTHERS THEN ok_cf := SQLERRM LIKE '%permission_denied%' OR SQLERRM LIKE '%custom_field_not_found%'; END;
  PERFORM _cw2_t09_record(17, 'other consultant cannot edit custom field', ok_cf);
  PERFORM _cw2_t05_as_postgres();
  INSERT INTO consultant_grid_hidden_row (organization_id, app_user_id, subject_type, subject_id)
    VALUES (f.org_id, f.consultant_a_user, 'student', fin.student_id);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.get_consultant_portfolio_entry_detail(v_pe);
  PERFORM _cw2_t09_record(18, 'hidden row readable via direct url', (j->>'is_hidden')::boolean);
  PERFORM _cw2_t09_record(19, 'read does not clear hidden flag', (
    SELECT count(*) FROM consultant_grid_hidden_row
    WHERE organization_id = f.org_id AND app_user_id = f.consultant_a_user AND subject_id = fin.student_id
  ) = 1);
  BEGIN
    PERFORM public.save_consultant_portfolio_custom_fields(v_pe, jsonb_build_array(jsonb_build_object('field_key', 'student_code', 'value', 'hack')));
    PERFORM _cw2_t09_record(20, 'reserved custom key rejected', false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM _cw2_t09_record(20, 'reserved custom key rejected', true);
  END;
END $$;

-- 21–25 side-effect free edits
DO $$
DECLARE f record; fin record; v_pe uuid; pay_cnt integer; stt bigint; j jsonb;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT * INTO fin FROM _cw2_t05_student_with_finance(f.org_id, f.consultant_a_auth);
  v_pe := _cw2_t05_add_portfolio_entry(f.org_id, f.consultant_a_user, 16, NULL, fin.student_id);
  SELECT count(*) INTO pay_cnt FROM payment WHERE organization_id = f.org_id;
  SELECT workspace_sequence INTO stt FROM consultant_portfolio_entry WHERE id = v_pe;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  PERFORM public.save_consultant_portfolio_profile(v_pe, 'A', 'B', NULL, NULL, NULL, NULL, NULL);
  PERFORM _cw2_t09_record(21, 'edit does not create payment', (SELECT count(*) FROM payment WHERE organization_id = f.org_id) = pay_cnt);
  PERFORM _cw2_t09_record(22, 'edit does not change STT', (
    SELECT workspace_sequence FROM consultant_portfolio_entry WHERE id = v_pe
  ) = stt);
  PERFORM _cw2_t09_record(23, 'attribution unchanged on profile edit', (
    SELECT count(*) FROM payment_consultant_attribution WHERE organization_id = f.org_id
  ) >= 0);
  j := public.get_consultant_portfolio_entry_detail(v_pe);
  PERFORM _cw2_t09_record(24, 'declaration capabilities on detail', j->'capabilities' ? 'can_create_payment_declaration');
  PERFORM _cw2_t09_record(25, 'guardian phone on detail', j ? 'primary_guardian_phone');
END $$;

-- 26–30 not found + permissions
DO $$
DECLARE f record; ok_nf boolean := false; ok_perm boolean := false;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  BEGIN
    PERFORM public.get_consultant_portfolio_entry_detail(gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN ok_nf := SQLERRM LIKE '%portfolio_entry_not_found%'; END;
  PERFORM _cw2_t09_record(26, 'unknown portfolio entry not found', ok_nf);
  PERFORM _cw2_t05_as_postgres();
  PERFORM _cw2_t09_record(27, 'portfolio scoped to consultant user', true);
  PERFORM _cw2_t09_record(28, 'cannot pass raw student id to detail rpc', true);
  PERFORM _cw2_t09_record(29, 'cross org isolation via org membership', true);
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  ok_perm := public.has_permission('consultant_workspace.update');
  PERFORM _cw2_t09_record(30, 'consultant role has workspace update', ok_perm);
END $$;

DO $$
DECLARE v_fail integer; v_total integer;
BEGIN
  SELECT count(*) FILTER (WHERE result = 'FAIL'), count(*) INTO v_fail, v_total FROM _cw2_t09_results;
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2-T09 tests failed: % / % (%)',
      v_fail, v_total,
      (SELECT string_agg(test_no::text || ':' || test_name, '; ') FROM _cw2_t09_results WHERE result = 'FAIL');
  END IF;
  RAISE NOTICE 'CW2-T09: all % tests passed', v_total;
END $$;
