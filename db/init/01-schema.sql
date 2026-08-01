-- =============================================================================
-- AI Job Search OS — application schema
-- Runs once on first Postgres boot (docker-entrypoint-initdb.d).
-- The n8n database itself is created separately (see scripts/bootstrap.sh).
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;          -- fuzzy text search for the CRM

CREATE SCHEMA IF NOT EXISTS app;
SET search_path TO app, public;

-- ---- Enums --------------------------------------------------------------
CREATE TYPE job_status      AS ENUM ('discovered','deduped','scored','parked','tailoring','ready','applied','rejected','archived');
CREATE TYPE app_status      AS ENUM ('draft','ready','submitted','interviewing','offer','rejected','withdrawn');
CREATE TYPE outreach_status AS ENUM ('draft','pending_approval','approved','queued','sent','failed','cancelled');
CREATE TYPE approval_status AS ENUM ('pending','approved','rejected','expired');
CREATE TYPE direction       AS ENUM ('inbound','outbound');
CREATE TYPE followup_status AS ENUM ('scheduled','done','snoozed','cancelled');

-- ---- Resumes (source of truth for tailoring) ---------------------------
CREATE TABLE resumes (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  label         TEXT NOT NULL,                 -- e.g. "Backend Engineer 2026"
  raw_text      TEXT NOT NULL,                 -- plain-text master resume
  structured    JSONB NOT NULL DEFAULT '{}',   -- parsed: skills, roles, achievements
  is_default    BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- Companies ---------------------------------------------------------
CREATE TABLE companies (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          TEXT NOT NULL,
  domain        TEXT,
  careers_url   TEXT,
  industry      TEXT,
  size          TEXT,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (name, domain)
);

-- ---- Jobs --------------------------------------------------------------
CREATE TABLE jobs (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  source        TEXT NOT NULL,                 -- 'greenhouse','lever','indeed','careers',...
  source_job_id TEXT,                          -- id at the source, if any
  title         TEXT NOT NULL,
  company_id    UUID REFERENCES companies(id),
  company_name  TEXT NOT NULL,                 -- denormalized for discovery speed
  location      TEXT,
  remote        BOOLEAN,
  url           TEXT NOT NULL,
  description   TEXT,
  raw           JSONB NOT NULL DEFAULT '{}',
  content_hash  TEXT NOT NULL,                 -- sha256(normalized title+company+desc) for exact dedup
  embedding_id  TEXT,                          -- id of vector in ChromaDB 'jobs' collection
  status        job_status NOT NULL DEFAULT 'discovered',
  discovered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (content_hash)
);
CREATE INDEX jobs_status_idx   ON jobs (status);
CREATE INDEX jobs_company_idx  ON jobs (company_name);
CREATE INDEX jobs_title_trgm   ON jobs USING gin (title gin_trgm_ops);

-- ---- Scores (one job can be scored against multiple resumes) ------------
CREATE TABLE job_scores (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id        UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  resume_id     UUID NOT NULL REFERENCES resumes(id) ON DELETE CASCADE,
  score         NUMERIC(5,2) NOT NULL,         -- 0-100
  breakdown     JSONB NOT NULL DEFAULT '{}',   -- {skills_match, experience_match, ...}
  reasoning     TEXT,
  model         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (job_id, resume_id)
);

-- ---- Applications ------------------------------------------------------
CREATE TABLE applications (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id              UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  resume_id           UUID NOT NULL REFERENCES resumes(id),
  tailored_resume_path TEXT,                   -- file under /data/storage
  cover_letter_path   TEXT,
  status              app_status NOT NULL DEFAULT 'draft',
  submitted_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (job_id, resume_id)
);

-- ---- Recruiters (CRM contacts) -----------------------------------------
CREATE TABLE recruiters (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  full_name     TEXT,
  email         TEXT,
  company_id    UUID REFERENCES companies(id),
  company_name  TEXT,
  title         TEXT,
  linkedin_url  TEXT,
  source        TEXT,                          -- where the contact was found (public source)
  confidence    NUMERIC(4,2) DEFAULT 0.5,      -- 0-1 confidence the email is correct
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (email)
);
CREATE INDEX recruiters_name_trgm ON recruiters USING gin (full_name gin_trgm_ops);

-- ---- Outreach (emails generated for recruiters) ------------------------
CREATE TABLE outreach (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  application_id UUID REFERENCES applications(id) ON DELETE SET NULL,
  recruiter_id  UUID REFERENCES recruiters(id) ON DELETE SET NULL,
  subject       TEXT NOT NULL,
  body          TEXT NOT NULL,
  status        outreach_status NOT NULL DEFAULT 'draft',
  approved_at   TIMESTAMPTZ,
  queued_at     TIMESTAMPTZ,
  sent_at       TIMESTAMPTZ,
  error         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX outreach_status_idx ON outreach (status);

-- ---- Interactions (full conversation history per recruiter) ------------
CREATE TABLE interactions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recruiter_id    UUID REFERENCES recruiters(id) ON DELETE SET NULL,
  application_id  UUID REFERENCES applications(id) ON DELETE SET NULL,
  outreach_id     UUID REFERENCES outreach(id) ON DELETE SET NULL,
  direction       direction NOT NULL,
  channel         TEXT NOT NULL DEFAULT 'email',
  message_id      TEXT,                        -- email Message-ID for threading/idempotency
  subject         TEXT,
  body            TEXT,
  summary         TEXT,                        -- AI summary
  classification  TEXT,                        -- 'interview_request','rejection','info_request',...
  sentiment       TEXT,                        -- 'positive','neutral','negative'
  suggested_reply TEXT,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id)
);
CREATE INDEX interactions_recruiter_idx ON interactions (recruiter_id);

-- ---- Follow-ups (scheduled, mirrored to Google Calendar) ---------------
CREATE TABLE followups (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recruiter_id      UUID REFERENCES recruiters(id) ON DELETE CASCADE,
  application_id    UUID REFERENCES applications(id) ON DELETE CASCADE,
  due_at            TIMESTAMPTZ NOT NULL,
  kind              TEXT NOT NULL DEFAULT 'nudge',
  status            followup_status NOT NULL DEFAULT 'scheduled',
  calendar_event_id TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX followups_due_idx ON followups (due_at) WHERE status = 'scheduled';

-- ---- Approvals (human-in-the-loop gate for risky actions) --------------
CREATE TABLE approvals (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type   TEXT NOT NULL,                 -- 'outreach','application',...
  entity_id     UUID NOT NULL,
  action        TEXT NOT NULL,                 -- 'send_email','submit_application',...
  payload       JSONB NOT NULL DEFAULT '{}',
  status        approval_status NOT NULL DEFAULT 'pending',
  token         TEXT NOT NULL DEFAULT uuid_generate_v4(),  -- used in approve/reject webhook links
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at    TIMESTAMPTZ
);
CREATE INDEX approvals_status_idx ON approvals (status);
CREATE UNIQUE INDEX approvals_token_idx ON approvals (token);

-- ---- Interview prep packages -------------------------------------------
CREATE TABLE interview_prep (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  application_id  UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
  package         JSONB NOT NULL,              -- company research, likely Qs, talking points
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- Reports (daily/weekly snapshots) ----------------------------------
CREATE TABLE reports (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  period        TEXT NOT NULL,                 -- 'daily' | 'weekly'
  generated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  payload       JSONB NOT NULL
);

-- ---- Structured logs (every workflow writes here) ----------------------
CREATE TABLE logs (
  id            BIGSERIAL PRIMARY KEY,
  ts            TIMESTAMPTZ NOT NULL DEFAULT now(),
  workflow      TEXT NOT NULL,
  module        TEXT,
  level         TEXT NOT NULL DEFAULT 'info',
  message       TEXT NOT NULL,
  context       JSONB NOT NULL DEFAULT '{}',
  execution_id  TEXT
);
CREATE INDEX logs_ts_idx       ON logs (ts DESC);
CREATE INDEX logs_workflow_idx ON logs (workflow, level);

-- ---- updated_at trigger for applications -------------------------------
CREATE OR REPLACE FUNCTION app.touch_updated_at() RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER applications_touch
  BEFORE UPDATE ON applications
  FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
