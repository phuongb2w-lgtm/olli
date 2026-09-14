# Olli M0-T04: full Supabase local verification
# Requires: Docker Desktop, npm install completed

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Set-Location $ProjectRoot

Write-Host "==> Supabase start..."
npx supabase start

Write-Host "==> Supabase db reset (migrations only; seed disabled in config)..."
npx supabase db reset

function Invoke-SupabaseSqlFile {
  param([string]$Path)
  $content = Get-Content -Raw -Path $Path
  $content | docker exec -i supabase_db_olli-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "psql failed: $Path" }
}

Write-Host "==> Apply dev seed fixtures..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\seed.sql")

Write-Host "==> Supabase db lint..."
npx supabase db lint
if ($LASTEXITCODE -ne 0) { throw "supabase db lint failed" }

Write-Host "==> M0-T03 integrity tests (25)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m0_integrity_tests.sql")

Write-Host "==> M0-T04 security tests (30)..."
Invoke-SupabaseSqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m0_security_tests.sql")

Write-Host "==> Generating TypeScript types..."
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot "types") | Out-Null
npx supabase gen types typescript --local | Set-Content -Path (Join-Path $ProjectRoot "types\database.generated.ts") -Encoding utf8

if ($LASTEXITCODE -ne 0) { throw "Verification failed" }

Write-Host ""
Write-Host "SUCCESS: Supabase verification complete (25/25 integrity + 30/30 security)."
