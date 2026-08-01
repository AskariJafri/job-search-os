# AI Job Search OS

A **completely free, self-hosted AI Job Search Operating System**. It discovers jobs,
scores them against your resume, tailors applications truthfully, finds recruiter
contacts from public sources, drafts outreach for your approval, monitors your inbox,
tracks every interaction in a CRM, schedules follow-ups, and produces reports — all
running locally with Docker and local LLMs. **No paid APIs required.**

> Built with: n8n · PostgreSQL · Ollama · ChromaDB · Playwright · Gmail IMAP/SMTP ·
> Google Calendar · Docker

## What it does

1. Searches multiple job boards and company career pages
2. Removes duplicate jobs (exact hash + semantic similarity)
3. Scores each job against your resume
4. Tailors your resume — **truthfully**, never inventing experience
5. Generates customized cover letters
6. Finds recruiter contacts from legitimate public sources
7. Generates personalized outreach emails
8. **Queues every email for your approval before sending**
9. Monitors your inbox continuously
10. Classifies replies, summarizes them, suggests the best response
11. Tracks every recruiter interaction in a searchable CRM
12. Schedules follow-ups automatically (Google Calendar)
13. Produces daily and weekly reports
14. Builds interview-prep packages and a knowledge base

## Quick start

```bash
cp .env.example .env          # then edit secrets (see notes below)
docker compose up -d          # start postgres, ollama, chromadb, playwright, n8n
./scripts/bootstrap.sh        # create n8n db, pull Ollama models, seed Chroma
#   (Windows: pwsh ./scripts/bootstrap.ps1)
```

Open n8n at <http://localhost:5678> (basic-auth from `.env`), import the workflows from
`n8n/workflows/`, and set up credentials (Postgres, Gmail, Google Calendar) in the n8n UI.

### Before you start — required setup

- **Gmail**: enable 2FA and create an *App Password*; put it in `GMAIL_APP_PASSWORD`.
- **n8n encryption key**: `openssl rand -hex 32` → `N8N_ENCRYPTION_KEY`.
- **Playwright API key**: any random string → `PLAYWRIGHT_API_KEY`.
- **Ollama models**: defaults are `llama3.1:8b` (reasoning), `llama3.2:3b` (fast),
  `nomic-embed-text` (embeddings). Change in `.env`; a GPU is strongly recommended.
- **Google Calendar**: configured via OAuth2 in the n8n credentials UI.

## Repository layout

```
.
├── docker-compose.yml          # the whole stack
├── .env.example                # all configuration
├── db/init/01-schema.sql       # Postgres application schema
├── services/playwright-service # scraping microservice (ATS APIs + Playwright)
├── n8n/workflows/              # exported, importable workflows
│   ├── 00-shared/              # reusable sub-workflows (Ollama, Chroma, log, error)
│   └── NN-<module>/            # one folder per module
├── config/sources.example.yml  # which boards/companies to discover from
├── scripts/                    # bootstrap + helpers
└── docs/                       # architecture, testing, module notes
```

## Safety & ethics

- **Nothing outbound sends without your approval.** Enforced in the DB and workflows.
- **Truthful tailoring only.** The master resume is the only source of facts.
- **Respectful scraping.** robots.txt is honored, requests are rate-limited per host,
  and official free APIs are preferred over browser rendering.
- **Rate limits** on outreach (`OUTREACH_MAX_PER_DAY`, min interval) to avoid spam.

## Status

Built incrementally, one module at a time. See `docs/architecture.md` for the module map
and the task list for current progress.

## Security note

Do **not** commit secrets. `.env` and any `*_key.txt` / `*_token.txt` files are
git-ignored. The loose `claude_key.txt`, `huggingface_token.txt`, and `context_7_key.txt`
files in this folder are **not used** by the system (it is fully Ollama-based) and should
be deleted or rotated if they contain real keys.
```
