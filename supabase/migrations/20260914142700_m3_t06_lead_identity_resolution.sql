-- M3-T06: Lead identity resolution and deduplication (pre-conversion, no M1 mutations).

-- =============================================================================
-- RESOLUTION STATE (separate from CRM source data)
-- Unresolved = absence of a row.
-- =============================================================================

CREATE TABLE lead_candidate_identity_resolution (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id             uuid NOT NULL,
  lead_candidate_id           uuid NOT NULL,
  resolution_mode             text NOT NULL,
  student_id                  uuid,
  is_stale                    boolean NOT NULL DEFAULT false,
  strong_match_acknowledged   boolean NOT NULL DEFAULT false,
  identity_snapshot           jsonb NOT NULL DEFAULT '{}'::jsonb,
  resolved_by                 uuid NOT NULL,
  resolved_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, lead_candidate_id),
  CONSTRAINT lead_candidate_identity_mode_check CHECK (
    resolution_mode IN ('use_existing', 'create_new')
  ),
  CONSTRAINT lead_candidate_identity_use_existing_check CHECK (
    (resolution_mode = 'use_existing' AND student_id IS NOT NULL)
    OR (resolution_mode = 'create_new' AND student_id IS NULL)
  ),
  FOREIGN KEY (organization_id, lead_candidate_id)
    REFERENCES lead_candidate (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, student_id)
    REFERENCES student (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, resolved_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_candidate_identity_candidate
  ON lead_candidate_identity_resolution (organization_id, lead_candidate_id);

CREATE TRIGGER lead_candidate_identity_resolution_updated_at
  BEFORE UPDATE ON lead_candidate_identity_resolution
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_candidate_identity_resolution IS
  'Operator identity decision for a lead candidate before conversion. Does not create Student rows.';

CREATE TABLE lead_contact_identity_resolution (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id             uuid NOT NULL,
  lead_contact_id             uuid NOT NULL,
  resolution_mode             text NOT NULL,
  guardian_id                 uuid,
  is_stale                    boolean NOT NULL DEFAULT false,
  strong_match_acknowledged   boolean NOT NULL DEFAULT false,
  identity_snapshot           jsonb NOT NULL DEFAULT '{}'::jsonb,
  resolved_by                 uuid NOT NULL,
  resolved_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, lead_contact_id),
  CONSTRAINT lead_contact_identity_mode_check CHECK (
    resolution_mode IN ('use_existing', 'create_new')
  ),
  CONSTRAINT lead_contact_identity_use_existing_check CHECK (
    (resolution_mode = 'use_existing' AND guardian_id IS NOT NULL)
    OR (resolution_mode = 'create_new' AND guardian_id IS NULL)
  ),
  FOREIGN KEY (organization_id, lead_contact_id)
    REFERENCES lead_contact (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, guardian_id)
    REFERENCES guardian (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, resolved_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_contact_identity_contact
  ON lead_contact_identity_resolution (organization_id, lead_contact_id);

CREATE TRIGGER lead_contact_identity_resolution_updated_at
  BEFORE UPDATE ON lead_contact_identity_resolution
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_contact_identity_resolution IS
  'Operator identity decision for a lead contact before conversion. Does not create Guardian rows.';

-- =============================================================================
-- RESOLUTION HISTORY (append-only)
-- =============================================================================

CREATE TABLE lead_identity_resolution_event (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id           uuid NOT NULL,
  subject_type              text NOT NULL,
  subject_id                uuid NOT NULL,
  previous_resolution_mode  text,
  new_resolution_mode       text,
  previous_target_id        uuid,
  new_target_id             uuid,
  changed_by                uuid NOT NULL,
  changed_at                timestamptz NOT NULL DEFAULT now(),
  note                      text,
  UNIQUE (organization_id, id),
  CONSTRAINT lead_identity_resolution_event_subject_check CHECK (
    subject_type IN ('candidate', 'contact')
  ),
  CONSTRAINT lead_identity_resolution_event_mode_check CHECK (
    (previous_resolution_mode IS NULL OR previous_resolution_mode IN ('use_existing', 'create_new'))
    AND (new_resolution_mode IS NULL OR new_resolution_mode IN ('use_existing', 'create_new'))
  ),
  FOREIGN KEY (organization_id, changed_by)
    REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_identity_resolution_event_subject
  ON lead_identity_resolution_event (organization_id, subject_type, subject_id, changed_at DESC);

COMMENT ON TABLE lead_identity_resolution_event IS
  'Append-only identity resolution audit for candidates and contacts. Canonical timeline evidence.';

-- =============================================================================
-- ELIGIBILITY HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_eligible_identity_student(p_student_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.student s
    WHERE s.id = p_student_id
      AND s.organization_id = public.current_organization_id()
      AND s.status IN ('prospect', 'active')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_eligible_identity_guardian(p_guardian_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.guardian g
    WHERE g.id = p_guardian_id
      AND g.organization_id = public.current_organization_id()
      AND g.status = 'active'
  );
$$;

COMMENT ON FUNCTION public.is_eligible_identity_student(uuid) IS
  'Conversion reuse eligibility: same-org student with status prospect or active.';

COMMENT ON FUNCTION public.is_eligible_identity_guardian(uuid) IS
  'Conversion reuse eligibility: same-org guardian with status active.';

-- =============================================================================
-- SNAPSHOT HELPERS (stale detection)
-- Material fields: candidate given/family/DOB; contact given/family/phone/email.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.build_lead_candidate_identity_snapshot(
  p_given_name text,
  p_family_name text,
  p_date_of_birth date
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'given_name', p_given_name,
    'family_name', p_family_name,
    'date_of_birth', p_date_of_birth
  );
$$;

CREATE OR REPLACE FUNCTION public.build_lead_contact_identity_snapshot(
  p_given_name text,
  p_family_name text,
  p_phone text,
  p_email text
)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'given_name', p_given_name,
    'family_name', p_family_name,
    'phone_normalized', public.normalize_phone_digits(p_phone),
    'email_normalized', public.normalize_email_key(p_email)
  );
$$;

-- =============================================================================
-- STALE RESOLUTION TRIGGERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trg_lead_candidate_mark_identity_stale()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.given_name IS DISTINCT FROM OLD.given_name
     OR NEW.family_name IS DISTINCT FROM OLD.family_name
     OR NEW.date_of_birth IS DISTINCT FROM OLD.date_of_birth
  THEN
    UPDATE lead_candidate_identity_resolution
    SET is_stale = true, updated_at = now()
    WHERE organization_id = NEW.organization_id
      AND lead_candidate_id = NEW.id
      AND is_stale = false;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_candidate_mark_identity_stale
  AFTER UPDATE OF given_name, family_name, date_of_birth ON lead_candidate
  FOR EACH ROW EXECUTE FUNCTION public.trg_lead_candidate_mark_identity_stale();

CREATE OR REPLACE FUNCTION public.trg_lead_contact_mark_identity_stale()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.given_name IS DISTINCT FROM OLD.given_name
     OR NEW.family_name IS DISTINCT FROM OLD.family_name
     OR NEW.phone IS DISTINCT FROM OLD.phone
     OR NEW.email IS DISTINCT FROM OLD.email
  THEN
    UPDATE lead_contact_identity_resolution
    SET is_stale = true, updated_at = now()
    WHERE organization_id = NEW.organization_id
      AND lead_contact_id = NEW.id
      AND is_stale = false;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_contact_mark_identity_stale
  AFTER UPDATE OF given_name, family_name, phone, email ON lead_contact
  FOR EACH ROW EXECUTE FUNCTION public.trg_lead_contact_mark_identity_stale();

-- =============================================================================
-- DIRECT MUTATION PROTECTION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_lead_candidate_identity_resolution()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_identity_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.is_stale IS DISTINCT FROM OLD.is_stale
     AND NEW.resolution_mode IS NOT DISTINCT FROM OLD.resolution_mode
     AND NEW.student_id IS NOT DISTINCT FROM OLD.student_id
     AND NEW.strong_match_acknowledged IS NOT DISTINCT FROM OLD.strong_match_acknowledged
     AND NEW.identity_snapshot IS NOT DISTINCT FROM OLD.identity_snapshot
     AND NEW.resolved_by IS NOT DISTINCT FROM OLD.resolved_by
     AND NEW.resolved_at IS NOT DISTINCT FROM OLD.resolved_at
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Lead candidate identity resolution must be changed through resolve_lead_candidate_identity()'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER lead_candidate_identity_resolution_protect
  BEFORE INSERT OR UPDATE OR DELETE ON lead_candidate_identity_resolution
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_candidate_identity_resolution();

CREATE OR REPLACE FUNCTION public.protect_lead_contact_identity_resolution()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_identity_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.is_stale IS DISTINCT FROM OLD.is_stale
     AND NEW.resolution_mode IS NOT DISTINCT FROM OLD.resolution_mode
     AND NEW.guardian_id IS NOT DISTINCT FROM OLD.guardian_id
     AND NEW.strong_match_acknowledged IS NOT DISTINCT FROM OLD.strong_match_acknowledged
     AND NEW.identity_snapshot IS NOT DISTINCT FROM OLD.identity_snapshot
     AND NEW.resolved_by IS NOT DISTINCT FROM OLD.resolved_by
     AND NEW.resolved_at IS NOT DISTINCT FROM OLD.resolved_at
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'Lead contact identity resolution must be changed through resolve_lead_contact_identity()'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER lead_contact_identity_resolution_protect
  BEFORE INSERT OR UPDATE OR DELETE ON lead_contact_identity_resolution
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_contact_identity_resolution();

CREATE OR REPLACE FUNCTION public.protect_lead_identity_resolution_event_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('olli.lead_identity_mutation', true) = 'true' THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Lead identity resolution history is immutable'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER lead_identity_resolution_event_protect_immutable
  BEFORE UPDATE OR DELETE ON lead_identity_resolution_event
  FOR EACH ROW EXECUTE FUNCTION public.protect_lead_identity_resolution_event_immutable();

-- =============================================================================
-- INTERNAL: append history
-- =============================================================================

CREATE OR REPLACE FUNCTION public.append_lead_identity_resolution_event(
  p_subject_type text,
  p_subject_id uuid,
  p_previous_resolution_mode text,
  p_new_resolution_mode text,
  p_previous_target_id uuid,
  p_new_target_id uuid,
  p_note text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid := public.current_organization_id();
  v_actor uuid := public.current_app_user_id();
  v_event_id uuid;
BEGIN
  INSERT INTO lead_identity_resolution_event (
    organization_id,
    subject_type,
    subject_id,
    previous_resolution_mode,
    new_resolution_mode,
    previous_target_id,
    new_target_id,
    changed_by,
    note
  )
  VALUES (
    v_org_id,
    p_subject_type,
    p_subject_id,
    p_previous_resolution_mode,
    p_new_resolution_mode,
    p_previous_target_id,
    p_new_target_id,
    v_actor,
    NULLIF(btrim(p_note), '')
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

-- =============================================================================
-- MATCHING: candidate → student (SECURITY DEFINER, lead.read, minimal fields)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.find_student_matches_for_lead_candidate(
  p_lead_candidate_id uuid
)
RETURNS TABLE (
  student_id uuid,
  given_name text,
  family_name text,
  date_of_birth date,
  student_code text,
  status text,
  match_confidence text,
  match_reasons text[],
  sort_rank integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_candidate lead_candidate%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT * INTO v_candidate
  FROM lead_candidate
  WHERE id = p_lead_candidate_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  WITH direct_matches AS (
    SELECT
      s.id AS student_id,
      s.given_name,
      s.family_name,
      s.date_of_birth,
      s.student_code,
      s.status,
      CASE
        WHEN v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth IS NOT NULL
             AND s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 'strong'
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
          THEN 'possible'
        ELSE NULL
      END AS confidence,
      CASE
        WHEN v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth IS NOT NULL
             AND s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN ARRAY['same_name_and_dob']::text[]
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
          THEN ARRAY['same_name']::text[]
        ELSE ARRAY[]::text[]
      END AS match_reasons,
      CASE
        WHEN v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth IS NOT NULL
             AND s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 2
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
          THEN 1
        ELSE 0
      END AS sort_rank
    FROM student s
    WHERE s.organization_id = v_org_id
      AND (
        (s.given_name = v_candidate.given_name AND s.family_name = v_candidate.family_name)
      )
  ),
  guardian_link_matches AS (
    SELECT
      s.id AS student_id,
      s.given_name,
      s.family_name,
      s.date_of_birth,
      s.student_code,
      s.status,
      CASE
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 'strong'
        ELSE 'possible'
      END AS confidence,
      ARRAY['linked_via_guardian_contact']::text[] AS match_reasons,
      CASE
        WHEN s.given_name = v_candidate.given_name
             AND s.family_name = v_candidate.family_name
             AND v_candidate.date_of_birth IS NOT NULL
             AND s.date_of_birth = v_candidate.date_of_birth
          THEN 2
        ELSE 1
      END AS sort_rank
    FROM lead_contact lc
    JOIN guardian g
      ON g.organization_id = lc.organization_id
     AND (
       (lc.phone_normalized IS NOT NULL
         AND public.normalize_phone_digits(g.phone) = lc.phone_normalized
         AND length(lc.phone_normalized) >= 4)
       OR (lc.email_normalized IS NOT NULL
         AND public.normalize_email_key(g.email) = lc.email_normalized)
     )
    JOIN student_guardian sg
      ON sg.organization_id = g.organization_id
     AND sg.guardian_id = g.id
     AND sg.status = 'active'
    JOIN student s
      ON s.organization_id = sg.organization_id
     AND s.id = sg.student_id
    WHERE lc.organization_id = v_org_id
      AND lc.lead_id = v_candidate.lead_id
      AND lc.status = 'active'
      AND (
        s.given_name = v_candidate.given_name
        OR s.family_name = v_candidate.family_name
      )
  ),
  combined AS (
    SELECT * FROM direct_matches dm WHERE dm.confidence IS NOT NULL
    UNION ALL
    SELECT * FROM guardian_link_matches
  ),
  ranked AS (
    SELECT
      c.student_id,
      c.given_name,
      c.family_name,
      c.date_of_birth,
      c.student_code,
      c.status,
      c.confidence,
      c.match_reasons,
      c.sort_rank,
      ROW_NUMBER() OVER (
        PARTITION BY c.student_id
        ORDER BY c.sort_rank DESC,
          CASE c.confidence WHEN 'strong' THEN 2 ELSE 1 END DESC
      ) AS rn
    FROM combined c
  )
  SELECT
    r.student_id,
    r.given_name,
    r.family_name,
    r.date_of_birth,
    r.student_code,
    r.status,
    r.confidence AS match_confidence,
    r.match_reasons,
    r.sort_rank
  FROM ranked r
  WHERE r.rn = 1
  ORDER BY r.sort_rank DESC, r.family_name, r.given_name;
END;
$$;

COMMENT ON FUNCTION public.find_student_matches_for_lead_candidate(uuid) IS
  'Tenant-safe student match suggestions for a lead candidate. SECURITY DEFINER exposes only identity fields with lead.read. Name-only matches are possible, never deterministic.';

-- =============================================================================
-- MATCHING: contact → guardian
-- =============================================================================

CREATE OR REPLACE FUNCTION public.find_guardian_matches_for_lead_contact(
  p_lead_contact_id uuid
)
RETURNS TABLE (
  guardian_id uuid,
  given_name text,
  family_name text,
  phone text,
  email text,
  status text,
  match_confidence text,
  match_reasons text[],
  sort_rank integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_contact lead_contact%ROWTYPE;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT * INTO v_contact
  FROM lead_contact
  WHERE id = p_lead_contact_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
  WITH matches AS (
    SELECT
      g.id AS guardian_id,
      g.given_name,
      g.family_name,
      g.phone,
      g.email,
      g.status,
      CASE
        WHEN v_contact.phone_normalized IS NOT NULL
             AND length(v_contact.phone_normalized) >= 4
             AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized
          THEN 'strong'
        WHEN v_contact.email_normalized IS NOT NULL
             AND public.normalize_email_key(g.email) = v_contact.email_normalized
          THEN 'strong'
        WHEN g.given_name = v_contact.given_name
             AND g.family_name = v_contact.family_name
          THEN 'possible'
        ELSE NULL
      END AS confidence,
      CASE
        WHEN v_contact.phone_normalized IS NOT NULL
             AND length(v_contact.phone_normalized) >= 4
             AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized
          THEN ARRAY['same_phone']::text[]
        WHEN v_contact.email_normalized IS NOT NULL
             AND public.normalize_email_key(g.email) = v_contact.email_normalized
          THEN ARRAY['same_email']::text[]
        WHEN g.given_name = v_contact.given_name
             AND g.family_name = v_contact.family_name
          THEN ARRAY['same_name']::text[]
        ELSE ARRAY[]::text[]
      END AS match_reasons,
      CASE
        WHEN v_contact.phone_normalized IS NOT NULL
             AND length(v_contact.phone_normalized) >= 4
             AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized
          THEN 3
        WHEN v_contact.email_normalized IS NOT NULL
             AND public.normalize_email_key(g.email) = v_contact.email_normalized
          THEN 3
        WHEN g.given_name = v_contact.given_name
             AND g.family_name = v_contact.family_name
          THEN 1
        ELSE 0
      END AS sort_rank
    FROM guardian g
    WHERE g.organization_id = v_org_id
      AND (
        (v_contact.phone_normalized IS NOT NULL
          AND length(v_contact.phone_normalized) >= 4
          AND public.normalize_phone_digits(g.phone) = v_contact.phone_normalized)
        OR (v_contact.email_normalized IS NOT NULL
          AND public.normalize_email_key(g.email) = v_contact.email_normalized)
        OR (g.given_name = v_contact.given_name AND g.family_name = v_contact.family_name)
      )
  )
  SELECT
    m.guardian_id,
    m.given_name,
    m.family_name,
    m.phone,
    m.email,
    m.status,
    m.confidence AS match_confidence,
    m.match_reasons,
    m.sort_rank
  FROM matches m
  WHERE m.confidence IS NOT NULL
  ORDER BY m.sort_rank DESC, m.family_name, m.given_name;
END;
$$;

COMMENT ON FUNCTION public.find_guardian_matches_for_lead_contact(uuid) IS
  'Tenant-safe guardian match suggestions for a lead contact. Phone/email equality is strong evidence but never auto-merges.';

-- =============================================================================
-- RESOLVE RPCs
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
        'candidate',
        p_lead_candidate_id,
        v_existing.resolution_mode,
        NULL,
        v_existing.student_id,
        NULL,
        v_note
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
      SELECT 1
      FROM public.find_student_matches_for_lead_candidate(p_lead_candidate_id) m
      WHERE m.match_confidence = 'strong'
    ) INTO v_has_strong;

    IF v_has_strong AND NOT COALESCE(p_acknowledge_strong_match, false) THEN
      RAISE EXCEPTION 'strong_match_ack_required' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  v_snapshot := public.build_lead_candidate_identity_snapshot(
    v_candidate.given_name,
    v_candidate.family_name,
    v_candidate.date_of_birth
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
        'candidate',
        p_lead_candidate_id,
        v_existing.resolution_mode,
        p_resolution_mode,
        v_existing.student_id,
        p_student_id,
        v_note
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
        'candidate',
        p_lead_candidate_id,
        NULL,
        p_resolution_mode,
        NULL,
        p_student_id,
        v_note
      );

      INSERT INTO lead_candidate_identity_resolution (
        organization_id,
        lead_candidate_id,
        resolution_mode,
        student_id,
        is_stale,
        strong_match_acknowledged,
        identity_snapshot,
        resolved_by
      )
      VALUES (
        v_org_id,
        p_lead_candidate_id,
        p_resolution_mode,
        p_student_id,
        false,
        CASE
          WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false)
          ELSE false
        END,
        v_snapshot,
        v_actor
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
        'contact',
        p_lead_contact_id,
        v_existing.resolution_mode,
        NULL,
        v_existing.guardian_id,
        NULL,
        v_note
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
      SELECT 1
      FROM public.find_guardian_matches_for_lead_contact(p_lead_contact_id) m
      WHERE m.match_confidence = 'strong'
    ) INTO v_has_strong;

    IF v_has_strong AND NOT COALESCE(p_acknowledge_strong_match, false) THEN
      RAISE EXCEPTION 'strong_match_ack_required' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  v_snapshot := public.build_lead_contact_identity_snapshot(
    v_contact.given_name,
    v_contact.family_name,
    v_contact.phone,
    v_contact.email
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
        'contact',
        p_lead_contact_id,
        v_existing.resolution_mode,
        p_resolution_mode,
        v_existing.guardian_id,
        p_guardian_id,
        v_note
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
        'contact',
        p_lead_contact_id,
        NULL,
        p_resolution_mode,
        NULL,
        p_guardian_id,
        v_note
      );

      INSERT INTO lead_contact_identity_resolution (
        organization_id,
        lead_contact_id,
        resolution_mode,
        guardian_id,
        is_stale,
        strong_match_acknowledged,
        identity_snapshot,
        resolved_by
      )
      VALUES (
        v_org_id,
        p_lead_contact_id,
        p_resolution_mode,
        p_guardian_id,
        false,
        CASE
          WHEN p_resolution_mode = 'create_new' THEN COALESCE(p_acknowledge_strong_match, false)
          ELSE false
        END,
        v_snapshot,
        v_actor
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
-- READINESS HELPER FOR T07
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_lead_identity_resolution_status(p_lead_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_unresolved_candidates integer := 0;
  v_unresolved_contacts integer := 0;
  v_stale_count integer := 0;
  v_ineligible_count integer := 0;
  v_ready boolean := true;
  v_candidates jsonb := '[]'::jsonb;
  v_contacts jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('lead.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  IF NOT EXISTS (
    SELECT 1 FROM lead l WHERE l.id = p_lead_id AND l.organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'lead_candidate_id', lc.id,
    'resolution_mode', r.resolution_mode,
    'student_id', r.student_id,
    'is_stale', COALESCE(r.is_stale, false),
    'target_eligible', CASE
      WHEN r.resolution_mode = 'use_existing' THEN public.is_eligible_identity_student(r.student_id)
      ELSE true
    END
  ) ORDER BY lc.is_primary_candidate DESC, lc.given_name), '[]'::jsonb)
  INTO v_candidates
  FROM lead_candidate lc
  LEFT JOIN lead_candidate_identity_resolution r
    ON r.lead_candidate_id = lc.id AND r.organization_id = lc.organization_id
  WHERE lc.lead_id = p_lead_id
    AND lc.organization_id = v_org_id
    AND lc.status = 'active';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'lead_contact_id', lc.id,
    'resolution_mode', r.resolution_mode,
    'guardian_id', r.guardian_id,
    'is_stale', COALESCE(r.is_stale, false),
    'target_eligible', CASE
      WHEN r.resolution_mode = 'use_existing' THEN public.is_eligible_identity_guardian(r.guardian_id)
      ELSE true
    END
  ) ORDER BY lc.is_primary_contact DESC, lc.given_name), '[]'::jsonb)
  INTO v_contacts
  FROM lead_contact lc
  LEFT JOIN lead_contact_identity_resolution r
    ON r.lead_contact_id = lc.id AND r.organization_id = lc.organization_id
  WHERE lc.lead_id = p_lead_id
    AND lc.organization_id = v_org_id
    AND lc.status = 'active';

  SELECT count(*) INTO v_unresolved_candidates
  FROM lead_candidate lc
  LEFT JOIN lead_candidate_identity_resolution r
    ON r.lead_candidate_id = lc.id AND r.organization_id = lc.organization_id
  WHERE lc.lead_id = p_lead_id
    AND lc.organization_id = v_org_id
    AND lc.status = 'active'
    AND r.id IS NULL;

  SELECT count(*) INTO v_unresolved_contacts
  FROM lead_contact lc
  LEFT JOIN lead_contact_identity_resolution r
    ON r.lead_contact_id = lc.id AND r.organization_id = lc.organization_id
  WHERE lc.lead_id = p_lead_id
    AND lc.organization_id = v_org_id
    AND lc.status = 'active'
    AND r.id IS NULL;

  SELECT count(*) INTO v_stale_count
  FROM (
    SELECT r.id
    FROM lead_candidate lc
    JOIN lead_candidate_identity_resolution r
      ON r.lead_candidate_id = lc.id AND r.organization_id = lc.organization_id
    WHERE lc.lead_id = p_lead_id AND lc.organization_id = v_org_id AND lc.status = 'active' AND r.is_stale
    UNION ALL
    SELECT r.id
    FROM lead_contact lc
    JOIN lead_contact_identity_resolution r
      ON r.lead_contact_id = lc.id AND r.organization_id = lc.organization_id
    WHERE lc.lead_id = p_lead_id AND lc.organization_id = v_org_id AND lc.status = 'active' AND r.is_stale
  ) stale_rows;

  SELECT count(*) INTO v_ineligible_count
  FROM (
    SELECT r.id
    FROM lead_candidate lc
    JOIN lead_candidate_identity_resolution r
      ON r.lead_candidate_id = lc.id AND r.organization_id = lc.organization_id
    WHERE lc.lead_id = p_lead_id
      AND lc.organization_id = v_org_id
      AND lc.status = 'active'
      AND r.resolution_mode = 'use_existing'
      AND NOT public.is_eligible_identity_student(r.student_id)
    UNION ALL
    SELECT r.id
    FROM lead_contact lc
    JOIN lead_contact_identity_resolution r
      ON r.lead_contact_id = lc.id AND r.organization_id = lc.organization_id
    WHERE lc.lead_id = p_lead_id
      AND lc.organization_id = v_org_id
      AND lc.status = 'active'
      AND r.resolution_mode = 'use_existing'
      AND NOT public.is_eligible_identity_guardian(r.guardian_id)
  ) ineligible_rows;

  v_ready := v_unresolved_candidates = 0
    AND v_unresolved_contacts = 0
    AND v_stale_count = 0
    AND v_ineligible_count = 0;

  RETURN jsonb_build_object(
    'lead_id', p_lead_id,
    'ready', v_ready,
    'unresolved_candidates', v_unresolved_candidates,
    'unresolved_contacts', v_unresolved_contacts,
    'stale_count', v_stale_count,
    'ineligible_target_count', v_ineligible_count,
    'candidates', v_candidates,
    'contacts', v_contacts
  );
END;
$$;

COMMENT ON FUNCTION public.get_lead_identity_resolution_status(uuid) IS
  'Deterministic pre-conversion identity readiness. Every active candidate/contact must be explicitly resolved, not stale, and use_existing targets must remain eligible.';

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE lead_candidate_identity_resolution ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_candidate_identity_resolution FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_contact_identity_resolution ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_contact_identity_resolution FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_identity_resolution_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_identity_resolution_event FORCE ROW LEVEL SECURITY;

CREATE POLICY lead_candidate_identity_resolution_select ON lead_candidate_identity_resolution
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_contact_identity_resolution_select ON lead_contact_identity_resolution
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_identity_resolution_event_select ON lead_identity_resolution_event
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.read')
  );

CREATE POLICY lead_candidate_identity_resolution_insert ON lead_candidate_identity_resolution
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND resolved_by = public.current_app_user_id()
  );

CREATE POLICY lead_candidate_identity_resolution_update ON lead_candidate_identity_resolution
  FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
  )
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND resolved_by = public.current_app_user_id()
  );

CREATE POLICY lead_candidate_identity_resolution_delete ON lead_candidate_identity_resolution
  FOR DELETE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
  );

CREATE POLICY lead_contact_identity_resolution_insert ON lead_contact_identity_resolution
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND resolved_by = public.current_app_user_id()
  );

CREATE POLICY lead_contact_identity_resolution_update ON lead_contact_identity_resolution
  FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
  )
  WITH CHECK (
    organization_id = public.current_organization_id()
    AND resolved_by = public.current_app_user_id()
  );

CREATE POLICY lead_contact_identity_resolution_delete ON lead_contact_identity_resolution
  FOR DELETE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
  );

CREATE POLICY lead_identity_resolution_event_insert ON lead_identity_resolution_event
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.update')
    AND changed_by = public.current_app_user_id()
  );

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON lead_candidate_identity_resolution TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON lead_contact_identity_resolution TO authenticated;
GRANT SELECT, INSERT ON lead_identity_resolution_event TO authenticated;

GRANT EXECUTE ON FUNCTION public.is_eligible_identity_student(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_eligible_identity_guardian(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_student_matches_for_lead_candidate(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.find_guardian_matches_for_lead_contact(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_lead_candidate_identity(uuid, text, uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_lead_contact_identity(uuid, text, uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_lead_identity_resolution_status(uuid) TO authenticated;
