import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const devices = {
  'mobile' : { width: 390, height: 844 },
  'tablet' : { width: 768, height: 1024 },
  'desktop' : { width: 1440, height: 900 },
};

function writeJson(obj) {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
}

function isNonEmptyString(val) {
  return typeof val === 'string' && val.trim().length > 0;
}

function ensureOutputDir(filePath) {
  const dir = path.dirname(filePath);
  if (!dir || dir === '.') return;
  fs.mkdirSync(dir, { recursive: true });
}

function clamp(num, min, max) {
  return Math.max(min, Math.min(max, num));
}

function parseInput() {
  const raw = fs.readFileSync(0, 'utf8');
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function main() {
  const input = parseInput();
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    console.error('Invalid JSON input (expected an object)');
    writeJson({ status: 'fail', reason: 'invalid_json' });
    process.exitCode = 1;
    return;
  }

  const {
    url,
    device,
    selector,
    output,
    headless = true,
    timeoutMs = 15000,
    waitUntil = 'networkidle',
    fullPage = false,
    minPadding = 360,
    maxPadding = 900,
    purpose,
  } = input;

  if (!isNonEmptyString(url) || !isNonEmptyString(device) || !isNonEmptyString(selector) || !isNonEmptyString(output)) {
    console.error('Missing required fields: url, device, selector, output');
    writeJson({ status: 'fail', reason: 'missing_required_fields', url, device, selector, output });
    process.exitCode = 1;
    return;
  }

  const viewport = devices[device];
  if (!viewport) {
    console.error(`Unknown device: ${device}`);
    writeJson({ status: 'fail', reason: 'unknown_device', device, allowedDevices: Object.keys(devices) });
    process.exitCode = 1;
    return;
  }

  const allowedWaitUntil = new Set(['commit', 'domcontentloaded', 'load', 'networkidle']);
  if (!allowedWaitUntil.has(waitUntil)) {
    console.error(`Invalid waitUntil: ${waitUntil}`);
    writeJson({ status: 'fail', reason: 'invalid_waitUntil', waitUntil, allowed: Array.from(allowedWaitUntil) });
    process.exitCode = 1;
    return;
  }

  const minPaddingNum = Number(minPadding);
  const maxPaddingNum = Number(maxPadding);
  if (!Number.isFinite(minPaddingNum) || !Number.isFinite(maxPaddingNum) || minPaddingNum <= 0 || maxPaddingNum <= 0) {
    console.error('Invalid minPadding/maxPadding (expected positive numbers)');
    writeJson({ status: 'fail', reason: 'invalid_padding', minPadding, maxPadding });
    process.exitCode = 1;
    return;
  }
  if (minPaddingNum > maxPaddingNum) {
    console.error('Invalid minPadding/maxPadding (minPadding must be <= maxPadding)');
    writeJson({ status: 'fail', reason: 'invalid_padding_range', minPadding: minPaddingNum, maxPadding: maxPaddingNum });
    process.exitCode = 1;
    return;
  }

  let browser;
  try {
    ensureOutputDir(output);

    browser = await chromium.launch({ headless: Boolean(headless) });
    const page = await browser.newPage({ viewport });

    page.setDefaultTimeout(Number(timeoutMs) || 15000);
    page.setDefaultNavigationTimeout(Number(timeoutMs) || 15000);
    await page.emulateMedia({ reducedMotion: 'reduce' });

    await page.goto(url, { waitUntil });

    // Reduce flakiness/jitter in screenshots.
    await page.addStyleTag({
      content: `
        *,
        *::before,
        *::after {
          animation: none !important;
          transition: none !important;
          caret-color: transparent !important;
        }
        html { scroll-behavior: auto !important; }
        [data-cursor-shot="1"] {
          outline: 3px solid rgba(255, 0, 128, 0.85) !important;
          outline-offset: 2px !important;
        }
      `,
    });

    const locator = page.locator(selector).first();
    await locator.waitFor({ state: 'visible' });
    await locator.scrollIntoViewIfNeeded();
    await locator.evaluate((el) => el.setAttribute('data-cursor-shot', '1'));

    if (fullPage) {
      await page.screenshot({ path: output, fullPage: true });
    } else {
      const box = await locator.boundingBox();
      if (!box) throw new Error(`Could not compute bounding box for selector: ${selector}`);

      const minDim = Math.min(viewport.width, viewport.height);
      const shotSize = clamp(minDim, minPaddingNum, maxPaddingNum);

      const cx = box.x + box.width / 2;
      const cy = box.y + box.height / 2;
      const half = shotSize / 2;

      const doc = await page.evaluate(() => ({
        width: document.documentElement.scrollWidth,
        height: document.documentElement.scrollHeight,
      }));

      const x = clamp(cx - half, 0, Math.max(0, doc.width - shotSize));
      const y = clamp(cy - half, 0, Math.max(0, doc.height - shotSize));

      const clip = {
        x,
        y,
        width: Math.min(shotSize, doc.width - x),
        height: Math.min(shotSize, doc.height - y),
      };

      await page.screenshot({ path: output, clip });
    }

    writeJson({
      status: 'ok',
      ...(isNonEmptyString(purpose) ? { purpose: purpose.trim() } : {}),
      url,
      device,
      selector,
      viewport,
      output,
      fullPage: Boolean(fullPage),
      minPadding: minPaddingNum,
      maxPadding: maxPaddingNum,
      timeoutMs: Number(timeoutMs) || 15000,
      waitUntil,
    });
    process.exitCode = 0;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(message);
    writeJson({
      status: 'fail',
      reason: 'runtime_error',
      message,
      url,
      device,
      selector,
      output,
    });
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
}

await main();
