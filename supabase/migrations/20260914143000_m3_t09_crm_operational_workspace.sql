-- M3-T09: CRM operational workspace — atomic lead intake and operational guards.

-- =============================================================================
-- CONVERTED LEAD PEOPLE EDIT GUARD
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_converted_lead_people_edits()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_status text;
BEGIN
  SELECT l.status INTO v_status
  FROM lead l
  WHERE l.id = COALESCE(NEW.lead_id, OLD.lead_id)
    AND l.organization_id = COALESCE(NEW.organization_id, OLD.organization_id);

  IF v_status = 'converted' THEN
    IF TG_OP = 'INSERT' THEN
      RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
    END IF;

    IF TG_TABLE_NAME = 'lead_candidate' THEN
      IF NEW.given_name IS DISTINCT FROM OLD.given_name
         OR NEW.family_name IS DISTINCT FROM OLD.family_name
         OR NEW.date_of_birth IS DISTINCT FROM OLD.date_of_birth
         OR NEW.status IS DISTINCT FROM OLD.status
         OR NEW.is_primary_candidate IS DISTINCT FROM OLD.is_primary_candidate
      THEN
        RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
      END IF;
    ELSIF TG_TABLE_NAME = 'lead_contact' THEN
      IF NEW.given_name IS DISTINCT FROM OLD.given_name
         OR NEW.family_name IS DISTINCT FROM OLD.family_name
         OR NEW.phone IS DISTINCT FROM OLD.phone
         OR NEW.email IS DISTINCT FROM OLD.email
         OR NEW.relationship_type IS DISTINCT FROM OLD.relationship_type
         OR NEW.status IS DISTINCT FROM OLD.status
         OR NEW.is_primary_contact IS DISTINCT FROM OLD.is_primary_contact
         OR NEW.is_billing_contact IS DISTINCT FROM OLD.is_billing_contact
      THEN
        RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_candidate_protect_converted_edits
  BEFORE INSERT OR UPDATE ON lead_candidate
  FOR EACH ROW EXECUTE FUNCTION public.protect_converted_lead_people_edits();

CREATE TRIGGER lead_contact_protect_converted_edits
  BEFORE INSERT OR UPDATE ON lead_contact
  FOR EACH ROW EXECUTE FUNCTION public.protect_converted_lead_people_edits();

CREATE OR REPLACE FUNCTION public.protect_converted_lead_operational_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'converted' THEN
    IF NEW.lead_source_id IS DISTINCT FROM OLD.lead_source_id
       OR NEW.lead_campaign_id IS DISTINCT FROM OLD.lead_campaign_id
       OR NEW.referral_guardian_id IS DISTINCT FROM OLD.referral_guardian_id
       OR NEW.referral_student_id IS DISTINCT FROM OLD.referral_student_id
    THEN
      RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_protect_converted_operational_fields
  BEFORE UPDATE ON lead
  FOR EACH ROW EXECUTE FUNCTION public.protect_converted_lead_operational_fields();

-- =============================================================================
-- ATOMIC LEAD INTAKE
-- =============================================================================

CREATE OR REPLACE FUNCTION public._validate_lead_catalog_refs(
  p_org_id uuid,
  p_source_id uuid,
  p_campaign_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_source_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM lead_source
      WHERE id = p_source_id AND organization_id = p_org_id AND status = 'active'
    ) THEN
      RAISE EXCEPTION 'invalid_source' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_campaign_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM lead_campaign
      WHERE id = p_campaign_id AND organization_id = p_org_id AND status = 'active'
    ) THEN
      RAISE EXCEPTION 'invalid_campaign' USING ERRCODE = 'P0002';
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_lead_with_people(
  p_lead jsonb,
  p_candidates jsonb,
  p_contacts jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_lead_id uuid;
  v_source_id uuid;
  v_campaign_id uuid;
  v_referral_guardian_id uuid;
  v_referral_student_id uuid;
  v_candidate_ids uuid[] := ARRAY[]::uuid[];
  v_contact_ids uuid[] := ARRAY[]::uuid[];
  v_c record;
  v_ct record;
  v_candidate_id uuid;
  v_contact_id uuid;
  v_primary_candidates integer := 0;
  v_primary_contacts integer := 0;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF NOT public.has_permission('lead.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF jsonb_array_length(COALESCE(p_candidates, '[]'::jsonb)) < 1
     OR jsonb_array_length(COALESCE(p_contacts, '[]'::jsonb)) < 1
  THEN
    RAISE EXCEPTION 'intake_people_required' USING ERRCODE = 'P0001';
  END IF;

  v_source_id := NULLIF(p_lead->>'lead_source_id', '')::uuid;
  v_campaign_id := NULLIF(p_lead->>'lead_campaign_id', '')::uuid;
  v_referral_guardian_id := NULLIF(p_lead->>'referral_guardian_id', '')::uuid;
  v_referral_student_id := NULLIF(p_lead->>'referral_student_id', '')::uuid;

  PERFORM public._validate_lead_catalog_refs(v_org_id, v_source_id, v_campaign_id);

  IF v_referral_guardian_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM guardian WHERE id = v_referral_guardian_id AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_referral' USING ERRCODE = 'P0002';
  END IF;

  IF v_referral_student_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM student WHERE id = v_referral_student_id AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_referral' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO lead (
    organization_id, status, assigned_user_id,
    lead_source_id, lead_campaign_id,
    referral_guardian_id, referral_student_id,
    notes_summary, created_by, updated_by
  )
  VALUES (
    v_org_id, 'new', NULL,
    v_source_id, v_campaign_id,
    v_referral_guardian_id, v_referral_student_id,
    NULLIF(btrim(p_lead->>'notes_summary'), ''),
    v_actor, v_actor
  )
  RETURNING id INTO v_lead_id;

  FOR v_c IN
    SELECT *
    FROM jsonb_to_recordset(COALESCE(p_candidates, '[]'::jsonb)) AS x(
      given_name text,
      family_name text,
      date_of_birth date,
      is_primary_candidate boolean
    )
  LOOP
    IF v_c.given_name IS NULL OR btrim(v_c.given_name) = ''
       OR v_c.family_name IS NULL OR btrim(v_c.family_name) = ''
    THEN
      RAISE EXCEPTION 'invalid_candidate' USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(v_c.is_primary_candidate, false) THEN
      v_primary_candidates := v_primary_candidates + 1;
    END IF;

    INSERT INTO lead_candidate (
      organization_id, lead_id, given_name, family_name, date_of_birth,
      is_primary_candidate, created_by, updated_by
    )
    VALUES (
      v_org_id, v_lead_id, btrim(v_c.given_name), btrim(v_c.family_name), v_c.date_of_birth,
      COALESCE(v_c.is_primary_candidate, false), v_actor, v_actor
    )
    RETURNING id INTO v_candidate_id;

    v_candidate_ids := array_append(v_candidate_ids, v_candidate_id);
  END LOOP;

  IF v_primary_candidates > 1 THEN
    RAISE EXCEPTION 'primary_candidate_conflict' USING ERRCODE = 'P0001';
  END IF;

  IF v_primary_candidates = 0 THEN
    UPDATE lead_candidate
    SET is_primary_candidate = true, updated_by = v_actor
    WHERE id = v_candidate_ids[1] AND organization_id = v_org_id;
  END IF;

  FOR v_ct IN
    SELECT *
    FROM jsonb_to_recordset(COALESCE(p_contacts, '[]'::jsonb)) AS x(
      given_name text,
      family_name text,
      phone text,
      email text,
      relationship_type text,
      is_primary_contact boolean,
      is_billing_contact boolean
    )
  LOOP
    IF v_ct.given_name IS NULL OR btrim(v_ct.given_name) = ''
       OR v_ct.family_name IS NULL OR btrim(v_ct.family_name) = ''
    THEN
      RAISE EXCEPTION 'invalid_contact' USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(v_ct.is_primary_contact, false) THEN
      v_primary_contacts := v_primary_contacts + 1;
    END IF;

    INSERT INTO lead_contact (
      organization_id, lead_id, given_name, family_name, phone, email,
      relationship_type, is_primary_contact, is_billing_contact,
      created_by, updated_by
    )
    VALUES (
      v_org_id, v_lead_id, btrim(v_ct.given_name), btrim(v_ct.family_name),
      NULLIF(btrim(v_ct.phone), ''), NULLIF(btrim(v_ct.email), ''),
      COALESCE(NULLIF(v_ct.relationship_type, ''), 'guardian'),
      COALESCE(v_ct.is_primary_contact, false),
      COALESCE(v_ct.is_billing_contact, false),
      v_actor, v_actor
    )
    RETURNING id INTO v_contact_id;

    v_contact_ids := array_append(v_contact_ids, v_contact_id);
  END LOOP;

  IF v_primary_contacts > 1 THEN
    RAISE EXCEPTION 'primary_contact_conflict' USING ERRCODE = 'P0001';
  END IF;

  IF v_primary_contacts = 0 THEN
    UPDATE lead_contact
    SET is_primary_contact = true, is_billing_contact = true, updated_by = v_actor
    WHERE id = v_contact_ids[1] AND organization_id = v_org_id;
  END IF;

  RETURN jsonb_build_object(
    'lead_id', v_lead_id,
    'candidate_ids', to_jsonb(v_candidate_ids),
    'contact_ids', to_jsonb(v_contact_ids)
  );
END;
$$;

COMMENT ON FUNCTION public.create_lead_with_people(jsonb, jsonb, jsonb) IS
  'Atomic CRM lead intake: Lead + Candidates + Contacts. assigned_user_id remains null; use assign_lead() after creation.';

GRANT EXECUTE ON FUNCTION public.create_lead_with_people(jsonb, jsonb, jsonb) TO authenticated;

-- =============================================================================
-- OPERATIONAL LEAD UPDATE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_lead_operational(
  p_lead_id uuid,
  p_notes_summary text DEFAULT NULL,
  p_lead_source_id uuid DEFAULT NULL,
  p_lead_campaign_id uuid DEFAULT NULL,
  p_clear_source boolean DEFAULT false,
  p_clear_campaign boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_lead lead%ROWTYPE;
  v_source_id uuid;
  v_campaign_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_lead FROM lead
  WHERE id = p_lead_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_lead.status = 'converted' THEN
    RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
  END IF;

  v_source_id := CASE
    WHEN p_clear_source THEN NULL
    WHEN p_lead_source_id IS NOT NULL THEN p_lead_source_id
    ELSE v_lead.lead_source_id
  END;
  v_campaign_id := CASE
    WHEN p_clear_campaign THEN NULL
    WHEN p_lead_campaign_id IS NOT NULL THEN p_lead_campaign_id
    ELSE v_lead.lead_campaign_id
  END;

  PERFORM public._validate_lead_catalog_refs(v_org_id, v_source_id, v_campaign_id);

  UPDATE lead
  SET
    notes_summary = COALESCE(NULLIF(btrim(p_notes_summary), ''), notes_summary),
    lead_source_id = v_source_id,
    lead_campaign_id = v_campaign_id,
    updated_by = v_actor
  WHERE id = p_lead_id AND organization_id = v_org_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_lead_operational(uuid, text, uuid, uuid, boolean, boolean) TO authenticated;

-- =============================================================================
-- CATALOG MANAGEMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION public.upsert_lead_source_catalog(
  p_id uuid,
  p_code text,
  p_display_name text,
  p_status text DEFAULT 'active'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('lead.manage_sources') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('active', 'inactive') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF p_id IS NULL THEN
    INSERT INTO lead_source (organization_id, code, display_name, status, created_by, updated_by)
    VALUES (v_org_id, lower(btrim(p_code)), btrim(p_display_name), p_status, v_actor, v_actor)
    RETURNING id INTO v_id;
  ELSE
    UPDATE lead_source
    SET
      display_name = btrim(p_display_name),
      status = p_status,
      updated_by = v_actor
    WHERE id = p_id AND organization_id = v_org_id
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_lead_campaign_catalog(
  p_id uuid,
  p_code text,
  p_name text,
  p_lead_source_id uuid DEFAULT NULL,
  p_status text DEFAULT 'active'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('lead.manage_sources') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('active', 'inactive', 'archived') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF p_lead_source_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM lead_source WHERE id = p_lead_source_id AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'invalid_source' USING ERRCODE = 'P0002';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO lead_campaign (organization_id, code, name, lead_source_id, status, created_by, updated_by)
    VALUES (v_org_id, lower(btrim(p_code)), btrim(p_name), p_lead_source_id, p_status, v_actor, v_actor)
    RETURNING id INTO v_id;
  ELSE
    UPDATE lead_campaign
    SET
      name = btrim(p_name),
      lead_source_id = p_lead_source_id,
      status = p_status,
      updated_by = v_actor
    WHERE id = p_id AND organization_id = v_org_id
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_lead_lost_reason_catalog(
  p_id uuid,
  p_code text,
  p_display_name text,
  p_status text DEFAULT 'active'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('lead.manage_sources') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('active', 'inactive') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF p_id IS NULL THEN
    INSERT INTO lead_lost_reason (organization_id, code, display_name, status, created_by, updated_by)
    VALUES (v_org_id, lower(btrim(p_code)), btrim(p_display_name), p_status, v_actor, v_actor)
    RETURNING id INTO v_id;
  ELSE
    UPDATE lead_lost_reason
    SET
      display_name = btrim(p_display_name),
      status = p_status,
      updated_by = v_actor
    WHERE id = p_id AND organization_id = v_org_id
    RETURNING id INTO v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_lead_source_catalog(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_lead_campaign_catalog(uuid, text, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_lead_lost_reason_catalog(uuid, text, text, text) TO authenticated;
