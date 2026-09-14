-- M0-T03: Olli PostgreSQL data foundation
-- Canonical schema from M0-T02 (accepted). Table naming: singular snake_case.
-- Physical name `app_user` replaces logical User (PostgreSQL reserved word).

-- =============================================================================
-- EXTENSIONS
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- =============================================================================
-- SHARED FUNCTIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION initialize_organization_cost_groups()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO cost_group (organization_id, group_slot)
  VALUES (NEW.id, 1), (NEW.id, 2);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION prevent_expense_category_reparent()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.cost_group_id IS DISTINCT FROM NEW.cost_group_id THEN
    IF EXISTS (
      SELECT 1 FROM expense
      WHERE expense_category_id = NEW.id AND status = 'posted'
    ) THEN
      RAISE EXCEPTION 'Cannot reparent expense category with posted expenses. Archive and create a new category.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_expense_cost_group()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  cat_group_id uuid;
BEGIN
  SELECT cost_group_id INTO cat_group_id
  FROM expense_category WHERE id = NEW.expense_category_id;

  IF cat_group_id IS NULL THEN
    RAISE EXCEPTION 'Expense category not found';
  END IF;

  IF NEW.cost_group_id IS DISTINCT FROM cat_group_id THEN
    RAISE EXCEPTION 'expense.cost_group_id must match expense_category.cost_group_id at posting';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION protect_completed_session_teacher()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'completed'
     AND OLD.teacher_id IS DISTINCT FROM NEW.teacher_id THEN
    RAISE EXCEPTION 'Cannot change teacher_id on a completed teaching session';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_attendance_context()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  enr_class_id uuid;
  enr_org_id uuid;
  ses_class_id uuid;
  ses_org_id uuid;
BEGIN
  SELECT e.class_id, e.organization_id
    INTO enr_class_id, enr_org_id
  FROM enrollment e WHERE e.id = NEW.enrollment_id;

  SELECT ts.class_id, ts.organization_id
    INTO ses_class_id, ses_org_id
  FROM teaching_session ts WHERE ts.id = NEW.teaching_session_id;

  IF enr_class_id IS NULL OR ses_class_id IS NULL THEN
    RAISE EXCEPTION 'Invalid enrollment or teaching session reference';
  END IF;

  IF enr_class_id <> ses_class_id THEN
    RAISE EXCEPTION 'Attendance enrollment class must match teaching session class';
  END IF;

  IF enr_org_id <> ses_org_id OR NEW.organization_id <> enr_org_id THEN
    RAISE EXCEPTION 'Cross-organization attendance context rejected';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_payment_allocations()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_payment_id uuid;
  total_allocated bigint;
  payment_amount bigint;
BEGIN
  v_payment_id := COALESCE(NEW.payment_id, OLD.payment_id);

  SELECT COALESCE(SUM(amount), 0) INTO total_allocated
  FROM payment_allocation WHERE payment_id = v_payment_id;

  SELECT amount INTO payment_amount FROM payment WHERE id = v_payment_id;

  IF total_allocated > payment_amount THEN
    RAISE EXCEPTION 'Total payment allocations (%) exceed payment amount (%)', total_allocated, payment_amount;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION protect_finalized_assessment_result()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'finalized' AND (
       OLD.raw_score IS DISTINCT FROM NEW.raw_score
    OR OLD.max_score IS DISTINCT FROM NEW.max_score
  ) THEN
    RAISE EXCEPTION 'Cannot modify scores on a finalized assessment result';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION validate_teacher_user_org()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  user_org uuid;
BEGIN
  IF NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT organization_id INTO user_org FROM app_user WHERE id = NEW.user_id;
  IF user_org IS DISTINCT FROM NEW.organization_id THEN
    RAISE EXCEPTION 'Teacher user_id must belong to the same organization';
  END IF;
  RETURN NEW;
END;
$$;

-- =============================================================================
-- GLOBAL / SYSTEM REFERENCE (no organization_id)
-- =============================================================================

CREATE TABLE permission (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE permission IS 'Global authorization capability catalog; not tenant-owned.';

CREATE TABLE observation_indicator (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT observation_indicator_code_check CHECK (code ~ '^[a-z][a-z0-9_]*$')
);

COMMENT ON TABLE observation_indicator IS 'Controlled indicator codes for ObservationRating; global reference.';

-- =============================================================================
-- ORGANIZATION & ACCESS
-- =============================================================================

CREATE TABLE organization (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL,
  default_locale text NOT NULL DEFAULT 'vi',
  timezone       text NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
  currency_code  text NOT NULL DEFAULT 'VND',
  status         text NOT NULL DEFAULT 'active',
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organization_status_check CHECK (status IN ('active', 'inactive')),
  CONSTRAINT organization_locale_check CHECK (default_locale IN ('vi', 'en'))
);

CREATE TRIGGER organization_updated_at
  BEFORE UPDATE ON organization
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE app_user (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id  uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  email            text NOT NULL,
  display_name     text NOT NULL,
  preferred_locale text NOT NULL DEFAULT 'vi',
  status           text NOT NULL DEFAULT 'active',
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid,
  updated_by       uuid,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, email),
  CONSTRAINT app_user_status_check CHECK (status IN ('active', 'inactive', 'locked')),
  CONSTRAINT app_user_locale_check CHECK (preferred_locale IN ('vi', 'en'))
);

CREATE INDEX idx_app_user_organization ON app_user (organization_id);
CREATE INDEX idx_app_user_active ON app_user (organization_id) WHERE status = 'active';

CREATE TRIGGER app_user_updated_at
  BEFORE UPDATE ON app_user
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE app_user
  ADD CONSTRAINT app_user_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT app_user_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT;

CREATE TABLE role (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  code            text NOT NULL,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CONSTRAINT role_status_check CHECK (status IN ('active', 'inactive'))
);

CREATE INDEX idx_role_organization ON role (organization_id);

CREATE TRIGGER role_updated_at
  BEFORE UPDATE ON role
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE role_permission (
  role_id       uuid NOT NULL REFERENCES role (id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permission (id) ON DELETE RESTRICT,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_role (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id         uuid NOT NULL,
  role_id         uuid NOT NULL,
  effective_from  date NOT NULL DEFAULT CURRENT_DATE,
  effective_to    date,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT user_role_status_check CHECK (status IN ('active', 'ended')),
  CONSTRAINT user_role_dates_check CHECK (effective_to IS NULL OR effective_to >= effective_from),
  FOREIGN KEY (organization_id, user_id) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, role_id) REFERENCES role (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_user_role_user ON user_role (organization_id, user_id);

CREATE TRIGGER user_role_updated_at
  BEFORE UPDATE ON user_role
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- PEOPLE
-- =============================================================================

CREATE TABLE student (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  student_code    text,
  given_name      text NOT NULL,
  family_name     text NOT NULL,
  date_of_birth   date,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT student_status_check CHECK (status IN ('prospect', 'active', 'inactive', 'graduated', 'withdrawn'))
);

CREATE INDEX idx_student_organization ON student (organization_id);
CREATE INDEX idx_student_active ON student (organization_id, status) WHERE status = 'active';

CREATE TRIGGER student_updated_at
  BEFORE UPDATE ON student
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE student
  ADD CONSTRAINT student_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT student_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

CREATE TABLE guardian (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  given_name      text NOT NULL,
  family_name     text NOT NULL,
  email           text,
  phone           text,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT guardian_status_check CHECK (status IN ('active', 'inactive'))
);

CREATE INDEX idx_guardian_organization ON guardian (organization_id);
CREATE INDEX idx_guardian_active ON guardian (organization_id) WHERE status = 'active';

CREATE TRIGGER guardian_updated_at
  BEFORE UPDATE ON guardian
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE guardian
  ADD CONSTRAINT guardian_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT guardian_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

CREATE TABLE student_guardian (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL,
  student_id        uuid NOT NULL,
  guardian_id       uuid NOT NULL,
  relationship_type text NOT NULL DEFAULT 'guardian',
  is_primary_contact boolean NOT NULL DEFAULT false,
  is_billing_contact boolean NOT NULL DEFAULT false,
  status            text NOT NULL DEFAULT 'active',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, student_id, guardian_id),
  CONSTRAINT student_guardian_status_check CHECK (status IN ('active', 'ended')),
  CONSTRAINT student_guardian_relationship_check CHECK (
    relationship_type IN ('mother', 'father', 'guardian', 'other')
  ),
  FOREIGN KEY (organization_id, student_id) REFERENCES student (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, guardian_id) REFERENCES guardian (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_student_guardian_student ON student_guardian (organization_id, student_id);
CREATE INDEX idx_student_guardian_guardian ON student_guardian (organization_id, guardian_id);

CREATE TRIGGER student_guardian_updated_at
  BEFORE UPDATE ON student_guardian
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE teacher (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  user_id         uuid REFERENCES app_user (id) ON DELETE SET NULL,
  employee_code   text,
  given_name      text NOT NULL,
  family_name     text NOT NULL,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT teacher_status_check CHECK (status IN ('active', 'inactive', 'on_leave', 'terminated'))
);

CREATE TRIGGER teacher_validate_user_org
  BEFORE INSERT OR UPDATE OF user_id, organization_id ON teacher
  FOR EACH ROW EXECUTE FUNCTION validate_teacher_user_org();

CREATE INDEX idx_teacher_organization ON teacher (organization_id);
CREATE INDEX idx_teacher_active ON teacher (organization_id) WHERE status = 'active';

CREATE TRIGGER teacher_updated_at
  BEFORE UPDATE ON teacher
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE teacher
  ADD CONSTRAINT teacher_created_by_fk
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id),
  ADD CONSTRAINT teacher_updated_by_fk
  FOREIGN KEY (organization_id, updated_by) REFERENCES app_user (organization_id, id);

-- =============================================================================
-- ACADEMIC OPERATIONS
-- =============================================================================

CREATE TABLE course (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  level_code      text,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CONSTRAINT course_status_check CHECK (status IN ('active', 'inactive', 'archived'))
);

CREATE INDEX idx_course_organization ON course (organization_id);

CREATE TRIGGER course_updated_at
  BEFORE UPDATE ON course
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE class (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  course_id       uuid NOT NULL,
  name            text NOT NULL,
  term_start_date date,
  term_end_date   date,
  capacity        integer,
  status          text NOT NULL DEFAULT 'planned',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT class_status_check CHECK (status IN ('planned', 'active', 'completed', 'cancelled')),
  CONSTRAINT class_term_dates_check CHECK (
    term_end_date IS NULL OR term_start_date IS NULL OR term_end_date >= term_start_date
  ),
  FOREIGN KEY (organization_id, course_id) REFERENCES course (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_class_organization ON class (organization_id);
CREATE INDEX idx_class_course ON class (organization_id, course_id);
CREATE INDEX idx_class_status ON class (organization_id, status);

CREATE TRIGGER class_updated_at
  BEFORE UPDATE ON class
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE class_schedule (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  class_id        uuid NOT NULL,
  weekday_code    text NOT NULL,
  start_time      time NOT NULL,
  end_time        time NOT NULL,
  effective_from  date NOT NULL,
  effective_to    date,
  location        text,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT class_schedule_status_check CHECK (status IN ('active', 'ended')),
  CONSTRAINT class_schedule_weekday_check CHECK (
    weekday_code IN ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')
  ),
  CONSTRAINT class_schedule_time_check CHECK (end_time > start_time),
  CONSTRAINT class_schedule_dates_check CHECK (effective_to IS NULL OR effective_to >= effective_from),
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_class_schedule_class ON class_schedule (organization_id, class_id);

CREATE TRIGGER class_schedule_updated_at
  BEFORE UPDATE ON class_schedule
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE enrollment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  student_id      uuid NOT NULL,
  class_id        uuid NOT NULL,
  start_date      date NOT NULL,
  end_date        date,
  status          text NOT NULL DEFAULT 'pending',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  updated_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT enrollment_status_check CHECK (
    status IN ('pending', 'active', 'transferred', 'withdrawn', 'completed')
  ),
  CONSTRAINT enrollment_dates_check CHECK (end_date IS NULL OR end_date >= start_date),
  FOREIGN KEY (organization_id, student_id) REFERENCES student (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  CONSTRAINT enrollment_no_overlap EXCLUDE USING gist (
    organization_id WITH =,
    student_id WITH =,
    class_id WITH =,
    daterange(start_date, COALESCE(end_date, 'infinity'::date), '[)') WITH &&
  ) WHERE (status IN ('pending', 'active'))
);

CREATE INDEX idx_enrollment_student ON enrollment (organization_id, student_id, status, start_date);
CREATE INDEX idx_enrollment_class ON enrollment (organization_id, class_id, status, start_date);

CREATE TRIGGER enrollment_updated_at
  BEFORE UPDATE ON enrollment
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE class_teacher_assignment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  class_id        uuid NOT NULL,
  teacher_id      uuid NOT NULL,
  role_code       text NOT NULL DEFAULT 'primary',
  effective_from  date NOT NULL,
  effective_to    date,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT class_teacher_assignment_status_check CHECK (status IN ('active', 'ended')),
  CONSTRAINT class_teacher_assignment_role_check CHECK (role_code IN ('primary', 'assistant')),
  CONSTRAINT class_teacher_assignment_dates_check CHECK (effective_to IS NULL OR effective_to >= effective_from),
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teacher_id) REFERENCES teacher (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_class_teacher_assignment_class ON class_teacher_assignment (organization_id, class_id);

CREATE TRIGGER class_teacher_assignment_updated_at
  BEFORE UPDATE ON class_teacher_assignment
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE teaching_session (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL,
  class_id          uuid NOT NULL,
  class_schedule_id uuid REFERENCES class_schedule (id) ON DELETE SET NULL,
  teacher_id        uuid NOT NULL,
  scheduled_start_at timestamptz NOT NULL,
  scheduled_end_at   timestamptz NOT NULL,
  actual_start_at    timestamptz,
  actual_end_at      timestamptz,
  status             text NOT NULL DEFAULT 'scheduled',
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid,
  updated_by         uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT teaching_session_status_check CHECK (
    status IN ('scheduled', 'in_progress', 'completed', 'cancelled')
  ),
  CONSTRAINT teaching_session_scheduled_times_check CHECK (scheduled_end_at > scheduled_start_at),
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teacher_id) REFERENCES teacher (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_teaching_session_class_time ON teaching_session (organization_id, class_id, scheduled_start_at);
CREATE INDEX idx_teaching_session_teacher ON teaching_session (organization_id, teacher_id);

CREATE TRIGGER teaching_session_updated_at
  BEFORE UPDATE ON teaching_session
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER teaching_session_protect_teacher
  BEFORE UPDATE ON teaching_session
  FOR EACH ROW EXECUTE FUNCTION protect_completed_session_teacher();

CREATE TABLE attendance (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  teaching_session_id uuid NOT NULL,
  enrollment_id       uuid NOT NULL,
  status              text NOT NULL,
  recorded_at         timestamptz NOT NULL DEFAULT now(),
  recorded_by         uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (teaching_session_id, enrollment_id),
  CONSTRAINT attendance_status_check CHECK (
    status IN ('present', 'absent', 'late', 'excused')
  ),
  FOREIGN KEY (organization_id, teaching_session_id) REFERENCES teaching_session (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_attendance_session ON attendance (teaching_session_id);
CREATE INDEX idx_attendance_enrollment ON attendance (organization_id, enrollment_id);

CREATE TRIGGER attendance_updated_at
  BEFORE UPDATE ON attendance
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER attendance_validate_context
  BEFORE INSERT OR UPDATE ON attendance
  FOR EACH ROW EXECUTE FUNCTION validate_attendance_context();

-- =============================================================================
-- LEARNING EVIDENCE
-- =============================================================================

CREATE TABLE assessment (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL,
  class_id             uuid NOT NULL,
  assessment_type_code text NOT NULL,
  title                text NOT NULL,
  max_score            numeric(12, 2) NOT NULL,
  assessed_on          date NOT NULL,
  status               text NOT NULL DEFAULT 'draft',
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  created_by           uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT assessment_status_check CHECK (status IN ('draft', 'open', 'closed')),
  CONSTRAINT assessment_max_score_check CHECK (max_score > 0),
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_assessment_class ON assessment (organization_id, class_id);

CREATE TRIGGER assessment_updated_at
  BEFORE UPDATE ON assessment
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE assessment_result (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assessment_id   uuid NOT NULL,
  enrollment_id   uuid NOT NULL,
  raw_score       numeric(12, 2) NOT NULL,
  max_score       numeric(12, 2) NOT NULL,
  status          text NOT NULL DEFAULT 'draft',
  recorded_by     uuid,
  finalized_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (assessment_id, enrollment_id),
  CONSTRAINT assessment_result_status_check CHECK (status IN ('draft', 'finalized', 'corrected')),
  CONSTRAINT assessment_result_max_score_check CHECK (max_score > 0),
  CONSTRAINT assessment_result_raw_score_check CHECK (raw_score >= 0 AND raw_score <= max_score),
  FOREIGN KEY (organization_id, assessment_id) REFERENCES assessment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_assessment_result_enrollment ON assessment_result (organization_id, enrollment_id);

CREATE TRIGGER assessment_result_updated_at
  BEFORE UPDATE ON assessment_result
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER assessment_result_protect_finalized
  BEFORE UPDATE ON assessment_result
  FOR EACH ROW EXECUTE FUNCTION protect_finalized_assessment_result();

CREATE TABLE teacher_observation (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  enrollment_id       uuid NOT NULL,
  class_id            uuid NOT NULL,
  teacher_id          uuid NOT NULL,
  teaching_session_id uuid REFERENCES teaching_session (id) ON DELETE SET NULL,
  observed_at         timestamptz NOT NULL,
  comment             text,
  status              text NOT NULL DEFAULT 'draft',
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT teacher_observation_status_check CHECK (status IN ('draft', 'recorded', 'void')),
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teacher_id) REFERENCES teacher (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_teacher_observation_enrollment ON teacher_observation (organization_id, enrollment_id, observed_at);

CREATE TRIGGER teacher_observation_updated_at
  BEFORE UPDATE ON teacher_observation
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE observation_rating (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id        uuid NOT NULL,
  teacher_observation_id uuid NOT NULL,
  indicator_code         text NOT NULL,
  rating_code            text NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (teacher_observation_id, indicator_code),
  FOREIGN KEY (organization_id, teacher_observation_id) REFERENCES teacher_observation (organization_id, id) ON DELETE CASCADE,
  FOREIGN KEY (indicator_code) REFERENCES observation_indicator (code) ON DELETE RESTRICT,
  CONSTRAINT observation_rating_rating_check CHECK (
    rating_code IN ('low', 'medium', 'high')
  )
);

CREATE INDEX idx_observation_rating_observation ON observation_rating (teacher_observation_id);

CREATE TABLE progress_evaluation (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         uuid NOT NULL,
  enrollment_id           uuid NOT NULL,
  class_id                uuid NOT NULL,
  teacher_id              uuid NOT NULL,
  evaluation_period_start date NOT NULL,
  evaluation_period_end   date NOT NULL,
  evaluated_at            timestamptz NOT NULL,
  progress_level_code     text NOT NULL,
  improvement_code        text NOT NULL,
  summary_comment         text,
  status                  text NOT NULL DEFAULT 'draft',
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT progress_evaluation_status_check CHECK (status IN ('draft', 'finalized')),
  CONSTRAINT progress_evaluation_period_check CHECK (evaluation_period_end >= evaluation_period_start),
  CONSTRAINT progress_evaluation_progress_check CHECK (
    progress_level_code IN ('below_expectation', 'on_track', 'above_expectation')
  ),
  CONSTRAINT progress_evaluation_improvement_check CHECK (
    improvement_code IN ('declined', 'stable', 'improved', 'significantly_improved')
  ),
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teacher_id) REFERENCES teacher (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_progress_evaluation_enrollment ON progress_evaluation (organization_id, enrollment_id, evaluated_at);

CREATE TRIGGER progress_evaluation_updated_at
  BEFORE UPDATE ON progress_evaluation
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- FINANCE
-- =============================================================================

CREATE TABLE tuition_plan (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  course_id             uuid,
  class_id              uuid,
  amount                bigint NOT NULL,
  currency_code         text NOT NULL DEFAULT 'VND',
  billing_frequency_code text NOT NULL DEFAULT 'monthly',
  effective_from        date NOT NULL,
  effective_to          date,
  status                text NOT NULL DEFAULT 'active',
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT tuition_plan_amount_check CHECK (amount > 0),
  CONSTRAINT tuition_plan_status_check CHECK (status IN ('active', 'inactive', 'archived')),
  CONSTRAINT tuition_plan_dates_check CHECK (effective_to IS NULL OR effective_to >= effective_from),
  FOREIGN KEY (organization_id, course_id) REFERENCES course (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_tuition_plan_scope ON tuition_plan (organization_id, course_id, class_id, effective_from);

CREATE TRIGGER tuition_plan_updated_at
  BEFORE UPDATE ON tuition_plan
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE charge (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  student_id      uuid NOT NULL,
  enrollment_id   uuid,
  guardian_id     uuid NOT NULL,
  tuition_plan_id uuid,
  amount          bigint NOT NULL,
  currency_code   text NOT NULL DEFAULT 'VND',
  charged_at      date NOT NULL DEFAULT CURRENT_DATE,
  due_date        date,
  description     text,
  status          text NOT NULL DEFAULT 'open',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT charge_amount_check CHECK (amount > 0),
  CONSTRAINT charge_status_check CHECK (status IN ('open', 'partially_paid', 'paid', 'void')),
  FOREIGN KEY (organization_id, student_id) REFERENCES student (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, enrollment_id) REFERENCES enrollment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, guardian_id) REFERENCES guardian (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, tuition_plan_id) REFERENCES tuition_plan (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_charge_enrollment ON charge (organization_id, enrollment_id);
CREATE INDEX idx_charge_guardian_due ON charge (organization_id, guardian_id, due_date);
CREATE INDEX idx_charge_status ON charge (organization_id, status);

CREATE TRIGGER charge_updated_at
  BEFORE UPDATE ON charge
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE financial_adjustment (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL,
  charge_id            uuid NOT NULL,
  adjustment_type_code text NOT NULL,
  amount_delta         bigint NOT NULL,
  reason_code          text,
  notes                text,
  adjusted_at          timestamptz NOT NULL DEFAULT now(),
  approved_by          uuid,
  status               text NOT NULL DEFAULT 'posted',
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT financial_adjustment_type_check CHECK (
    adjustment_type_code IN ('discount', 'waiver', 'correction', 'reversal')
  ),
  CONSTRAINT financial_adjustment_status_check CHECK (status IN ('posted', 'void')),
  CONSTRAINT financial_adjustment_amount_delta_check CHECK (amount_delta <> 0),
  FOREIGN KEY (organization_id, charge_id) REFERENCES charge (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, approved_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_financial_adjustment_charge ON financial_adjustment (organization_id, charge_id);

CREATE TABLE payment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  guardian_id     uuid NOT NULL,
  amount          bigint NOT NULL,
  currency_code   text NOT NULL DEFAULT 'VND',
  paid_at         timestamptz NOT NULL DEFAULT now(),
  method_code     text NOT NULL DEFAULT 'cash',
  reference_number text,
  status          text NOT NULL DEFAULT 'posted',
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT payment_amount_check CHECK (amount > 0),
  CONSTRAINT payment_status_check CHECK (status IN ('posted', 'void')),
  FOREIGN KEY (organization_id, guardian_id) REFERENCES guardian (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_payment_guardian_date ON payment (organization_id, guardian_id, paid_at);

CREATE TABLE payment_allocation (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  payment_id      uuid NOT NULL,
  charge_id       uuid NOT NULL,
  amount          bigint NOT NULL,
  allocated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT payment_allocation_amount_check CHECK (amount > 0),
  FOREIGN KEY (organization_id, payment_id) REFERENCES payment (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, charge_id) REFERENCES charge (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_payment_allocation_charge ON payment_allocation (organization_id, charge_id);
CREATE INDEX idx_payment_allocation_payment ON payment_allocation (payment_id);

CREATE TRIGGER payment_allocation_validate_total
  AFTER INSERT OR UPDATE OR DELETE ON payment_allocation
  FOR EACH ROW EXECUTE FUNCTION validate_payment_allocations();

CREATE TABLE cost_group (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organization (id) ON DELETE RESTRICT,
  group_slot      smallint NOT NULL,
  code            text,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, group_slot),
  CONSTRAINT cost_group_slot_check CHECK (group_slot IN (1, 2)),
  CONSTRAINT cost_group_status_check CHECK (status IN ('active', 'inactive'))
);

CREATE INDEX idx_cost_group_organization ON cost_group (organization_id);

CREATE TRIGGER cost_group_updated_at
  BEFORE UPDATE ON cost_group
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Initialize both Cost B structural slots when an organization is created
CREATE TRIGGER organization_initialize_cost_groups
  AFTER INSERT ON organization
  FOR EACH ROW EXECUTE FUNCTION initialize_organization_cost_groups();

CREATE TABLE expense_category (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  cost_group_id   uuid NOT NULL,
  code            text,
  display_name    text NOT NULL,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CONSTRAINT expense_category_status_check CHECK (status IN ('active', 'inactive', 'archived')),
  FOREIGN KEY (organization_id, cost_group_id) REFERENCES cost_group (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_expense_category_group ON expense_category (organization_id, cost_group_id);

CREATE TRIGGER expense_category_updated_at
  BEFORE UPDATE ON expense_category
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER expense_category_prevent_reparent
  BEFORE UPDATE OF cost_group_id ON expense_category
  FOR EACH ROW EXECUTE FUNCTION prevent_expense_category_reparent();

CREATE TABLE expense (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL,
  expense_category_id uuid NOT NULL,
  cost_group_id       uuid NOT NULL,
  amount              bigint NOT NULL,
  currency_code       text NOT NULL DEFAULT 'VND',
  incurred_date       date NOT NULL,
  description         text,
  reference           text,
  teacher_id          uuid,
  class_id            uuid,
  status              text NOT NULL DEFAULT 'posted',
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid,
  UNIQUE (organization_id, id),
  CONSTRAINT expense_amount_check CHECK (amount > 0),
  CONSTRAINT expense_status_check CHECK (status IN ('posted', 'void')),
  FOREIGN KEY (organization_id, expense_category_id) REFERENCES expense_category (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, cost_group_id) REFERENCES cost_group (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, teacher_id) REFERENCES teacher (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, class_id) REFERENCES class (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by) REFERENCES app_user (organization_id, id) ON DELETE RESTRICT
);

CREATE INDEX idx_expense_date ON expense (organization_id, incurred_date);
CREATE INDEX idx_expense_category ON expense (organization_id, expense_category_id);
CREATE INDEX idx_expense_cost_group ON expense (organization_id, cost_group_id);

CREATE TRIGGER expense_validate_cost_group
  BEFORE INSERT OR UPDATE ON expense
  FOR EACH ROW EXECUTE FUNCTION validate_expense_cost_group();

-- =============================================================================
-- DERIVED VIEWS (verification / reporting helpers — not source of truth)
-- =============================================================================

CREATE OR REPLACE VIEW charge_balance AS
SELECT
  c.id AS charge_id,
  c.organization_id,
  c.amount
    + COALESCE((
        SELECT SUM(fa.amount_delta)
        FROM financial_adjustment fa
        WHERE fa.charge_id = c.id AND fa.status = 'posted'
      ), 0)
    - COALESCE((
        SELECT SUM(pa.amount)
        FROM payment_allocation pa
        WHERE pa.charge_id = c.id
      ), 0) AS outstanding_balance
FROM charge c
WHERE c.status <> 'void';

COMMENT ON VIEW charge_balance IS 'Derived outstanding balance per charge; not a stored source of truth.';
