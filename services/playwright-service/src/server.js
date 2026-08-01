// AI Job Search OS — Playwright scraping microservice.
// Authenticated (X-Api-Key), rate-limited, robots-aware. n8n is the only client.
import express from 'express';
import { scrapers } from './scrapers/index.js';
import { render } from './lib/browser.js';
import { isAllowed } from './lib/robots.js';
import { closeBrowser } from './lib/browser.js';
import { log } from './lib/logger.js';

const PORT = Number(process.env.PORT || 4000);
const API_KEY = process.env.API_KEY || '';

const app = express();
app.use(express.json({ limit: '2mb' }));

// ---- Auth middleware ----------------------------------------------------
app.use((req, res, next) => {
  if (req.path === '/health') return next();
  if (!API_KEY) return res.status(500).json({ error: 'API_KEY not configured' });
  if (req.get('X-Api-Key') !== API_KEY) return res.status(401).json({ error: 'unauthorized' });
  next();
});

// ---- Routes -------------------------------------------------------------
app.get('/health', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// Unified scrape endpoint: { type: 'greenhouse'|'lever'|'genericCareers', ...args }
app.post('/scrape', async (req, res) => {
  const { type, ...args } = req.body || {};
  const fn = scrapers[type];
  if (!fn) return res.status(400).json({ error: `unknown scraper '${type}'` });
  try {
    const jobs = await fn(args);
    log.info('scrape ok', { type, count: jobs.length });
    res.json({ type, count: jobs.length, jobs });
  } catch (err) {
    log.error('scrape failed', { type, error: String(err) });
    res.status(502).json({ error: String(err) });
  }
});

// Generic render: robots-gated browser fetch returning rendered text/html.
app.post('/render', async (req, res) => {
  const { url, waitForSelector } = req.body || {};
  if (!url) return res.status(400).json({ error: 'url required' });
  if (!(await isAllowed(url))) return res.status(403).json({ error: 'disallowed by robots.txt' });
  try {
    const result = await render(url, { waitForSelector });
    res.json(result);
  } catch (err) {
    log.error('render failed', { url, error: String(err) });
    res.status(502).json({ error: String(err) });
  }
});

const server = app.listen(PORT, () => log.info('playwright-service listening', { port: PORT }));

// Graceful shutdown so Chromium is always cleaned up.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    log.info('shutting down', { sig });
    server.close();
    await closeBrowser();
    process.exit(0);
  });
}
