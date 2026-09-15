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

    out[path.basename(file)] = await page.evaluate(async () => {
      const s = AmsSync.getState();
      const m = s.mapping;
      if (!m) return { mapping: null, workouts: [], error: s.lastError ? String(s.lastError.message || s.lastError) : null };
      await AmsDb.set('moveLog', { since: null, moves: {} });
      const st = await AmsSync.stats();
      const stats = {
        today: AmsSync.todayKey(),
        summary: { any: st.any, counted: st.counted, done: st.done, missed: st.missed, unlogged: st.unlogged, answered: st.answered,
          firstDay: st.firstDay, lastDay: st.lastDay, streak: st.streak,
          sport: { rows: st.sport.rows.map(r => ({ id: r.id, label: r.label, planned: r.planned, done: r.done, missed: r.missed, unlogged: r.unlogged,
                    plannedSeconds: r.plannedSeconds, doneSeconds: r.doneSeconds, rate: r.rate })), worst: st.sport.worst ? st.sport.worst.id : null },
          moves: { missed: st.moves.missed, moved: st.moves.moved, keptByMoving: st.moves.keptByMoving } },
        trends: st.trends.sports.map(t => t.enough
          ? { sport: t.sport, enough: true, have: t.sessions, need: 8, usable: undefined, easyOnly: t.easyOnly, sessions: t.sessions, change: t.change,
              verdict: t.verdict, speedChange: t.speedChange, hrChange: t.hrChange, then: t.then, now: t.now }
          : { sport: t.sport, enough: false, have: t.have, need: t.need, usable: t.usable, easyOnly: t.easyOnly }),
        load: { planned: st.load.planned, actual: st.load.actual, weeks: st.load.weeks,
          sports: st.load.sports.map(x => ({ sport: x.sport, planned: x.planned, actual: x.actual, shareActual: x.shareActual, sharePlanned: x.sharePlanned })) }
      };
      const results = (w) => {
        const o = {};
        Object.keys(w.results || {}).forEach((k) => { o[k] = w.results[k].text; });
        return o;
      };
      return {
        stats,
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
