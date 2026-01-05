# Scripts

This folder contains automation scripts for the site.

## Setup

To set up Playwright for browser automation:
```bash
cd scripts/
npm install
npx playwright install
```

## Uninstall

To remove Playwright and its dependencies:
```bash
cd scripts/
npm uninstall playwright
rm -rf node_modules/
rm package-lock.json
```

The browser binaries are stored in a system cache. To remove them:

**macOS/Linux:**
```bash
rm -rf ~/Library/Caches/ms-playwright  # macOS
rm -rf ~/.cache/ms-playwright          # Linux
```

**Windows:**
```powershell
rmdir /s %USERPROFILE%\AppData\Local\ms-playwright
```

## Scripts

- `screenshot.js` - Makes screenshots
Usage:
    
```bash
cd scripts
npm run shot:mobile -- \
  --url "http://localhost:1313/posts/editing/" \
  --selector "img.wrap-figure" \
  --output "test.png"
```

### Notes
- This tool is intentionally **single-shot**: provide one `url` + `selector` + `device` + `output` per invocation.
- Prefer `npm run shot:mobile` / `npm run shot:desktop` to avoid re-typing `--device`.
- For any additional CLI args, keep using the npm separator: `npm run shot:mobile -- --url ... --selector ... --output ...`
- `--output` must be a **filename only** (no path). Screenshots are always written under `scripts/artifacts/` (gitignored).
- By default it screenshots a **square region centered on** the element matched by `selector` (to capture surrounding context). Use `"minPadding"`/`"maxPadding"` to control the side length. Set `"fullPage": true` only when you need broader context.
