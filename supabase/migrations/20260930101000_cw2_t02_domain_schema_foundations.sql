-- CW2-T02b: Consultant Workspace V2 domain/schema foundations (no grid, allocator, or UI).

INSERT INTO public.permission (code) VALUES
  ('consultant_workspace.read'),
  ('consultant_workspace.update'),
  ('consultant_custom_field.manage')
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION public._cw2_apply_consultant_workspace_permissions(p_role_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.role_permission (role_id, permission_id)
  SELECT p_role_id, p.id
  FROM public.permission p
  WHERE p.code IN (
    'consultant_workspace.read',
    'consultant_workspace.update',
    'consultant_custom_field.manage'
  )
  ON CONFLICT DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public._cw2_apply_consultant_workspace_permissions(uuid) IS
  'CW2: attach workspace/custom-field permissions to org consultant role template.';

ALTER TABLE public.app_user
  ADD COLUMN IF NOT EXISTS consultant_operational_code char(2);

ALTER TABLE public.app_user
  ADD CONSTRAINT app_user_consultant_operational_code_format_check
  CHECK (
    consultant_operational_code IS NULL
    OR (
      consultant_operational_code ~ '^[0-9]{2}$'
      AND consultant_operational_code <> '00'
    )
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_app_user_org_consultant_operational_code_unique
  ON public.app_user (organization_id, consultant_operational_code)
  WHERE consultant_operational_code IS NOT NULL;

COMMENT ON COLUMN public.app_user.consultant_operational_code IS
  'CW2: immutable-at-allocation consultant attribution digit (01=primary owner). Assigned via trusted RPC only; not arbitrary user input.';

CREATE OR REPLACE FUNCTION public._cw2_validate_consultant_operational_code(p_code char(2))
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT p_code IS NOT NULL
    AND p_code ~ '^[0-9]{2}$'
    AND p_code <> '00';
$$;

CREATE OR REPLACE FUNCTION public.protect_app_user_consultant_operational_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.is_trusted_schema_mutation_role() THEN
    RETURN NEW;
  END IF;

  IF NEW.consultant_operational_code IS DISTINCT FROM OLD.consultant_operational_code THEN
    RAISE EXCEPTION 'consultant_operational_code_trusted_path_only';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS app_user_protect_consultant_operational_code ON public.app_user;
CREATE TRIGGER app_user_protect_consultant_operational_code
  BEFORE UPDATE OF consultant_operational_code ON public.app_user
  FOR EACH ROW EXECUTE FUNCTION public.protect_app_user_consultant_operational_code();

CREATE TABLE public.organization_student_sequence (
  organization_id           uuid PRIMARY KEY
    REFERENCES public.organization (id) ON DELETE RESTRICT,
  last_allocated_sequence integer NOT NULL DEFAULT 0,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organization_student_sequence_bounds_check
    CHECK (last_allocated_sequence >= 0 AND last_allocated_sequence <= 9999)
);

COMMENT ON TABLE public.organization_student_sequence IS
  'CW2: center-wide official student sequence state per organization. last_allocated_sequence is the highest NNNN already issued (0000 never stored). T03 allocates next = last + 1 inside a transaction with FOR UPDATE; fail closed when next > 9999.';

COMMENT ON COLUMN public.organization_student_sequence.last_allocated_sequence IS
  'Highest center-wide sequence number already assigned to an official student_code. Next official allocation uses last_allocated_sequence + 1.';

CREATE TRIGGER organization_student_sequence_updated_at
  BEFORE UPDATE ON public.organization_student_sequence
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.organization_student_sequence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_student_sequence FORCE ROW LEVEL SECURITY;

CREATE POLICY organization_student_sequence_select ON public.organization_student_sequence
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      public.has_permission('student.read')
      OR public.has_permission('consultant_workspace.read')
      OR public.has_permission('consultant_revenue.review')
      OR public.is_primary_owner()
    )
  );

CREATE TABLE public.consultant_portfolio_sequence (
  organization_id      uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  consultant_user_id   uuid NOT NULL,
  last_workspace_sequence bigint NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, consultant_user_id),
  FOREIGN KEY (organization_id, consultant_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT,
  CONSTRAINT consultant_portfolio_sequence_nonneg CHECK (last_workspace_sequence >= 0)
);

COMMENT ON TABLE public.consultant_portfolio_sequence IS
  'CW2: monotonic STT counter per (organization, consultant). T04+ assigns workspace_sequence without renumbering on sort/filter.';

CREATE TABLE public.consultant_portfolio_entry (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  consultant_user_id   uuid NOT NULL,
  workspace_sequence   bigint NOT NULL,
  portfolio_entered_at timestamptz NOT NULL DEFAULT now(),
  lead_id              uuid,
  student_id           uuid,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT consultant_portfolio_entry_subject_check
    CHECK (lead_id IS NOT NULL OR student_id IS NOT NULL),
  FOREIGN KEY (organization_id, consultant_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, lead_id)
    REFERENCES public.lead (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, student_id)
    REFERENCES public.student (organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, consultant_user_id, workspace_sequence)
);

CREATE UNIQUE INDEX idx_consultant_portfolio_entry_lead
  ON public.consultant_portfolio_entry (organization_id, consultant_user_id, lead_id)
  WHERE lead_id IS NOT NULL;

CREATE UNIQUE INDEX idx_consultant_portfolio_entry_student
  ON public.consultant_portfolio_entry (organization_id, consultant_user_id, student_id)
  WHERE student_id IS NOT NULL;

CREATE INDEX idx_consultant_portfolio_entry_consultant
  ON public.consultant_portfolio_entry (organization_id, consultant_user_id, workspace_sequence DESC);

COMMENT ON TABLE public.consultant_portfolio_entry IS
  'CW2: one portfolio row per consultant-owned lead/student identity. On lead→student conversion, update lead_id/student_id on the same row to preserve STT (T08+).';

ALTER TABLE public.consultant_portfolio_sequence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_portfolio_sequence FORCE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_portfolio_entry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_portfolio_entry FORCE ROW LEVEL SECURITY;

CREATE POLICY consultant_portfolio_sequence_select ON public.consultant_portfolio_sequence
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      (public.has_permission('consultant_workspace.read') AND consultant_user_id = public.current_app_user_id())
      OR public.has_permission('report.executive.read')
      OR public.is_primary_owner()
    )
  );

CREATE POLICY consultant_portfolio_entry_select ON public.consultant_portfolio_entry
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      (public.has_permission('consultant_workspace.read') AND consultant_user_id = public.current_app_user_id())
      OR public.has_permission('report.executive.read')
      OR public.is_primary_owner()
    )
  );

CREATE TABLE public.payment_consultant_attribution (
  id                              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id                 uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  payment_id                      uuid NOT NULL,
  consultant_user_id              uuid NOT NULL,
  consultant_operational_code     char(2) NOT NULL,
  attributed_amount               bigint NOT NULL CHECK (attributed_amount > 0),
  currency_code                   text NOT NULL DEFAULT 'VND',
  consultant_revenue_declaration_id uuid,
  attribution_recorded_at         timestamptz NOT NULL DEFAULT now(),
  created_at                      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, payment_id),
  CONSTRAINT payment_consultant_attribution_code_check
    CHECK (public._cw2_validate_consultant_operational_code(consultant_operational_code)),
  FOREIGN KEY (organization_id, payment_id)
    REFERENCES public.payment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, consultant_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (consultant_revenue_declaration_id)
    REFERENCES public.consultant_revenue_declaration (id) ON DELETE RESTRICT
);

CREATE INDEX idx_payment_consultant_attribution_consultant_month
  ON public.payment_consultant_attribution (organization_id, consultant_user_id, attribution_recorded_at);

COMMENT ON TABLE public.payment_consultant_attribution IS
  'CW2: immutable snapshot linking posted M2 payment cash to consultant for monthly sales. Not declaration totals; not revenue_recognition_event.';

ALTER TABLE public.payment_consultant_attribution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_consultant_attribution FORCE ROW LEVEL SECURITY;

CREATE POLICY payment_consultant_attribution_select ON public.payment_consultant_attribution
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      public.has_permission('consultant_revenue.review')
      OR public.has_permission('payment.read')
      OR public.has_permission('report.executive.read')
      OR (
        public.has_permission('consultant_workspace.read')
        AND consultant_user_id = public.current_app_user_id()
      )
    )
  );

ALTER TABLE public.consultant_revenue_declaration
  ADD COLUMN IF NOT EXISTS lead_id uuid,
  ADD COLUMN IF NOT EXISTS student_id uuid,
  ADD COLUMN IF NOT EXISTS course_id uuid,
  ADD COLUMN IF NOT EXISTS enrollment_id uuid,
  ADD COLUMN IF NOT EXISTS enrollment_financial_terms_id uuid,
  ADD COLUMN IF NOT EXISTS total_obligation_amount numeric(19, 4),
  ADD COLUMN IF NOT EXISTS promotion_context text,
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS consultant_operational_code_snapshot char(2);

ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_org_id_unique
    UNIQUE (organization_id, id);

ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_obligation_nonneg
    CHECK (total_obligation_amount IS NULL OR total_obligation_amount > 0),
  ADD CONSTRAINT consultant_revenue_declaration_code_snapshot_check
    CHECK (
      consultant_operational_code_snapshot IS NULL
      OR public._cw2_validate_consultant_operational_code(consultant_operational_code_snapshot)
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_consultant_revenue_declaration_idempotency
  ON public.consultant_revenue_declaration (organization_id, consultant_user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

ALTER TABLE public.consultant_revenue_declaration
  ADD CONSTRAINT consultant_revenue_declaration_org_lead_fk
    FOREIGN KEY (organization_id, lead_id)
    REFERENCES public.lead (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT consultant_revenue_declaration_org_student_fk
    FOREIGN KEY (organization_id, student_id)
    REFERENCES public.student (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT consultant_revenue_declaration_org_course_fk
    FOREIGN KEY (organization_id, course_id)
    REFERENCES public.course (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT consultant_revenue_declaration_org_enrollment_fk
    FOREIGN KEY (organization_id, enrollment_id)
    REFERENCES public.enrollment (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT consultant_revenue_declaration_org_terms_fk
    FOREIGN KEY (organization_id, enrollment_financial_terms_id)
    REFERENCES public.enrollment_financial_terms (organization_id, id) ON DELETE RESTRICT;

COMMENT ON COLUMN public.consultant_revenue_declaration.total_obligation_amount IS
  'Snapshot of authoritative obligation at submit; does not replace enrollment_financial_terms.';

DROP POLICY IF EXISTS consultant_revenue_declaration_insert ON public.consultant_revenue_declaration;
CREATE POLICY consultant_revenue_declaration_insert ON public.consultant_revenue_declaration
  FOR INSERT
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.declare')
    AND consultant_user_id = public.current_app_user_id()
    AND status IN ('pending', 'draft')
  );

DROP POLICY IF EXISTS consultant_revenue_declaration_update ON public.consultant_revenue_declaration;
CREATE POLICY consultant_revenue_declaration_update_reviewer ON public.consultant_revenue_declaration
  FOR UPDATE
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.review')
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.review')
  );

CREATE POLICY consultant_revenue_declaration_update_consultant_draft ON public.consultant_revenue_declaration
  FOR UPDATE
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.declare')
    AND consultant_user_id = public.current_app_user_id()
    AND status IN ('draft', 'returned')
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_revenue.declare')
    AND consultant_user_id = public.current_app_user_id()
    AND status IN ('draft', 'returned', 'pending')
  );

CREATE TABLE public.consultant_custom_field_definition (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  owner_app_user_id uuid NOT NULL,
  field_key         text NOT NULL,
  label             text NOT NULL,
  data_type         text NOT NULL DEFAULT 'text',
  sort_order        integer NOT NULL DEFAULT 0,
  status            text NOT NULL DEFAULT 'active',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, owner_app_user_id, field_key),
  CONSTRAINT consultant_custom_field_definition_status_check
    CHECK (status IN ('active', 'archived')),
  CONSTRAINT consultant_custom_field_definition_data_type_check
    CHECK (data_type IN ('text', 'date', 'phone', 'url')),
  CONSTRAINT consultant_custom_field_definition_key_format_check
    CHECK (field_key ~ '^[a-z][a-z0-9_]{1,48}$'),
  FOREIGN KEY (organization_id, owner_app_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.consultant_custom_field_value (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  field_definition_id  uuid NOT NULL,
  subject_type         text NOT NULL,
  subject_id           uuid NOT NULL,
  value_text           text NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, field_definition_id, subject_type, subject_id),
  CONSTRAINT consultant_custom_field_value_subject_type_check
    CHECK (subject_type IN ('lead', 'student')),
  FOREIGN KEY (organization_id, field_definition_id)
    REFERENCES public.consultant_custom_field_definition (organization_id, id) ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION public._cw2_custom_field_key_reserved(p_key text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT lower(btrim(p_key)) = ANY (ARRAY[
    'student_code', 'status', 'given_name', 'family_name', 'student_id', 'lead_id',
    'consultant', 'course', 'enrollment', 'payment', 'charge', 'id', 'organization_id'
  ]::text[]);
$$;

CREATE OR REPLACE FUNCTION public.protect_consultant_custom_field_definition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF public._cw2_custom_field_key_reserved(NEW.field_key) THEN
    RAISE EXCEPTION 'custom_field_key_reserved';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER consultant_custom_field_definition_reserved_key
  BEFORE INSERT OR UPDATE OF field_key ON public.consultant_custom_field_definition
  FOR EACH ROW EXECUTE FUNCTION public.protect_consultant_custom_field_definition();

ALTER TABLE public.consultant_custom_field_definition ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_custom_field_definition FORCE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_custom_field_value ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_custom_field_value FORCE ROW LEVEL SECURITY;

CREATE POLICY consultant_custom_field_definition_owner ON public.consultant_custom_field_definition
  FOR ALL TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND owner_app_user_id = public.current_app_user_id()
    AND public.has_permission('consultant_custom_field.manage')
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND owner_app_user_id = public.current_app_user_id()
    AND public.has_permission('consultant_custom_field.manage')
  );

CREATE POLICY consultant_custom_field_value_owner ON public.consultant_custom_field_value
  FOR ALL TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_custom_field.manage')
    AND EXISTS (
      SELECT 1 FROM public.consultant_custom_field_definition d
      WHERE d.id = field_definition_id
        AND d.organization_id = consultant_custom_field_value.organization_id
        AND d.owner_app_user_id = public.current_app_user_id()
    )
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('consultant_custom_field.manage')
    AND EXISTS (
      SELECT 1 FROM public.consultant_custom_field_definition d
      WHERE d.id = field_definition_id
        AND d.organization_id = consultant_custom_field_value.organization_id
        AND d.owner_app_user_id = public.current_app_user_id()
    )
  );

CREATE TABLE public.consultant_workspace_preference (
  organization_id uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  app_user_id     uuid NOT NULL,
  grid_preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, app_user_id),
  FOREIGN KEY (organization_id, app_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.consultant_grid_hidden_row (
  organization_id uuid NOT NULL REFERENCES public.organization (id) ON DELETE RESTRICT,
  app_user_id     uuid NOT NULL,
  subject_type    text NOT NULL,
  subject_id      uuid NOT NULL,
  hidden_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, app_user_id, subject_type, subject_id),
  CONSTRAINT consultant_grid_hidden_row_subject_type_check
    CHECK (subject_type IN ('lead', 'student')),
  FOREIGN KEY (organization_id, app_user_id)
    REFERENCES public.app_user (organization_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE public.consultant_grid_hidden_row IS
  'CW2: personal view-only hide; never mutates lead/student authoritative status.';

ALTER TABLE public.consultant_workspace_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_workspace_preference FORCE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_grid_hidden_row ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultant_grid_hidden_row FORCE ROW LEVEL SECURITY;

CREATE POLICY consultant_workspace_preference_self ON public.consultant_workspace_preference
  FOR ALL TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND app_user_id = public.current_app_user_id()
    AND public.has_permission('consultant_workspace.read')
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND app_user_id = public.current_app_user_id()
    AND public.has_permission('consultant_workspace.read')
  );

CREATE POLICY consultant_grid_hidden_row_self ON public.consultant_grid_hidden_row
  FOR ALL TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND app_user_id = public.current_app_user_id()
    AND public.has_permission('consultant_workspace.read')
  )
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND app_user_id = public.current_app_user_id()
    AND public.has_permission('consultant_workspace.read')
  );

CREATE OR REPLACE FUNCTION public.initialize_organization_cw2_foundation(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_primary uuid;
  v_role_id uuid;
BEGIN
  INSERT INTO public.organization_student_sequence (organization_id, last_allocated_sequence)
  VALUES (p_organization_id, 0)
  ON CONFLICT (organization_id) DO NOTHING;

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = p_organization_id;

  IF v_primary IS NOT NULL THEN
    UPDATE public.app_user
    SET consultant_operational_code = '01'
    WHERE id = v_primary
      AND organization_id = p_organization_id
      AND consultant_operational_code IS NULL;
  END IF;

  SELECT r.id INTO v_role_id
  FROM public.role r
  WHERE r.organization_id = p_organization_id
    AND r.is_canonical_template
    AND r.canonical_code = 'consultant';

  IF v_role_id IS NOT NULL THEN
    PERFORM public._cw2_apply_consultant_workspace_permissions(v_role_id);
  END IF;
END;
$$;

-- Ensure primary owner receives code 01 when assigned after org bootstrap (seed runs post-migration).
CREATE OR REPLACE FUNCTION public.set_primary_owner_for_organization(
  p_organization_id uuid,
  p_app_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_app_user_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.app_user u
      WHERE u.organization_id = p_organization_id
        AND u.id = p_app_user_id
        AND u.membership_status = 'member'
    ) THEN
      RAISE EXCEPTION 'invalid_primary_owner_candidate';
    END IF;
  END IF;

  UPDATE public.organization_entitlement oe
  SET primary_app_user_id = p_app_user_id
  WHERE oe.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entitlement_missing';
  END IF;

  PERFORM public.initialize_organization_cw2_foundation(p_organization_id);
END;
$$;

CREATE OR REPLACE FUNCTION public._cw2_next_consultant_operational_code(p_organization_id uuid)
RETURNS char(2)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code integer;
  v_candidate char(2);
BEGIN
  SELECT COALESCE(max(consultant_operational_code::integer), 1) INTO v_code
  FROM public.app_user
  WHERE organization_id = p_organization_id
    AND consultant_operational_code IS NOT NULL;

  IF v_code < 2 THEN
    v_code := 1;
  END IF;

  FOR v_code IN v_code + 1 .. 99 LOOP
    v_candidate := lpad(v_code::text, 2, '0');
    IF NOT EXISTS (
      SELECT 1 FROM public.app_user u
      WHERE u.organization_id = p_organization_id
        AND u.consultant_operational_code = v_candidate
    ) THEN
      RETURN v_candidate;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'consultant_operational_code_exhausted' USING ERRCODE = 'P0001';
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_consultant_operational_code(p_target_app_user_id uuid)
RETURNS char(2)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_primary uuid;
  v_code char(2);
  v_is_consultant boolean;
BEGIN
  IF NOT public.is_trusted_schema_mutation_role() AND NOT public.is_primary_owner() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT oe.primary_app_user_id INTO v_primary
  FROM public.organization_entitlement oe
  WHERE oe.organization_id = v_org_id;

  IF p_target_app_user_id = v_primary THEN
    v_code := '01';
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public.user_role ur
      JOIN public.role r ON r.id = ur.role_id
      WHERE ur.organization_id = v_org_id
        AND ur.user_id = p_target_app_user_id
        AND ur.status = 'active'
        AND r.is_canonical_template
        AND r.canonical_code = 'consultant'
    ) INTO v_is_consultant;

    IF NOT v_is_consultant THEN
      RAISE EXCEPTION 'target_not_consultant_role';
    END IF;

    SELECT consultant_operational_code INTO v_code
    FROM public.app_user
    WHERE id = p_target_app_user_id AND organization_id = v_org_id;

    IF v_code IS NOT NULL THEN
      RETURN v_code;
    END IF;

    v_code := public._cw2_next_consultant_operational_code(v_org_id);
  END IF;

  UPDATE public.app_user
  SET consultant_operational_code = v_code
  WHERE id = p_target_app_user_id
    AND organization_id = v_org_id
    AND consultant_operational_code IS NULL;

  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_initialize_organization_cw2_foundation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.initialize_organization_cw2_foundation(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS organization_initialize_cw2_foundation ON public.organization;
CREATE TRIGGER organization_initialize_cw2_foundation
  AFTER INSERT ON public.organization
  FOR EACH ROW EXECUTE FUNCTION public.trg_initialize_organization_cw2_foundation();

INSERT INTO public.organization_student_sequence (organization_id, last_allocated_sequence)
SELECT o.id, 0
FROM public.organization o
ON CONFLICT (organization_id) DO NOTHING;

DO $$
DECLARE
  org_record record;
BEGIN
  FOR org_record IN SELECT id FROM public.organization LOOP
    PERFORM public.initialize_organization_cw2_foundation(org_record.id);
  END LOOP;
END $$;

DO $$
DECLARE
  org_record record;
  user_record record;
  v_code char(2);
BEGIN
  FOR org_record IN SELECT id FROM public.organization LOOP
    FOR user_record IN
      SELECT DISTINCT u.id
      FROM public.app_user u
      JOIN public.user_role ur ON ur.user_id = u.id AND ur.organization_id = u.organization_id
      JOIN public.role r ON r.id = ur.role_id
      WHERE u.organization_id = org_record.id
        AND u.consultant_operational_code IS NULL
        AND ur.status = 'active'
        AND r.is_canonical_template
        AND r.canonical_code = 'consultant'
      ORDER BY u.created_at, u.id
    LOOP
      v_code := public._cw2_next_consultant_operational_code(org_record.id);
      UPDATE public.app_user
      SET consultant_operational_code = v_code
      WHERE id = user_record.id AND organization_id = org_record.id;
    END LOOP;
  END LOOP;
END $$;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT id FROM public.role
    WHERE is_canonical_template AND canonical_code = 'consultant'
  LOOP
    PERFORM public._cw2_apply_consultant_workspace_permissions(r.id);
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.initialize_organization_cw2_foundation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.initialize_organization_cw2_foundation(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_organization_cw2_foundation(uuid) TO service_role;

REVOKE ALL ON FUNCTION public._cw2_next_consultant_operational_code(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._cw2_next_consultant_operational_code(uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.assign_consultant_operational_code(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_consultant_operational_code(uuid) TO authenticated;
