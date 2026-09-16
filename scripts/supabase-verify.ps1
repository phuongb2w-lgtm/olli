# Olli M0-T04: full Supabase local verification
# Requires: Docker Desktop, npm install completed

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Set-Location $ProjectRoot

Write-Host "==> Supabase start..."
npx supabase start --ignore-health-check

Write-Host "==> Supabase db reset (migrations only; seed disabled in config)..."
npx supabase db reset

function Invoke-SupabaseSqlFile {
  param([string]$Path)
  $content = Get-Content -Raw -Path $Path -Encoding utf8
  $content | docker exec -i supabase_db_olli-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "psql failed: $Path" }
}

Write-Host "==> Create Auth users via GoTrue admin API..."
node (Join-Path $ProjectRoot "scripts\seed-auth-users.mjs")
if ($LASTEXITCODE -ne 0) { throw "seed-auth-users.mjs failed" }

Write-Host "==> Apply dev seed fixtures..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\seed.sql")

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

Write-Host "==> Generating TypeScript types..."
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "types") | Out-Null
npx supabase gen types typescript --local | Set-Content -Path (Join-Path $ProjectRoot "types\database.generated.ts") -Encoding utf8

if ($LASTEXITCODE -ne 0) { throw "Verification failed" }

Write-Host ""
Write-Host "SUCCESS: Supabase verification complete (25/25 integrity + 30/30 security + 5/5 charge_balance + 6/6 locale + 12/12 cost_domain + 20/20 capital_depreciation + 35/35 enrollment_financial + 41/41 payment_allocation + 30/30 revenue_recognition + 24/24 personnel_costing + 35/35 class_cost_allocation + 35/35 class_financial_simulator + 5/5 milestone_acceptance + 29/29 crm_foundation + 25/25 lead_lifecycle)."
