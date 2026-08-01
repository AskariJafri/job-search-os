-- Seed a placeholder default resume so the pipeline is runnable end-to-end.
-- REPLACE the raw_text with your real master resume (plain text) before using.
SET search_path TO app, public;

INSERT INTO app.resumes (label, raw_text, is_default)
SELECT 'Default Resume (REPLACE ME)',
$$Jane Doe — Backend Engineer
Email: jane@example.com | Location: Remote

SUMMARY
Backend engineer with 5 years building Python/Node services, REST APIs, and
event-driven automation. Comfortable with PostgreSQL, Docker, and CI/CD.

EXPERIENCE
Acme Corp — Senior Backend Engineer (2022–present)
- Built and operated microservices handling 2M requests/day.
- Led migration to Dockerized deployments; cut deploy time 60%.

Globex — Backend Engineer (2019–2022)
- Designed PostgreSQL schemas and wrote performance-critical queries.
- Automated internal workflows, saving ~10 hours/week.

SKILLS
Python, JavaScript/Node.js, PostgreSQL, Docker, REST, n8n, Playwright, Git

EDUCATION
B.S. Computer Science$$,
true
WHERE NOT EXISTS (SELECT 1 FROM app.resumes WHERE is_default = true);
