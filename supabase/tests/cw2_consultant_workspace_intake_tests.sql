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
    'Nguyen', 'Inline', '2017-06-01', 'Tran', 'Parent', '0909000001', '[]'::jsonb
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
    'Tran', 'NoDob', NULL, 'Le', 'Parent', '0909111222', '[]'::jsonb
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
    v_pe, 'Tran', 'NoDob', '2017-03-15', 'Le', 'Parent', '0909111222', NULL
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

DO $$
DECLARE v_fail integer;
BEGIN
  SELECT count(*) INTO v_fail FROM _cw2_intake_results WHERE result = 'FAIL';
  IF v_fail > 0 THEN
    RAISE EXCEPTION 'CW2 intake tests failed: %', v_fail;
  END IF;
END $$;
