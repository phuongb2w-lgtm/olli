-- M8-T10 post-restore semantic verification (run against recovery database).

\set ON_ERROR_STOP on

DO $$
DECLARE
  v_org uuid := 'd0100000-0000-4000-8000-000000000001';
  v_owner_app uuid := 'd0100001-0000-4000-8000-000000000001';
  v_student uuid := 'd0100100-0000-4000-8000-000000000001';
  v_lead uuid := 'd0100300-0000-4000-8000-000000000001';
  v_sub_status text;
  v_primary uuid;
  v_charge_amt numeric;
  v_lead_status text;
  v_session_count integer;
  v_rls boolean;
  v_migration_count integer;
BEGIN
  SELECT count(*) INTO v_migration_count FROM supabase_migrations.schema_migrations;
  IF v_migration_count < 59 THEN
    RAISE EXCEPTION 'T10-VERIFY migration history too small: %', v_migration_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM organization WHERE id = v_org AND name = 'M8-T10 DR Fixture Org') THEN
    RAISE EXCEPTION 'T10-VERIFY DR fixture organization missing';
  END IF;

  SELECT relrowsecurity INTO v_rls
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'organization';
  IF NOT COALESCE(v_rls, false) THEN
    RAISE EXCEPTION 'T10-VERIFY RLS not enabled on organization';
  END IF;

  SELECT os.status INTO v_sub_status
  FROM organization_subscription os
  WHERE os.organization_id = v_org;
  IF v_sub_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'T10-VERIFY subscription status expected active, got %', v_sub_status;
  END IF;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM organization_entitlement oe
  WHERE oe.organization_id = v_org;
  IF v_primary IS DISTINCT FROM v_owner_app THEN
    RAISE EXCEPTION 'T10-VERIFY Primary Owner mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM user_role ur
    JOIN role r ON r.id = ur.role_id
    WHERE ur.organization_id = v_org
      AND ur.user_id = v_owner_app
      AND r.canonical_code = 'center_manager'
      AND ur.status = 'active'
  ) THEN
    RAISE EXCEPTION 'T10-VERIFY owner center_manager membership missing';
  END IF;

  SELECT amount INTO v_charge_amt FROM charge
  WHERE organization_id = v_org AND student_id = v_student
  LIMIT 1;
  IF v_charge_amt IS DISTINCT FROM 250000 THEN
    RAISE EXCEPTION 'T10-VERIFY finance charge amount mismatch: %', v_charge_amt;
  END IF;

  SELECT status INTO v_lead_status FROM lead WHERE id = v_lead;
  IF v_lead_status IS DISTINCT FROM 'qualified' THEN
    RAISE EXCEPTION 'T10-VERIFY CRM lead status mismatch: %', v_lead_status;
  END IF;

  SELECT count(*) INTO v_session_count FROM teaching_session WHERE organization_id = v_org;
  IF v_session_count < 1 THEN
    RAISE EXCEPTION 'T10-VERIFY teaching session missing after restore';
  END IF;

  RAISE NOTICE 'T10-VERIFY PASS: cross-domain DR fixture semantics intact';
END $$;
