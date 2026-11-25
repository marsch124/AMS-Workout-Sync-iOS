/* Chapter 3 — Logging a session. From a session's page: Done · 35m, Log details, Missed, Adjust logged data, the notes beside a log,
   and an extra workout. Everything the chapter invents starts with "log". Words are the app's own (SessionView, LogFormView,
   LogExtras, ExtraViews; spec S.4, D.8, D.12, W.1). */
(() => {
const dd = s => { const t = String(s || '').trim().toLowerCase().replace(',', '.'); if (!t) return null;
  if (t.includes(':')) { const p = t.split(':').map(Number); if (p.some(isNaN)) return null; return p.length === 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 3600 + p[1] * 60; }
  const n = Number(t); return isNaN(n) ? null : n * 60; };
const FORM = ['len', 'dist', 'pace', 'hr', 'rpe'];
const snap = S => { const o = {}; FORM.forEach(k => { o[k] = S['log_' + k] || ''; }); return o; };
const changes = S => FORM.filter(k => (S['log_' + k] || '') !== ((S.log_o || {})[k] || '')).length + (S.log_brickDiff ? 1 : 0);
const brickSum = S => { const b = dd(S.log_bike), c = (() => { const t = String(S.log_change || '').trim(); if (!t) return null; if (t.endsWith('s')) return Number(t.slice(0, -1)); if (t.includes(':')) { const p = t.split(':').map(Number); return p[0] * 60 + p[1]; } return Number(t) * 60; })(), r = dd(S.log_run);
  return (b && c != null && r) ? b + c + r : null; };
const clock = sec => { const m = Math.round(sec / 60); return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`; };
const PLACES = ['Neck', 'Shoulder', 'Back', 'Hip', 'Thigh', 'Knee', 'Shin', 'Calf', 'Achilles', 'Foot', 'Other'];
const heart = () => icon('heart', 'i');

/* The session's page. kind 'run' = Easy run + 4x20 s strides (35m, Z2); 'brick' = a 1h 40m brick. */
const page = (S, brick) => {
  const state = S.log_state, done = state === 'done', missed = state === 'missed';
  const sp = brick ? 'brick' : 'run', word = brick ? 'Brick' : 'Run', title = brick ? 'Long brick: bike then run' : 'Easy run + 4x20 s strides';
  const day = brick ? 'Saturday 19 September' : 'Wednesday 16 September', plan = brick ? '1h 40m' : '35m', zone = brick ? 'Z2' : 'Z2';
  const figs = [];
  if (done) { figs.push(['Duration', dur(Number(S.log_len) || (brick ? 100 : 35))]);
    if (S.log_dist) figs.push(['Distance', S.log_dist + ' km']); if (S.log_pace) figs.push(['Pace /km', S.log_pace]);
    if (S.log_hr) figs.push(['Heart rate', S.log_hr + ' bpm']); if (S.log_rpe) figs.push(['Effort', S.log_rpe + ' / 10']); }
  const effort = S.log_effort ? ['Effort', S.log_effort + ' / 10'] : null; if (effort && !S.log_rpe) figs.push(effort);
  const askHow = done && !S.log_rpe && !S.log_effort;
  const buttons = done ? `<div class="log-btns">${S.log_health && !S.log_used ? K.btn('Fill from Garmin', 'log.pen', { icon: 'heart', t: 'log.fill' }) : ''}</div>`
    : `<div class="log-btns">
        ${K.btn('Done · ' + plan, 'log.done', { main: true, icon: 'check', t: 'log.done' })}
        ${K.btn(missed ? 'Log it after all' : 'Log details', brick ? 'log.openb' : 'log.open', { icon: S.log_health ? 'heart' : undefined, t: missed ? 'log.after' : 'log.details' })}
        ${missed ? '' : K.btn('Missed', 'log.missedOpen', { danger: true, t: 'log.missed' })}
        ${K.btn('Move', 'log.move')}</div>`;
  return `${K.back('Today', 'log.back')}
    <span class="k-line">${K.sport(sp, { size: 40 })}<span class="k-col log-words"><span class="k-sportword k-sp-${sp}">${word}</span>
      <span class="k-muted">${day}</span></span>${done ? K.done({ t: 'log.tick' }) : ''}</span>
    <b class="log-title">${title}</b>
    <span class="k-muted k-small">Why: ${brick ? 'a long aerobic day — bike then run, as in a race.' : 'easy aerobic — builds your base without costing much.'}</span>
    <span class="k-line">${K.chip(plan)}${K.chip(zone)}</span>
    ${buttons}
    ${missed ? '<b class="log-bad">Marked missed</b>' : ''}
    ${askHow ? `<div class="k-card" data-t="log.how"><b>How hard was it?</b><div class="log-effort">${[1,2,3,4,5,6,7,8,9,10].map(n => `<button data-act="log.effort" data-arg="${n}" data-t="log.effort:${n}">${n}</button>`).join('')}</div>
      <span class="k-muted k-small">1 very easy · 7 hard · 10 all out</span></div>` : ''}
    ${figs.length ? `<span class="k-line"><span class="k-cap">What you did</span>${done ? `<button class="k-btn k-quiet log-pen" data-act="log.pen" data-t="log.pen" aria-label="Adjust logged data">${icon('pen')}</button>` : ''}</span>
      <div class="k-stats">${figs.map(f => K.stat(f[1], f[0])).join('')}</div>` : ''}
    ${S.log_note ? `<div class="k-card">${esc(S.log_note)}</div>` : ''}
    ${done && brick && S.log_stomach ? `<div class="k-card" data-t="log.block"><span class="k-cap">Your notes on this session</span>
      <div class="k-stats">${K.stat(S.log_bike || '—', 'Bike')}${K.stat(S.log_change || '—', 'Change-over')}${K.stat(S.log_run || '—', 'Run')}</div>
      <div class="k-stats">${K.stat(S.log_stomach, 'Stomach')}</div>
      ${S.log_niggle ? `<span class="k-small">${esc(S.log_niggle)}</span>` : ''}
      <span class="k-line">${K.btn(S.log_niggle ? 'Change niggle' : 'Niggle?', 'log.niggleOpen')}${K.btn('Change notes', 'log.openb')}${K.btn('Fuel notes', 'log.fuel')}</span></div>` : ''}`;
};

CHAPTER({
  id: 'log',
  title: 'Logging a session',
  icon: 'check',
  needs: 'A minute after each session: one press if it went as planned, a few numbers if you want them kept.',
  gives: 'What you did sits beside what was planned, and the weeks add up from it.',
  start: () => ({ device: 'phone', part: 'today', screen: 'log.run', sheet: null, log_state: 'todo', log_len: '', log_dist: '', log_pace: '', log_hr: '', log_rpe: '',
    log_effort: 0, log_o: {}, log_tried: false, log_adjust: false, log_health: false, log_used: false, log_note: '', log_mnote: '',
    log_bike: '', log_change: '', log_run: '', log_stomach: '', log_niggle: '', log_nplace: '', log_nside: '', log_nline: '', log_ntried: false, log_brickDiff: false,
    log_xkind: 'walk', log_xwhat: '', log_xdur: '', log_xtried: false, log_xrows: [], log_xeffort: 0 }),
  screens: {
    'log.run': S => page(S, false),
    'log.brick': S => page(S, true),
    'log.today': S => `<h1 class="k-h1">Today</h1>
      <div class="k-card"><span class="k-line">${K.sport('run')}<span class="k-col"><span class="k-sportword k-sp-run">Run</span><b>Easy run + 4x20 s strides</b>
        <span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span></span></span></div>
      ${K.btn('Extra workout', 'log.xopen', { icon: 'plus', t: 'log.xbtn' })}
      ${S.log_xrows.map(x => `<button class="k-card log-ex" data-act="log.xplate" data-t="log.xrow"><span class="k-cap">Extra workout</span><b>${esc(x.what || x.kind)}</b><span class="k-muted">${esc(x.kind)} · ${dur(x.min)}${x.training ? ' · counts as training' : ''}</span></button>`).join('')}`,
  },
  sheets: {
    'log.form': S => {
      const n = changes(S), h = S.log_health && !S.log_used;
      return `<h3>${S.log_adjust ? 'Adjust logged data' : 'How did it go?'}</h3>
      <span class="k-cap k-sp-run k-sportword">RUN · Wed 16 Sep</span><span class="k-muted k-small">Easy run + 4x20 s strides</span>
      ${h ? `<div class="log-sug"><span class="k-cap">From Apple Health</span><b>Run · 07:12</b><span class="k-muted k-small">36m · 6.2 km · avg 138 bpm · Garmin Connect</span>
        ${K.btn('Use', 'log.use', { t: 'log.use' })}<span class="k-muted k-small">Use fills time, distance and heart rate; the pace is yours to type. Nothing is saved until you press Save.</span></div>` : ''}
      <div class="k-field"><label for="in-log_len">Duration</label>${K.input('log_len', S, { ph: 'e.g. 45', t: 'log.len' })}<span class="k-muted k-small">Just a number means minutes — 45 is 45 minutes, 90 is an hour and a half. Or write it out: 1:15, 1h20, 90min.</span></div>
      <div class="k-field"><label for="in-log_dist">Distance</label><span class="k-muted k-small">km or m</span>${K.input('log_dist', S, { ph: 'e.g. 12.4', t: 'log.dist' })}</div>
      <div class="k-field"><label for="in-log_pace">Pace (min/km)</label>${K.input('log_pace', S, { ph: 'e.g. 4:52', t: 'log.pace' })}</div>
      <div class="k-field"><label for="in-log_hr">Average heart rate (bpm)</label>${K.input('log_hr', S, { ph: 'e.g. 135', t: 'log.hr' })}</div>
      <div class="k-field"><label for="in-log_rpe">Perceived effort (RPE) (1-10)</label>${K.input('log_rpe', S, { ph: '1–10', w: 70, t: 'log.rpe' })}
        <span class="k-muted k-small">${esc(RPE[Number(S.log_rpe)] || '1 easy — 10 all out')}</span></div>
      <span class="k-muted k-small">Photos: Add photo — kept on this device only.</span>
      ${S.log_tried && n === 0 ? '<span class="log-bad" data-t="log.problem">Nothing has changed yet — fill in the time you did, or a number you want to correct.</span>' : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close', { t: 'log.cancel' })}${K.btn(n ? `Save ${n} change${n === 1 ? '' : 's'}` : 'Save', 'log.save', { main: true, t: 'log.save' })}</div>`; },
    'log.formb': S => {
      const sum = brickSum(S), n = changes(S);
      return `<h3>${S.log_adjust ? 'Adjust logged data' : 'How did it go?'}</h3>
      <span class="k-cap k-sp-run k-sportword">BRICK · Sat 19 Sep</span><span class="k-muted k-small">Long brick: bike then run</span>
      <div class="k-field"><label for="in-log_len">Duration</label>${K.input('log_len', S, { ph: 'e.g. 45', t: 'log.len' })}</div>
      <span class="k-cap">Notes beside the log</span>
      <div class="log-box"><div class="log-three">
        <div><label for="in-log_bike">Bike time</label>${K.input('log_bike', S, { ph: '1:10', t: 'log.bike' })}</div>
        <div><label for="in-log_change">Change-over</label>${K.input('log_change', S, { ph: '1:30', t: 'log.change' })}</div>
        <div><label for="in-log_run">Run time</label>${K.input('log_run', S, { ph: '40', t: 'log.runbox' })}</div></div>
        <span class="k-muted k-small">Bike and run: minutes, or 1:10 for an hour and ten. Change-over: minutes:seconds.</span>
        ${sum && Math.round(sum / 60) !== Math.round((dd(S.log_len) || 0) / 60) ? K.btn(`Use ${dur(Math.round(sum / 60))} as the length`, 'log.sum', { t: 'log.sum' }) : ''}</div>
      <div class="log-box"><span class="log-btns"><b>Stomach OK?</b>${['Fine', 'So-so', 'Upset'].map(w => `<button class="k-btn${S.log_stomach === w ? ' k-main' : ''}" data-act="log.stomach" data-arg="${w}" data-t="log.stomach:${w}"><span>${w}</span></button>`).join('')}</span>
        <span class="k-muted k-small">What did you eat and drink?</span>${K.btn('Fuel notes', 'log.fuel')}</div>
      <div class="log-box"><span class="log-btns"><b>Niggle?</b><span class="k-muted k-small">${esc(S.log_niggle ? S.log_niggle.replace('Niggle: ', '') : 'Nothing noted')}</span>${K.btn(S.log_niggle ? 'Change' : 'Add', 'log.niggleOpen', { t: 'log.niggle' })}</span></div>
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn(n ? `Save ${n} change${n === 1 ? '' : 's'}` : 'Save', 'log.saveb', { main: true, t: 'log.saveb' })}</div>`; },
    'log.niggle': S => `<h3>Niggle?</h3><span class="k-muted k-small">A note for yourself. Nothing here is advice or a diagnosis.</span>
      <div class="k-field"><label for="in-log_nplace">Where</label>${K.select('log_nplace', S, [['', 'Choose…'], ...PLACES], { t: 'log.nplace' })}</div>
      ${S.log_nplace && !['Neck', 'Back', 'Other'].includes(S.log_nplace) ? `<div class="k-field"><label for="in-log_nside">Which side</label>${K.select('log_nside', S, [['', 'Not said'], 'left', 'right', 'both'], {})}</div>` : ''}
      <div class="k-field"><label for="in-log_nline">In your words</label>${K.input('log_nline', S, { ph: 'e.g. tight after the hills' })}</div>
      ${S.log_ntried && !S.log_nplace ? '<span class="log-bad">Pick where it is first.</span>' : ''}
      <div class="k-foot">${K.btn('Cancel', 'log.niggleCancel')}${K.btn('Save', 'log.niggleSave', { main: true })}</div>`,
    'log.missed': S => `<h3>Mark this session as missed?</h3>
      <span class="k-muted k-small">Only the missed marker and your note are written. Nothing else in the row changes, and you can still log it later if you did it after all.</span>
      <div class="k-field">${K.input('log_mnote', S, { ph: 'Why? (optional)', t: 'log.mnote' })}</div>
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Mark missed', 'log.missedMark', { danger: true, t: 'log.markmissed' })}</div>`,
    'log.extra': S => `<h3>Extra workout</h3>
      <div class="k-field"><label>When</label><span>Wed 16 Sep</span></div>
      <div class="k-field"><label for="in-log_xkind">What kind of thing</label>${K.select('log_xkind', S, [['walk', 'Walk'], ['hike', 'Hike'], ['yoga', 'Yoga'], ['swim', 'Swim'], ['bike', 'Bike'], ['run', 'Run'], ['strength', 'Strength'], ['other', 'Something else']], { t: 'log.xkind' })}</div>
      <div class="k-field"><label for="in-log_xwhat">What it was</label>${K.input('log_xwhat', S, { ph: 'e.g. Dog walk along the river', t: 'log.xwhat' })}</div>
      <div class="k-field"><label for="in-log_xdur">Duration</label>${K.input('log_xdur', S, { ph: 'e.g. 35', t: 'log.xdur' })}<span class="k-muted k-small">Just a number means minutes. Or 1:15, 1h20, 90min.</span></div>
      <div class="k-field"><label>Counts as training?</label><b>${['swim', 'bike', 'run', 'strength', 'rowing'].includes(S.log_xkind) ? 'Yes — count it as training' : 'No — it does not add load'}</b></div>
      ${S.log_xtried && !dd(S.log_xdur) && !S.log_xwhat ? '<span class="log-bad" data-t="log.xproblem">Give it at least a duration — "35", or 1:15 — or a word about what it was.</span>' : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'log.xsave', { main: true, t: 'log.xsave' })}</div>`,
    'log.xplate': S => { const x = S.log_xrows[0] || { kind: 'walk', what: '', min: 0 };
      return `<h3>Extra workout</h3><div class="k-card"><b>${esc(x.what || x.kind)}</b><span class="k-muted">${esc(x.kind)} · ${dur(x.min)}</span></div>
      ${S.log_xeffort ? `<b class="k-oktext">Effort ${S.log_xeffort} / 10 saved</b>` : `<div class="k-card"><b>How hard was it?</b><div class="log-effort">${[1,2,3,4,5,6,7,8,9,10].map(n => `<button data-act="log.xeffort" data-arg="${n}" data-t="log.xeffort:${n}">${n}</button>`).join('')}</div></div>`}
      <div class="k-foot">${K.btn('Close', 'sheet.close')}</div>`; },
  },
  actions: {
    'log.back'() { toast('Today has its own chapter.'); },
    'log.move'() { toast('Move is in the next chapter.'); },
    'log.fuel'() { toast('Fuel notes lists every answer to “Stomach OK?”, newest first.'); },
    'log.done'(a, S) { S.log_state = 'done'; S.log_len = S.screen === 'log.brick' ? '100' : '35'; },
    'log.effort'(a, S) { S.log_effort = Number(a); },
    'log.open'(a, S) { S.log_o = snap(S); S.log_adjust = false; S.log_tried = false; S.sheet = 'log.form'; },
    'log.openb'(a, S) { S.log_o = snap(S); S.log_adjust = S.log_state === 'done'; S.log_tried = false; S.sheet = 'log.formb'; },
    'log.pen'(a, S) { S.log_o = snap(S); S.log_adjust = true; S.log_tried = false; S.sheet = 'log.form'; },
    'log.use'(a, S) { S.log_len = '36'; S.log_dist = '6.2'; S.log_hr = '138'; S.log_used = true; },
    'log.save'(a, S) { if (changes(S) === 0) { S.log_tried = true; return; } S.log_state = 'done'; S.sheet = null; },
    'log.sum'(a, S) { S.log_len = String(Math.round(brickSum(S) / 60)); },
    'log.stomach'(a, S) { S.log_stomach = S.log_stomach === a ? '' : a; },
    'log.saveb'(a, S) { S.log_state = 'done'; if (!S.log_len) S.log_len = '100'; S.sheet = null; },
    'log.niggleOpen'(a, S) { S.log_ntried = false; S.sheet = 'log.niggle'; },
    'log.niggleCancel'(a, S) { S.sheet = S.screen === 'log.brick' && S.log_state === 'todo' ? 'log.formb' : (S.log_state === 'done' ? null : 'log.formb'); },
    'log.niggleSave'(a, S) { if (!S.log_nplace) { S.log_ntried = true; return; }
      const side = S.log_nside && !['Neck', 'Back', 'Other'].includes(S.log_nplace) ? S.log_nside + ' ' : '';
      S.log_niggle = 'Niggle: ' + side + S.log_nplace.toLowerCase() + (S.log_nline ? ' — ' + S.log_nline : '');
      S.sheet = S.log_state === 'done' ? null : 'log.formb'; },
    'log.missedOpen'(a, S) { S.sheet = 'log.missed'; },
    'log.missedMark'(a, S) { S.log_state = 'missed'; S.sheet = null; },
    'log.xopen'(a, S) { S.log_xtried = false; S.sheet = 'log.extra'; },
    'log.xsave'(a, S) { const m = dd(S.log_xdur);
      if (!m && !S.log_xwhat) { S.log_xtried = true; return; }
      S.log_xrows.unshift({ kind: ({ walk: 'Walk', hike: 'Hike', yoga: 'Yoga', swim: 'Swim', bike: 'Bike', run: 'Run', strength: 'Strength', other: 'Something else' })[S.log_xkind], what: S.log_xwhat, min: m ? Math.round(m / 60) : 0, training: ['swim', 'bike', 'run', 'strength'].includes(S.log_xkind) });
      S.sheet = null; },
    'log.xplate'(a, S) { S.sheet = 'log.xplate'; },
    'log.xeffort'(a, S) { S.log_xeffort = Number(a); },
  },
  steps: [
    { kind: 'look', head: 'Four buttons under a session', target: 'log.done',
      text: 'A session that is still to do has <b>Done · 35m</b> (green, as planned), <b>Log details</b>, <b>Missed</b> and <b>Move</b>. The planned length stays on the green one: it is what gets written.',
      hint: 'Because your plan lives in the app, every device can log. With a keyboard, Space does what the green button does, while nothing is open on top.', real: 'Today › a session' },
    { kind: 'try', head: 'Done as planned, then how hard', set: { screen: 'log.run' }, target: S => S.log_state !== 'done' ? 'log.done' : 'log.effort:6',
      text: 'Press <b>Done · 35m</b>. Then answer <b>How hard was it?</b> with a number, say 6.',
      until: S => S.log_state === 'done' && S.log_effort === 6, ok: 'The page shows What you did: Duration 35m, Effort 6 / 10. Nothing but the length and the done mark was written.',
      robot: [['act', 'log.done'], ['act', 'log.effort', 6]] },
    { kind: 'look', head: 'The log form', shot: 'log-01-form',
      text: 'Log details opens <b>How did it go?</b>: Cancel at the top left, the boxes for the sport (here Duration, Distance with km or m, Pace, Average heart rate, effort), and the green Save at the foot. Under the title, a note says if Apple Health is not connected.',
      hint: 'Once you have asked for more fields, the form shows them every time.', real: 'Log details' },
    { kind: 'try', head: 'Log details with your own numbers', set: { screen: 'log.run' }, target: S => S.sheet !== 'log.form' ? 'log.details' : !S.log_len ? 'log.len' : !S.log_hr ? 'log.hr' : 'log.save',
      text: 'Press <b>Log details</b>. Type the length 40 and an average heart rate 138, then press <b>Save</b>.',
      until: S => S.log_state === 'done' && S.log_len === '40' && S.log_hr === '138', ok: 'The page is closed. Save said how many boxes it writes, and only those were written.',
      robot: [['act', 'log.open'], ['in', 'log_len', '40'], ['in', 'log_hr', '138'], ['act', 'log.save']] },
    { kind: 'try', head: 'Fill from the watch', set: { screen: 'log.run', log_health: true, sheet: 'log.form', log_o: {} }, target: 'log.use', only: 'iPhone',
      text: 'When a workout from your watch matches, <b>Log details</b> wears a heart and the form offers it under <b>From Apple Health</b>. Press <b>Use</b>: it fills time, distance and heart rate. The pace stays yours.',
      hint: 'Apple Health is on the iPhone only. Nothing is saved until Save.', real: 'Log details › From Apple Health',
      until: S => S.log_used && S.log_len === '36', ok: 'Time 36, distance 6.2 and heart rate 138 are in the boxes, edged as changed. Press Save to keep them.',
      robot: [['act', 'log.use']] },
    { kind: 'try', head: 'Save with nothing changed', set: { screen: 'log.run', sheet: 'log.form', log_o: {} }, target: 'log.save',
      text: 'The form is open and empty. Press <b>Save</b>.',
      until: S => S.log_tried && S.sheet === 'log.form', ok: 'A red line says nothing has changed yet. The button stays green and nothing is written.',
      robot: [['act', 'log.save']] },
    { kind: 'try', head: 'Missed, with a reason', set: { screen: 'log.run' }, target: S => S.sheet !== 'log.missed' ? 'log.missed' : (!S.log_mnote ? 'log.mnote' : 'log.markmissed'),
      text: 'Press <b>Missed</b>, write why in the box if you like, and press <b>Mark missed</b>.',
      until: S => S.log_state === 'missed', ok: 'The page says “Marked missed” in red. Only that marker and your note were written.',
      robot: [['act', 'log.missedOpen'], ['in', 'log_mnote', 'Rain all day'], ['act', 'log.missedMark']] },
    { kind: 'try', head: 'Log it after all', set: { screen: 'log.run', log_state: 'missed' }, target: 'log.after',
      text: 'You did it after all. <b>Log details</b> now reads <b>Log it after all</b>. Press it.',
      until: S => S.sheet === 'log.form', ok: 'The log form opens as for any session. Saving it replaces the missed marker.',
      robot: [['act', 'log.open']] },
    { kind: 'try', head: 'Adjust logged data', set: { screen: 'log.run', log_state: 'done', log_len: '35' }, target: S => S.sheet !== 'log.form' ? 'log.pen' : S.log_len !== '40' ? 'log.len' : 'log.save',
      text: 'On a done session the pen beside <b>What you did</b> opens <b>Adjust logged data</b>. Change the duration to 40 and press <b>Save 1 change</b>.',
      until: S => S.log_state === 'done' && S.log_len === '40', ok: 'Only the one box you changed was written, so nothing newer in your plan is overwritten.',
      robot: [['act', 'log.pen'], ['in', 'log_len', '40'], ['act', 'log.save']] },
    { kind: 'look', head: 'Notes beside the log, in the form', shot: 'log-02-form-extras',
      text: 'Under <b>NOTES BESIDE THE LOG</b> a brick has Bike time, Change-over and Run time, and a button <b>Use 1h 36m as the length</b>. Then <b>Stomach OK?</b> with Fine, So-so and Upset, <b>Fuel notes</b>, <b>Niggle?</b>, and for a swim the <b>Open water</b> switch with Wetsuit and Water temperature.',
      hint: 'This picture shows every row at once; a real session shows only the ones that fit it.', real: 'Log details' },
    { kind: 'try', head: 'Notes beside a brick log', set: { screen: 'log.brick', sheet: 'log.formb', log_len: '100', log_o: { len: '100' } },
      target: S => !S.log_bike ? 'log.bike' : !S.log_change ? 'log.change' : !S.log_run ? 'log.runbox' : !S.log_stomach ? 'log.stomach:So-so' : 'log.saveb',
      text: 'Under <b>Notes beside the log</b>, type bike 1:05, change-over 1:20 and run 30. Choose <b>So-so</b> under <b>Stomach OK?</b> (sessions of 90 minutes or more), then press <b>Save</b>.',
      hint: 'A swim has <b>Open water</b>, <b>Wetsuit</b>, <b>Water temperature</b> and <b>Sighting and conditions</b> instead. <b>Niggle?</b> is on every session.',
      until: S => S.log_state === 'done' && S.log_stomach === 'So-so' && !!S.log_bike, ok: 'The log is saved with the notes. The notes are kept first; if they cannot be kept, nothing is logged.',
      robot: [['in', 'log_bike', '1:05'], ['in', 'log_change', '1:20'], ['in', 'log_run', '30'], ['act', 'log.stomach', 'So-so'], ['act', 'log.saveb']] },
    { kind: 'look', head: 'Where the notes show afterwards', shot: 'log-03-done-notes',
      text: 'On the done session, <b>Your notes on this session</b> shows tiles (bike, change-over, run; open water, wetsuit, water; stomach with your words), then the niggle line. <b>Change niggle</b> and <b>Fuel notes</b> sit at the foot; <b>Change notes</b> opens the rest again.',
      hint: 'This picture mixes a brick and a swim to show every tile. Niggles you note are counted on Progress, in a card called Niggles.' },
    { kind: 'look', head: 'Fuel notes: every answer in one list', shot: 'log-04-fuel-notes',
      text: '<b>Fuel notes</b> opens a page with a blue head card that counts your answers (4 long sessions · 2 fine · 1 so-so · 1 upset), then one card for each long session, newest first: the date, the title, your answer, the length and your words.',
      hint: 'For learning what you take on long days. It gives no advice.', real: 'Stomach OK? › Fuel notes' },
    { kind: 'look', head: 'Niggles on Progress', shot: 'log-05-niggles',
      text: 'Every niggle you note is counted on Progress in a purple card <b>NIGGLES</b>: how many are noted and on how many places, each place with how often and since when, then every note by date. The last line points to the Stop sign page under Not well?',
      hint: 'The card is hidden until you have noted one.', real: 'Progress › Niggles' },
    { kind: 'look', head: 'The extra workout form', shot: 'log-06-extra-form',
      text: 'On Today, <b>Extra workout</b> opens this form: When, a note about Apple Health, <b>What kind of thing</b> (Walk here), <b>What it was</b>, Duration, Distance and Average heart rate, with Cancel and a green Save. Further down are Effort, Counts as training? and Notes.',
      real: 'Today › Extra workout' },
    { kind: 'try', head: 'An extra workout', set: { screen: 'log.today' }, target: S => S.sheet !== 'log.extra' ? 'log.xbtn' : !S.log_xwhat ? 'log.xwhat' : !S.log_xdur ? 'log.xdur' : 'log.xsave',
      text: 'Something the plan did not ask for. Press <b>Extra workout</b>, write “Dog walk”, a duration of 35, and press <b>Save</b>. It goes beside the plan, never into it.',
      real: 'Today › Extra workout', until: S => S.log_xrows.length === 1, ok: 'It is listed on Today under the plan. Press it and its page asks How hard was it? — a Walk does not count as training until you say so.',
      robot: [['act', 'log.xopen'], ['in', 'log_xwhat', 'Dog walk'], ['in', 'log_xdur', '35'], ['act', 'log.xsave']] },
    { kind: 'look', head: 'An extra, opened on its own', shot: 'log-07-extra-detail',
      text: 'Press a saved extra and its own page opens, headed <b>Extra workout</b> with Close at the top left. A card shows the kind (EXTRA · WALK), what it was and the length, with a tick. In the app, <b>How hard was it?</b> comes below it until you answer, and a round pen sits in the card’s corner; this picture shows neither.',
      hint: 'A walk does not count as training unless you say so.' },
    { kind: 'check', head: 'Where can you log?', text: 'Your plan lives in this app and in iCloud. You are on the iPad. Can you press Done there?',
      answers: ['No, only the iPhone logs', 'Yes: the plan is in the app, so every device logs', 'Only the Mac'], right: 1,
      ok: 'Right. Only a plan kept in Excel in Dropbox limits logging to the iPhone; Apple Health, though, is the iPhone’s alone.' },
  ],
});
const RPE = ['', 'Barely moving. You could keep this up all day.', 'Very easy. Warming up, or coming back down.', 'Easy. Talking takes no effort at all.', 'Steady. Still talking in whole sentences.', 'Moderate. The sentences are getting shorter.', 'Firm. A few words at a time.', 'Hard. Single words, and you are watching the clock.', 'Very hard. Talking is out.', 'Nearly everything. You are counting down to the end.', 'Everything. You could not hold this for long.'];
})();
