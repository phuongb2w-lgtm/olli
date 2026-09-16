-- M3-T02: Core CRM data foundation — lead, candidate, contact, reference catalogs.

-- =============================================================================
-- PERMISSIONS
-- =============================================================================

INSERT INTO permission (code) VALUES
  ('lead.read'),
  ('lead.create'),
  ('lead.update'),
  ('lead.assign'),
  ('lead.convert'),
  ('lead.manage_sources')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- NORMALIZATION HELPERS (deterministic identity keys for contact dedup/search)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.normalize_phone_digits(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g'), '');
$$;

CREATE OR REPLACE FUNCTION public.normalize_email_key(p_email text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_email IS NULL OR btrim(p_email) = '' THEN NULL
    ELSE lower(btrim(p_email))
  END;
$$;

COMMENT ON FUNCTION public.normalize_phone_digits(text) IS
  'Strip non-digits from phone for deterministic comparison. Mirrors application normalizePhoneDigits.';

COMMENT ON FUNCTION public.normalize_email_key(text) IS
  'Lowercase trimmed email for deterministic comparison. Mirrors application normalizedEmailKey.';

-- =============================================================================
-- REFERENCE CATALOGS
-- =============================================================================

CREATE TABLE lead_source (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  code            text NOT NULL,
  display_name    text NOT NULL,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CONSTRAINT lead_source_status_check CHECK (status IN ('active', 'inactive')),
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_source_organization ON lead_source (organization_id);
CREATE INDEX idx_lead_source_active ON lead_source (organization_id, status) WHERE status = 'active';

CREATE TRIGGER lead_source_updated_at
  BEFORE UPDATE ON lead_source
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_source IS
  'Organization-scoped lead acquisition source catalog. code is stable machine identity; display_name is org label.';

CREATE TABLE lead_lost_reason (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  code            text NOT NULL,
  display_name    text NOT NULL,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CONSTRAINT lead_lost_reason_status_check CHECK (status IN ('active', 'inactive')),
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_lost_reason_organization ON lead_lost_reason (organization_id);
CREATE INDEX idx_lead_lost_reason_active ON lead_lost_reason (organization_id, status) WHERE status = 'active';

CREATE TRIGGER lead_lost_reason_updated_at
  BEFORE UPDATE ON lead_lost_reason
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_lost_reason IS
  'Organization-scoped lost-prospect reason catalog. Historical lead references remain valid when inactive.';

CREATE TABLE lead_campaign (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  lead_source_id  uuid,
  expense_id      uuid,
  start_date      date,
  end_date        date,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CONSTRAINT lead_campaign_status_check CHECK (status IN ('active', 'inactive', 'archived')),
  CONSTRAINT lead_campaign_dates_check CHECK (
    end_date IS NULL OR start_date IS NULL OR end_date >= start_date
  ),
  FOREIGN KEY (organization_id, lead_source_id) REFERENCES lead_source (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, expense_id) REFERENCES expense (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_campaign_organization ON lead_campaign (organization_id);
CREATE INDEX idx_lead_campaign_source ON lead_campaign (organization_id, lead_source_id);
CREATE INDEX idx_lead_campaign_active ON lead_campaign (organization_id, status) WHERE status = 'active';

CREATE TRIGGER lead_campaign_updated_at
  BEFORE UPDATE ON lead_campaign
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_campaign IS
  'CRM attribution campaign. Optional expense_id bridges to M2 marketing spend without duplicating accounting facts.';

COMMENT ON COLUMN lead_campaign.expense_id IS
  'Optional nullable link to M2 expense (Cost C). Does not alter expense or revenue behavior.';

-- =============================================================================
-- LEAD (canonical pre-enrollment inquiry)
-- =============================================================================

CREATE TABLE lead (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  status               text NOT NULL DEFAULT 'new',
  assigned_user_id     uuid,
  lead_source_id       uuid,
  lead_campaign_id     uuid,
  referral_guardian_id uuid,
  referral_student_id  uuid,
  notes_summary        text,
  lost_reason_id       uuid,
  lost_notes           text,
  lost_at              timestamptz,
  lost_by              uuid,
  converted_at         timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  created_by           uuid,
  updated_by           uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT lead_status_check CHECK (status IN (
    'new',
    'contacted',
    'qualified',
    'trial_scheduled',
    'trial_completed',
    'converted',
    'lost',
    'reactivated'
  )),
  CONSTRAINT lead_lost_reason_required CHECK (
    status <> 'lost' OR lost_reason_id IS NOT NULL
  ),
  CONSTRAINT lead_converted_at_consistency CHECK (
    status <> 'converted' OR converted_at IS NOT NULL
  ),
  FOREIGN KEY (organization_id, assigned_user_id) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_source_id) REFERENCES lead_source (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_campaign_id) REFERENCES lead_campaign (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lost_reason_id) REFERENCES lead_lost_reason (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, referral_guardian_id) REFERENCES guardian (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, referral_student_id) REFERENCES student (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lost_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_organization ON lead (organization_id);
CREATE INDEX idx_lead_status ON lead (organization_id, status);
CREATE INDEX idx_lead_assigned_user ON lead (organization_id, assigned_user_id) WHERE assigned_user_id IS NOT NULL;
CREATE INDEX idx_lead_source ON lead (organization_id, lead_source_id);
CREATE INDEX idx_lead_campaign ON lead (organization_id, lead_campaign_id);

CREATE TRIGGER lead_updated_at
  BEFORE UPDATE ON lead
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead IS
  'Canonical CRM inquiry record. Lead is not Student — pre-enrollment lifecycle owned by M3 until conversion.';

COMMENT ON COLUMN lead.converted_at IS
  'Set when status becomes converted. Conversion RPC implemented in M3-T07.';

-- =============================================================================
-- LEAD CANDIDATE (prospective learner)
-- =============================================================================

CREATE TABLE lead_candidate (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL,
  lead_id              uuid NOT NULL,
  given_name           text NOT NULL,
  family_name          text NOT NULL,
  date_of_birth        date,
  target_course_id     uuid,
  target_class_id      uuid,
  is_primary_candidate boolean NOT NULL DEFAULT false,
  status               text NOT NULL DEFAULT 'active',
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  created_by           uuid,
  updated_by           uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT lead_candidate_status_check CHECK (status IN ('active', 'converted', 'removed')),
  CONSTRAINT lead_candidate_dob_check CHECK (date_of_birth IS NULL OR date_of_birth <= CURRENT_DATE),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, target_course_id) REFERENCES course (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, target_class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_candidate_lead ON lead_candidate (organization_id, lead_id);
CREATE INDEX idx_lead_candidate_active ON lead_candidate (organization_id, lead_id, status) WHERE status = 'active';

CREATE UNIQUE INDEX idx_lead_candidate_primary_unique
  ON lead_candidate (organization_id, lead_id)
  WHERE status = 'active' AND is_primary_candidate = true;

CREATE TRIGGER lead_candidate_updated_at
  BEFORE UPDATE ON lead_candidate
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE lead_candidate IS
  'Prospective learner attached to a lead. Multiple candidates per lead supported (siblings). No Student FK until conversion (M3-T07).';

-- =============================================================================
-- LEAD CONTACT (future guardian / contact person)
-- =============================================================================

CREATE TABLE lead_contact (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    uuid NOT NULL,
  lead_id            uuid NOT NULL,
  given_name         text NOT NULL,
  family_name        text NOT NULL,
  phone              text,
  email              text,
  phone_normalized   text,
  email_normalized   text,
  relationship_type  text NOT NULL DEFAULT 'guardian',
  is_primary_contact boolean NOT NULL DEFAULT false,
  is_billing_contact boolean NOT NULL DEFAULT false,
  status             text NOT NULL DEFAULT 'active',
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid,
  updated_by         uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT lead_contact_status_check CHECK (status IN ('active', 'ended')),
  CONSTRAINT lead_contact_relationship_check CHECK (
    relationship_type IN ('mother', 'father', 'guardian', 'other')
  ),
  FOREIGN KEY (organization_id, lead_id) REFERENCES lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_lead_contact_lead ON lead_contact (organization_id, lead_id);
CREATE INDEX idx_lead_contact_phone ON lead_contact (organization_id, phone_normalized)
  WHERE phone_normalized IS NOT NULL AND status = 'active';
CREATE INDEX idx_lead_contact_email ON lead_contact (organization_id, email_normalized)
  WHERE email_normalized IS NOT NULL AND status = 'active';

CREATE UNIQUE INDEX idx_lead_contact_primary_unique
  ON lead_contact (organization_id, lead_id)
  WHERE status = 'active' AND is_primary_contact = true;

CREATE TRIGGER lead_contact_updated_at
  BEFORE UPDATE ON lead_contact
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE FUNCTION public.trg_lead_contact_normalize_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.phone_normalized := public.normalize_phone_digits(NEW.phone);
  NEW.email_normalized := public.normalize_email_key(NEW.email);
  RETURN NEW;
END;
$$;

CREATE TRIGGER lead_contact_normalize_identity
  BEFORE INSERT OR UPDATE OF phone, email ON lead_contact
  FOR EACH ROW EXECUTE FUNCTION public.trg_lead_contact_normalize_identity();

COMMENT ON TABLE lead_contact IS
  'Contact persons on a lead. Maps to future Guardian at conversion. No global phone/email uniqueness — shared family contacts allowed.';

-- =============================================================================
-- ORGANIZATION BOOTSTRAP: default CRM reference catalogs
-- =============================================================================

CREATE OR REPLACE FUNCTION public.seed_organization_lead_reference_data(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO lead_source (organization_id, code, display_name)
  SELECT p_organization_id, v.code, v.display_name
  FROM (VALUES
    ('walk_in', 'Walk-in'),
    ('facebook', 'Facebook'),
    ('website', 'Website'),
    ('referral', 'Referral'),
    ('phone', 'Phone inquiry'),
    ('event', 'Event'),
    ('other', 'Other')
  ) AS v(code, display_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM lead_source ls
    WHERE ls.organization_id = p_organization_id AND ls.code = v.code
  );

  INSERT INTO lead_lost_reason (organization_id, code, display_name)
  SELECT p_organization_id, v.code, v.display_name
  FROM (VALUES
    ('price_too_high', 'Price too high'),
    ('schedule_conflict', 'Schedule conflict'),
    ('chose_competitor', 'Chose competitor'),
    ('no_response', 'No response'),
    ('not_ready', 'Not ready yet'),
    ('location', 'Location / distance'),
    ('other', 'Other')
  ) AS v(code, display_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM lead_lost_reason lr
    WHERE lr.organization_id = p_organization_id AND lr.code = v.code
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.initialize_organization_crm_reference_data()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM public.seed_organization_lead_reference_data(NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER organization_initialize_crm_reference
  AFTER INSERT ON organization
  FOR EACH ROW EXECUTE FUNCTION public.initialize_organization_crm_reference_data();

COMMENT ON FUNCTION public.seed_organization_lead_reference_data(uuid) IS
  'Idempotent baseline lead_source and lead_lost_reason rows for one organization.';

-- Backfill existing organizations.
DO $$
DECLARE
  org_record record;
BEGIN
  FOR org_record IN SELECT id FROM organization LOOP
    PERFORM public.seed_organization_lead_reference_data(org_record.id);
  END LOOP;
END;
$$;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE lead_source ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_source FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_lost_reason ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_lost_reason FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_campaign FORCE ROW LEVEL SECURITY;
ALTER TABLE lead ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_candidate FORCE ROW LEVEL SECURITY;
ALTER TABLE lead_contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_contact FORCE ROW LEVEL SECURITY;

CREATE POLICY lead_source_select ON lead_source FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_source_insert ON lead_source FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.manage_sources'));

CREATE POLICY lead_source_update ON lead_source FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.manage_sources'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY lead_lost_reason_select ON lead_lost_reason FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_lost_reason_insert ON lead_lost_reason FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.manage_sources'));

CREATE POLICY lead_lost_reason_update ON lead_lost_reason FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.manage_sources'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY lead_campaign_select ON lead_campaign FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_campaign_insert ON lead_campaign FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.manage_sources'));

CREATE POLICY lead_campaign_update ON lead_campaign FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.manage_sources'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY lead_select ON lead FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_insert ON lead FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.create'));

CREATE POLICY lead_update ON lead FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY lead_candidate_select ON lead_candidate FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_candidate_insert ON lead_candidate FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.create')
    AND EXISTS (
      SELECT 1 FROM lead l
      WHERE l.id = lead_candidate.lead_id
        AND l.organization_id = public.current_organization_id()
    )
  );

CREATE POLICY lead_candidate_update ON lead_candidate FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY lead_contact_select ON lead_contact FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.read'));

CREATE POLICY lead_contact_insert ON lead_contact FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('lead.create')
    AND EXISTS (
      SELECT 1 FROM lead l
      WHERE l.id = lead_contact.lead_id
        AND l.organization_id = public.current_organization_id()
    )
  );

CREATE POLICY lead_contact_update ON lead_contact FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('lead.update'))
  WITH CHECK (organization_id = public.current_organization_id());

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON
  lead_source,
  lead_lost_reason,
  lead_campaign,
  lead,
  lead_candidate,
  lead_contact
TO authenticated;

GRANT EXECUTE ON FUNCTION public.normalize_phone_digits(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_email_key(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.seed_organization_lead_reference_data(uuid) TO authenticated;
