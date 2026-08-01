#!/usr/bin/env bash
# Bootstrap the AI Job Search OS after `docker compose up -d`.
# Idempotent: safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

# Load .env so we can reference model names etc.
set -a; [ -f .env ] && . ./.env; set +a

echo "==> Waiting for Postgres..."
until docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1; do
  sleep 2
done

echo "==> Creating n8n database (if missing)..."
docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tc \
  "SELECT 1 FROM pg_database WHERE datname='${N8N_DB_NAME}'" | grep -q 1 || \
docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c \
  "CREATE DATABASE ${N8N_DB_NAME}"

echo "==> Pulling Ollama models (this can take a while on first run)..."
for m in "${OLLAMA_MODEL_REASONING}" "${OLLAMA_MODEL_FAST}" "${OLLAMA_MODEL_EMBED}"; do
  echo "    - ${m}"
  docker compose exec -T ollama ollama pull "${m}"
done

echo "==> Seeding ChromaDB collections..."
for c in jobs resumes knowledge_base; do
  curl -fsS -X POST "http://localhost:${CHROMA_PORT}/api/v2/tenants/default_tenant/databases/default_database/collections" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${c}\",\"get_or_create\":true}" >/dev/null && echo "    - ${c} ready" || echo "    - ${c} (already exists or v1 API)"
done

echo "==> Done. Open n8n at http://localhost:${N8N_PORT}"
echo "    Next: import workflows from ./n8n/workflows and set credentials in the n8n UI."
