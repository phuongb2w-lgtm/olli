-- M0-T04: Production-safe reference data (idempotent).
-- Available after migrations without requiring seed.sql in production.

INSERT INTO permission (code) VALUES
  ('organization.read'),
  ('organization.update'),
  ('permission.read'),
  ('user.read'),
  ('user.manage'),
  ('role.read'),
  ('role.manage'),
  ('student.create'),
  ('student.read'),
  ('student.update'),
  ('guardian.create'),
  ('guardian.read'),
  ('guardian.update'),
  ('teacher.create'),
  ('teacher.read'),
  ('teacher.update'),
  ('enrollment.create'),
  ('enrollment.read'),
  ('enrollment.update'),
  ('attendance.record'),
  ('attendance.read'),
  ('assessment.create'),
  ('assessment.read'),
  ('assessment_result.record'),
  ('observation.record'),
  ('observation.read'),
  ('progress_evaluation.record'),
  ('charge.create'),
  ('charge.read'),
  ('payment.record'),
  ('payment.read'),
  ('expense.create'),
  ('expense.read'),
  ('report.read')
ON CONFLICT (code) DO NOTHING;

INSERT INTO observation_indicator (code) VALUES
  ('concentration'),
  ('engagement'),
  ('participation')
ON CONFLICT (code) DO NOTHING;
