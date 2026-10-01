# Olli M0-T04: full Supabase local verification
# Requires: Docker Desktop, npm install completed

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Set-Location $ProjectRoot

Write-Host "==> Supabase start..."
npx supabase start --ignore-health-check

function Invoke-SupabaseDbReset {
  param([int]$MaxAttempts = 3)
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "==> Supabase db reset (attempt $attempt/$MaxAttempts; seed disabled in config)..."
    npx supabase db reset
    if ($LASTEXITCODE -eq 0) { return }
    if ($attempt -lt $MaxAttempts) {
      Write-Host "==> db reset failed; restarting stack before retry..."
      npx supabase stop 2>$null
      Start-Sleep -Seconds 15
      npx supabase start --ignore-health-check
      Start-Sleep -Seconds 10
    }
  }
  throw "supabase db reset failed after $MaxAttempts attempts"
}

Invoke-SupabaseDbReset

Write-Host "==> Ensure Supabase stack is up after reset..."
npx supabase start --ignore-health-check

function Wait-LocalSupabaseAuthReady {
  Write-Host "==> Wait for Kong-routed Auth admin API after reset..."
  node (Join-Path $ProjectRoot "scripts\wait-local-supabase-auth-ready.mjs")
  if ($LASTEXITCODE -eq 0) { return }
  Write-Host "==> Auth admin still unavailable; restarting Kong and Auth containers once..."
  docker restart supabase_kong_olli-local supabase_auth_olli-local | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "docker restart supabase_kong_olli-local / supabase_auth_olli-local failed"
  }
  node (Join-Path $ProjectRoot "scripts\wait-local-supabase-auth-ready.mjs")
  if ($LASTEXITCODE -ne 0) {
    throw "Auth admin API not ready after reset (Kong-routed admin probe failed)"
  }
}

Wait-LocalSupabaseAuthReady

function Invoke-SupabaseSqlFile {
  param([string]$Path)
  $content = Get-Content -Raw -Path $Path -Encoding utf8
  $content | docker exec -i supabase_db_olli-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "psql failed: $Path" }
}

Write-Host "==> Create Auth users via GoTrue admin API..."
$seedOk = $false
for ($seedAttempt = 1; $seedAttempt -le 3; $seedAttempt++) {
  node (Join-Path $ProjectRoot "scripts\seed-auth-users.mjs")
  if ($LASTEXITCODE -eq 0) {
    $seedOk = $true
    break
  }
  if ($seedAttempt -lt 3) {
    Write-Host "==> seed-auth-users failed; re-check Auth readiness ($seedAttempt/3)..."
    Wait-LocalSupabaseAuthReady
  }
}
if (-not $seedOk) { throw "seed-auth-users.mjs failed after 3 attempts" }

Write-Host "==> Apply dev seed fixtures..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\seed.sql")

Write-Host "==> Wait for database after seed..."
Start-Sleep -Seconds 10

Write-Host "==> Supabase db lint..."
npx supabase db lint
if ($LASTEXITCODE -ne 0) { throw "supabase db lint failed" }

Write-Host "==> M0-T03 integrity tests (25)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m0_integrity_tests.sql")

Write-Host "==> M0-T04 security tests (30)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m0_security_tests.sql")

Write-Host "==> M0-T05 charge_balance tests (5)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m0_charge_balance_tests.sql")

Write-Host "==> M0-T06 locale persistence tests (6)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m0_locale_tests.sql")

Write-Host "==> M2-T02 cost domain tests (12)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_cost_domain_tests.sql")

Write-Host "==> M2-T03 capital depreciation tests (20)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_capital_depreciation_tests.sql")

Write-Host "==> M2-T04 enrollment financial tests (35)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_enrollment_financial_tests.sql")

Write-Host "==> M2-T05 payment/allocation tests (41)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_payment_allocation_tests.sql")

Write-Host "==> M2-T06 revenue recognition tests (30)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_revenue_recognition_tests.sql")

Write-Host "==> M2-T07 personnel costing tests (24)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_personnel_costing_tests.sql")

Write-Host "==> M2-T08 class cost allocation tests (35)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_class_cost_allocation_tests.sql")

Write-Host "==> M2-T09 class financial simulator tests (35)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_class_financial_simulator_tests.sql")

Write-Host "==> M2-T11 milestone acceptance tests (5)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m2_milestone_acceptance_tests.sql")

Write-Host "==> M3-T02 CRM foundation tests (29)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_crm_foundation_tests.sql")

Write-Host "==> M3-T03 lead lifecycle tests (25)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_lead_lifecycle_tests.sql")

Write-Host "==> M3-T04 lead assignment tests (27)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_lead_assignment_tests.sql")

Write-Host "==> M3-T05 lead trial tests (35)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_lead_trial_tests.sql")

Write-Host "==> M3-T06 lead identity resolution tests (40)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_lead_identity_resolution_tests.sql")

Write-Host "==> M3-T07 lead conversion tests (48)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_lead_conversion_tests.sql")

Write-Host "==> M3-T08 CRM attribution reporting tests (28)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_crm_attribution_reporting_tests.sql")

Write-Host "==> M3-T09 CRM operational workspace tests (25)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_crm_operational_workspace_tests.sql")

Write-Host "==> M3-T10 milestone acceptance tests (5)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m3_milestone_acceptance_tests.sql")

Write-Host "==> M4-T02 teacher unavailability tests (22)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_teacher_unavailability_tests.sql")

Write-Host "==> M4-T03 timetable integrity tests (26)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_timetable_integrity_tests.sql")

Write-Host "==> M4-T04 conflict detection tests (28)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_conflict_detection_tests.sql")

Write-Host "==> M4-T05 operational calendar tests (30)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_operational_calendar_tests.sql")

Write-Host "==> M4-T06 session mutation tests (44)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_session_mutation_tests.sql")

Write-Host "==> M4-T07 workload analytics tests (35)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_workload_analytics_tests.sql")

Write-Host "==> M4-T08 daily operations tests (20)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_daily_operations_tests.sql")

Write-Host "==> M4 milestone acceptance tests (8)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m4_milestone_acceptance_tests.sql")

Write-Host "==> M5-T01 foundation tests (25)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t01_foundation_tests.sql")

Write-Host "==> M5-T01.1 semantic correction tests (10)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t01_1_semantic_correction_tests.sql")

Write-Host "==> M5-T02 financial intelligence tests (28)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t02_financial_intelligence_tests.sql")

Write-Host "==> M5-T03 academic quality tests (36)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t03_academic_quality_tests.sql")

Write-Host "==> M5-T04 CRM admissions intelligence tests (30)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t04_crm_admissions_intelligence_tests.sql")

Write-Host "==> M5-T04.1 consultant conversion semantics tests (9)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t04_1_consultant_conversion_semantics_tests.sql")

Write-Host "==> M5-T05 teaching operations intelligence tests (37)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t05_teaching_operations_intelligence_tests.sql")

Write-Host "==> M5-T06 executive overview tests (32)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t06_executive_overview_tests.sql")

Write-Host "==> M5-T07 executive exception follow-up tests (40)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t07_executive_exception_follow_up_tests.sql")

Write-Host "==> M5-T08 management intelligence hardening tests (17)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_t08_hardening_tests.sql")

Write-Host "==> M5-T09 milestone acceptance tests (16)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m5_milestone_acceptance_tests.sql")

Write-Host "==> M6-T02 access foundation tests (25)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m6_t02_access_foundation_tests.sql")

Write-Host "==> M6-T03 staff provisioning tests (10)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m6_t03_staff_provisioning_tests.sql")

Write-Host "==> M6-T04 center account administration tests (10)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m6_t04_center_account_administration_tests.sql")

Write-Host "==> M6-T05 staff lifecycle tests (56)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m6_t05_staff_lifecycle_tests.sql")

Write-Host "==> M6-T06 security isolation tests (18)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m6_t06_security_isolation_tests.sql")

Write-Host "==> M7-T02 center provisioning tests (7)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m7_t02_center_provisioning_tests.sql")

Write-Host "==> M7-T03 subscription entitlement tests (18)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m7_t03_subscription_entitlement_tests.sql")

Write-Host "==> M7-T04 commercial access tests (20)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m7_t04_commercial_access_tests.sql")

Write-Host "==> M7-T05 owner subscription UX tests (6)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m7_t05_owner_subscription_status_ux_tests.sql")

Write-Host "==> M7-T06 owner onboarding center setup tests (8)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m7_t06_owner_onboarding_center_setup_tests.sql")

Write-Host "==> M7-T07 commercialization integration tests (10)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m7_t07_commercialization_integration_tests.sql")

Write-Host "==> M8-T07 rate limit tests (14)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m8_t07_rate_limit_tests.sql")

Write-Host "==> CW2-T02 domain foundation tests (18)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t02_domain_foundation_tests.sql")

Write-Host "==> CW2-T02.1 student sequence bootstrap tests (8)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t02_1_student_sequence_bootstrap_tests.sql")

Write-Host "==> CW2-T03 official student code allocator tests (25)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t03_official_student_code_allocator_tests.sql")

Write-Host "==> CW2-T04 accounting confirmation tests (42)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t04_accounting_confirmation_tests.sql")

Write-Host "==> CW2-T04.1 accountant lead-first confirmation tests (18)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t04_1_accountant_lead_first_tests.sql")

Write-Host "==> CW2-T05 consultant workspace read model tests (42)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t05_consultant_workspace_read_model_tests.sql")

Write-Host "==> CW2-T07 payment declaration drawer tests (32)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t07_payment_declaration_drawer_tests.sql")

Write-Host "==> CW2-T08 consultant monthly sales tests (30)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t08_consultant_monthly_sales_tests.sql")

Write-Host "==> CW2-T09 portfolio detail tests (30)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t09_portfolio_detail_tests.sql")

Write-Host "==> CW2-T10 milestone acceptance tests (18)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\cw2_t10_milestone_acceptance_tests.sql")

Write-Host "==> Generating TypeScript types..."
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "types") | Out-Null
npx supabase gen types typescript --local | Set-Content -Path (Join-Path $ProjectRoot "types\database.generated.ts") -Encoding utf8

if ($LASTEXITCODE -ne 0) { throw "Verification failed" }

Write-Host ""
Write-Host "SUCCESS: Supabase verification complete (includes CW2-T04.1 18/18 accountant lead-first; 25/25 integrity + 30/30 security + 5/5 charge_balance + 6/6 locale + 12/12 cost_domain + 20/20 capital_depreciation + 35/35 enrollment_financial + 41/41 payment_allocation + 30/30 revenue_recognition + 24/24 personnel_costing + 35/35 class_cost_allocation + 35/35 class_financial_simulator + 5/5 m2_milestone_acceptance + 29/29 crm_foundation + 25/25 lead_lifecycle + 27/27 lead_assignment + 35/35 lead_trial + 40/40 lead_identity_resolution + 48/48 lead_conversion + 28/28 crm_attribution_reporting + 25/25 crm_operational_workspace + 5/5 m3_milestone_acceptance + 22/22 m4_teacher_unavailability + 26/26 m4_timetable_integrity + 28/28 m4_conflict_detection + 30/30 m4_operational_calendar + 44/44 m4_session_mutation + 35/35 m4_workload_analytics + 20/20 m4_daily_operations + 8/8 m4_milestone_acceptance + 25/25 m5_t01_foundation + 10/10 m5_t01_1_semantic_correction + 28/28 m5_t02_financial_intelligence + 36/36 m5_t03_academic_quality + 30/30 m5_t04_crm_admissions_intelligence + 9/9 m5_t04_1_consultant_conversion_semantics + 37/37 m5_t05_teaching_operations_intelligence + 32/32 m5_t06_executive_overview + 40/40 m5_t07_executive_exception_follow_up + 17/17 m5_t08_hardening + 16/16 m5_milestone_acceptance + 25/25 m6_t02_access_foundation + 10/10 m6_t03_staff_provisioning + 10/10 m6_t04_center_account_administration + 56/56 m6_t05_staff_lifecycle + 18/18 m6_t06_security_isolation)."
