-- M3-T07: Atomic lead conversion to M1 Student / Guardian / Enrollment.

-- =============================================================================
-- CONVERSION OUTPUT COLUMNS ON CRM SUBJECTS
-- =============================================================================

ALTER TABLE lead_candidate
  ADD COLUMN converted_student_id uuid,
  ADD CONSTRAINT lead_candidate_converted_student_fk
    FOREIGN KEY (organization_id, converted_student_id)
    REFERENCES student (organization_id, id) ON DELETE RESTRICT;

COMMENT ON COLUMN lead_candidate.converted_student_id IS
  'Canonical M1 student produced by lead conversion. Set once; immutable after conversion.';

ALTER TABLE lead_contact
  ADD COLUMN converted_guardian_id uuid,
  ADD CONSTRAINT lead_contact_converted_guardian_fk
    FOREIGN KEY (organization_id, converted_guardian_id)
    REFERENCES guardian (organization_id, id) ON DELETE RESTRICT;

COMMENT ON COLUMN lead_contact.converted_guardian_id IS
  'Canonical M1 guardian produced by lead conversion. Set once; immutable after conversion.';

-- =============================================================================
-- CONVERSION AUDIT TABLES (immutable)
-- =============================================================================

CREATE TABLE lead_conversion (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL,
  lead_id              uuid NOT NULL,
  converted_by         uuid NOT NULL,
  converted_at         timestamptz NOT NULL DEFAULT now(),
  lead_source_id       uuid,
  lead_campaign_id     uuid,
  assigned_user_id     uuid,
  referral_guardian_id uuid,
  referral_student_id  uuid,
  metadata             jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, lead_id),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, converted_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_source_id) REFERENCES lead_source (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_campaign_id) REFERENCES lead_campaign (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, assigned_user_id) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, referral_guardian_id) REFERENCES guardian (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, referral_student_id) REFERENCES student (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_conversion_lead ON lead_conversion (organization_id, lead_id);

COMMENT ON TABLE lead_conversion IS
  'Immutable successful CRM → M1 handoff record. One canonical conversion per lead.';

CREATE TABLE lead_conversion_candidate (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  lead_conversion_id  uuid NOT NULL,
  lead_candidate_id   uuid NOT NULL,
  student_id          uuid NOT NULL,
  resolution_mode     text NOT NULL,
  was_created         boolean NOT NULL,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, lead_conversion_id, lead_candidate_id),
  CONSTRAINT lead_conversion_candidate_mode_check CHECK (
    resolution_mode IN ('use_existing', 'create_new')
  ),
  FOREIGN KEY (organization_id, lead_conversion_id)
    REFERENCES lead_conversion (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_candidate_id)
    REFERENCES lead_candidate (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, student_id)
    REFERENCES student (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE lead_conversion_contact (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  lead_conversion_id  uuid NOT NULL,
  lead_contact_id     uuid NOT NULL,
  guardian_id         uuid NOT NULL,
  resolution_mode     text NOT NULL,
  was_created         boolean NOT NULL,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, lead_conversion_id, lead_contact_id),
  CONSTRAINT lead_conversion_contact_mode_check CHECK (
    resolution_mode IN ('use_existing', 'create_new')
  ),
  FOREIGN KEY (organization_id, lead_conversion_id)
    REFERENCES lead_conversion (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_contact_id)
    REFERENCES lead_contact (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, guardian_id)
    REFERENCES guardian (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE lead_conversion_student_guardian (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  lead_conversion_id  uuid NOT NULL,
  lead_candidate_id   uuid NOT NULL,
  lead_contact_id     uuid NOT NULL,
  student_id          uuid NOT NULL,
  guardian_id         uuid NOT NULL,
  student_guardian_id uuid NOT NULL,
  relationship_type   text NOT NULL,
  is_primary_contact  boolean NOT NULL DEFAULT false,
  is_billing_contact  boolean NOT NULL DEFAULT false,
  was_created         boolean NOT NULL,
  was_reused          boolean NOT NULL,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, lead_conversion_id, lead_candidate_id, lead_contact_id),
  CONSTRAINT lead_conversion_sg_relationship_check CHECK (
    relationship_type IN ('mother', 'father', 'guardian', 'other')
  ),
  FOREIGN KEY (organization_id, lead_conversion_id)
    REFERENCES lead_conversion (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_candidate_id)
    REFERENCES lead_candidate (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_contact_id)
    REFERENCES lead_contact (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, student_id)
    REFERENCES student (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, guardian_id)
    REFERENCES guardian (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, student_guardian_id)
    REFERENCES student_guardian (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE lead_conversion_enrollment (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  lead_conversion_id  uuid NOT NULL,
  lead_candidate_id   uuid NOT NULL,
  enrollment_id       uuid NOT NULL,
  class_id            uuid NOT NULL,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, lead_conversion_id, lead_candidate_id),
  FOREIGN KEY (organization_id, lead_conversion_id)
    REFERENCES lead_conversion (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_candidate_id)
    REFERENCES lead_candidate (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_id)
    REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id)
    REFERENCES class (organization_id, id) ON DELETE RESTRICT
);

-- =============================================================================
-- IMMUTABILITY PROTECTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_lead_conversion_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_conversion_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Lead conversion records are immutable'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER lead_conversion_protect_immutable
  BEFORE UPDATE OR DELETE ON lead_conversion
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_conversion_immutable();

CREATE TRIGGER lead_conversion_candidate_protect_immutable
  BEFORE UPDATE OR DELETE ON lead_conversion_candidate
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_conversion_immutable();

CREATE TRIGGER lead_conversion_contact_protect_immutable
  BEFORE UPDATE OR DELETE ON lead_conversion_contact
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_conversion_immutable();

CREATE TRIGGER lead_conversion_sg_protect_immutable
  BEFORE UPDATE OR DELETE ON lead_conversion_student_guardian
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_conversion_immutable();

CREATE TRIGGER lead_conversion_enrollment_protect_immutable
  BEFORE UPDATE OR DELETE ON lead_conversion_enrollment
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_conversion_immutable();

CREATE OR REPLACE FUNCTION public.protect_lead_conversion_subject_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_conversion_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.converted_student_id IS DISTINCT FROM OLD.converted_student_id
     OR NEW.status IS DISTINCT FROM OLD.status
  THEN
    RAISE EXCEPTION 'Lead candidate conversion fields are immutable after conversion'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_candidate_protect_conversion_fields
  BEFORE UPDATE ON lead_candidate
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_conversion_subject_fields();

CREATE OR REPLACE FUNCTION public.protect_lead_contact_conversion_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_conversion_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF NEW.converted_guardian_id IS DISTINCT FROM OLD.converted_guardian_id THEN
    RAISE EXCEPTION 'Lead contact conversion fields are immutable after conversion'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_contact_protect_conversion_fields
  BEFORE UPDATE ON lead_contact
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_contact_conversion_fields();

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public._conversion_build_result(p_conversion_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_conv lead_conversion%ROWTYPE;
BEGIN
  SELECT * INTO v_conv
  FROM lead_conversion
  WHERE id = p_conversion_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN jsonb_build_object(
    'lead_conversion_id', v_conv.id,
    'lead_id', v_conv.lead_id,
    'converted_at', v_conv.converted_at,
    'converted_by', v_conv.converted_by,
    'already_converted', true,
    'candidates', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'lead_candidate_id', cc.lead_candidate_id,
        'student_id', cc.student_id,
        'resolution_mode', cc.resolution_mode,
        'was_created', cc.was_created
      ) ORDER BY cc.lead_candidate_id)
      FROM lead_conversion_candidate cc
      WHERE cc.lead_conversion_id = v_conv.id AND cc.organization_id = v_org_id
    ), '[]'::jsonb),
    'contacts', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'lead_contact_id', ct.lead_contact_id,
        'guardian_id', ct.guardian_id,
        'resolution_mode', ct.resolution_mode,
        'was_created', ct.was_created
      ) ORDER BY ct.lead_contact_id)
      FROM lead_conversion_contact ct
      WHERE ct.lead_conversion_id = v_conv.id AND ct.organization_id = v_org_id
    ), '[]'::jsonb),
    'relationships', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'lead_candidate_id', sg.lead_candidate_id,
        'lead_contact_id', sg.lead_contact_id,
        'student_id', sg.student_id,
        'guardian_id', sg.guardian_id,
        'student_guardian_id', sg.student_guardian_id,
        'was_created', sg.was_created,
        'was_reused', sg.was_reused
      ) ORDER BY sg.lead_candidate_id, sg.lead_contact_id)
      FROM lead_conversion_student_guardian sg
      WHERE sg.lead_conversion_id = v_conv.id AND sg.organization_id = v_org_id
    ), '[]'::jsonb),
    'enrollments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'lead_candidate_id', en.lead_candidate_id,
        'enrollment_id', en.enrollment_id,
        'class_id', en.class_id
      ) ORDER BY en.lead_candidate_id)
      FROM lead_conversion_enrollment en
      WHERE en.lead_conversion_id = v_conv.id AND en.organization_id = v_org_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._conversion_ensure_student_guardian(
  p_student_id uuid,
  p_guardian_id uuid,
  p_relationship_type text,
  p_is_primary_contact boolean,
  p_is_billing_contact boolean,
  p_actor uuid
)
RETURNS TABLE (student_guardian_id uuid, was_created boolean, was_reused boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_existing student_guardian%ROWTYPE;
  v_sg_id uuid;
  v_created boolean := false;
  v_reused boolean := false;
BEGIN
  SELECT * INTO v_existing
  FROM student_guardian
  WHERE organization_id = v_org_id
    AND student_id = p_student_id
    AND guardian_id = p_guardian_id;

  IF FOUND THEN
    v_sg_id := v_existing.id;
    v_reused := true;
    IF v_existing.status = 'ended' THEN
      UPDATE student_guardian
      SET
        status = 'active',
        relationship_type = p_relationship_type,
        is_billing_contact = p_is_billing_contact OR v_existing.is_billing_contact,
        updated_by = p_actor
      WHERE id = v_existing.id AND organization_id = v_org_id;
    END IF;
  ELSE
    INSERT INTO student_guardian (
      organization_id,
      student_id,
      guardian_id,
      relationship_type,
      is_primary_contact,
      is_billing_contact,
      status,
      created_by,
      updated_by
    )
    VALUES (
      v_org_id,
      p_student_id,
      p_guardian_id,
      p_relationship_type,
      false,
      p_is_billing_contact,
      'active',
      p_actor,
      p_actor
    )
    RETURNING id INTO v_sg_id;
    v_created := true;
  END IF;

  IF p_is_primary_contact THEN
    UPDATE student_guardian
    SET is_primary_contact = false, updated_by = p_actor
    WHERE organization_id = v_org_id
      AND student_id = p_student_id
      AND status = 'active'
      AND id <> v_sg_id
      AND is_primary_contact = true;

    UPDATE student_guardian
    SET is_primary_contact = true, updated_by = p_actor
    WHERE id = v_sg_id AND organization_id = v_org_id;
  END IF;

  RETURN QUERY SELECT v_sg_id, v_created, v_reused;
END;
$$;

CREATE OR REPLACE FUNCTION public._conversion_validate_enrollment(
  p_class_id uuid,
  p_status text,
  p_start_date date,
  p_exclude_enrollment_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_class class%ROWTYPE;
  v_operational_count integer;
BEGIN
  SELECT * INTO v_class
  FROM class
  WHERE id = p_class_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_class' USING ERRCODE = 'P0002';
  END IF;

  IF v_class.status = 'closed' THEN
    RAISE EXCEPTION 'class_closed' USING ERRCODE = 'P0001';
  END IF;

  IF p_status NOT IN ('pending', 'active') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;

  IF v_class.status = 'planned' AND p_status <> 'pending' THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = 'P0001';
  END IF;

  IF p_start_date IS NULL THEN
    RAISE EXCEPTION 'invalid_date' USING ERRCODE = 'P0001';
  END IF;

  IF v_class.capacity IS NOT NULL AND v_class.capacity > 0 THEN
    SELECT count(*)::integer INTO v_operational_count
    FROM enrollment
    WHERE organization_id = v_org_id
      AND class_id = p_class_id
      AND status IN ('pending', 'active')
      AND (p_exclude_enrollment_id IS NULL OR id <> p_exclude_enrollment_id);

    IF v_operational_count >= v_class.capacity THEN
      RAISE EXCEPTION 'capacity_reached' USING ERRCODE = 'P0001';
    END IF;
  END IF;
END;
$$;

-- =============================================================================
-- CANONICAL CONVERSION RPC
-- V1: whole-lead conversion — all active candidates/contacts materialized atomically.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.convert_lead(
  p_lead_id uuid,
  p_relationships jsonb DEFAULT '[]'::jsonb,
  p_enrollments jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_lead lead%ROWTYPE;
  v_existing_conv lead_conversion%ROWTYPE;
  v_readiness jsonb;
  v_conversion_id uuid;
  v_candidate_count integer;
  v_contact_count integer;
  v_rel record;
  v_enr record;
  v_candidate lead_candidate%ROWTYPE;
  v_contact lead_contact%ROWTYPE;
  v_resolution lead_candidate_identity_resolution%ROWTYPE;
  v_contact_resolution lead_contact_identity_resolution%ROWTYPE;
  v_student_id uuid;
  v_guardian_id uuid;
  v_was_created boolean;
  v_has_strong boolean;
  v_student_map jsonb := '{}'::jsonb;
  v_guardian_map jsonb := '{}'::jsonb;
  v_effective_relationships jsonb;
  v_sg_result record;
  v_enrollment_id uuid;
  v_class_id uuid;
  v_enrollment_status text;
  v_start_date date;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.convert') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_lead
  FROM lead
  WHERE id = p_lead_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_lead.status = 'converted' THEN
    SELECT * INTO v_existing_conv
    FROM lead_conversion
    WHERE lead_id = p_lead_id AND organization_id = v_org_id;

    IF FOUND THEN
      RETURN public._conversion_build_result(v_existing_conv.id);
    END IF;

    RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
  END IF;

  IF v_lead.status = 'lost' THEN
    RAISE EXCEPTION 'lead_lost' USING ERRCODE = 'P0001';
  END IF;

  SELECT public.get_lead_identity_resolution_status(p_lead_id) INTO v_readiness;

  IF NOT COALESCE((v_readiness->>'ready')::boolean, false) THEN
    RAISE EXCEPTION 'identity_not_ready' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO v_candidate_count
  FROM lead_candidate
  WHERE lead_id = p_lead_id AND organization_id = v_org_id AND status = 'active';

  SELECT count(*) INTO v_contact_count
  FROM lead_contact
  WHERE lead_id = p_lead_id AND organization_id = v_org_id AND status = 'active';

  IF v_candidate_count = 0 OR v_contact_count = 0 THEN
    RAISE EXCEPTION 'identity_not_ready' USING ERRCODE = 'P0001';
  END IF;

  v_effective_relationships := COALESCE(p_relationships, '[]'::jsonb);
  IF jsonb_array_length(v_effective_relationships) = 0 THEN
    IF v_candidate_count = 1 AND v_contact_count = 1 THEN
      SELECT jsonb_build_array(jsonb_build_object(
        'lead_candidate_id', lc.id,
        'lead_contact_id', ct.id
      ))
      INTO v_effective_relationships
      FROM lead_candidate lc
      CROSS JOIN lead_contact ct
      WHERE lc.lead_id = p_lead_id AND lc.organization_id = v_org_id AND lc.status = 'active'
        AND ct.lead_id = p_lead_id AND ct.organization_id = v_org_id AND ct.status = 'active';
    ELSE
      RAISE EXCEPTION 'relationship_mapping_required' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  PERFORM set_config('olli.lead_conversion_mutation', 'true', true);
  PERFORM set_config('olli.lead_lifecycle_mutation', 'true', true);

  INSERT INTO lead_conversion (
    organization_id,
    lead_id,
    converted_by,
    lead_source_id,
    lead_campaign_id,
    assigned_user_id,
    referral_guardian_id,
    referral_student_id,
    metadata
  )
  VALUES (
    v_org_id,
    p_lead_id,
    v_actor,
    v_lead.lead_source_id,
    v_lead.lead_campaign_id,
    v_lead.assigned_user_id,
    v_lead.referral_guardian_id,
    v_lead.referral_student_id,
    jsonb_build_object('prior_status', v_lead.status)
  )
  RETURNING id INTO v_conversion_id;

  -- Materialize candidates
  FOR v_candidate IN
    SELECT * FROM lead_candidate
    WHERE lead_id = p_lead_id AND organization_id = v_org_id AND status = 'active'
    ORDER BY is_primary_candidate DESC, given_name
  LOOP
    SELECT * INTO v_resolution
    FROM lead_candidate_identity_resolution
    WHERE lead_candidate_id = v_candidate.id AND organization_id = v_org_id;

    IF NOT FOUND OR v_resolution.is_stale THEN
      RAISE EXCEPTION 'stale_candidate_resolution' USING ERRCODE = 'P0001';
    END IF;

    IF v_resolution.resolution_mode = 'use_existing' THEN
      IF NOT public.is_eligible_identity_student(v_resolution.student_id) THEN
        RAISE EXCEPTION 'ineligible_target' USING ERRCODE = 'P0001';
      END IF;
      v_student_id := v_resolution.student_id;
      v_was_created := false;

      UPDATE student
      SET
        status = CASE WHEN status = 'prospect' THEN 'active' ELSE status END,
        updated_by = v_actor
      WHERE id = v_student_id AND organization_id = v_org_id;
    ELSE
      SELECT EXISTS (
        SELECT 1
        FROM public.find_student_matches_for_lead_candidate(v_candidate.id) m
        WHERE m.match_confidence = 'strong'
      ) INTO v_has_strong;

      IF v_has_strong AND NOT COALESCE(v_resolution.strong_match_acknowledged, false) THEN
        RAISE EXCEPTION 'duplicate_risk_changed' USING ERRCODE = 'P0001';
      END IF;

      INSERT INTO student (
        organization_id, given_name, family_name, date_of_birth, status, created_by, updated_by
      )
      VALUES (
        v_org_id,
        v_candidate.given_name,
        v_candidate.family_name,
        v_candidate.date_of_birth,
        'active',
        v_actor,
        v_actor
      )
      RETURNING id INTO v_student_id;
      v_was_created := true;
    END IF;

    INSERT INTO lead_conversion_candidate (
      organization_id, lead_conversion_id, lead_candidate_id, student_id,
      resolution_mode, was_created
    )
    VALUES (
      v_org_id, v_conversion_id, v_candidate.id, v_student_id,
      v_resolution.resolution_mode, v_was_created
    );

    UPDATE lead_candidate
    SET status = 'converted', converted_student_id = v_student_id, updated_by = v_actor
    WHERE id = v_candidate.id AND organization_id = v_org_id;

    v_student_map := v_student_map || jsonb_build_object(v_candidate.id::text, v_student_id);
  END LOOP;

  -- Materialize contacts
  FOR v_contact IN
    SELECT * FROM lead_contact
    WHERE lead_id = p_lead_id AND organization_id = v_org_id AND status = 'active'
    ORDER BY is_primary_contact DESC, given_name
  LOOP
    SELECT * INTO v_contact_resolution
    FROM lead_contact_identity_resolution
    WHERE lead_contact_id = v_contact.id AND organization_id = v_org_id;

    IF NOT FOUND OR v_contact_resolution.is_stale THEN
      RAISE EXCEPTION 'stale_contact_resolution' USING ERRCODE = 'P0001';
    END IF;

    IF v_contact_resolution.resolution_mode = 'use_existing' THEN
      IF NOT public.is_eligible_identity_guardian(v_contact_resolution.guardian_id) THEN
        RAISE EXCEPTION 'ineligible_target' USING ERRCODE = 'P0001';
      END IF;
      v_guardian_id := v_contact_resolution.guardian_id;
      v_was_created := false;
    ELSE
      SELECT EXISTS (
        SELECT 1
        FROM public.find_guardian_matches_for_lead_contact(v_contact.id) m
        WHERE m.match_confidence = 'strong'
      ) INTO v_has_strong;

      IF v_has_strong AND NOT COALESCE(v_contact_resolution.strong_match_acknowledged, false) THEN
        RAISE EXCEPTION 'duplicate_risk_changed' USING ERRCODE = 'P0001';
      END IF;

      INSERT INTO guardian (
        organization_id, given_name, family_name, phone, email, status, created_by, updated_by
      )
      VALUES (
        v_org_id,
        v_contact.given_name,
        v_contact.family_name,
        v_contact.phone,
        v_contact.email,
        'active',
        v_actor,
        v_actor
      )
      RETURNING id INTO v_guardian_id;
      v_was_created := true;
    END IF;

    INSERT INTO lead_conversion_contact (
      organization_id, lead_conversion_id, lead_contact_id, guardian_id,
      resolution_mode, was_created
    )
    VALUES (
      v_org_id, v_conversion_id, v_contact.id, v_guardian_id,
      v_contact_resolution.resolution_mode, v_was_created
    );

    UPDATE lead_contact
    SET converted_guardian_id = v_guardian_id, updated_by = v_actor
    WHERE id = v_contact.id AND organization_id = v_org_id;

    v_guardian_map := v_guardian_map || jsonb_build_object(v_contact.id::text, v_guardian_id);
  END LOOP;

  -- StudentGuardian relationships (explicit mapping only)
  FOR v_rel IN
    SELECT *
    FROM jsonb_to_recordset(v_effective_relationships) AS x(
      lead_candidate_id uuid,
      lead_contact_id uuid
    )
  LOOP
    IF NOT v_student_map ? v_rel.lead_candidate_id::text
       OR NOT v_guardian_map ? v_rel.lead_contact_id::text THEN
      RAISE EXCEPTION 'invalid_relationship_mapping' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_contact
    FROM lead_contact
    WHERE id = v_rel.lead_contact_id AND organization_id = v_org_id;

    SELECT * INTO v_sg_result
    FROM public._conversion_ensure_student_guardian(
      (v_student_map->>v_rel.lead_candidate_id::text)::uuid,
      (v_guardian_map->>v_rel.lead_contact_id::text)::uuid,
      v_contact.relationship_type,
      v_contact.is_primary_contact,
      v_contact.is_billing_contact,
      v_actor
    );

    INSERT INTO lead_conversion_student_guardian (
      organization_id,
      lead_conversion_id,
      lead_candidate_id,
      lead_contact_id,
      student_id,
      guardian_id,
      student_guardian_id,
      relationship_type,
      is_primary_contact,
      is_billing_contact,
      was_created,
      was_reused
    )
    VALUES (
      v_org_id,
      v_conversion_id,
      v_rel.lead_candidate_id,
      v_rel.lead_contact_id,
      (v_student_map->>v_rel.lead_candidate_id::text)::uuid,
      (v_guardian_map->>v_rel.lead_contact_id::text)::uuid,
      v_sg_result.student_guardian_id,
      v_contact.relationship_type,
      v_contact.is_primary_contact,
      v_contact.is_billing_contact,
      v_sg_result.was_created,
      v_sg_result.was_reused
    );
  END LOOP;

  -- Optional enrollments
  FOR v_enr IN
    SELECT *
    FROM jsonb_to_recordset(COALESCE(p_enrollments, '[]'::jsonb)) AS x(
      lead_candidate_id uuid,
      class_id uuid,
      start_date date,
      status text
    )
  LOOP
    IF NOT v_student_map ? v_enr.lead_candidate_id::text THEN
      RAISE EXCEPTION 'invalid_enrollment_mapping' USING ERRCODE = 'P0001';
    END IF;

    v_class_id := v_enr.class_id;
    v_enrollment_status := COALESCE(v_enr.status, 'pending');
    v_start_date := COALESCE(v_enr.start_date, CURRENT_DATE);

    PERFORM public._conversion_validate_enrollment(v_class_id, v_enrollment_status, v_start_date);

    INSERT INTO enrollment (
      organization_id, student_id, class_id, start_date, status, created_by, updated_by
    )
    VALUES (
      v_org_id,
      (v_student_map->>v_enr.lead_candidate_id::text)::uuid,
      v_class_id,
      v_start_date,
      v_enrollment_status,
      v_actor,
      v_actor
    )
    RETURNING id INTO v_enrollment_id;

    INSERT INTO lead_conversion_enrollment (
      organization_id, lead_conversion_id, lead_candidate_id, enrollment_id, class_id
    )
    VALUES (
      v_org_id, v_conversion_id, v_enr.lead_candidate_id, v_enrollment_id, v_class_id
    );
  END LOOP;

  INSERT INTO lead_status_history (
    organization_id, lead_id, from_status, to_status, changed_by, notes
  )
  VALUES (
    v_org_id, p_lead_id, v_lead.status, 'converted', v_actor, 'Lead converted to academic records'
  );

  UPDATE lead
  SET status = 'converted', converted_at = now(), updated_by = v_actor
  WHERE id = p_lead_id AND organization_id = v_org_id;

  PERFORM set_config('olli.lead_conversion_mutation', 'false', true);
  PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);

  RETURN public._conversion_build_result(v_conversion_id) || jsonb_build_object('already_converted', false);

EXCEPTION
  WHEN exclusion_violation THEN
    PERFORM set_config('olli.lead_conversion_mutation', 'false', true);
    PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);
    RAISE EXCEPTION 'overlap_conflict' USING ERRCODE = '23P01';
  WHEN OTHERS THEN
    PERFORM set_config('olli.lead_conversion_mutation', 'false', true);
    PERFORM set_config('olli.lead_lifecycle_mutation', 'false', true);
    RAISE;
END;
$$;

COMMENT ON FUNCTION public.convert_lead(uuid, jsonb, jsonb) IS
  'Atomic CRM → M1 conversion. V1 whole-lead: all active candidates/contacts materialized. Idempotent on already-converted leads.';

-- =============================================================================
-- FREEZE IDENTITY RESOLUTION AFTER CONVERSION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.resolve_lead_candidate_identity(
  p_lead_candidate_id uuid,
  p_resolution_mode text DEFAULT NULL,
  p_student_id uuid DEFAULT NULL,
  p_acknowledge_strong_match boolean DEFAULT false,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_candidate lead_candidate%ROWTYPE;
  v_existing lead_candidate_identity_resolution%ROWTYPE;
  v_has_existing boolean := false;
  v_snapshot jsonb;
  v_has_strong boolean := false;
  v_note text := NULLIF(btrim(p_note), '');
  v_lead_status text;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_candidate
  FROM lead_candidate
  WHERE id = p_lead_candidate_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND OR v_candidate.status <> 'active' THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT l.status INTO v_lead_status
  FROM lead l
  WHERE l.id = v_candidate.lead_id AND l.organization_id = v_org_id;

  IF v_lead_status = 'converted' THEN
    RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_existing
  FROM lead_candidate_identity_resolution
  WHERE lead_candidate_id = p_lead_candidate_id AND organization_id = v_org_id
  FOR UPDATE;

  v_has_existing := FOUND;

  IF p_resolution_mode IS NULL THEN
    IF NOT v_has_existing THEN
      RETURN jsonb_build_object('lead_candidate_id', p_lead_candidate_id, 'resolution_mode', NULL);
    END IF;

    PERFORM set_config('olli.lead_identity_mutation', 'true', true);
    BEGIN
      PERFORM public.append_lead_identity_resolution_event(
        'candidate', p_lead_candidate_id,
        v_existing.resolution_mode, NULL,
        v_existing.student_id, NULL, v_note
      );
      DELETE FROM lead_candidate_identity_resolution
      WHERE id = v_existing.id AND organization_id = v_org_id;
      PERFORM set_config('olli.lead_identity_mutation', 'false', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('olli.lead_identity_mutation', 'false', true);
      RAISE;
    END;

    RETURN jsonb_build_object('lead_candidate_id', p_lead_candidate_id, 'resolution_mode', NULL);
  END IF;

  IF p_resolution_mode NOT IN ('use_existing', 'create_new') THEN
    RAISE EXCEPTION 'invalid_resolution' USING ERRCODE = 'P0001';
  END IF;

  IF p_resolution_mode = 'use_existing' THEN
    IF p_student_id IS NULL THEN
      RAISE EXCEPTION 'invalid_resolution' USING ERRCODE = 'P0001';
    END IF;
    IF NOT public.is_eligible_identity_student(p_student_id) THEN
      RAISE EXCEPTION 'ineligible_target' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    IF p_student_id IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_resolution' USING ERRCODE = 'P0001';
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.find_student_matches_for_lead_candidate(p_lead_candidate_id) m
      WHERE m.match_confidence = 'strong'
    ) INTO v_has_strong;

    IF v_has_strong AND NOT COALESCE(p_acknowledge_strong_match, false) THEN
      RAISE EXCEPTION 'strong_match_ack_required' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  v_snapshot := public.build_lead_candidate_identity_snapshot(
    v_candidate.given_name, v_candidate.family_name, v_candidate.date_of_birth
  );

  IF v_has_existing
     AND v_existing.resolution_mode = p_resolution_mode
     AND v_existing.student_id IS NOT DISTINCT FROM p_student_id
     AND v_existing.is_stale = false
  THEN
    RETURN jsonb_build_object(
      'lead_candidate_id', p_lead_candidate_id,
      'resolution_mode', v_existing.resolution_mode,
      'student_id', v_existing.student_id,
      'is_stale', v_existing.is_stale,
      'strong_match_acknowledged', v_existing.strong_match_acknowledged,
      'no_op', true
    );
  END IF;

  PERFORM set_config('olli.lead_identity_mutation', 'true', true);
  BEGIN
    IF v_has_existing THEN
      PERFORM public.append_lead_identity_resolution_event(
        'candidate', p_lead_candidate_id,
        v_existing.resolution_mode, p_resolution_mode,
        v_existing.student_id, p_student_id, v_note
      );
      UPDATE lead_candidate_identity_resolution
      SET
        resolution_mode = p_resolution_mode,
        student_id = p_student_id,
        is_stale = false,
        strong_match_acknowledged = CASE
          WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false)
          ELSE false
        END,
        identity_snapshot = v_snapshot,
        resolved_by = v_actor,
        resolved_at = now(),
        updated_at = now()
      WHERE id = v_existing.id AND organization_id = v_org_id;
    ELSE
      PERFORM public.append_lead_identity_resolution_event(
        'candidate', p_lead_candidate_id,
        NULL, p_resolution_mode, NULL, p_student_id, v_note
      );
      INSERT INTO lead_candidate_identity_resolution (
        organization_id, lead_candidate_id, resolution_mode, student_id,
        is_stale, strong_match_acknowledged, identity_snapshot, resolved_by
      )
      VALUES (
        v_org_id, p_lead_candidate_id, p_resolution_mode, p_student_id,
        false,
        CASE WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false) ELSE false END,
        v_snapshot, v_actor
      );
    END IF;
    PERFORM set_config('olli.lead_identity_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_identity_mutation', 'false', true);
    RAISE;
  END;

  RETURN jsonb_build_object(
    'lead_candidate_id', p_lead_candidate_id,
    'resolution_mode', p_resolution_mode,
    'student_id', p_student_id,
    'is_stale', false,
    'strong_match_acknowledged', CASE
      WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false)
      ELSE false
    END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_lead_contact_identity(
  p_lead_contact_id uuid,
  p_resolution_mode text DEFAULT NULL,
  p_guardian_id uuid DEFAULT NULL,
  p_acknowledge_strong_match boolean DEFAULT false,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_contact lead_contact%ROWTYPE;
  v_existing lead_contact_identity_resolution%ROWTYPE;
  v_has_existing boolean := false;
  v_snapshot jsonb;
  v_has_strong boolean := false;
  v_note text := NULLIF(btrim(p_note), '');
  v_lead_status text;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.update') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  SELECT * INTO v_contact
  FROM lead_contact
  WHERE id = p_lead_contact_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND OR v_contact.status <> 'active' THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT l.status INTO v_lead_status
  FROM lead l
  WHERE l.id = v_contact.lead_id AND l.organization_id = v_org_id;

  IF v_lead_status = 'converted' THEN
    RAISE EXCEPTION 'lead_converted' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_existing
  FROM lead_contact_identity_resolution
  WHERE lead_contact_id = p_lead_contact_id AND organization_id = v_org_id
  FOR UPDATE;

  v_has_existing := FOUND;

  IF p_resolution_mode IS NULL THEN
    IF NOT v_has_existing THEN
      RETURN jsonb_build_object('lead_contact_id', p_lead_contact_id, 'resolution_mode', NULL);
    END IF;

    PERFORM set_config('olli.lead_identity_mutation', 'true', true);
    BEGIN
      PERFORM public.append_lead_identity_resolution_event(
        'contact', p_lead_contact_id,
        v_existing.resolution_mode, NULL,
        v_existing.guardian_id, NULL, v_note
      );
      DELETE FROM lead_contact_identity_resolution
      WHERE id = v_existing.id AND organization_id = v_org_id;
      PERFORM set_config('olli.lead_identity_mutation', 'false', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('olli.lead_identity_mutation', 'false', true);
      RAISE;
    END;

    RETURN jsonb_build_object('lead_contact_id', p_lead_contact_id, 'resolution_mode', NULL);
  END IF;

  IF p_resolution_mode NOT IN ('use_existing', 'create_new') THEN
    RAISE EXCEPTION 'invalid_resolution' USING ERRCODE = 'P0001';
  END IF;

  IF p_resolution_mode = 'use_existing' THEN
    IF p_guardian_id IS NULL THEN
      RAISE EXCEPTION 'invalid_resolution' USING ERRCODE = 'P0001';
    END IF;
    IF NOT public.is_eligible_identity_guardian(p_guardian_id) THEN
      RAISE EXCEPTION 'ineligible_target' USING ERRCODE = 'P0001';
    END IF;
  ELSE
    IF p_guardian_id IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_resolution' USING ERRCODE = 'P0001';
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.find_guardian_matches_for_lead_contact(p_lead_contact_id) m
      WHERE m.match_confidence = 'strong'
    ) INTO v_has_strong;

    IF v_has_strong AND NOT COALESCE(p_acknowledge_strong_match, false) THEN
      RAISE EXCEPTION 'strong_match_ack_required' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  v_snapshot := public.build_lead_contact_identity_snapshot(
    v_contact.given_name, v_contact.family_name, v_contact.phone, v_contact.email
  );

  IF v_has_existing
     AND v_existing.resolution_mode = p_resolution_mode
     AND v_existing.guardian_id IS NOT DISTINCT FROM p_guardian_id
     AND v_existing.is_stale = false
  THEN
    RETURN jsonb_build_object(
      'lead_contact_id', p_lead_contact_id,
      'resolution_mode', v_existing.resolution_mode,
      'guardian_id', v_existing.guardian_id,
      'is_stale', v_existing.is_stale,
      'strong_match_acknowledged', v_existing.strong_match_acknowledged,
      'no_op', true
    );
  END IF;

  PERFORM set_config('olli.lead_identity_mutation', 'true', true);
  BEGIN
    IF v_has_existing THEN
      PERFORM public.append_lead_identity_resolution_event(
        'contact', p_lead_contact_id,
        v_existing.resolution_mode, p_resolution_mode,
        v_existing.guardian_id, p_guardian_id, v_note
      );
      UPDATE lead_contact_identity_resolution
      SET
        resolution_mode = p_resolution_mode,
        guardian_id = p_guardian_id,
        is_stale = false,
        strong_match_acknowledged = CASE
          WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false)
          ELSE false
        END,
        identity_snapshot = v_snapshot,
        resolved_by = v_actor,
        resolved_at = now(),
        updated_at = now()
      WHERE id = v_existing.id AND organization_id = v_org_id;
    ELSE
      PERFORM public.append_lead_identity_resolution_event(
        'contact', p_lead_contact_id,
        NULL, p_resolution_mode, NULL, p_guardian_id, v_note
      );
      INSERT INTO lead_contact_identity_resolution (
        organization_id, lead_contact_id, resolution_mode, guardian_id,
        is_stale, strong_match_acknowledged, identity_snapshot, resolved_by
      )
      VALUES (
        v_org_id, p_lead_contact_id, p_resolution_mode, p_guardian_id,
        false,
        CASE WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false) ELSE false END,
        v_snapshot, v_actor
      );
    END IF;
    PERFORM set_config('olli.lead_identity_mutation', 'false', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('olli.lead_identity_mutation', 'false', true);
    RAISE;
  END;

  RETURN jsonb_build_object(
    'lead_contact_id', p_lead_contact_id,
    'resolution_mode', p_resolution_mode,
    'guardian_id', p_guardian_id,
    'is_stale', false,
    'strong_match_acknowledged', CASE
      WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false)
      ELSE false
    END
  );
END;
$$;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE lead_conversion ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_candidate FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_contact FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_student_guardian ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_student_guardian FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_enrollment ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_conversion_enrollment FORCE ROW LEVEL SECURITY;

CREATE POLICY lead_conversion_select ON lead_conversion
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_conversion_candidate_select ON lead_conversion_candidate
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_conversion_contact_select ON lead_conversion_contact
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_conversion_sg_select ON lead_conversion_student_guardian
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_conversion_enrollment_select ON lead_conversion_enrollment
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON lead_conversion TO authenticated;
GRANT SELECT ON lead_conversion_candidate TO authenticated;
GRANT SELECT ON lead_conversion_contact TO authenticated;
GRANT SELECT ON lead_conversion_student_guardian TO authenticated;
GRANT SELECT ON lead_conversion_enrollment TO authenticated;

GRANT EXECUTE ON FUNCTION public.convert_lead(uuid, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public._conversion_build_result(uuid) TO authenticated;
