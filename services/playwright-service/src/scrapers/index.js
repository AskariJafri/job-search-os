// Uniform job shape returned by every scraper:
//   { source, source_job_id, title, company_name, location, remote, url, description }
import { schedule } from '../lib/rateLimiter.js';
import { isAllowed } from '../lib/robots.js';
import { render } from '../lib/browser.js';
import { log } from '../lib/logger.js';

const UA = process.env.SCRAPE_USER_AGENT || 'JobSearchOS/1.0';

function stripHtml(html = '') {
  return html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}
function looksRemote(s = '') { return /remote|anywhere|distributed/i.test(s); }

// ---- Greenhouse (free public ATS API) ----------------------------------
// board = the company token, e.g. "stripe" for boards.greenhouse.io/stripe
export async function greenhouse({ board }) {
  const url = `https://boards-api.greenhouse.io/v1/boards/${board}/jobs?content=true`;
  return schedule(url, async () => {
    const res = await fetch(url, { headers: { 'User-Agent': UA } });
    if (!res.ok) throw new Error(`greenhouse ${board}: HTTP ${res.status}`);
    const data = await res.json();
    return (data.jobs || []).map((j) => ({
      source: 'greenhouse',
      source_job_id: String(j.id),
      title: j.title,
      company_name: board,
      location: j.location?.name || null,
      remote: looksRemote(j.location?.name),
      url: j.absolute_url,
      description: stripHtml(j.content || ''),
    }));
  });
}

// ---- Lever (free public ATS API) ---------------------------------------
// company = the Lever token, e.g. "netflix" for jobs.lever.co/netflix
export async function lever({ company }) {
  const url = `https://api.lever.co/v0/postings/${company}?mode=json`;
  return schedule(url, async () => {
    const res = await fetch(url, { headers: { 'User-Agent': UA } });
    if (!res.ok) throw new Error(`lever ${company}: HTTP ${res.status}`);
    const data = await res.json();
    return (data || []).map((j) => ({
      source: 'lever',
      source_job_id: j.id,
      title: j.text,
      company_name: company,
      location: j.categories?.location || null,
      remote: looksRemote(j.categories?.location || j.workplaceType),
      url: j.hostedUrl,
      description: stripHtml(j.descriptionPlain || j.description || ''),
    }));
  });
}

// ---- Generic career page (Playwright) ----------------------------------
// Renders the page (robots-gated), then extracts job links by a CSS selector.
// linkSelector defaults to anchors whose text/href hints at a job posting.
export async function genericCareers({ url, company_name, linkSelector }) {
  if (!(await isAllowed(url))) {
    log.warn('blocked by robots.txt', { url });
    return [];
  }
  return schedule(url, async () => {
    const { text } = await render(url, { waitForSelector: linkSelector });
    // Extraction of structured links is delegated to a second render call so
    // callers can pass a precise selector; here we return the rendered text
    // plus discovered links for downstream LLM/regex parsing in n8n.
    return [{
      source: 'careers',
      source_job_id: null,
      title: null,
      company_name: company_name || new URL(url).host,
      location: null,
      remote: null,
      url,
      description: text.slice(0, 20000),
    }];
  });
}

export const scrapers = { greenhouse, lever, genericCareers };
