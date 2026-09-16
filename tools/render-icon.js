/*
 * node tools/render-icon.js tools/app-icon.svg App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
 *
 * Draws the app icon from its SVG with Chrome (Playwright), so the PNG has
 * the geometry the SVG says — even strokes, round joins, no seams. Needs
 * NODE_PATH pointing at a node_modules with playwright and CHROME_PATH at a
 * Chrome binary, as tools/js-dump.js does.
 */
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const [svgPath, outPath] = process.argv.slice(2);
  const svg = fs.readFileSync(svgPath, 'utf8');
  const browser = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await page.setContent(`<!doctype html><html><body style="margin:0">${svg}</body></html>`);
  await page.screenshot({ path: outPath, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
  await browser.close();
  console.log('rendered', outPath);
})();
