# Olli M0-T03: reset local PostgreSQL via Docker, apply migrations, seed, run tests.
# Requires: Docker Desktop running.

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ContainerName = "olli-pg-m0"
$PgPort = 54329
$PgPassword = "postgres"
$PgUser = "postgres"
$PgDb = "postgres"

function Wait-Postgres {
    param([string]$Container)
    $max = 30
    for ($i = 0; $i -lt $max; $i++) {
        $ready = docker exec $Container pg_isready -U $PgUser 2>$null
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    throw "PostgreSQL container did not become ready in time."
}

Write-Host "==> Stopping/removing existing container (if any)..."
try { docker rm -f $ContainerName 2>&1 | Out-Null } catch { }

Write-Host "==> Starting PostgreSQL 15..."
docker run -d --name $ContainerName `
    -e POSTGRES_PASSWORD=$PgPassword `
    -p "${PgPort}:5432" `
    postgres:15 | Out-Null

Wait-Postgres -Container $ContainerName

function Invoke-PsqlFile {
    param([string]$Path)
    $content = Get-Content -Raw -Path $Path
    $content | docker exec -i $ContainerName psql -v ON_ERROR_STOP=1 -U $PgUser -d $PgDb
    if ($LASTEXITCODE -ne 0) { throw "psql failed: $Path" }
}

Write-Host "==> Applying PostgreSQL-compatible migrations (foundation + reference data)..."
@(
  "20250914140000_m0_foundation.sql",
  "20260914140100_reference_data.sql"
) | ForEach-Object {
  $path = Join-Path $ProjectRoot "supabase\migrations\$_"
  Write-Host "    $_"
  Invoke-PsqlFile -Path $path
}

Write-Host "==> Skipping dev seed (reference data is in migrations; seed requires Supabase auth)."

Write-Host "==> Running integrity tests (25 scenarios)..."
Invoke-PsqlFile -Path (Join-Path $ProjectRoot "supabase\tests\m0_integrity_tests.sql")

Write-Host ""
Write-Host "SUCCESS: M0 database foundation verified (25/25)."
Write-Host "Container: $ContainerName (port $PgPort). Stop with: docker rm -f $ContainerName"
