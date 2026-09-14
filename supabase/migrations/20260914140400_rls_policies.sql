-- M0-T04: Row Level Security policies (deny-by-default via ENABLE + FORCE RLS).

-- =============================================================================
-- ENABLE RLS ON ALL EXPOSED TABLES
-- =============================================================================

ALTER TABLE organization ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization FORCE ROW LEVEL SECURITY;
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_user FORCE ROW LEVEL SECURITY;
ALTER TABLE role ENABLE ROW LEVEL SECURITY;
ALTER TABLE role FORCE ROW LEVEL SECURITY;
ALTER TABLE role_permission ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permission FORCE ROW LEVEL SECURITY;
ALTER TABLE user_role ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_role FORCE ROW LEVEL SECURITY;
ALTER TABLE permission ENABLE ROW LEVEL SECURITY;
ALTER TABLE permission FORCE ROW LEVEL SECURITY;
ALTER TABLE observation_indicator ENABLE ROW LEVEL SECURITY;
ALTER TABLE observation_indicator FORCE ROW LEVEL SECURITY;
ALTER TABLE student ENABLE ROW LEVEL SECURITY;
ALTER TABLE student FORCE ROW LEVEL SECURITY;
ALTER TABLE guardian ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian FORCE ROW LEVEL SECURITY;
ALTER TABLE student_guardian ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_guardian FORCE ROW LEVEL SECURITY;
ALTER TABLE teacher ENABLE ROW LEVEL SECURITY;
ALTER TABLE teacher FORCE ROW LEVEL SECURITY;
ALTER TABLE course ENABLE ROW LEVEL SECURITY;
ALTER TABLE course FORCE ROW LEVEL SECURITY;
ALTER TABLE class ENABLE ROW LEVEL SECURITY;
ALTER TABLE class FORCE ROW LEVEL SECURITY;
ALTER TABLE class_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_schedule FORCE ROW LEVEL SECURITY;
ALTER TABLE enrollment ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollment FORCE ROW LEVEL SECURITY;
ALTER TABLE class_teacher_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_teacher_assignment FORCE ROW LEVEL SECURITY;
ALTER TABLE teaching_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE teaching_session FORCE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance FORCE ROW LEVEL SECURITY;
ALTER TABLE assessment ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment FORCE ROW LEVEL SECURITY;
ALTER TABLE assessment_result ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_result FORCE ROW LEVEL SECURITY;
ALTER TABLE teacher_observation ENABLE ROW LEVEL SECURITY;
ALTER TABLE teacher_observation FORCE ROW LEVEL SECURITY;
ALTER TABLE observation_rating ENABLE ROW LEVEL SECURITY;
ALTER TABLE observation_rating FORCE ROW LEVEL SECURITY;
ALTER TABLE progress_evaluation ENABLE ROW LEVEL SECURITY;
ALTER TABLE progress_evaluation FORCE ROW LEVEL SECURITY;
ALTER TABLE tuition_plan ENABLE ROW LEVEL SECURITY;
ALTER TABLE tuition_plan FORCE ROW LEVEL SECURITY;
ALTER TABLE charge ENABLE ROW LEVEL SECURITY;
ALTER TABLE charge FORCE ROW LEVEL SECURITY;
ALTER TABLE financial_adjustment ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_adjustment FORCE ROW LEVEL SECURITY;
ALTER TABLE payment ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment FORCE ROW LEVEL SECURITY;
ALTER TABLE payment_allocation ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_allocation FORCE ROW LEVEL SECURITY;
ALTER TABLE cost_group ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_group FORCE ROW LEVEL SECURITY;
ALTER TABLE expense_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_category FORCE ROW LEVEL SECURITY;
ALTER TABLE expense ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense FORCE ROW LEVEL SECURITY;

-- =============================================================================
-- ORGANIZATION & ACCESS
-- =============================================================================

CREATE POLICY organization_select_same_org ON organization
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND id = public.current_organization_id()
    AND public.has_permission('organization.read')
  );

CREATE POLICY organization_update_same_org ON organization
  FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND id = public.current_organization_id()
    AND public.has_permission('organization.update')
  )
  WITH CHECK (
    id = public.current_organization_id()
  );

CREATE POLICY app_user_select ON app_user
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      id = public.current_app_user_id()
      OR public.has_permission('user.read')
    )
  );

CREATE POLICY app_user_insert ON app_user
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('user.manage')
  );

CREATE POLICY app_user_update ON app_user
  FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      (id = public.current_app_user_id())
      OR public.has_permission('user.manage')
    )
  )
  WITH CHECK (
    organization_id = public.current_organization_id()
  );

CREATE POLICY role_select ON role
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('role.read')
  );

CREATE POLICY role_insert ON role
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('role.manage')
  );

CREATE POLICY role_update ON role
  FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('role.manage')
  )
  WITH CHECK (
    organization_id = public.current_organization_id()
  );

CREATE POLICY role_permission_select ON role_permission
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND public.has_permission('role.read')
    AND EXISTS (
      SELECT 1 FROM role r
      WHERE r.id = role_permission.role_id
        AND r.organization_id = public.current_organization_id()
    )
  );

CREATE POLICY role_permission_insert ON role_permission
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND public.has_permission('role.manage')
    AND EXISTS (
      SELECT 1 FROM role r
      WHERE r.id = role_permission.role_id
        AND r.organization_id = public.current_organization_id()
    )
  );

CREATE POLICY role_permission_update ON role_permission
  FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND public.has_permission('role.manage')
    AND EXISTS (
      SELECT 1 FROM role r
      WHERE r.id = role_permission.role_id
        AND r.organization_id = public.current_organization_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM role r
      WHERE r.id = role_permission.role_id
        AND r.organization_id = public.current_organization_id()
    )
  );

CREATE POLICY user_role_select ON user_role
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND (
      user_id = public.current_app_user_id()
      OR public.has_permission('role.read')
    )
  );

CREATE POLICY user_role_insert ON user_role
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('role.manage')
  );

CREATE POLICY user_role_update ON user_role
  FOR UPDATE TO authenticated
  USING (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('role.manage')
  )
  WITH CHECK (
    organization_id = public.current_organization_id()
  );

CREATE POLICY permission_select ON permission
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND public.has_permission('permission.read')
  );

CREATE POLICY observation_indicator_select ON observation_indicator
  FOR SELECT TO authenticated
  USING (
    public.is_active_app_user()
    AND public.has_permission('observation.read')
  );

-- =============================================================================
-- GENERIC ORG-SCOPED POLICY MACRO (applied per table below)
-- read_perm / create_perm / update_perm
-- =============================================================================

CREATE POLICY student_select ON student FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('student.read'));
CREATE POLICY student_insert ON student FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('student.create'));
CREATE POLICY student_update ON student FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('student.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY guardian_select ON guardian FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('guardian.read'));
CREATE POLICY guardian_insert ON guardian FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('guardian.create'));
CREATE POLICY guardian_update ON guardian FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('guardian.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY student_guardian_select ON student_guardian FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('guardian.read'));
CREATE POLICY student_guardian_insert ON student_guardian FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('guardian.create'));
CREATE POLICY student_guardian_update ON student_guardian FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('guardian.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY teacher_select ON teacher FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('teacher.read'));
CREATE POLICY teacher_insert ON teacher FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('teacher.create'));
CREATE POLICY teacher_update ON teacher FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('teacher.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY course_select ON course FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.read'));
CREATE POLICY course_insert ON course FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.create'));
CREATE POLICY course_update ON course FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY class_select ON class FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.read'));
CREATE POLICY class_insert ON class FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.create'));
CREATE POLICY class_update ON class FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY class_schedule_select ON class_schedule FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.read'));
CREATE POLICY class_schedule_insert ON class_schedule FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.create'));
CREATE POLICY class_schedule_update ON class_schedule FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY enrollment_select ON enrollment FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.read'));
CREATE POLICY enrollment_insert ON enrollment FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.create'));
CREATE POLICY enrollment_update ON enrollment FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY class_teacher_assignment_select ON class_teacher_assignment FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.read'));
CREATE POLICY class_teacher_assignment_insert ON class_teacher_assignment FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.create'));
CREATE POLICY class_teacher_assignment_update ON class_teacher_assignment FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY teaching_session_select ON teaching_session FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.read'));
CREATE POLICY teaching_session_insert ON teaching_session FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.create'));
CREATE POLICY teaching_session_update ON teaching_session FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('enrollment.update'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY attendance_select ON attendance FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('attendance.read'));
CREATE POLICY attendance_insert ON attendance FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('attendance.record'));
CREATE POLICY attendance_update ON attendance FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('attendance.record'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY assessment_select ON assessment FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('assessment.read'));
CREATE POLICY assessment_insert ON assessment FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('assessment.create'));
CREATE POLICY assessment_update ON assessment FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('assessment.create'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY assessment_result_select ON assessment_result FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('assessment.read'));
CREATE POLICY assessment_result_insert ON assessment_result FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('assessment_result.record'));
CREATE POLICY assessment_result_update ON assessment_result FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('assessment_result.record'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY teacher_observation_select ON teacher_observation FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('observation.read'));
CREATE POLICY teacher_observation_insert ON teacher_observation FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('observation.record'));
CREATE POLICY teacher_observation_update ON teacher_observation FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('observation.record'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY observation_rating_select ON observation_rating FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('observation.read'));
CREATE POLICY observation_rating_insert ON observation_rating FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_app_user()
    AND organization_id = public.current_organization_id()
    AND public.has_permission('observation.record')
    AND EXISTS (
      SELECT 1 FROM teacher_observation o
      WHERE o.id = observation_rating.teacher_observation_id
        AND o.organization_id = public.current_organization_id()
    )
  );
CREATE POLICY observation_rating_update ON observation_rating FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('observation.record'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY progress_evaluation_select ON progress_evaluation FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('observation.read'));
CREATE POLICY progress_evaluation_insert ON progress_evaluation FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('progress_evaluation.record'));
CREATE POLICY progress_evaluation_update ON progress_evaluation FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('progress_evaluation.record'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY tuition_plan_select ON tuition_plan FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.read'));
CREATE POLICY tuition_plan_insert ON tuition_plan FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'));
CREATE POLICY tuition_plan_update ON tuition_plan FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY charge_select ON charge FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.read'));
CREATE POLICY charge_insert ON charge FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'));
CREATE POLICY charge_update ON charge FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY financial_adjustment_select ON financial_adjustment FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.read'));
CREATE POLICY financial_adjustment_insert ON financial_adjustment FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'));
CREATE POLICY financial_adjustment_update ON financial_adjustment FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('charge.create'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY payment_select ON payment FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.read'));
CREATE POLICY payment_insert ON payment FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.record'));
CREATE POLICY payment_update ON payment FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.record'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY payment_allocation_select ON payment_allocation FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.read'));
CREATE POLICY payment_allocation_insert ON payment_allocation FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.record'));
CREATE POLICY payment_allocation_update ON payment_allocation FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('payment.record'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY cost_group_select ON cost_group FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('expense.read'));

CREATE POLICY expense_category_select ON expense_category FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('expense.read'));
CREATE POLICY expense_category_insert ON expense_category FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('expense.create'));
CREATE POLICY expense_category_update ON expense_category FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('expense.create'))
  WITH CHECK (organization_id = public.current_organization_id());

CREATE POLICY expense_select ON expense FOR SELECT TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('expense.read'));
CREATE POLICY expense_insert ON expense FOR INSERT TO authenticated
  WITH CHECK (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('expense.create'));
CREATE POLICY expense_update ON expense FOR UPDATE TO authenticated
  USING (public.is_active_app_user() AND organization_id = public.current_organization_id() AND public.has_permission('expense.create'))
  WITH CHECK (organization_id = public.current_organization_id());
