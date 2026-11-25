/* Chapter 9 — Tests, zones and steadiness: the Tests card, Enter a test result, Your zones, the zone sheet, Steady weeks,
   Niggles, Report as PDF. Invented figures; words from TestHistory, TestEntryView, ZonesView, SteadyWeeks, NigglesCard, MonthReport.
   The zone tables' headings and row names come from the plan's own sheet: here they are invented in the app's style. */
const ZN = { 1: 'Recovery', 2: 'Aerobic', 3: 'Tempo', 4: 'Threshold', 5: 'VO2max' };
const tstRound = x => Math.round(x);
const tstBand = (b, lo, hi) => tstRound(b * lo) + '–' + tstRound(b * hi);
const tstClock = s => { s = tstRound(s); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };
const tstSwim = s => Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
const tstHas = t => t.lthr != null || t.ftp != null || t.css != null || t.weight != null;
const tstNow = S => { const l = k => { const t = S.tst_tests.filter(x => x[k] != null).pop(); return t ? t[k] : null; }; return { lthr: l('lthr'), ftp: l('ftp'), css: l('css'), weight: l('weight'), latest: S.tst_tests.filter(tstHas).pop() }; };
const tstNums = t => [t.lthr != null && 'Threshold pulse ' + t.lthr, t.ftp != null && 'Bike power ' + t.ftp + ' W', t.css != null && 'Swim pace ' + tstSwim(t.css), t.weight != null && 'Weight ' + t.weight + ' kg'].filter(Boolean).join(' · ');
const tstTests0 = () => [
  { name: 'Test 1 (baseline)', dates: '14 Sep–16 Sep 2026', lthr: 160, ftp: 200, css: 112, weight: 72, notes: '' },
  { name: 'Test 2', dates: '26 Oct–28 Oct 2026', lthr: null, ftp: null, css: null, weight: null, notes: '' },
  { name: 'Test 3', dates: '30 Nov–02 Dec 2026', lthr: null, ftp: null, css: null, weight: null, notes: '' }];
/* Where an entry goes: the next test after the last one with numbers that still waits, else a new one. */
function tstTarget(tests) {
  const after = tests.map(tstHas).lastIndexOf(true) + 1, w = tests.slice(after).find(t => !tstHas(t));
  return w ? w.name : 'Test ' + (tests.length + 1);
}
function tstHeart(l, lthr) { return { 1: '< ' + tstRound(lthr * .81), 2: tstBand(lthr, .81, .89), 3: tstBand(lthr, .90, .95), 4: tstBand(lthr, .96, 1.02), 5: '> ' + tstRound(lthr * 1.02) }[l]; }
CHAPTER({
  id: 'tst',
  title: 'Tests, zones and steadiness',
  icon: 'stopwatch',
  needs: 'A test result now and then, if you test. A niggle noted when something nags. Nothing else: the other cards fill themselves.',
  gives: 'You can enter a test, see what it does to your zones, read Steady weeks and Niggles, and make the month report.',
  start: () => ({ part: 'progress', screen: 'tst.zones', tst_tests: tstTests0(), tst_lthr: '', tst_ftp: '', tst_swim: '', tst_weight: '', tst_notes: '',
    tst_tried: false, tst_problem: '', tst_saved: false, tst_zone: false, tst_sq: false, tst_nplace: '', tst_nside: '', tst_nline: '', tst_ntried: false,
    tst_ndone: '', tst_made: false }),
  screens: {
    /* Settings → Your zones */
    'tst.zones': S => {
      const done = S.tst_tests.filter(tstHas).reverse(), waiting = S.tst_tests.filter(t => !tstHas(t)), n = tstNow(S);
      const label = t => t.name + ', ' + t.dates;
      return `
      ${K.back('Settings', 'tst.note')}
      <h1 class="k-h1">Your zones</h1>
      <span class="k-cap">Your tests</span>
      ${K.btn('Enter a test result', 'tst.enter', { main: true, t: 'tst.enter' })}
      <div class="k-col" data-t="tst.list">${done.map(t => `<div class="k-card"><b>${esc(label(t))}</b><span>${esc(tstNums(t))}</span>${t.notes ? `<span class="k-muted k-small">${esc(t.notes)}</span>` : ''}</div>`).join('')}
        ${waiting.length ? `<div class="k-card"><b>Still to come</b>${waiting.map(t => `<span class="k-muted k-small">${esc(label(t))}</span>`).join('')}</div>` : ''}</div>
      <span class="k-cap">In use</span>
      <div class="k-grid3" data-t="tst.inuse">${[['LTHR (bpm)', n.lthr], ['CSS (sec/100 m)', n.css], ['Weight (kg)', n.weight]].filter(x => x[1] != null).map(([l, v]) =>
        `<div class="k-card"><b class="tst-n">${v}</b><span class="k-muted k-small">${l}</span></div>`).join('')}</div>
      <span class="k-muted k-small">From ${esc(label(n.latest))}</span>
      <div class="k-card" data-t="tst.table"><span class="k-cap">Heart-rate zones (bpm, from LTHR)</span>
        ${[1, 2, 3, 4, 5].map(z => `<div class="k-line"><span>Z${z} — ${ZN[z]}</span><b class="tst-n">${tstHeart(z, n.lthr)}</b></div>`).join('')}</div>
      <span class="k-muted k-small">Worked out from your latest test result.</span>`;
    },
    /* A session with its zone pill */
    'tst.session': S => `
      ${K.back('Sessions', 'tst.note')}
      <span class="k-line">${K.sport('run', { size: 40 })}<span class="k-col"><span class="k-sportword k-sp-run">Run</span><span class="k-muted">Wednesday 16 September</span></span></span>
      <b style="font-size:17px">Easy run + 4x20 s strides</b>
      <span class="k-line">${K.chip('35m')}<button class="tst-pill" data-act="tst.zone" data-t="tst.pill"><span>Z2</span><b>›</b></button></span>
      `,
    /* The Tests card on Progress, as a practice copy (the real picture is shown on the first step) */
    'tst.steady': S => {
      const f = [0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0];
      return `
      <b class="tst-h">Steady weeks</b>
      <div class="tst-tile" data-t="tst.steadycard"><span class="tst-tn">WEEKS IN A ROW WITH THE PLAN FOLLOWED</span>
        <span class="k-line" style="align-items:baseline"><b class="tst-big">5</b><b class="k-small">weeks</b></span>
        <div class="tst-sqs" data-t="tst.squares">${f.map((x, i) => `<div class="k-col" style="gap:2px;align-items:center"><i class="${x ? 'tst-full' : 'tst-out'}"></i><span class="tst-now">${i === 11 ? 'now' : '&nbsp;'}</span></div>`).join('')}</div>
        <div class="k-line k-small k-muted" data-t="tst.key"><i class="tst-full tst-sw"></i><span>followed</span><i class="tst-out tst-sw"></i><span>not followed</span></div>
        <span class="k-muted k-small">A full square is a week with at least 90 % of its due sessions done, as in Plan followed. An outlined square is a week below that. The last twelve weeks, oldest on the left.</span></div>
      ${S.tst_sq ? '<span class="k-small k-oktext">This week is not followed yet, and the row of 5 still stands. This week adds one only once it is followed.</span>' : `<button class="k-link" data-act="tst.sq" data-t="tst.sqbtn">What does the square marked now do?</button>`}`;
    },
    'tst.niggles': S => `
      <div class="tst-card" data-t="tst.ncard">
        <div class="tst-nhead"><span class="tst-cap">NIGGLES</span><b>4 noted on 2 places</b></div>
        <span><b>Left calf</b> <span class="k-muted k-small">· 3 times since Mon 7 Sep</span></span>
        <span><b>Right knee</b> <span class="k-muted k-small">· once since Sat 12 Sep</span></span>
        <hr class="tst-hr">
        ${[['SAT 12 SEP', 'Right knee — twinge on the stairs', 'Easy ride'], ['WED 9 SEP', 'Left calf — tight after the hills', 'Hill run'], ['TUE 8 SEP', 'Left calf', 'Steady swim'], ['MON 7 SEP', 'Left calf — a little stiff', 'Easy run']].map(([d, w, t]) =>
          `<div class="k-col" style="gap:1px"><b class="tst-nd">${d}</b><span class="k-small">${w}</span><span class="k-muted k-small">${t}</span></div>`).join('')}
        <span class="k-muted k-small" data-t="tst.nline">If something hurts, the Stop sign page is under Not well?</span></div>`,
    'tst.done': S => `
      ${K.back('Sessions', 'tst.note')}
      <b style="font-size:17px">Easy run + 4x20 s strides</b>
      <span class="k-line">${K.done()}<span>Done · 35m</span></span>
      <div class="k-card"><b class="k-h2">Your notes on this session</b>
        ${S.tst_ndone ? `<span data-t="tst.ndone">${esc(S.tst_ndone)}</span>` : '<span class="k-muted k-small">No notes yet.</span>'}
        ${K.btn(S.tst_ndone ? 'Change niggle' : 'Niggle?', 'tst.nopen', { t: 'tst.nopen' })}</div>`,
    'tst.report': S => `
      <b class="tst-title">Report as PDF</b>
      <span class="k-muted">August 2026 · one or two A4 pages</span>
      <div class="tst-tile" data-t="tst.contents"><span class="tst-tn">IN THE REPORT</span>
        <span>The month's facts: hours and sessions done of planned, hours per sport, the longest session, plan followed.</span>
        <span>A table of the weeks: planned and done hours for each sport.</span>
        <span>Your test values and your zones.</span>
        <span>How you felt each morning, as the five words.</span>
        <span>The sessions of the month: day, sport, title, planned, done, how hard.</span></div>
      <span class="k-muted k-small">The PDF is made on this device. You choose where it goes: the app sends it nowhere itself.</span>
      <button class="tst-make" data-act="tst.make" data-t="tst.make">Make the PDF</button>
      <button class="k-btn k-quiet k-full" data-act="tst.cancel" data-t="tst.cancel">Cancel</button>
      ${S.tst_made ? '<div class="k-band k-ok">' + icon('check') + '<span>The PDF is made. The share sheet opens so you can send it or save it. On a Mac it is saved through the share sheet.</span></div>' : ''}`,
    'tst.race': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card"><div class="k-top"><span><b style="font-size:34px;color:var(--pt)">4</b> <span class="k-muted">days to go</span></span><span class="k-sp"></span>
        <span class="tst-racebtn">${icon('race')}<span>The race</span></span></div>
        <span>Sprint triathlon (invented)</span><span class="tst-racelink" data-t="tst.racelink">Open your race page ›</span></div>`,
  },
  sheets: {
    'tst.entry': S => `<h3>Enter a test result</h3>
      <div><button class="k-btn" data-act="tst.same" data-t="tst.same">Same as the last test</button></div>
      <div class="k-field"><label for="in-tst_lthr">Threshold pulse</label><span class="k-line">${K.input('tst_lthr', S, { num: true, w: 70, ph: '160', t: 'tst.lthr' })}<span class="k-muted k-small">beats a minute</span></span></div>
      <div class="k-field"><label for="in-tst_ftp">Bike power (FTP)</label><span class="k-line">${K.input('tst_ftp', S, { num: true, w: 70, ph: '200', t: 'tst.ftp' })}<span class="k-muted k-small">watts</span></span></div>
      <div class="k-field"><label for="in-tst_swim">Swim pace per 100 m</label><span class="k-line">${K.input('tst_swim', S, { w: 70, ph: '1:50', t: 'tst.swim' })}<span class="k-muted k-small">min:sec</span></span></div>
      <div class="k-field"><label for="in-tst_weight">Weight</label><span class="k-line">${K.input('tst_weight', S, { num: true, w: 70, ph: '70', t: 'tst.weight' })}<span class="k-muted k-small">kg</span></span></div>
      <div class="k-field"><span>First day</span><b>Wed 16 Sep 2026</b></div>
      <div class="k-field"><span>Last day</span><b>Wed 16 Sep 2026</b></div>
      <div class="k-field"><label for="in-tst_notes">Notes</label>${K.input('tst_notes', S, { ph: 'Anything worth keeping' })}</div>
      <span class="k-muted k-small" data-t="tst.becomes">${S.tst_tests.some(t => !tstHas(t) && t.name === tstTarget(S.tst_tests)) ? 'Saves as ' : 'Saves as a new test, '}${tstTarget(S.tst_tests)}</span>
      <span class="k-muted k-small">Leave a box empty if that part was not tested; the zones keep the last number there is.</span>
      ${S.tst_problem ? `<span class="k-failtext k-small" data-t="tst.problem">${esc(S.tst_problem)}</span>` : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close', { t: 'tst.cancelentry' })}${K.btn('Save', 'tst.save', { main: true, t: 'tst.save' })}</div>`,
    'tst.zonesheet': S => { const n = tstNow(S); return `<h3 style="font-size:24px">Z2</h3>
      <span class="k-muted k-small">For you, from ${esc(n.latest.name + ', ' + n.latest.dates)}</span>
      <div class="k-card" data-t="tst.zrow"><span class="k-cap">Heart-rate zones (bpm, from LTHR)</span><div class="k-line"><span>Z2 — Aerobic</span><b class="tst-n">${tstHeart(2, n.lthr)}</b></div></div>
      <div class="k-foot"><button class="k-btn" data-act="tst.all">All your zones ›</button>${K.btn('Done', 'sheet.close', { main: true, t: 'tst.zdone' })}</div>`; },
    'tst.niggle': S => `<h3>Niggle?</h3>
      <span class="k-cap">Where</span>
      <div class="k-line">${['Neck', 'Shoulder', 'Back', 'Hip', 'Thigh', 'Knee', 'Shin', 'Calf', 'Achilles', 'Foot', 'Other'].map(p => `<button class="k-tile ${S.tst_nplace === p ? 'k-on' : ''}" data-act="tst.place" data-arg="${p}" data-t="tst.place:${p}">${p}</button>`).join('')}</div>
      <span class="k-cap">Which side</span>
      <div class="k-line">${['left', 'right', 'both'].map(p => `<button class="k-tile ${S.tst_nside === p ? 'k-on' : ''}" data-act="tst.side" data-arg="${p}" data-t="tst.side:${p}">${p[0].toUpperCase() + p.slice(1)}</button>`).join('')}</div>
      <span class="k-cap">In your words</span>${K.input('tst_nline', S, { ph: 'e.g. tight after the hills', t: 'tst.nline' })}
      <span class="k-muted k-small">A note for yourself. Nothing here is advice or a diagnosis.</span>
      ${S.tst_ntried && !S.tst_nplace ? `<span class="k-failtext k-small">Pick where it is first.</span>` : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'tst.nsave', { main: true, t: 'tst.nsave' })}</div>`,
  },
  actions: {
    'tst.note'() { toast('This page is not part of this chapter.'); },
    'tst.enter'(a, S) { S.sheet = 'tst.entry'; S.tst_problem = ''; },
    'tst.same'(a, S) { const t = S.tst_tests.filter(tstHas).pop(); S.tst_lthr = String(t.lthr ?? ''); S.tst_ftp = String(t.ftp ?? ''); S.tst_swim = t.css != null ? tstSwim(t.css) : ''; S.tst_weight = String(t.weight ?? ''); S.tst_problem = ''; },
    'tst.save'(a, S) {
      const num = (x, lo, hi, w, u) => { x = String(x).trim().replace(',', '.'); if (!x) return null; const v = Number(x); if (!isFinite(v) || v < lo || v > hi) throw w + ' needs a number from ' + lo + ' to ' + hi + ' ' + u + '.'; return v; };
      try {
        const lthr = num(S.tst_lthr, 80, 220, 'Threshold pulse', 'beats a minute'), ftp = num(S.tst_ftp, 50, 500, 'Bike power (FTP)', 'watts');
        let css = null; const sw = S.tst_swim.trim();
        if (sw) { const m = /^(\d+):(\d\d)$/.exec(sw); const sec = m ? Number(m[1]) * 60 + Number(m[2]) : NaN; if (!(sec >= 60 && sec <= 240) || Number(m && m[2]) > 59) throw 'Swim pace needs minutes and seconds between 1:00 and 4:00, like 1:50.'; css = sec; }
        const weight = num(S.tst_weight, 35, 150, 'Weight', 'kg');
        if (lthr == null && ftp == null && css == null && weight == null) throw 'Enter at least one number: pulse, bike power, swim pace or weight.';
        const name = tstTarget(S.tst_tests), t = S.tst_tests.find(x => x.name === name);
        if (t) Object.assign(t, { lthr, ftp, css, weight, notes: S.tst_notes.trim(), dates: '16 Sep 2026' });
        else S.tst_tests.push({ name, dates: '16 Sep 2026', lthr, ftp, css, weight, notes: S.tst_notes.trim() });
        S.tst_saved = true; S.sheet = null; S.tst_problem = '';
      } catch (e) { if (typeof e !== 'string') throw e; S.tst_problem = e; }
    },
    'tst.zone'(a, S) { S.sheet = 'tst.zonesheet'; S.tst_zone = true; },
    'tst.all'() { toast('The whole page is under Settings › Your zones, the one you saw first.'); },
    'tst.sq'(a, S) { S.tst_sq = true; },
    'tst.nopen'(a, S) { S.sheet = 'tst.niggle'; },
    'tst.place'(a, S) { S.tst_nplace = a; },
    'tst.side'(a, S) { S.tst_nside = a; },
    'tst.nsave'(a, S) {
      S.tst_ntried = true; if (!S.tst_nplace) return;
      const sided = !['Neck', 'Back', 'Other'].includes(S.tst_nplace) && S.tst_nside;
      const where = (sided ? S.tst_nside + ' ' : '') + S.tst_nplace.toLowerCase();
      S.tst_ndone = 'Niggle: ' + where + (S.tst_nline.trim() ? ' — ' + S.tst_nline.trim() : ''); S.sheet = null;
    },
    'tst.make'(a, S) { S.tst_made = true; },
    'tst.cancel'() { toast('Cancel closes the page and makes nothing.'); },
  },
  steps: [
    { kind: 'look', head: 'The Tests card', shot: 'tst-01-tests-card',
      text: 'Under the heading <b>Tests</b>, one purple tile each for Threshold pulse, Bike power (FTP) and Swim pace. The newest value stands large under the name, a grey line says how it stands against the earlier ones, and each test is a large dot with its first day under it. Equal results sit at the same height.',
      hint: 'On the swim tile a higher dot means more seconds, so slower. The app never says a result is better or worse. The card shows once a test has a number in that measure.', real: 'Progress, near the foot' },
    { kind: 'look', head: 'Your zones, the real page', shot: 'tst-02-zones',
      text: 'This is <b>Settings › Your zones</b>. At the top the green button <b>Enter a test result</b>, then your tests, done and still to come. Under <b>In use</b> stand the figures the app works with now, and under them the heart-rate zones worked out from the threshold pulse.',
      real: 'Settings › Your zones' },
    { kind: 'try', head: 'Open the test page', target: 'tst.enter', real: 'Settings › Your zones',
      text: 'The page is not on Progress: it is under <b>Settings › Your zones</b>. Press the green button <b>Enter a test result</b>.', until: S => S.sheet === 'tst.entry',
      ok: 'The page opens. Under the list on the page behind it are the tests you have and, in one card, the ones still to come.', robot: [['act', 'tst.enter']] },
    { kind: 'look', head: 'The boxes of the test page', shot: 'tst-03-test-new',
      text: 'The page has Cancel at the top and a green Save at the foot. Boxes: Threshold pulse (beats a minute), Bike power (FTP), Swim pace per 100 m (min:sec, like 1:50), Weight, First day, Last day and Notes. A box left empty means not tested this time, but one number is needed. The grey line <b>Saves as Test 2</b> says which test it fills.',
      hint: 'Limits: pulse 80 to 220, power 50 to 500, swim 1:00 to 4:00, weight 35 to 150. Same as the last test fills the four numbers only.' },
    { kind: 'try', head: 'Save with nothing typed', set: { sheet: 'tst.entry' }, target: 'tst.save', text: 'Press <b>Save</b> with every box empty.', until: S => !!S.tst_problem,
      ok: 'Save never greys out. One red line says what is missing, and nothing was written.', robot: [['act', 'tst.save']] },
    { kind: 'try', head: 'Type a pulse and save', set: { sheet: 'tst.entry' }, target: S => !S.tst_lthr ? 'tst.lthr' : 'tst.save',
      text: 'Type <b>164</b> in Threshold pulse. Leave the rest empty, then press <b>Save</b>.', until: S => S.tst_saved,
      ok: 'Saved. Test 2 is at the top of the list with its number, and Test 3 is still to come.', robot: [['in', 'tst_lthr', '164'], ['act', 'tst.save']] },
    { kind: 'look', head: 'What Save wrote and how the zones follow', set: { tst_saved: true, tst_tests: (() => { const t = tstTests0(); Object.assign(t[1], { lthr: 164, dates: '16 Sep 2026' }); return t; })() }, target: 'tst.list',
      text: 'The test is in the list, newest first, and <b>Still to come</b> keeps Test 3. Under <b>In use</b> every number is the last test that has it, so the pulse is 164 now and the weight is still the last one you entered. The zone tables follow at once. The app does not judge the result.',
      hint: 'A zone only ever changes from a test.' },
    { kind: 'try', head: 'Open a zone from a session', set: { screen: 'tst.session', part: 'sessions' }, target: 'tst.pill', real: 'a session’s page',
      text: 'The pill <b>Z2 ›</b> on a session opens what that zone is for you. Press it.', until: S => S.tst_zone,
      ok: 'A sheet shows the Z2 heart rate row from your latest test. A ride would show power too, and a swim its paces. <b>All your zones ›</b> opens the whole page.', robot: [['act', 'tst.zone']] },
    { kind: 'look', head: 'Steady weeks', shot: 'tst-05-steady',
      text: 'Twelve squares, oldest on the left, <b>now</b> under this week. Here the last two are full, so the figure is 2 weeks, and the other ten are outlined. A full purple square is a week with the plan followed: 90 % or more of its due sessions done. An outlined square is a week below that. The big figure counts the weeks in a row.',
      hint: 'A week with nothing due counts as not followed. There is no prize.' },
    { kind: 'look', head: 'Niggles: the card', shot: 'tst-06-niggles',
      text: 'A purple head card, <b>4 noted on 2 places</b>. Each place says how often and since when, left and right apart. Below, every note by date, newest first, with the session it belongs to. The card appears once you have noted one, and gives no advice.' },
    { kind: 'try', head: 'Note a niggle on a done session', set: { screen: 'tst.done', part: 'sessions' }, target: S => !S.sheet ? 'tst.nopen' : !S.tst_nplace ? 'tst.place:Calf' : !S.tst_nside ? 'tst.side:left' : 'tst.nsave', real: 'a done session’s page',
      text: 'A niggle comes from a note beside a log. Press <b>Niggle?</b>, choose <b>Calf</b> and <b>Left</b>, then press <b>Save</b>.', until: S => !!S.tst_ndone,
      ok: 'The session’s page now reads “Niggle: left calf”. Progress counts it in the Niggles card. If something hurts, the Stop sign page is under Not well?.',
      robot: [['act', 'tst.nopen'], ['act', 'tst.place', 'Calf'], ['act', 'tst.side', 'left'], ['act', 'tst.nsave']] },
    { kind: 'try', head: 'Make the month report', set: { screen: 'tst.report' }, target: 'tst.make', real: 'Progress › Month in review › Report as PDF',
      text: 'The button <b>Report as PDF</b> on the month card opens this page first: it lists exactly what the PDF holds. Press <b>Make the PDF</b>.', until: S => S.tst_made,
      ok: 'The PDF is made on this device and the share sheet opens. The app sends it nowhere itself.', robot: [['act', 'tst.make']] },
    { kind: 'look', head: 'The race page', set: { screen: 'tst.race' }, target: 'tst.racelink',
      text: 'On Progress, <b>The race</b> opens the race’s own words, and <b>Open your race page ›</b> takes you to the race page. The race chapter teaches it.' },
    { kind: 'check', head: 'Does this week break the row?', set: { screen: 'tst.steady' }, text: 'Your row of steady weeks stands at 5. This week is half over and not followed yet. What happens to the 5?',
      answers: ['It falls back to 0', 'It stays 5; this week adds one only when it is followed', 'It stays 5 until Sunday, then drops'], right: 1,
      ok: 'Right. This week never breaks the row. It adds one once it is followed.' },
  ],
});
