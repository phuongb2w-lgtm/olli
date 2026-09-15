-- M2-T02: Extend cost_group with canonical management domain codes (A, B1, B2, C).
-- Preserves existing cost_group IDs, expense.cost_group_id snapshots, and category/expense triggers.

-- =============================================================================
-- DOMAIN CODE COLUMN + BACKFILL
-- =============================================================================

ALTER TABLE cost_group
  ADD COLUMN cost_domain_code text;

COMMENT ON COLUMN cost_group.cost_domain_code IS
  'Stable management domain identity (not translated). Semantic source of truth for cost reporting.';

-- Deterministic backfill: legacy slot 1 = operating overhead (B1), slot 2 = personnel (B2).
UPDATE cost_group SET cost_domain_code = 'operating_overhead' WHERE group_slot = 1;
UPDATE cost_group SET cost_domain_code = 'personnel' WHERE group_slot = 2;

-- Add Cost A and Cost C groups for organizations that only had the legacy two slots.
INSERT INTO cost_group (organization_id, group_slot, cost_domain_code, code)
SELECT o.id, 3, 'capital', 'capital'
FROM organization o
WHERE NOT EXISTS (
  SELECT 1 FROM cost_group cg
  WHERE cg.organization_id = o.id AND cg.cost_domain_code = 'capital'
);

INSERT INTO cost_group (organization_id, group_slot, cost_domain_code, code)
SELECT o.id, 4, 'marketing_sales', 'marketing_sales'
FROM organization o
WHERE NOT EXISTS (
  SELECT 1 FROM cost_group cg
  WHERE cg.organization_id = o.id AND cg.cost_domain_code = 'marketing_sales'
);

-- Align legacy nullable code column with domain code where unset.
UPDATE cost_group SET code = cost_domain_code WHERE code IS NULL AND cost_domain_code IS NOT NULL;

ALTER TABLE cost_group
  ALTER COLUMN cost_domain_code SET NOT NULL;

ALTER TABLE cost_group
  DROP CONSTRAINT cost_group_slot_check;

ALTER TABLE cost_group
  ADD CONSTRAINT cost_group_slot_check CHECK (group_slot IN (1, 2, 3, 4));

ALTER TABLE cost_group
  ADD CONSTRAINT cost_group_domain_code_check CHECK (
    cost_domain_code IN ('capital', 'operating_overhead', 'personnel', 'marketing_sales')
  );

CREATE UNIQUE INDEX cost_group_organization_domain_unique
  ON cost_group (organization_id, cost_domain_code);

CREATE INDEX idx_cost_group_domain ON cost_group (organization_id, cost_domain_code);

-- =============================================================================
-- IMMUTABILITY: domain code must not change after creation
-- =============================================================================

CREATE OR REPLACE FUNCTION protect_cost_group_domain_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.cost_domain_code IS DISTINCT FROM NEW.cost_domain_code THEN
    RAISE EXCEPTION 'cost_domain_code is immutable; archive and create a new cost group if taxonomy changes';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER cost_group_protect_domain_code
  BEFORE UPDATE OF cost_domain_code ON cost_group
  FOR EACH ROW EXECUTE FUNCTION protect_cost_group_domain_code();

-- =============================================================================
-- EXPENSE CATEGORY: stable codes + uniqueness per org
-- =============================================================================

ALTER TABLE expense_category
  ADD CONSTRAINT expense_category_code_format_check CHECK (
    code IS NULL OR code ~ '^[a-z][a-z0-9_]*$'
  );

CREATE UNIQUE INDEX expense_category_organization_code_unique
  ON expense_category (organization_id, code)
  WHERE code IS NOT NULL;

-- =============================================================================
-- SEED CANONICAL CATEGORIES (idempotent per organization)
-- =============================================================================

CREATE OR REPLACE FUNCTION seed_organization_cost_categories(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  g_overhead uuid;
  g_personnel uuid;
  g_marketing uuid;
BEGIN
  SELECT id INTO g_overhead
  FROM cost_group
  WHERE organization_id = p_organization_id AND cost_domain_code = 'operating_overhead';

  SELECT id INTO g_personnel
  FROM cost_group
  WHERE organization_id = p_organization_id AND cost_domain_code = 'personnel';

  SELECT id INTO g_marketing
  FROM cost_group
  WHERE organization_id = p_organization_id AND cost_domain_code = 'marketing_sales';

  IF g_overhead IS NULL OR g_personnel IS NULL OR g_marketing IS NULL THEN
    RAISE EXCEPTION 'Cost taxonomy incomplete for organization %', p_organization_id;
  END IF;

  INSERT INTO expense_category (organization_id, cost_group_id, code, display_name)
  SELECT p_organization_id, g_overhead, v.code, v.display_name
  FROM (VALUES
    ('rent', 'Rent'),
    ('electricity', 'Electricity'),
    ('water', 'Water'),
    ('internet', 'Internet'),
    ('service_fees', 'Service fees'),
    ('other_operating_overhead', 'Other operating overhead')
  ) AS v(code, display_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM expense_category ec
    WHERE ec.organization_id = p_organization_id AND ec.code = v.code
  );

  INSERT INTO expense_category (organization_id, cost_group_id, code, display_name)
  SELECT p_organization_id, g_personnel, v.code, v.display_name
  FROM (VALUES
    ('teacher_compensation', 'Teacher compensation'),
    ('administrative_personnel', 'Administrative personnel'),
    ('other_personnel', 'Other personnel'),
    ('welfare_fund', 'Welfare fund')
  ) AS v(code, display_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM expense_category ec
    WHERE ec.organization_id = p_organization_id AND ec.code = v.code
  );

  INSERT INTO expense_category (organization_id, cost_group_id, code, display_name)
  SELECT p_organization_id, g_marketing, v.code, v.display_name
  FROM (VALUES
    ('advertising', 'Advertising'),
    ('marketing_campaigns', 'Marketing campaigns'),
    ('counselor_sales_salary', 'Counselor / sales salary'),
    ('sales_commission', 'Sales commission'),
    ('other_marketing_sales', 'Other marketing & sales')
  ) AS v(code, display_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM expense_category ec
    WHERE ec.organization_id = p_organization_id AND ec.code = v.code
  );
END;
$$;

-- Backfill canonical categories for all existing organizations.
DO $$
DECLARE
  org_record record;
BEGIN
  FOR org_record IN SELECT id FROM organization LOOP
    PERFORM seed_organization_cost_categories(org_record.id);
  END LOOP;
END;
$$;

-- =============================================================================
-- ORGANIZATION INITIALIZATION: four domains + baseline categories
-- =============================================================================

CREATE OR REPLACE FUNCTION initialize_organization_cost_groups()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO cost_group (organization_id, group_slot, cost_domain_code, code) VALUES
    (NEW.id, 1, 'operating_overhead', 'operating_overhead'),
    (NEW.id, 2, 'personnel', 'personnel'),
    (NEW.id, 3, 'capital', 'capital'),
    (NEW.id, 4, 'marketing_sales', 'marketing_sales');

  PERFORM seed_organization_cost_categories(NEW.id);

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION seed_organization_cost_categories(uuid) IS
  'Idempotent baseline expense categories for B1, B2, and C domains. Cost A categories deferred to M2-T03.';

COMMENT ON TABLE cost_group IS
  'Organization-owned management cost domain anchor. cost_domain_code is the canonical identity; group_slot is display order only.';
