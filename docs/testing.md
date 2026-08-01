# Testing strategy

Each module is verified before the next is built. Tests fall into four layers.

## 1. Infrastructure / smoke
- `docker compose config` — compose file is valid.
- `docker compose up -d` then `docker compose ps` — all services healthy.
- `curl localhost:4000/health` — playwright-service up.
- `curl localhost:8000/api/v2/heartbeat` — ChromaDB up.
- `docker compose exec ollama ollama list` — models present.
- `docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c '\dt app.*'` — schema applied.

## 2. Service unit tests (playwright-service)
- `npm test` in `services/playwright-service` (node:test).
- Pure helpers (`stripHtml`, `looksRemote`, rate-limiter ordering, robots gate) are
  tested without network. Scrapers are tested against recorded ATS JSON fixtures.

## 3. Workflow tests (n8n)
- Each module workflow has a **Manual Trigger** variant for dry runs.
- Sub-workflows in `00-shared` are tested in isolation with pinned input data
  (n8n "pinned data") so an LLM/DB change doesn't silently break callers.
- Idempotency: run discovery twice → row count for a fixed source is unchanged
  (proves `content_hash` dedup). Run inbox poll twice → no duplicate `interactions`.

## 4. End-to-end (per module gate)
- **M1 Discovery**: a known Greenhouse board returns > 0 jobs into `app.jobs`.
- **M2 Dedup**: inserting a near-duplicate job is flagged and not re-applied.
- **M3 Scoring/tailoring**: a tailored resume contains only facts present in the master
  resume (spot-checked + a "no new claims" LLM check); score is in 0–100.
- **M4 Outreach/approval**: an email stays `pending_approval` until the approval webhook
  is hit; only then does the sender pick it up.
- **M5 Inbox/CRM**: a test email is classified, summarized, and a follow-up row created.
- **M6 Reports/KB**: a daily report row is generated; KB semantic search returns the
  seeded application.

## Safety assertions (must always hold)
- No `outreach` row reaches `sent` without a corresponding `approved` approval.
- Outreach respects `OUTREACH_MAX_PER_DAY` and `OUTREACH_MIN_INTERVAL_MINUTES`.
- Scraper never requests a path disallowed by robots.txt when `SCRAPE_RESPECT_ROBOTS=true`.
