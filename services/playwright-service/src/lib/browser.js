// One shared Chromium instance, lazily launched, reused across requests.
// Each scrape gets its own context (isolated cookies) and is always closed.
import { chromium } from 'playwright';
import { log } from './logger.js';

const UA = process.env.SCRAPE_USER_AGENT || 'JobSearchOS/1.0';
let browserPromise = null;

function getBrowser() {
  if (!browserPromise) {
    log.info('launching chromium');
    browserPromise = chromium.launch({
      headless: true,
      args: ['--no-sandbox', '--disable-dev-shm-usage'],
    });
  }
  return browserPromise;
}

// render(url, { waitForSelector, timeoutMs }) -> { html, text, title }
export async function render(url, { waitForSelector, timeoutMs = 30000 } = {}) {
  const browser = await getBrowser();
  const context = await browser.newContext({ userAgent: UA });
  const page = await context.newPage();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
    if (waitForSelector) {
      await page.waitForSelector(waitForSelector, { timeout: timeoutMs }).catch(() => {});
    }
    const html = await page.content();
    const text = await page.evaluate(() => document.body?.innerText || '');
    const title = await page.title();
    return { html, text, title };
  } finally {
    await context.close();
  }
}

export async function closeBrowser() {
  if (browserPromise) {
    const b = await browserPromise;
    await b.close();
    browserPromise = null;
  }
}
