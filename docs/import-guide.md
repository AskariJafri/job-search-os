# Importing & wiring the workflows

The workflows in `n8n/workflows/` are plain JSON exports. After `docker compose up -d`
and `scripts/bootstrap`, import and wire them once.

## 1. Import

In the n8n UI (http://localhost:5678) → **Workflows → Import from File**, import every
`.json` under `n8n/workflows/`. Import the `00-shared/*` sub-workflows first.

## 2. Create credentials (once)

Credentials are **not** stored in the JSON (by design). Create these in
**Credentials → New**, using values from your `.env`:

| Credential | Type | Notes |
|---|---|---|
| `Postgres (jobsearch)` | Postgres | host `postgres`, db `jobsearch`, user/pass from `.env` |
| `Gmail SMTP` | SMTP | host `smtp.gmail.com`, port `465`, user = `GMAIL_ADDRESS`, pass = App Password |
| `Gmail IMAP` | IMAP | host `imap.gmail.com`, port `993`, same user + App Password |
| `Google Calendar` | Google Calendar OAuth2 | OAuth consent + client id/secret |

## 3. Attach credentials to nodes

Each Postgres node references a credential named `Postgres (jobsearch)` with a placeholder
id `REPLACE_PG_CRED`. On first open, n8n shows the node's credential dropdown — pick the
real credential you created. Same for `REPLACE_SMTP_CRED`, `REPLACE_IMAP_CRED`,
`REPLACE_GCAL_CRED`. You only do this once per credential; n8n remembers per node.

## 4. Wiring order (which workflow feeds which)

```
01 Discovery ─┐
              ▼
02 Dedup ─────► 03 Scoring/Tailor ─► 04a Draft Outreach ─► (you approve via email) ─► 04c Sender
                                                            ▲                                │
                                              04b Approval Webhook                           ▼
05a Inbox Monitor (IMAP trigger) ─► CRM ─► 05b Follow-up Scheduler                    interactions
06a Reports (daily/weekly) · 06b Interview Prep · 06c Knowledge Base
```

You can chain 01→02→03 by adding an **Execute Workflow** node at the end of each, or run
each on its own schedule (they pick up rows by `status`, so order is enforced by data,
not by triggers).

## 5. Activate

Turn on the schedule/trigger workflows: `01 Discovery`, `04c Sender`, `04b Approval
Webhook`, `05a Inbox Monitor`, `05b Follow-up Scheduler`, `06a Reports`, `06c Knowledge
Base`. Keep `02`, `03`, `04a`, `06b` manual until you've watched one full run.

## 6. Safety checks before going live

- Set `OUTREACH_REQUIRE_APPROVAL=true` (default) and confirm no outreach leaves
  `pending_approval` without you clicking the emailed link.
- Start with a **single** source in `01 Discovery` → `Load Sources`.
- Replace the seed resume: `UPDATE app.resumes SET raw_text = $$...$$ WHERE is_default;`
