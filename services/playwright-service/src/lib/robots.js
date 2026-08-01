// robots.txt gate. Cached per-host. Fails OPEN only when SCRAPE_RESPECT_ROBOTS
// is false; otherwise a fetch failure is treated as "disallowed" (fail closed).
import robotsParser from 'robots-parser';
import { log } from './logger.js';

const RESPECT = (process.env.SCRAPE_RESPECT_ROBOTS || 'true') === 'true';
const UA = process.env.SCRAPE_USER_AGENT || 'JobSearchOS/1.0';
const cache = new Map();

async function loadRobots(origin) {
  if (cache.has(origin)) return cache.get(origin);
  const robotsUrl = `${origin}/robots.txt`;
  let parser;
  try {
    const res = await fetch(robotsUrl, { headers: { 'User-Agent': UA } });
    const body = res.ok ? await res.text() : '';
    parser = robotsParser(robotsUrl, body);
  } catch (err) {
    log.warn('robots fetch failed', { origin, error: String(err) });
    parser = robotsParser(robotsUrl, ''); // empty => allowed by default
  }
  cache.set(origin, parser);
  return parser;
}

export async function isAllowed(url) {
  if (!RESPECT) return true;
  try {
    const origin = new URL(url).origin;
    const parser = await loadRobots(origin);
    return parser.isAllowed(url, UA) !== false;
  } catch {
    return false; // fail closed if we can't even parse the URL
  }
}
