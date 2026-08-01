# Bootstrap the AI Job Search OS after `docker compose up -d` (Windows / PowerShell).
# Idempotent: safe to re-run.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

# Load .env
$envVars = @{}
if (Test-Path ".env") {
  Get-Content ".env" | Where-Object { $_ -match "^\s*[^#].*=" } | ForEach-Object {
    $k, $v = $_ -split "=", 2
    $envVars[$k.Trim()] = $v.Trim()
  }
}
function E($k) { return $envVars[$k] }

Write-Host "==> Waiting for Postgres..."
do {
  $ready = docker compose exec -T postgres pg_isready -U $(E 'POSTGRES_USER') 2>$null
  if (-not ($ready -match "accepting")) { Start-Sleep -Seconds 2 }
} until ($ready -match "accepting")

Write-Host "==> Creating n8n database (if missing)..."
$exists = docker compose exec -T postgres psql -U $(E 'POSTGRES_USER') -d $(E 'POSTGRES_DB') -tc "SELECT 1 FROM pg_database WHERE datname='$(E 'N8N_DB_NAME')'"
if (-not ($exists -match "1")) {
  docker compose exec -T postgres psql -U $(E 'POSTGRES_USER') -d $(E 'POSTGRES_DB') -c "CREATE DATABASE $(E 'N8N_DB_NAME')"
}

Write-Host "==> Pulling Ollama models..."
foreach ($m in @($(E 'OLLAMA_MODEL_REASONING'), $(E 'OLLAMA_MODEL_FAST'), $(E 'OLLAMA_MODEL_EMBED'))) {
  Write-Host "    - $m"
  docker compose exec -T ollama ollama pull $m
}

Write-Host "==> Seeding ChromaDB collections..."
foreach ($c in @("jobs", "resumes", "knowledge_base")) {
  try {
    Invoke-RestMethod -Method Post -Uri "http://localhost:$(E 'CHROMA_PORT')/api/v2/tenants/default_tenant/databases/default_database/collections" `
      -ContentType "application/json" -Body "{`"name`":`"$c`",`"get_or_create`":true}" | Out-Null
    Write-Host "    - $c ready"
  } catch { Write-Host "    - $c (already exists or v1 API)" }
}

Write-Host "==> Done. Open n8n at http://localhost:$(E 'N8N_PORT')"
