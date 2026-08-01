// Respectful scraping: cap global concurrency AND enforce a minimum delay
// between requests to the same host. Keeps us a polite, low-impact crawler.
const MIN_DELAY = Number(process.env.SCRAPE_MIN_DELAY_MS || 2500);
const MAX_CONCURRENCY = Number(process.env.SCRAPE_MAX_CONCURRENCY || 2);

let active = 0;
const queue = [];
const lastHitByHost = new Map();

function hostOf(url) {
  try { return new URL(url).host; } catch { return 'unknown'; }
}

function next() {
  if (active >= MAX_CONCURRENCY || queue.length === 0) return;
  const { url, run, resolve, reject } = queue.shift();
  active++;
  const host = hostOf(url);
  const since = Date.now() - (lastHitByHost.get(host) || 0);
  const wait = Math.max(0, MIN_DELAY - since);
  setTimeout(async () => {
    try {
      lastHitByHost.set(host, Date.now());
      resolve(await run());
    } catch (err) {
      reject(err);
    } finally {
      active--;
      next();
    }
  }, wait);
}

// schedule(url, () => doWork()) -> Promise, throttled per-host + globally.
export function schedule(url, run) {
  return new Promise((resolve, reject) => {
    queue.push({ url, run, resolve, reject });
    next();
  });
}
