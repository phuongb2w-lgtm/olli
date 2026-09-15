-- M2-T04: Enrollment financial terms, payment schedule, and charge generation.

COMMENT ON TABLE tuition_plan IS
  'Optional list-price / payment-plan template at course or class scope. Not authoritative per-student tuition; enrollment_financial_terms holds the commercial agreement.';

-- =============================================================================
-- ENROLLMENT FINANCIAL TERMS
-- =============================================================================

CREATE TABLE enrollment_financial_terms (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  enrollment_id           uuid NOT NULL,
  tuition_plan_id         uuid,
  agreed_tuition_amount   bigint NOT NULL,
  discount_amount         bigint NOT NULL DEFAULT 0,
  net_tuition_amount      bigint NOT NULL,
  currency_code           text NOT NULL DEFAULT 'VND',
  agreement_date          date NOT NULL DEFAULT CURRENT_DATE,
  payment_plan_mode       text,
  recognition_basis_code  text,
  status                  text NOT NULL DEFAULT 'draft',
  superseded_by_id        uuid,
  notes                   text,
  charges_generated_at    timestamptz,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  created_by              uuid,
  updated_by              uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT enrollment_financial_terms_agreed_check CHECK (agreed_tuition_amount >= 0),
  CONSTRAINT enrollment_financial_terms_discount_check CHECK (discount_amount >= 0),
  CONSTRAINT enrollment_financial_terms_net_check CHECK (net_tuition_amount >= 0),
  CONSTRAINT enrollment_financial_terms_net_formula_check CHECK (
    net_tuition_amount = agreed_tuition_amount - discount_amount
  ),
  CONSTRAINT enrollment_financial_terms_status_check CHECK (
    status IN ('draft', 'active', 'superseded', 'cancelled')
  ),
  CONSTRAINT enrollment_financial_terms_payment_plan_check CHECK (
    payment_plan_mode IS NULL OR payment_plan_mode IN (
      'full_upfront', 'deposit_remainder', 'equal_installments', 'custom'
    )
  ),
  CONSTRAINT enrollment_financial_terms_recognition_check CHECK (
    recognition_basis_code IS NULL OR recognition_basis_code IN (
      'per_lesson', 'stage_checkpoint', 'deferred'
    )
  ),
  CONSTRAINT enrollment_financial_terms_superseded_check CHECK (
    superseded_by_id IS NULL OR status = 'superseded'
  ),
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, tuition_plan_id) REFERENCES tuition_plan (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, superseded_by_id) REFERENCES enrollment_financial_terms (organization_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX idx_enrollment_financial_terms_one_active
  ON enrollment_financial_terms (organization_id, enrollment_id)
  WHERE status = 'active';

CREATE UNIQUE INDEX idx_enrollment_financial_terms_one_draft
  ON enrollment_financial_terms (organization_id, enrollment_id)
  WHERE status = 'draft';

CREATE INDEX idx_enrollment_financial_terms_enrollment
  ON enrollment_financial_terms (organization_id, enrollment_id, status);

CREATE TRIGGER enrollment_financial_terms_updated_at
  BEFORE UPDATE ON enrollment_financial_terms
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE enrollment_financial_terms IS
  'Per-enrollment commercial agreement. Authoritative net tuition lives here, not on course/class.';

-- =============================================================================
-- PAYMENT SCHEDULE ITEMS
-- =============================================================================

CREATE TABLE enrollment_payment_schedule_item (
  id                           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id              uuid NOT NULL,
  enrollment_financial_terms_id uuid NOT NULL,
  sequence_number              integer NOT NULL,
  due_date                     date NOT NULL,
  amount                       bigint NOT NULL,
  label                        text,
  status                       text NOT NULL DEFAULT 'scheduled',
  created_at                   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (enrollment_financial_terms_id, sequence_number),
  CONSTRAINT enrollment_payment_schedule_item_amount_check CHECK (amount > 0),
  CONSTRAINT enrollment_payment_schedule_item_sequence_check CHECK (sequence_number > 0),
  CONSTRAINT enrollment_payment_schedule_item_status_check CHECK (
    status IN ('scheduled', 'void')
  ),
  FOREIGN KEY (organization_id, enrollment_financial_terms_id)
    REFERENCES enrollment_financial_terms (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_enrollment_payment_schedule_terms
  ON enrollment_payment_schedule_item (organization_id, enrollment_financial_terms_id, sequence_number);

COMMENT ON TABLE enrollment_payment_schedule_item IS
  'Deterministic due schedule for an enrollment agreement. Does not store paid amounts.';

-- =============================================================================
-- CHARGE PROVENANCE EXTENSIONS
-- =============================================================================

ALTER TABLE charge
  ADD COLUMN enrollment_financial_terms_id uuid,
  ADD COLUMN enrollment_payment_schedule_item_id uuid,
  ADD COLUMN charge_source_code text,
  ADD COLUMN agreed_tuition_snapshot bigint,
  ADD COLUMN net_tuition_snapshot bigint;

ALTER TABLE charge
  ADD CONSTRAINT charge_enrollment_financial_terms_fk
    FOREIGN KEY (organization_id, enrollment_financial_terms_id)
    REFERENCES enrollment_financial_terms (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT charge_enrollment_payment_schedule_item_fk
    FOREIGN KEY (organization_id, enrollment_payment_schedule_item_id)
    REFERENCES enrollment_payment_schedule_item (organization_id, id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX idx_charge_one_per_schedule_item
  ON charge (enrollment_payment_schedule_item_id)
  WHERE enrollment_payment_schedule_item_id IS NOT NULL;

ALTER TABLE charge
  ADD CONSTRAINT charge_source_code_check CHECK (
    charge_source_code IS NULL OR charge_source_code IN ('tuition')
  ),
  ADD CONSTRAINT charge_tuition_requires_enrollment CHECK (
    charge_source_code IS DISTINCT FROM 'tuition'
    OR (
      enrollment_id IS NOT NULL
      AND enrollment_financial_terms_id IS NOT NULL
      AND enrollment_payment_schedule_item_id IS NOT NULL
    )
  );

COMMENT ON COLUMN charge.enrollment_financial_terms_id IS
  'Provenance link to the enrollment agreement that generated this tuition charge.';
COMMENT ON COLUMN charge.enrollment_payment_schedule_item_id IS
  'One schedule item generates at most one tuition charge (idempotency anchor).';
COMMENT ON COLUMN charge.agreed_tuition_snapshot IS
  'List/agreed tuition from terms at charge generation time.';
COMMENT ON COLUMN charge.net_tuition_snapshot IS
  'Net tuition obligation from terms at charge generation time.';

-- =============================================================================
-- HELPERS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.installment_schedule_amount(
  p_total bigint,
  p_installment_count integer,
  p_sequence_number integer
)
RETURNS bigint
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_base bigint;
BEGIN
  IF p_installment_count IS NULL OR p_installment_count <= 0 THEN
    RAISE EXCEPTION 'invalid_installment_count';
  END IF;

  IF p_sequence_number < 1 OR p_sequence_number > p_installment_count THEN
    RAISE EXCEPTION 'sequence_number out of range';
  END IF;

  v_base := p_total / p_installment_count;

  IF p_sequence_number < p_installment_count THEN
    RETURN v_base;
  END IF;

  RETURN p_total - v_base * (p_installment_count - 1);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_enrollment_billing_guardian_id(p_enrollment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_org_id uuid;
  v_student_id uuid;
  v_guardian_id uuid;
BEGIN
  SELECT organization_id, student_id
    INTO v_org_id, v_student_id
  FROM enrollment
  WHERE id = p_enrollment_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT sg.guardian_id INTO v_guardian_id
  FROM student_guardian sg
  WHERE sg.organization_id = v_org_id
    AND sg.student_id = v_student_id
    AND sg.status = 'active'
    AND sg.is_billing_contact = true
  ORDER BY sg.created_at
  LIMIT 1;

  IF v_guardian_id IS NOT NULL THEN
    RETURN v_guardian_id;
  END IF;

  SELECT sg.guardian_id INTO v_guardian_id
  FROM student_guardian sg
  WHERE sg.organization_id = v_org_id
    AND sg.student_id = v_student_id
    AND sg.status = 'active'
    AND sg.is_primary_contact = true
  ORDER BY sg.created_at
  LIMIT 1;

  RETURN v_guardian_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.enrollment_schedule_total(p_terms_id uuid)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(SUM(amount), 0)
  FROM enrollment_payment_schedule_item
  WHERE enrollment_financial_terms_id = p_terms_id
    AND status = 'scheduled';
$$;

-- =============================================================================
-- IMMUTABILITY GUARDS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.protect_enrollment_financial_terms_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status = 'active' THEN
    IF NEW.agreed_tuition_amount IS DISTINCT FROM OLD.agreed_tuition_amount
       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.net_tuition_amount IS DISTINCT FROM OLD.net_tuition_amount
       OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
       OR NEW.payment_plan_mode IS DISTINCT FROM OLD.payment_plan_mode
       OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id
    THEN
      RAISE EXCEPTION 'Active enrollment financial terms cannot be silently rewritten; use financial_adjustment for corrections';
    END IF;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status IN ('superseded', 'cancelled') THEN
    IF NEW.agreed_tuition_amount IS DISTINCT FROM OLD.agreed_tuition_amount
       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.net_tuition_amount IS DISTINCT FROM OLD.net_tuition_amount
       OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
       OR NEW.payment_plan_mode IS DISTINCT FROM OLD.payment_plan_mode
       OR NEW.enrollment_id IS DISTINCT FROM OLD.enrollment_id
       OR NEW.status IS DISTINCT FROM OLD.status
    THEN
      RAISE EXCEPTION 'Historical enrollment financial terms are immutable';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER enrollment_financial_terms_protect_lifecycle
  BEFORE UPDATE ON enrollment_financial_terms
  FOR EACH ROW EXECUTE FUNCTION public.protect_enrollment_financial_terms_lifecycle();

CREATE OR REPLACE FUNCTION public.protect_enrollment_payment_schedule_draft_only()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_terms_id uuid;
  v_status text;
BEGIN
  v_terms_id := COALESCE(NEW.enrollment_financial_terms_id, OLD.enrollment_financial_terms_id);

  SELECT status INTO v_status
  FROM enrollment_financial_terms
  WHERE id = v_terms_id;

  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Payment schedule can only be modified while financial terms are draft';
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER enrollment_payment_schedule_draft_only
  BEFORE INSERT OR UPDATE OR DELETE ON enrollment_payment_schedule_item
  FOR EACH ROW EXECUTE FUNCTION public.protect_enrollment_payment_schedule_draft_only();

-- =============================================================================
-- INTERNAL: REPLACE DRAFT SCHEDULE
-- =============================================================================

CREATE OR REPLACE FUNCTION public._replace_enrollment_payment_schedule(
  p_terms_id uuid,
  p_mode text,
  p_items jsonb
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_item jsonb;
  v_seq integer := 0;
  v_total bigint := 0;
BEGIN
  SELECT * INTO v_terms FROM enrollment_financial_terms WHERE id = p_terms_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_terms.status <> 'draft' THEN
    RAISE EXCEPTION 'terms_not_draft' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM enrollment_payment_schedule_item
  WHERE enrollment_financial_terms_id = p_terms_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_seq := v_seq + 1;
    v_total := v_total + (v_item->>'amount')::bigint;

    INSERT INTO enrollment_payment_schedule_item (
      organization_id,
      enrollment_financial_terms_id,
      sequence_number,
      due_date,
      amount,
      label
    ) VALUES (
      v_terms.organization_id,
      p_terms_id,
      v_seq,
      (v_item->>'due_date')::date,
      (v_item->>'amount')::bigint,
      v_item->>'label'
    );
  END LOOP;

  IF v_total <> v_terms.net_tuition_amount THEN
    RAISE EXCEPTION 'schedule_total_mismatch' USING ERRCODE = 'P0001';
  END IF;

  UPDATE enrollment_financial_terms
  SET payment_plan_mode = p_mode,
      updated_by = CASE
        WHEN public.is_active_app_user()
          AND EXISTS (
            SELECT 1 FROM app_user au
            WHERE au.id = public.current_app_user_id()
              AND au.organization_id = v_terms.organization_id
          )
        THEN public.current_app_user_id()
        ELSE updated_by
      END
  WHERE id = p_terms_id;
END;
$$;

REVOKE ALL ON FUNCTION public._replace_enrollment_payment_schedule(uuid, text, jsonb) FROM PUBLIC;

-- =============================================================================
-- RPC: CREATE / UPDATE DRAFT TERMS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_enrollment_financial_terms(
  p_enrollment_id uuid,
  p_agreed_tuition_amount bigint,
  p_discount_amount bigint DEFAULT 0,
  p_agreement_date date DEFAULT CURRENT_DATE,
  p_tuition_plan_id uuid DEFAULT NULL,
  p_recognition_basis_code text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_currency text;
  v_net bigint;
  v_terms_id uuid;
BEGIN
  IF NOT public.is_active_app_user() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF p_agreed_tuition_amount IS NULL OR p_agreed_tuition_amount < 0 THEN
    RAISE EXCEPTION 'invalid_agreed_tuition' USING ERRCODE = 'P0001';
  END IF;

  IF p_discount_amount IS NULL OR p_discount_amount < 0 THEN
    RAISE EXCEPTION 'invalid_discount' USING ERRCODE = 'P0001';
  END IF;

  v_net := p_agreed_tuition_amount - p_discount_amount;

  IF v_net < 0 THEN
    RAISE EXCEPTION 'invalid_net_tuition' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM enrollment
    WHERE id = p_enrollment_id AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'enrollment_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1 FROM enrollment_financial_terms
    WHERE organization_id = v_org_id
      AND enrollment_id = p_enrollment_id
      AND status = 'draft'
  ) THEN
    RAISE EXCEPTION 'draft_terms_already_exist' USING ERRCODE = 'P0001';
  END IF;

  SELECT currency_code INTO v_currency FROM organization WHERE id = v_org_id;

  INSERT INTO enrollment_financial_terms (
    organization_id,
    enrollment_id,
    tuition_plan_id,
    agreed_tuition_amount,
    discount_amount,
    net_tuition_amount,
    currency_code,
    agreement_date,
    recognition_basis_code,
    notes,
    created_by,
    updated_by
  ) VALUES (
    v_org_id,
    p_enrollment_id,
    p_tuition_plan_id,
    p_agreed_tuition_amount,
    p_discount_amount,
    v_net,
    v_currency,
    COALESCE(p_agreement_date, CURRENT_DATE),
    p_recognition_basis_code,
    p_notes,
    v_actor,
    v_actor
  )
  RETURNING id INTO v_terms_id;

  RETURN v_terms_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_draft_enrollment_financial_terms(
  p_terms_id uuid,
  p_agreed_tuition_amount bigint,
  p_discount_amount bigint DEFAULT 0,
  p_agreement_date date DEFAULT NULL,
  p_tuition_plan_id uuid DEFAULT NULL,
  p_recognition_basis_code text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_actor uuid;
  v_net bigint;
  v_old_net bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();
  v_actor := public.current_app_user_id();

  IF p_agreed_tuition_amount IS NULL OR p_agreed_tuition_amount < 0
     OR p_discount_amount IS NULL OR p_discount_amount < 0 THEN
    RAISE EXCEPTION 'invalid_amounts' USING ERRCODE = 'P0001';
  END IF;

  v_net := p_agreed_tuition_amount - p_discount_amount;
  IF v_net < 0 THEN
    RAISE EXCEPTION 'invalid_net_tuition' USING ERRCODE = 'P0001';
  END IF;

  SELECT net_tuition_amount INTO v_old_net
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = v_org_id AND status = 'draft';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'draft_terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE enrollment_financial_terms
  SET agreed_tuition_amount = p_agreed_tuition_amount,
      discount_amount = p_discount_amount,
      net_tuition_amount = v_net,
      agreement_date = COALESCE(p_agreement_date, agreement_date),
      tuition_plan_id = p_tuition_plan_id,
      recognition_basis_code = p_recognition_basis_code,
      notes = p_notes,
      updated_by = v_actor
  WHERE id = p_terms_id;

  IF v_net IS DISTINCT FROM v_old_net THEN
    DELETE FROM enrollment_payment_schedule_item
    WHERE enrollment_financial_terms_id = p_terms_id;
  END IF;
END;
$$;

-- =============================================================================
-- RPC: PAYMENT SCHEDULE MODES
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_enrollment_payment_schedule_full_upfront(
  p_terms_id uuid,
  p_due_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_net bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT net_tuition_amount INTO v_net
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM public._replace_enrollment_payment_schedule(
    p_terms_id,
    'full_upfront',
    jsonb_build_array(
      jsonb_build_object('due_date', p_due_date, 'amount', v_net, 'label', 'Full payment')
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_enrollment_payment_schedule_deposit_remainder(
  p_terms_id uuid,
  p_deposit_amount bigint,
  p_deposit_due_date date,
  p_remainder_due_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_net bigint;
  v_remainder bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT net_tuition_amount INTO v_net
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_deposit_amount IS NULL OR p_deposit_amount <= 0 OR p_deposit_amount >= v_net THEN
    RAISE EXCEPTION 'invalid_deposit' USING ERRCODE = 'P0001';
  END IF;

  v_remainder := v_net - p_deposit_amount;

  PERFORM public._replace_enrollment_payment_schedule(
    p_terms_id,
    'deposit_remainder',
    jsonb_build_array(
      jsonb_build_object('due_date', p_deposit_due_date, 'amount', p_deposit_amount, 'label', 'Deposit'),
      jsonb_build_object('due_date', p_remainder_due_date, 'amount', v_remainder, 'label', 'Remainder')
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_enrollment_payment_schedule_installments(
  p_terms_id uuid,
  p_installment_count integer,
  p_first_due_date date
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_net bigint;
  v_items jsonb := '[]'::jsonb;
  v_amount bigint;
  v_due date;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_installment_count IS NULL OR p_installment_count <= 0 THEN
    RAISE EXCEPTION 'invalid_installment_count' USING ERRCODE = 'P0001';
  END IF;

  SELECT net_tuition_amount INTO v_net
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_due := p_first_due_date;

  FOR v_seq IN 1..p_installment_count LOOP
    v_amount := public.installment_schedule_amount(v_net, p_installment_count, v_seq);
    v_items := v_items || jsonb_build_array(
      jsonb_build_object(
        'due_date', v_due,
        'amount', v_amount,
        'label', format('Installment %s', v_seq)
      )
    );
    v_due := (date_trunc('month', v_due)::date + make_interval(months => 1))::date;
  END LOOP;

  PERFORM public._replace_enrollment_payment_schedule(
    p_terms_id,
    'equal_installments',
    v_items
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_enrollment_payment_schedule_custom(
  p_terms_id uuid,
  p_schedule jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_schedule IS NULL OR jsonb_typeof(p_schedule) <> 'array' OR jsonb_array_length(p_schedule) = 0 THEN
    RAISE EXCEPTION 'invalid_schedule' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public._replace_enrollment_payment_schedule(
    p_terms_id,
    'custom',
    p_schedule
  );
END;
$$;

-- =============================================================================
-- RPC: ACTIVATE + GENERATE CHARGES
-- =============================================================================

CREATE OR REPLACE FUNCTION public.activate_enrollment_financial_terms(p_terms_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_schedule_total bigint;
  v_prior_active uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_terms.status <> 'draft' THEN
    RAISE EXCEPTION 'terms_not_draft' USING ERRCODE = 'P0001';
  END IF;

  v_schedule_total := public.enrollment_schedule_total(p_terms_id);

  IF v_schedule_total <> v_terms.net_tuition_amount THEN
    RAISE EXCEPTION 'schedule_total_mismatch' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM enrollment_payment_schedule_item
    WHERE enrollment_financial_terms_id = p_terms_id AND status = 'scheduled'
  ) THEN
    RAISE EXCEPTION 'schedule_required' USING ERRCODE = 'P0001';
  END IF;

  SELECT id INTO v_prior_active
  FROM enrollment_financial_terms
  WHERE organization_id = v_terms.organization_id
    AND enrollment_id = v_terms.enrollment_id
    AND status = 'active'
    AND id <> p_terms_id;

  IF v_prior_active IS NOT NULL THEN
    UPDATE enrollment_financial_terms
    SET status = 'superseded',
        superseded_by_id = p_terms_id,
        updated_by = public.current_app_user_id()
    WHERE id = v_prior_active;
  END IF;

  UPDATE enrollment_financial_terms
  SET status = 'active',
      updated_by = public.current_app_user_id()
  WHERE id = p_terms_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_enrollment_charges(p_terms_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_guardian_id uuid;
  v_created integer := 0;
  r record;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_terms.status <> 'active' THEN
    RAISE EXCEPTION 'terms_not_active' USING ERRCODE = 'P0001';
  END IF;

  v_guardian_id := public.resolve_enrollment_billing_guardian_id(v_terms.enrollment_id);

  IF v_guardian_id IS NULL THEN
    RAISE EXCEPTION 'billing_guardian_required' USING ERRCODE = 'P0001';
  END IF;

  FOR r IN
    SELECT si.*
    FROM enrollment_payment_schedule_item si
    WHERE si.enrollment_financial_terms_id = p_terms_id
      AND si.status = 'scheduled'
    ORDER BY si.sequence_number
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM charge
      WHERE enrollment_payment_schedule_item_id = r.id
    ) THEN
      INSERT INTO charge (
        organization_id,
        student_id,
        enrollment_id,
        guardian_id,
        tuition_plan_id,
        amount,
        currency_code,
        charged_at,
        due_date,
        description,
        status,
        created_by,
        enrollment_financial_terms_id,
        enrollment_payment_schedule_item_id,
        charge_source_code,
        agreed_tuition_snapshot,
        net_tuition_snapshot
      )
      SELECT
        v_terms.organization_id,
        e.student_id,
        e.id,
        v_guardian_id,
        v_terms.tuition_plan_id,
        r.amount,
        v_terms.currency_code,
        CURRENT_DATE,
        r.due_date,
        COALESCE(r.label, 'Tuition'),
        'open',
        public.current_app_user_id(),
        v_terms.id,
        r.id,
        'tuition',
        v_terms.agreed_tuition_amount,
        v_terms.net_tuition_amount
      FROM enrollment e
      WHERE e.id = v_terms.enrollment_id;

      v_created := v_created + 1;
    END IF;
  END LOOP;

  IF v_created > 0 OR v_terms.charges_generated_at IS NULL THEN
    UPDATE enrollment_financial_terms
    SET charges_generated_at = COALESCE(charges_generated_at, now()),
        updated_by = public.current_app_user_id()
    WHERE id = p_terms_id;
  END IF;

  RETURN v_created;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_enrollment_tuition_correction(
  p_terms_id uuid,
  p_new_net_tuition bigint,
  p_reason_code text DEFAULT 'correction',
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_terms enrollment_financial_terms%ROWTYPE;
  v_delta bigint;
  v_charge_id uuid;
  v_adjustment_id uuid;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.create') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE id = p_terms_id AND organization_id = public.current_organization_id();

  IF NOT FOUND OR v_terms.status <> 'active' THEN
    RAISE EXCEPTION 'active_terms_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF p_new_net_tuition IS NULL OR p_new_net_tuition < 0 THEN
    RAISE EXCEPTION 'invalid_net_tuition' USING ERRCODE = 'P0001';
  END IF;

  v_delta := p_new_net_tuition - v_terms.net_tuition_amount;

  IF v_delta = 0 THEN
    RETURN NULL;
  END IF;

  SELECT c.id INTO v_charge_id
  FROM charge c
  WHERE c.enrollment_financial_terms_id = p_terms_id
    AND c.status IN ('open', 'partially_paid')
  ORDER BY c.due_date NULLS LAST, c.created_at
  LIMIT 1;

  IF v_charge_id IS NULL THEN
    RAISE EXCEPTION 'no_open_charge_for_correction' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO financial_adjustment (
    organization_id,
    charge_id,
    adjustment_type_code,
    amount_delta,
    reason_code,
    notes,
    approved_by,
    status
  ) VALUES (
    v_terms.organization_id,
    v_charge_id,
    'correction',
    v_delta,
    p_reason_code,
    p_notes,
    public.current_app_user_id(),
    'posted'
  )
  RETURNING id INTO v_adjustment_id;

  RETURN v_adjustment_id;
END;
$$;

-- =============================================================================
-- RPC: FINANCIAL SUMMARY (derived read model)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_enrollment_financial_summary(p_enrollment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_terms enrollment_financial_terms%ROWTYPE;
  v_scheduled bigint;
  v_charged bigint;
  v_adjustments bigint;
  v_allocated bigint;
  v_outstanding bigint;
BEGIN
  IF NOT public.is_active_app_user() OR NOT public.has_permission('charge.read') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org_id := public.current_organization_id();

  SELECT * INTO v_terms
  FROM enrollment_financial_terms
  WHERE enrollment_id = p_enrollment_id
    AND organization_id = v_org_id
    AND status = 'active'
  LIMIT 1;

  SELECT COALESCE(SUM(si.amount), 0) INTO v_scheduled
  FROM enrollment_payment_schedule_item si
  JOIN enrollment_financial_terms t ON t.id = si.enrollment_financial_terms_id
  WHERE t.enrollment_id = p_enrollment_id
    AND t.organization_id = v_org_id
    AND t.status = 'active'
    AND si.status = 'scheduled';

  SELECT COALESCE(SUM(c.amount), 0) INTO v_charged
  FROM charge c
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND c.charge_source_code = 'tuition'
    AND c.status <> 'void';

  SELECT COALESCE(SUM(fa.amount_delta), 0) INTO v_adjustments
  FROM financial_adjustment fa
  JOIN charge c ON c.id = fa.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND fa.status = 'posted';

  SELECT COALESCE(SUM(pa.amount), 0) INTO v_allocated
  FROM payment_allocation pa
  JOIN charge c ON c.id = pa.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND c.organization_id = v_org_id
    AND c.status <> 'void';

  SELECT COALESCE(SUM(cb.outstanding_balance), 0) INTO v_outstanding
  FROM charge_balance cb
  JOIN charge c ON c.id = cb.charge_id
  WHERE c.enrollment_id = p_enrollment_id
    AND cb.organization_id = v_org_id;

  RETURN jsonb_build_object(
    'enrollment_id', p_enrollment_id,
    'active_terms_id', v_terms.id,
    'net_tuition', COALESCE(v_terms.net_tuition_amount, 0),
    'scheduled_amount', v_scheduled,
    'charged_amount', v_charged,
    'adjustments_amount', v_adjustments,
    'allocated_amount', v_allocated,
    'outstanding_amount', v_outstanding,
    'recognized_revenue', NULL
  );
END;
$$;

-- =============================================================================
-- RLS
-- =============================================================================

ALTER TABLE enrollment_financial_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollment_financial_terms FORCE ROW LEVEL SECURITY;
ALTER TABLE enrollment_payment_schedule_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollment_payment_schedule_item FORCE ROW LEVEL SECURITY;

CREATE POLICY enrollment_financial_terms_select ON enrollment_financial_terms FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.read'));

CREATE POLICY enrollment_financial_terms_insert ON enrollment_financial_terms FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'));

CREATE POLICY enrollment_financial_terms_update ON enrollment_financial_terms FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY enrollment_payment_schedule_select ON enrollment_payment_schedule_item FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.read'));

CREATE POLICY enrollment_payment_schedule_insert ON enrollment_payment_schedule_item FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'));

CREATE POLICY enrollment_payment_schedule_update ON enrollment_payment_schedule_item FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY enrollment_payment_schedule_delete ON enrollment_payment_schedule_item FOR DELETE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'));

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON enrollment_financial_terms, enrollment_payment_schedule_item TO authenticated;

GRANT EXECUTE ON FUNCTION public.installment_schedule_amount(bigint, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_enrollment_billing_guardian_id(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enrollment_schedule_total(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_enrollment_financial_terms(uuid, bigint, bigint, date, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_draft_enrollment_financial_terms(uuid, bigint, bigint, date, uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_enrollment_payment_schedule_full_upfront(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_enrollment_payment_schedule_deposit_remainder(uuid, bigint, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_enrollment_payment_schedule_installments(uuid, integer, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_enrollment_payment_schedule_custom(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_enrollment_financial_terms(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_enrollment_charges(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_enrollment_tuition_correction(uuid, bigint, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_enrollment_financial_summary(uuid) TO authenticated;
