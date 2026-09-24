/**

 * Restore Org A/B commercial + seat headroom for Playwright (dev/test only).

 */



import { execSync } from "node:child_process";



export const ORG_A = "a0000000-0000-4000-8000-000000000001";

export const ORG_B = "b0000000-0000-4000-8000-000000000001";
export const ORG_C = "c0000000-0000-4000-8000-000000000001";



export function runPsql(sql) {

  const oneLine = sql.replace(/\s+/g, " ").trim();

  execSync(

    `docker exec -i supabase_db_olli-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c ${JSON.stringify(oneLine)}`,

    { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },

  );

}



export function ensureM5T05TeacherFixture() {

  runPsql(`

    DO $$

    DECLARE

      v_org uuid := '${ORG_A}';

      v_role uuid;

      v_user uuid;

      v_auth uuid := 'e2222222-2222-4222-8222-222222222222';

      v_teacher uuid;

    BEGIN

      SELECT id INTO v_user FROM app_user WHERE email = 'm5-t05-teacher@olli.local';

      IF v_user IS NULL THEN

        SELECT id INTO v_role FROM role WHERE organization_id = v_org AND code = 'm5_t05_teacher';

        IF v_role IS NULL THEN

          INSERT INTO role (organization_id, code) VALUES (v_org, 'm5_t05_teacher') RETURNING id INTO v_role;

          INSERT INTO role_permission (role_id, permission_id)

          SELECT v_role, p.id FROM permission p

          WHERE p.code IN (

            'organization.read', 'enrollment.read', 'attendance.record', 'attendance.read', 'teacher.read'

          );

        END IF;

        INSERT INTO app_user (organization_id, email, display_name, auth_user_id, status)

        VALUES (v_org, 'm5-t05-teacher@olli.local', 'M5 T05 Teacher', v_auth, 'active')

        RETURNING id INTO v_user;

        INSERT INTO user_role (organization_id, user_id, role_id, effective_from, status)

        VALUES (v_org, v_user, v_role, CURRENT_DATE, 'active');

      END IF;

      SELECT id INTO v_teacher FROM teacher WHERE organization_id = v_org AND user_id = v_user LIMIT 1;

      IF v_teacher IS NULL THEN

        INSERT INTO teacher (organization_id, given_name, family_name, status, user_id)

        VALUES (v_org, 'M5T05', 'Linked', 'active', v_user);

      END IF;

    END $$;

  `);

}



export function cleanupEphemeralE2EStaff() {
  runPsql(`
    DO $$
    DECLARE v_org uuid;
    BEGIN
      FOREACH v_org IN ARRAY ARRAY['${ORG_A}'::uuid, '${ORG_C}'::uuid] LOOP
        DELETE FROM public.staff_lifecycle_event sle
        USING public.app_user u
        WHERE sle.organization_id = v_org
          AND u.organization_id = v_org
          AND (
            (sle.target_app_user_id = u.id OR sle.actor_app_user_id = u.id)
            AND (
              u.email LIKE 'm6-t07-%'
              OR u.email LIKE 'm6-t05-e2e-%'
              OR (
                u.email LIKE 'm6-t04-%'
                AND u.email NOT IN (
                  'm6-t04-org-c-owner@olli.local',
                  'm6-t04-accountant@olli.local',
                  'm6-t04-consultant@olli.local',
                  'm6-t04-academic-ops@olli.local'
                )
              )
            )
          );
        DELETE FROM public.staff_provisioning_request spr
        WHERE spr.organization_id = v_org
          AND (
            spr.normalized_email LIKE 'm6-t07-%'
            OR spr.normalized_email LIKE 'm6-t05-e2e-%'
            OR (
              spr.normalized_email LIKE 'm6-t04-%'
              AND spr.normalized_email NOT IN (
                'm6-t04-org-c-owner@olli.local',
                'm6-t04-accountant@olli.local',
                'm6-t04-consultant@olli.local',
                'm6-t04-academic-ops@olli.local'
              )
            )
          );
        DELETE FROM public.user_role ur
        USING public.app_user u
        WHERE ur.organization_id = v_org
          AND ur.user_id = u.id
          AND u.organization_id = v_org
          AND (
            u.email LIKE 'm6-t07-%'
            OR u.email LIKE 'm6-t05-e2e-%'
            OR (
              u.email LIKE 'm6-t04-%'
              AND u.email NOT IN (
                'm6-t04-org-c-owner@olli.local',
                'm6-t04-accountant@olli.local',
                'm6-t04-consultant@olli.local',
                'm6-t04-academic-ops@olli.local'
              )
            )
          );
        DELETE FROM public.app_user u
        WHERE u.organization_id = v_org
          AND (
            u.email LIKE 'm6-t07-%'
            OR u.email LIKE 'm6-t05-e2e-%'
            OR (
              u.email LIKE 'm6-t04-%'
              AND u.email NOT IN (
                'm6-t04-org-c-owner@olli.local',
                'm6-t04-accountant@olli.local',
                'm6-t04-consultant@olli.local',
                'm6-t04-academic-ops@olli.local'
              )
            )
          );
      END LOOP;
    END $$;
  `);
}

export function restoreFixtureOrgCommercialState() {
  cleanupEphemeralE2EStaff();

  for (const orgId of [ORG_A, ORG_B, ORG_C]) {
    runPsql(
      `UPDATE public.organization_subscription SET status = 'active', activated_at = COALESCE(activated_at, now()), suspended_at = NULL, cancelled_at = NULL WHERE organization_id = '${orgId}';`,
    );
  }

  runPsql(
    `UPDATE public.organization_entitlement SET staff_limit = 100 WHERE organization_id = '${ORG_A}';`,
  );

  ensureM5T05TeacherFixture();
}


