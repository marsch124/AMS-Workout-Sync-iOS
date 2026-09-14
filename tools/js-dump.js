/*
 * node tools/js-dump.js <workbook.xlsx> [...]
 *
 * What the web app makes of a workbook, printed in the shape plan-dump prints
 * for the native reader. The web app is served on http://localhost:7810/ (see
 * tools/parity.sh) and each workbook is opened in a fresh browser context, so
 * a layout remembered from the previous file cannot colour the next one.
 */
const { chromium } = require('playwright');
const path = require('path');

const CHROME = process.env.CHROME_PATH || '';
const LAUNCH = CHROME && require('fs').existsSync(CHROME) ? { executablePath: CHROME } : {};

(async () => {
  const files = process.argv.slice(2);
  const browser = await chromium.launch(LAUNCH);
  const out = {};

  for (const file of files) {
    const context = await browser.newContext();
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('dialog', d => d.accept());

    await page.goto('http://localhost:7810/', { waitUntil: 'networkidle' });
    await page.click('.tab[data-tab="settings"]');
    await page.waitForSelector('#openLocalButton');
    await page.setInputFiles('#localFileInput', path.resolve(file));
    await page.waitForFunction(() => {
      const s = AmsSync.getState();
      return (s.plan && s.plan.length) || s.lastError;
    }, null, { timeout: 30000 }).catch(() => {});

    out[path.basename(file)] = await page.evaluate(() => {
      const s = AmsSync.getState();
      const m = s.mapping;
      if (!m) return { mapping: null, workouts: [], error: s.lastError ? String(s.lastError.message || s.lastError) : null };
      const results = (w) => {
        const o = {};
        Object.keys(w.results || {}).forEach((k) => { o[k] = w.results[k].text; });
        return o;
      };
      return {
        mapping: {
          sheets: m.sheets, headerRow: m.headerRow, firstDataRow: m.firstDataRow, lastDataRow: m.lastDataRow,
          mode: m.mode, sectionColumn: m.sectionColumn || null, columns: m.columns,
          units: { duration: m.units.duration, distance: m.units.distance, paceIsTime: !!m.units.paceIsTime },
          doneValue: m.doneValue, missedValue: m.missedValue
        },
        workouts: s.plan.map((w) => ({
          key: w.key, sheet: w.sheet, row: w.row, rows: w.rows, dayKey: w.dayKey,
          discipline: w.discipline.id, title: w.title, phase: w.phase || '',
          sections: w.sections.map((x) => ({ kind: x.kind, label: x.label, text: x.text })),
          plannedDurationRaw: w.planned.durationRaw === undefined ? null : w.planned.durationRaw,
          plannedDistanceRaw: w.planned.distanceRaw === undefined ? null : w.planned.distanceRaw,
          intensity: w.planned.intensity || '',
          plannedSeconds: AmsPlan.plannedDurationSeconds(w, m),
          results: results(w),
          loggedInSheet: !!w.loggedInSheet,
          missed: AmsSync.isMissed(w)
        }))
      };
    });
    if (errors.length) out[path.basename(file)].pageErrors = errors;
    await context.close();
  }

  await browser.close();
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
})();
