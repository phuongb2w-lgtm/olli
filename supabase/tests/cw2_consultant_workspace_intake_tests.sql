-- CW2 corrective: consultant workspace inline intake

CREATE TEMP TABLE IF NOT EXISTS _cw2_intake_results (
  test_no integer PRIMARY KEY,
  test_name text NOT NULL,
  result text NOT NULL CHECK (result IN ('PASS', 'FAIL'))
);
GRANT ALL ON TABLE _cw2_intake_results TO authenticated, anon;

CREATE OR REPLACE FUNCTION _cw2_intake_record(test_no integer, test_name text, passed boolean)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _cw2_intake_results (test_no, test_name, result)
  VALUES (test_no, test_name, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

DO $$
DECLARE f record; j jsonb; v_pe uuid; v_seq bigint; v_cc char(2);
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.create_consultant_workspace_portfolio_intake(
    'Nguyen', 'Inline', '2017-06-01', 'Tran', 'Parent', '0909000001', NULL, '[]'::jsonb
  );
  v_pe := (j->>'portfolio_entry_id')::uuid;
  SELECT workspace_sequence INTO v_seq FROM consultant_portfolio_entry WHERE id = v_pe;
  PERFORM _cw2_intake_record(1, 'intake creates portfolio entry', v_pe IS NOT NULL AND v_seq >= 1);
  PERFORM _cw2_intake_record(2, 'intake stays lead lifecycle', (j->>'subject_type') = 'lead');
  PERFORM _cw2_intake_record(3, 'no official student code allocated', j->>'student_code_official' IS NULL);
  PERFORM _cw2_intake_record(4, 'provisional display uses 0000 suffix', (j->>'student_code_display') LIKE '%0000');
END $$;

-- Null DOB intake: no fake YY; provisional display stays incomplete until DOB exists
DO $$
DECLARE f record; j jsonb; v_pe uuid; j2 jsonb; v_cc char(2); v_disp text;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  PERFORM _cw2_t05_as_postgres();
  SELECT consultant_operational_code INTO v_cc FROM app_user WHERE id = f.consultant_a_user;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);
  j := public.create_consultant_workspace_portfolio_intake(
    'Tran', 'NoDob', NULL, 'Le', 'Parent', '0909111222', NULL, '[]'::jsonb
  );
  v_pe := (j->>'portfolio_entry_id')::uuid;
  PERFORM _cw2_intake_record(5, 'null DOB intake has no official code', j->>'student_code_official' IS NULL);
  PERFORM _cw2_intake_record(6, 'null DOB intake has null provisional display', j->>'student_code_display' IS NULL);
  PERFORM _cw2_intake_record(
    7,
    'null DOB does not fabricate YY in domain helper',
    public._cw2_provisional_student_code_display(v_cc, NULL) IS NULL
  );
  j2 := public.save_consultant_portfolio_profile(
    v_pe, 'Tran', 'NoDob', '2017-03-15', 'Le', 'Parent', '0909111222', NULL, NULL
  );
  v_disp := j2->>'student_code_display';
  PERFORM _cw2_intake_record(
    8,
    'DOB via profile path resolves provisional CCYY0000',
    v_disp = v_cc || '170000'
  );
  PERFORM _cw2_intake_record(
    9,
    'student row still has no official NNNN after DOB save',
    j2->>'student_code_official' IS NULL AND NOT public._cw2_is_official_student_code(v_disp)
  );
END $$;

-- Guardian + list/detail read model after intake
DO $$
DECLARE
  f record;
  j jsonb;
  j_list jsonb;
  v_pe uuid;
  v_cc char(2);
  v_row jsonb;
  v_seq_before bigint;
  v_seq_after bigint;
BEGIN
  SELECT * INTO f FROM _cw2_t05_org();
  SELECT consultant_operational_code INTO v_cc FROM app_user WHERE id = f.consultant_a_user;
  PERFORM _cw2_t05_as_auth(f.consultant_a_auth);

  SELECT last_allocated_sequence INTO v_seq_before
  FROM organization_student_sequence WHERE organization_id = f.org_id;

  j := public.create_consultant_workspace_portfolio_intake(
    'NGUYEN VAN', 'AN', '2017-06-09', 'NGUYEN VAN', 'B', '0912345678', '001234567890', '[]'::jsonb
  );
  v_pe := (j->>'portfolio_entry_id')::uuid;

  PERFORM _cw2_intake_record(10, 'intake detail primary guardian given', j->>'primary_guardian_given_name' = 'B');
  PERFORM _cw2_intake_record(11, 'intake detail primary guardian phone', j->>'primary_guardian_phone' = '0912345678');
  PERFORM _cw2_intake_record(12, 'intake DOB persisted', (j->>'date_of_birth') = '2017-06-09');
  PERFORM _cw2_intake_record(13, 'intake PIN persisted with leading zeroes', j->>'personal_identification_number' = '001234567890');
  PERFORM _cw2_intake_record(
    14,
    'intake provisional CCYY0000',
    j->>'student_code_display' = v_cc || '170000'
  );

  j_list := public.list_consultant_workspace_portfolio('{}'::jsonb, 'workspace_sequence', 'desc', 50);
  SELECT elem INTO v_row
  FROM jsonb_array_elements(j_list->'rows') elem
  WHERE (elem->>'portfolio_entry_id')::uuid = v_pe
  LIMIT 1;

  PERFORM _cw2_intake_record(15, 'list returns guardian name after reload', v_row->>'primary_guardian_name' LIKE '%B%');
  PERFORM _cw2_intake_record(16, 'list returns guardian phone after reload', v_row->>'primary_guardian_phone' = '0912345678');
  PERFORM _cw2_intake_record(17, 'list DOB matches detail', v_row->>'date_of_birth' = '2017-06-09');
  PERFORM _cw2_intake_record(18, 'list provisional code matches detail', v_row->>'student_code_display' = j->>'student_code_display');

  SELECT last_allocated_sequence INTO v_seq_after
  FROM organization_student_sequence WHERE organization_id = f.org_id;
  PERFORM _cw2_intake_record(19, 'provisional display does not consume official sequence', v_seq_after = v_seq_before);

  j := public.save_consultant_portfolio_profile(
    v_pe, 'NGUYEN VAN', 'AN', '2018-01-01', 'NGUYEN VAN', 'B', '0912345678', '001234567890', NULL
  );
  PERFORM _cw2_intake_record(
    20,
    'pre-official DOB change updates provisional YY',
    j->>'student_code_display' = v_cc || '180000'
  );
END $$;

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _cw2_intake_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2 intake tests failed: %', v_fail;
  END IF;
END $$;
