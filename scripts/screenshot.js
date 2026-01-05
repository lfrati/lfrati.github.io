import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright';

const devices = {
  'mobile' : { width: 390, height: 844 },
  'tablet' : { width: 768, height: 1024 },
  'desktop' : { width: 1440, height: 900 },
};

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ARTIFACTS_DIR = path.resolve(SCRIPT_DIR, 'artifacts');

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

function toBool(val) {
  if (typeof val === 'boolean') return val;
  if (typeof val === 'number') return val !== 0;
  if (!isNonEmptyString(val)) return false;
  const s = val.trim().toLowerCase();
  if (['true', '1', 'yes', 'y', 'on'].includes(s)) return true;
  if (['false', '0', 'no', 'n', 'off'].includes(s)) return false;
  return Boolean(val);
}

function normalizeKey(key) {
  return String(key).replace(/^-+/, '').trim();
}

function parseCliArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg) continue;

    // End-of-options delimiter (we don't support positionals, so just skip it)
    if (arg === '--') continue;

    // Short flags we care about
    if (arg === '-h') out.help = true;
    if (arg === '-u') out.url = argv[++i];
    if (arg === '-d') out.device = argv[++i];
    if (arg === '-s') out.selector = argv[++i];
    if (arg === '-o') out.output = argv[++i];

    if (!arg.startsWith('--')) continue;

    const eq = arg.indexOf('=');
    const rawKey = normalizeKey(eq >= 0 ? arg.slice(0, eq) : arg);
    const key = rawKey.startsWith('no-') ? rawKey.slice(3) : rawKey;
    const isNegated = rawKey.startsWith('no-');

    let value;
    if (eq >= 0) {
      value = arg.slice(eq + 1);
    } else if (isNegated) {
      value = false;
    } else {
      const next = argv[i + 1];
      if (next != null && !String(next).startsWith('-')) {
        value = next;
        i++;
      } else {
        value = true;
      }
    }

    out[key] = value;
  }

  // Friendly aliases
  if (out['full-page'] != null && out.fullPage == null) out.fullPage = out['full-page'];
  if (out['wait-until'] != null && out.waitUntil == null) out.waitUntil = out['wait-until'];
  if (out['timeout-ms'] != null && out.timeoutMs == null) out.timeoutMs = out['timeout-ms'];
  if (out['min-padding'] != null && out.minPadding == null) out.minPadding = out['min-padding'];
  if (out['max-padding'] != null && out.maxPadding == null) out.maxPadding = out['max-padding'];

  // --headed is a common convention
  if (out.headed === true) out.headless = false;

  return out;
}

function printUsage() {
  const msg = `
Usage:
  npm run shot -- --url <URL> --device <mobile|tablet|desktop> --selector <CSS> --output <FILENAME.png> [options]

Required:
  -u, --url        Absolute URL (usually under http://localhost:1313)
  -d, --device     mobile | tablet | desktop
  -s, --selector   CSS selector for the element to screenshot
  -o, --output     Filename only (no path). Saved under scripts/artifacts/

Options:
      --fullPage | --no-fullPage
      --minPadding <num>   (default 360)
      --maxPadding <num>   (default 900)
      --timeoutMs <num>    (default 15000)
      --waitUntil <commit|domcontentloaded|load|networkidle> (default networkidle)
      --headless <bool>    (default true)
      --headed             (alias for --headless=false)
  -h, --help

Notes:
  - Input via stdin JSON is deprecated; prefer CLI flags.
`.trim();
  process.stderr.write(`${msg}\n`);
}

function parseInput() {
  const raw = fs.readFileSync(0, 'utf8');
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function resolveOutputPath(output) {
  if (!isNonEmptyString(output)) return null;

  let filename = output.trim();
  if (!filename.toLowerCase().endsWith('.png')) filename = `${filename}.png`;

  // Enforce filename-only (no path traversal, no separators)
  if (filename !== path.basename(filename) || /[\\/]/.test(filename) || filename.includes('..')) {
    return { error: 'output_must_be_filename_only', filename };
  }

  const outputPath = path.join(ARTIFACTS_DIR, filename);
  return { filename, outputPath };
}

async function main() {
  const cli = parseCliArgs(process.argv.slice(2));
  if (cli.help || cli.h === true) {
    printUsage();
    process.exitCode = 0;
    return;
  }

  // If the user provided *any* CLI args, treat this as a CLI invocation.
  // This avoids surprising fallbacks to stdin JSON when only optional flags are passed.
  const hasCli = process.argv.slice(2).length > 0;

  const input = hasCli ? cli : parseInput();
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    if (!hasCli) printUsage();
    console.error(hasCli ? 'Invalid CLI arguments' : 'Invalid JSON input (expected an object)');
    writeJson({ status: 'fail', reason: hasCli ? 'invalid_args' : 'invalid_json' });
    process.exitCode = 1;
    return;
  }

  if (!hasCli) {
    console.error('Deprecated: stdin JSON input. Prefer CLI flags: npm run shot -- --url ... --device ... --selector ... --output ...');
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
  } = input;

  if (!isNonEmptyString(url) || !isNonEmptyString(device) || !isNonEmptyString(selector) || !isNonEmptyString(output)) {
    console.error('Missing required fields: url, device, selector, output');
    writeJson({ status: 'fail', reason: 'missing_required_fields', url, device, selector, output });
    process.exitCode = 1;
    return;
  }

  const resolved = resolveOutputPath(output);
  if (!resolved) {
    console.error('Missing required field: output');
    writeJson({ status: 'fail', reason: 'missing_required_fields', url, device, selector, output });
    process.exitCode = 1;
    return;
  }
  if (resolved.error) {
    console.error('Invalid output (must be filename only; output is always written under scripts/artifacts/)');
    writeJson({ status: 'fail', reason: resolved.error, output });
    process.exitCode = 1;
    return;
  }

  const { filename: outputFile, outputPath } = resolved;

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
    ensureOutputDir(outputPath);

    browser = await chromium.launch({ headless: toBool(headless) });
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

    const fullPageBool = toBool(fullPage);
    if (fullPageBool) {
      await page.screenshot({ path: outputPath, fullPage: true });
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

      await page.screenshot({ path: outputPath, clip });
    }

    writeJson({
      status: 'ok',
      url,
      device,
      selector,
      viewport,
      output: outputFile,
      outputPath: path.relative(process.cwd(), outputPath),
      fullPage: fullPageBool,
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
      output: outputFile,
      outputPath: path.relative(process.cwd(), outputPath),
    });
    process.exitCode = 1;
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
}

await main();
