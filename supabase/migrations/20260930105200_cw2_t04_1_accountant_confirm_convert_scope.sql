-- CW2-T04.1: confirm-scoped convert_lead requires submitted pending CW2 declaration (no broad lead.convert for Accountant).

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

  IF NOT (
    public.has_permission('lead.convert')
    OR (
      NULLIF(current_setting('cw2.declaration_confirm', true), '') IS NOT NULL
      AND public.has_permission('payment.record')
      AND public.has_permission('consultant_revenue.review')
      AND EXISTS (
        SELECT 1 FROM public.consultant_revenue_declaration d
        WHERE d.id = NULLIF(current_setting('cw2.declaration_confirm', true), '')::uuid
          AND d.organization_id = public.current_organization_id()
          AND d.lead_id = p_lead_id
          AND d.workflow_kind = 'cw2_payment'
          AND d.status = 'pending'
          AND d.submitted_at IS NOT NULL
      )
    )
  ) THEN
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
  'M3 lead conversion. General callers need lead.convert. CW2 Accounting confirmation may invoke during confirm_consultant_payment_declaration via session cw2.declaration_confirm when the caller has payment.record + consultant_revenue.review and the declaration is a submitted pending cw2_payment for the same lead (T04.1).';

