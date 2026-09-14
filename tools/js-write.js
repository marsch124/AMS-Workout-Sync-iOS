/*
 * node tools/js-write.js <scenarios.json> <out-dir>
 *
 * The web app's side of the writer comparison: each scenario's steps applied
 * to a fresh copy of its workbook by the web app's own code — AmsXlsx.open,
 * autoDetect + prepareMapping, AmsPlan.build, buildEdits, writeCells, save —
 * exactly the calls a sync makes, minus Dropbox. Needs the web app on
 * http://localhost:7810/.
 */
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const CHROME = process.env.CHROME_PATH || '';
const LAUNCH = CHROME && fs.existsSync(CHROME) ? { executablePath: CHROME } : {};

(async () => {
  const scenarios = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const outDir = process.argv[3];
  fs.mkdirSync(outDir, { recursive: true });

  const browser = await chromium.launch(LAUNCH);
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', e => pageErrors.push(e.message));
  await page.goto('http://localhost:7810/', { waitUntil: 'networkidle' });

  let written = 0;
  for (const scenario of scenarios) {
    const input = fs.readFileSync(scenario.file).toString('base64');
    const result = await page.evaluate(async ({ input, steps }) => {
      try {
        const bytes = Uint8Array.from(atob(input), c => c.charCodeAt(0));
        const wb = await AmsXlsx.open(bytes);
        const mapping = await AmsMapping.autoDetect(wb);
        await AmsSync.prepareMapping(wb, mapping);
        const plan = await AmsPlan.build(wb, mapping);
        const names = {};
        for (const sheet of mapping.sheets) names[sheet] = AmsPlan.learnWeekdayNames(await wb.readSheet(sheet), mapping);

        for (const step of steps) {
          const workout = plan.find(w => w.key === step.key);
          if (!workout) return { error: 'no session ' + step.key };
          const entry = Object.assign({}, step.entry);
          if (entry.moveTo) entry.weekdayNames = names[workout.sheet];
          const edits = AmsPlan.buildEdits(workout, entry, mapping);
          await wb.writeCells(workout.sheet, edits);
        }
        const blob = await wb.save();
        const out = new Uint8Array(await blob.arrayBuffer());
        let bin = '';
        for (let i = 0; i < out.length; i += 0x8000) bin += String.fromCharCode.apply(null, out.subarray(i, i + 0x8000));
        return { data: btoa(bin) };
      } catch (e) {
        return { error: String(e && e.message || e) };
      }
    }, { input, steps: scenario.steps });

    if (result.error) {
      console.log(scenario.name + ': ' + result.error);
    } else {
      fs.writeFileSync(path.join(outDir, scenario.name + '.xlsx'), Buffer.from(result.data, 'base64'));
      written++;
    }
  }

  await browser.close();
  if (pageErrors.length) console.log('page errors:', pageErrors.slice(0, 5));
  console.log(written + ' of ' + scenarios.length + ' written');
})();
