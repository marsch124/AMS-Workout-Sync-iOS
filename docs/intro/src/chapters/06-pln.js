/* Chapter 6 — The Plan page, on the iPad and the Mac (device 'pad' for the whole chapter).
   Sources: PlanPage, WeekBoard, MonthGrid, YearView, SeasonView, PlanNumbers, WideRoot, KeyCommands, SyncStatus; Core KeyGuide, PlanOverview. */
const PLN = {
  today: '2026-09-16',
  wd: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
  mo: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
  sports: { swim: 'Swim', bike: 'Bike', run: 'Run', strength: 'Strength', mobility: 'Mobility', rest: 'Rest' },
  css: { swim: 'sw', bike: 'bi', run: 'ru', strength: 'st', mobility: 'mo', rest: 're' },
  dt: d => { const [y, m, n] = d.split('-').map(Number); return new Date(Date.UTC(y, m - 1, n)); },
  key: t => t.toISOString().slice(0, 10),
  add: (d, n) => { const t = PLN.dt(d); t.setUTCDate(t.getUTCDate() + n); return PLN.key(t); },
  short: d => { const t = PLN.dt(d); return PLN.wd[t.getUTCDay()].slice(0, 3) + ' ' + t.getUTCDate() + ' ' + PLN.mo[t.getUTCMonth()].slice(0, 3); },
  monday: d => { const t = PLN.dt(d), k = (t.getUTCDay() + 6) % 7; return PLN.add(d, -k); },
  monthName: m => PLN.mo[+m.slice(5) - 1] + ' ' + m.slice(0, 4),
  addMonth: (m, n) => { const i = +m.slice(0, 4) * 12 + (+m.slice(5) - 1) + n; return String(Math.floor(i / 12)).padStart(4, '0') + '-' + String(i % 12 + 1).padStart(2, '0'); },
  lastDay: m => PLN.add(PLN.addMonth(m, 1) + '-01', -1),
  grid: m => { const rows = [], first = PLN.monday(m + '-01'), last = PLN.lastDay(m); for (let d = first; d <= last; d = PLN.add(d, 7)) rows.push([0, 1, 2, 3, 4, 5, 6].map(i => PLN.add(d, i))); return rows; },
  ses: () => [
    ['p1', '2026-09-09', 'swim', 'Easy technique', 30], ['p2', '2026-09-09', 'mobility', 'Hips and T-spine', 15], ['p3', '2026-09-10', 'run', 'Easy run, cadence', 30],
    ['r1', '2026-09-11', 'rest', 'Rest day', 0], ['p4', '2026-09-12', 'bike', 'Steady aerobic ride', 60], ['p5', '2026-09-13', 'run', 'Easy run + strides', 35],
    ['p6', '2026-09-13', 'strength', 'Squat, hinge, press, row', 30], ['p7', '2026-09-14', 'swim', 'Technique', 35], ['p8', '2026-09-15', 'bike', 'Easy spin, cadence 90+', 45],
    ['p9', '2026-09-16', 'run', 'Easy run + 4x20 s strides', 35], ['r2', '2026-09-18', 'rest', 'Rest day', 0], ['p10', '2026-09-19', 'bike', 'Steady aerobic ride', 65],
    ['p11', '2026-09-20', 'run', 'Easy run, flat route', 40]].map(([id, day, sport, title, min]) => ({ id, day, sport, title, min, st: 'todo' })),
  cols: () => Array.from({ length: 13 }, (_, i) => ({ d: i % 2 ? -1 : i / 2 })),
  range: S => S.pln_mode === 'week' ? [S.pln_week, PLN.add(S.pln_week, 6)] : S.pln_mode === 'month' ? [S.pln_month + '-01', PLN.lastDay(S.pln_month)] : ['2026-09-09', '2026-09-20'],
  inRange: (S, a, b) => S.pln_ses.filter(w => w.sport !== 'rest' && w.day >= a && w.day <= b),
  mins: l => l.reduce((n, w) => n + w.min, 0),
  scope: S => S.pln_mode === 'week' ? (S.pln_week === PLN.monday(PLN.today) ? 'This week' : 'Week of ' + PLN.short(S.pln_week)) : S.pln_mode === 'month' ? PLN.monthName(S.pln_month) : 'The season',
  title: S => S.pln_mode === 'week' ? PLN.short(S.pln_week) + ' – ' + PLN.short(PLN.add(S.pln_week, 6)) : S.pln_mode === 'month' ? PLN.monthName(S.pln_month) : 'Season 2026',
  face: w => `<b>${esc(w.title)}</b><span class="pln-len"><span>${w.min ? dur(w.min) : ''}</span>${w.st === 'done' ? K.done() : ''}</span>`,
  card: w => {
    const lift = w.st === 'todo' && w.sport !== 'rest';
    return `<button class="pln-card pln-${PLN.css[w.sport]}" data-act="pln.open" data-arg="${w.id}" data-t="pln.card:${w.id}"${lift ? ' data-grip' : ''}>${PLN.face(w)}</button>`;
  },
  seasonHTML: S => {
    const weeks = ['2026-09-07', '2026-09-14'].map(m => [m, PLN.mins(PLN.inRange(S, m, PLN.add(m, 6)))]), tall = Math.max(...weeks.map(w => w[1]), 1);
    const chosen = S.pln_mode === 'week' ? [S.pln_week] : S.pln_mode === 'month' ? PLN.grid(S.pln_month).map(r => r[0]) : [];
    return `<div class="pln-season" data-t="pln.season">${weeks.map(([m, n]) => `<button class="pln-bar${chosen.includes(m) ? ' pln-on' : ''}" data-act="pln.bar" data-arg="${m}" data-t="pln.bar:${m}" aria-label="Week of ${PLN.short(m)}"><b style="height:${Math.max(4, 54 * n / tall)}px"></b>${m === PLN.monday(PLN.today) ? `<u style="left:${100 * 2.5 / 7}%"></u>` : ''}</button>`).join('')}</div>
      <span class="k-muted" style="font-size:11px">Tap a bar to see its week</span>`;
  },
  head: S => {
    const [a, b] = PLN.range(S), l = PLN.inRange(S, a, b), planned = PLN.mins(l), done = PLN.mins(l.filter(w => w.st === 'done'));
    const steps = S.pln_mode === 'week' ? [['pln.week', '-1', 'Previous week', 'pln.prev'], ['pln.week', '0', 'This week', 'pln.this'], ['pln.week', '1', 'Next week', 'pln.next']]
      : S.pln_mode === 'month' ? [['pln.month', '-1', 'Previous month', 'pln.mprev'], ['pln.month', '0', 'This month', 'pln.mthis'], ['pln.month', '1', 'Next month', 'pln.mnext']] : [];
    return `<div class="pln-head">${K.seg([['week', 'Week'], ['month', 'Month'], ['year', 'Year']], S.pln_mode, 'pln.mode', 'pln.switch')}
        <span class="pln-steps"><button class="pln-step" data-act="pln.print" data-t="pln.print">Print</button>${steps.map(([act, arg, w, t]) => `<button class="pln-step" data-act="${act}" data-arg="${arg}" data-t="${t}">${w}</button>`).join('')}</span></div>
      <div class="pln-title"><b data-t="pln.title">${esc(PLN.title(S))}</b><span class="k-muted k-fig">${done > 0 ? dur(planned) + ' planned · ' + dur(done) + ' done' : dur(planned) + ' planned'}</span></div>`;
  },
  moved: S => S.pln_moved ? `<div class="pln-moved" data-t="pln.moved"><span>${esc(S.pln_moved.text)}</span>${K.btn('Undo', 'pln.undo', { t: 'pln.undo' })}</div>` : '',
  week: S => {
    const days = [0, 1, 2, 3, 4, 5, 6].map(i => PLN.add(S.pln_week, i));
    const col = (d, pos, index) => {
      const day = days[d], all = S.pln_ses.filter(w => w.day === day), tr = all.filter(w => w.sport !== 'rest'), show = tr.length ? tr : all;
      const head = PLN.short(day).split(' ').slice(0, 2).join(' ') + (PLN.dt(day).getUTCDay() === 1 || +day.slice(8) === 1 ? ' ' + PLN.mo[PLN.dt(day).getUTCMonth()].slice(0, 3) : '');
      const extras = day === '2026-09-15' ? `<div class="pln-rule"></div><div class="pln-extra pln-wa"><span>Dog walk<small>35m</small></span>${K.done()}</div>` : '';
      return `<div class="pln-col${day === PLN.today ? ' pln-today' : ''}" data-drag="pln_cols" data-i="${index}" data-t="pln.day:${day}"><span class="pln-h">${head}</span>${show.map(PLN.card).join('')}${extras}<button class="pln-add" data-act="pln.addnote">+ Add</button></div>`;
    };
    return `<span class="pln-hint">Drag a session to another day</span><div class="pln-board" data-t="pln.board">${S.pln_cols.map((c, i) => c.d < 0 ? `<i class="pln-dummy" hidden data-drag="pln_cols" data-i="${i}"></i>` : col(c.d, c.d, i)).join('')}</div>${PLN.moved(S)}`;
  },
  month: S => {
    const rows = PLN.grid(S.pln_month);
    return `<span class="pln-hint" data-t="pln.hint">Drag a session to another day</span><div class="pln-month" data-t="pln.monthgrid"><span></span>${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(d => `<span class="pln-mh">${d}</span>`).join('')}
      ${rows.map(r => { const l = PLN.inRange(S, r[0], r[6]), p = PLN.mins(l), dn = PLN.mins(l.filter(w => w.st === 'done'));
        return `<div class="pln-wk"><b>${p ? PLN.short(r[0]).split(' ').slice(0, 2).join(' ') + ' ' + PLN.mo[PLN.dt(r[0]).getUTCMonth()].slice(0, 3) : PLN.short(r[0])}</b>${p ? dur(p) : ''}${dn ? '<br>' + dur(dn) + ' done' : ''}</div>`
          + r.map(d => { const all = S.pln_ses.filter(w => w.day === d), tr = all.filter(w => w.sport !== 'rest'), show = tr.length ? tr : all;
            return `<div class="pln-cell${d === PLN.today ? ' pln-today' : ''}${d.startsWith(S.pln_month) ? '' : ' pln-out'}"><span>${+d.slice(8)}${d === PLN.today ? ' · Today' : ''}</span>${show.map(w => `<button class="pln-chip pln-${PLN.css[w.sport]}" style="border:0;text-align:left;font:inherit;color:inherit;cursor:pointer" data-act="pln.open" data-arg="${w.id}">${w.sport === 'rest' ? 'Rest day' : PLN.sports[w.sport]}${w.min ? '<small>' + dur(w.min) + '</small>' : ''}</button>`).join('')}</div>`; }).join(''); }).join('')}</div>${PLN.moved(S)}`;
  },
  year: S => {
    const m = '2026-09', rows = PLN.grid(m), l = PLN.inRange(S, m + '-01', PLN.lastDay(m));
    return `<div class="pln-year"><button class="pln-block" data-act="pln.openmonth" data-arg="${m}" data-t="pln.block:${m}"><b style="color:var(--s-ok-text)">September 2026</b><small>${dur(PLN.mins(l))}</small>
      <div class="pln-sq">${['M', 'T', 'W', 'T', 'F', 'S', 'S'].map(d => `<small style="text-align:center;font-size:9px">${d}</small>`).join('')}${rows.flat().map(d => {
        if (!d.startsWith(m)) return '<i class="pln-n"></i>';
        const ws = S.pln_ses.filter(w => w.day === d && w.sport !== 'rest').sort((a, b) => b.min - a.min);
        return `<i class="${ws.length ? 'pln-f pln-' + PLN.css[ws[0].sport] : ''}${d === PLN.today ? ' pln-t' : ''}"></i>`; }).join('')}</div></button></div>
      <span class="k-muted" style="font-size:11px">Recorded, still to do, missed, rest day, today. Colour = the day's main sport · Tap a month to open it</span>`;
  },
  numbers: S => {
    const [a, b] = PLN.range(S), l = PLN.inRange(S, a, b), per = {};
    l.forEach(w => { per[w.sport] = per[w.sport] || [0, 0]; per[w.sport][0] += w.min; if (w.st === 'done') per[w.sport][1] += w.min; });
    const keys = Object.keys(per).sort((x, y) => per[y][0] - per[x][0]), most = Math.max(1, ...keys.map(k => per[k][0]));
    const due = l.filter(w => w.day < PLN.today || (w.day === PLN.today && w.st === 'done')), dn = due.filter(w => w.st === 'done').length;
    return `<div class="pln-nums" data-t="pln.numbers">
      <div class="pln-num"><span class="pln-nt">By sport<small>${esc(PLN.scope(S))}</small></span>${keys.length ? keys.map(k => `<div class="pln-sp pln-${PLN.css[k]}"><span><b>${PLN.sports[k]}</b> ${per[k][1] ? dur(per[k][1]) + ' done of ' + dur(per[k][0]) : dur(per[k][0]) + ' planned'}</span><i><em style="width:${100 * per[k][0] / most}%"></em></i></div>`).join('') : '<span class="k-muted k-small">Nothing planned</span>'}</div>
      <div class="pln-num"><span class="pln-nt">Load<small>last 12 weeks, up to today</small></span><div class="pln-load">${'<i></i>'.repeat(12)}</div><span class="k-small k-muted">This week so far 105</span><span class="k-muted" style="font-size:10.5px">Load = minutes × how hard (1–10)</span></div>
      <div class="pln-num"><span class="pln-nt">Plan followed<small>${esc(PLN.scope(S))}</small></span>${due.length ? `<span class="k-small"><b>${dn} of ${due.length} sessions due so far</b> <span class="k-muted">${Math.round(100 * dn / due.length)} %</span></span>` : '<span class="k-muted k-small">Nothing due yet</span>'}</div></div>`;
  },
};

CHAPTER({
  id: 'pln',
  title: 'The Plan page',
  icon: 'calendar',
  needs: 'An iPad or a Mac. The keys need a keyboard.',
  gives: 'The whole season, a week, a month or the year on one page, your numbers beside it, a session moved to another day by a drag, and the keys for a quick way round.',
  start: () => ({ device: 'pad', part: 'plan', screen: 'pln.plan', pln_mode: 'week', pln_week: '2026-09-14', pln_month: '2026-09', pln_ses: PLN.ses(), pln_cols: PLN.cols(),
    pln_moved: null, pln_seen: [], pln_year: false, pln_done: false }),
  screens: {
    'pln.plan': S => `${PLN.seasonHTML(S)}${PLN.head(S)}${S.pln_mode === 'week' ? PLN.week(S) : S.pln_mode === 'month' ? PLN.month(S) : PLN.year(S)}${PLN.numbers(S)}`,
    'pln.session': S => { const w = S.pln_ses.find(x => x.id === S.pln_open) || S.pln_ses[0];
      return `${K.back('Plan', 'pln.back', { t: 'pln.back' })}
        <span class="k-line">${K.sport(w.sport, { size: 40 })}<span class="k-col"><span class="k-sportword k-sp-${w.sport}">${esc(PLN.sports[w.sport])}</span><span class="k-muted">${esc(PLN.long(w.day))}</span></span></span>
        <b style="font-size:19px">${esc(w.title)}</b><span class="k-muted k-small">Why: easy aerobic — builds your base without costing much.</span>
        <span class="k-line">${K.chip(dur(w.min))}${K.chip('Z2')}</span>
        ${w.st === 'done' ? `<div class="k-band k-ok" data-t="pln.logged">${K.done()}<span>Done · ${dur(w.min)}</span></div>`
          : `<div class="k-line">${K.btn('Done · ' + dur(w.min), 'pln.done', { main: true, icon: 'check', t: 'pln.done' })}${K.btn('Log details', 'pln.note')}${K.btn('Missed', 'pln.note', { danger: true })}${K.btn('Move', 'pln.note')}</div>`}`; },
  },
  sidefoot: S => `<button class="pln-keys" data-act="pln.keys" data-t="pln.keys">Keys</button><span class="pln-sync"><i></i>Same on all devices</span>`,
  sheets: {
    'pln.keys': S => `<div class="pln-keyhead" data-t="pln.keysplate"><b>Keys</b><span>For an iPad with a keyboard, and the Mac. Hold ⌘ on an iPad to see them too.</span></div>
      ${[['⌘1 … ⌘6', 'Open Today, Plan, Sessions, Body, Progress, Settings'], ['⌘N', 'New session, on the day shown or today'],
        ['← →', 'On Plan: the week before or after (Week), the month before or after (Month)'], ['⌘T', 'Jump to today'],
        ['Space', 'On an open session: Done as planned, where that button is'], ['⌘F', 'Go to the search box, on a page that has one'],
        ['Esc', 'Close the open page without saving'], ['? or ⌘/', 'Show this list']].map(([k, a]) => `<div class="pln-keyrow"><code>${k}</code><span>${a}</span></div>`).join('')}
      <div class="k-foot" style="justify-content:center">${K.btn('Done', 'sheet.close', { main: true, t: 'pln.keysdone' })}</div>`,
    'pln.print': S => `<h3 style="text-align:center">Print the plan</h3><span>Choose This week, Next week or This month, look at the page, then Print or Save as PDF. The Sessions chapter shows the page of choices.</span>
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}</div>`,
  },
  actions: {
    'pln.mode'(arg, S) { S.pln_mode = arg; if (arg === 'year') S.pln_year = true; },
    'pln.bar'(arg, S) { S.pln_week = arg; S.pln_mode = 'week'; },
    'pln.week'(arg, S) { S.pln_week = arg === '0' ? PLN.monday(PLN.today) : PLN.add(S.pln_week, 7 * Number(arg)); S.pln_seen.push('w' + arg); },
    'pln.month'(arg, S) { S.pln_month = arg === '0' ? PLN.today.slice(0, 7) : PLN.addMonth(S.pln_month, Number(arg)); },
    'pln.openmonth'(arg, S) { S.pln_month = arg; S.pln_mode = 'month'; },
    'pln.print'(arg, S) { S.sheet = 'pln.print'; },
    'pln.addnote'() { toast('A new session has its own chapter: Sessions.'); },
    'pln.note'() { toast('That has its own chapter.'); },
    'pln.open'(arg, S) { S.pln_open = arg; S.screen = 'pln.session'; },
    'pln.back'(arg, S) { S.screen = 'pln.plan'; },
    'pln.done'(arg, S) { const w = S.pln_ses.find(x => x.id === S.pln_open); if (w && w.st === 'todo') { w.st = 'done'; S.pln_done = true; } },
    'pln.keys'(arg, S) { S.sheet = 'pln.keys'; },
    'pln.undo'(arg, S) { const m = S.pln_moved; if (!m) return; const w = S.pln_ses.find(x => x.id === m.id); if (w) w.day = m.prev; S.pln_moved = null; },
    /* A drag of a session card over another day's column. The list has a hidden row between every two days, so the card that was
       lifted is told apart from the days it pushed along: it is the one that moved by more than one place. */
    drop(key, S) {
      if (key !== 'pln_cols') return;
      const c = S.pln_cols; let at = -1; c.forEach((x, i) => { if (x.d >= 0 && Math.abs(i - 2 * x.d) >= 2) at = i; });
      S.pln_cols = PLN.cols(); if (at < 0) return;
      const from = PLN.add(S.pln_week, c[at].d), to = PLN.add(S.pln_week, at / 2);
      const w = S.pln_ses.find(x => x.day === from && x.st === 'todo' && x.sport !== 'rest'); if (!w) return;
      w.day = to; S.pln_moved = { id: w.id, prev: from, text: `${w.title} moved to ${PLN.short(to)}` };
    },
    /* The keys that need no ⌘: the arrows, Space, ?, Escape. */
    key(k, S) {
      if (S.sheet === 'pln.keys') { if (k === 'Escape') S.sheet = null; return; }
      if (S.sheet) { if (k === 'Escape') S.sheet = null; return; }
      if (k === '?') { S.sheet = 'pln.keys'; return; }
      if (S.screen === 'pln.session') { if (k === ' ') { const w = S.pln_ses.find(x => x.id === S.pln_open); if (w && w.st === 'todo') { w.st = 'done'; S.pln_done = true; } } return; }
      if (k === 'ArrowLeft' || k === 'ArrowRight') {
        const d = k === 'ArrowRight' ? 1 : -1;
        if (S.pln_mode === 'week') S.pln_week = PLN.add(S.pln_week, 7 * d); else if (S.pln_mode === 'month') S.pln_month = PLN.addMonth(S.pln_month, d);
      }
    },
  },
  steps: [
    { kind: 'look', head: 'One page for the whole plan', shot: 'pln-01-week', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'This is <b>Plan</b>, the page the iPhone does not have. At the top are the season’s bars, one for each week. Under them are the switch <b>Week · Month · Year</b> and small green buttons, the line "Drag a session to another day", the week as a board with <b>+ Add</b> in each day, and below it your numbers: By sport, Load and Plan followed.',
      hint: 'At the foot of the side list stand the word Keys and a dot with its words, here "iCloud is off". Wide enough, the numbers stand in a column beside the board.' },
    { kind: 'try', head: 'Choose a week from the season', set: { pln_mode: 'month' }, target: 'pln.bar:2026-09-07', only: 'iPad and Mac',
      text: 'Each bar is a week, as tall as the hours planned in it. A line marks today. Press the <b>first</b> bar.',
      until: S => S.pln_mode === 'week' && S.pln_week === '2026-09-07', real: 'Plan, the bars at the top',
      ok: 'The page switches to Week and shows that week. The outline round a bar says which week, or which weeks, the page shows.',
      robot: [['act', 'pln.bar', '2026-09-07']] },
    { kind: 'try', head: 'Week, Month, Year', only: 'iPad and Mac', target: S => !S.pln_year ? 'pln.mode:year' : 'pln.block:2026-09',
      text: 'The switch holds the three views. Press <b>Year</b>, then press the block <b>September 2026</b>.',
      until: S => S.pln_year && S.pln_mode === 'month', ok: 'A month in the Year view opens in Month. Week, Month and Year share the choice, so the title and the numbers follow it.',
      robot: [['act', 'pln.mode', 'year'], ['act', 'pln.openmonth', '2026-09']] },
    { kind: 'look', head: 'The Year view', shot: 'pln-03-year',
      text: 'The title now says <b>Season 2026</b>. Under it a block for each month, here <b>September 2026</b>, with a small calendar of squares. A square has the colour of the day\u2019s main sport, pale while still to do. The green outline is today. The line under the blocks explains the squares. Press a block to open that month.' },
    { kind: 'look', head: 'The month as a calendar', shot: 'pln-02-month', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'The Month view has a row for each week, with the week’s hours at its left, and a cell for each day. Today’s cell is green. The days of the neighbouring months are pale. The numbers under it now say <b>September 2026</b>.',
      hint: 'A session still to do can be dragged to another day in the Month too, exactly as in the Week.' },
    { kind: 'try', head: 'Move to another week', only: 'iPad and Mac', target: S => S.pln_seen.includes('w1') ? 'pln.this' : 'pln.next',
      text: 'In Week, press <b>Next week</b>, then <b>This week</b>. These buttons change nothing in the plan.',
      until: S => S.pln_seen.includes('w1') && S.pln_week === '2026-09-14' && S.pln_seen.includes('w0'), ok: 'Back on the week that holds today. Month has Previous month, This month and Next month in the same place.',
      robot: [['act', 'pln.week', '1'], ['act', 'pln.week', '0']] },
    { kind: 'try', head: 'Open a session, and mark it done', only: 'iPad and Mac', target: S => S.screen === 'pln.session' ? 'pln.done' : 'pln.card:p9',
      text: 'Press today’s card <b>Easy run + 4x20 s strides</b>. On the session’s page, press <b>Done · 35m</b>. Or press the <b>Space</b> bar on a keyboard.',
      until: S => S.pln_done, ok: 'The session is done as planned, 35m. There is no question first.',
      hint: 'Space only works while no page or question lies over the session.',
      robot: [['act', 'pln.open', 'p9'], ['key', ' ']] },
    { kind: 'try', head: 'Drag a session to another day', only: 'iPad and Mac', target: S => S.pln_moved ? 'pln.moved' : 'pln.card:p10',
      text: 'Press the card <b>Steady aerobic ride</b> on Saturday, hold, and let go over the column <b>Fri 18</b>. The column you are over gets a blue frame.',
      hint: 'Only a session still to do can be lifted. A done session, a missed one and a rest day stay. There are no arrow buttons.',
      until: S => S.pln_ses.find(w => w.id === 'p10').day === '2026-09-18', real: 'Plan, Week and Month',
      ok: 'A line says "Steady aerobic ride moved to Fri 18 Sep", with <b>Undo</b>. In the real app it stays for eight seconds. The move is listed under Changes to the plan.',
      robot: [['drag', 'pln_cols', 10, 8]] },
    { kind: 'try', head: 'Undo the move', only: 'iPad and Mac', target: 'pln.undo',
      set: () => { const ses = PLN.ses(); ses.find(w => w.id === 'p10').day = '2026-09-18'; return { pln_ses: ses, pln_moved: { id: 'p10', prev: '2026-09-19', text: 'Steady aerobic ride moved to Fri 18 Sep' } }; },
      text: 'Press <b>Undo</b> in the line under the board.', until: S => S.pln_ses.find(w => w.id === 'p10').day === '2026-09-19',
      ok: 'The ride is back on Saturday. Later, the same undo is under Settings › Changes to the plan.',
      robot: [['act', 'pln.undo']] },
    { kind: 'try', head: 'The Keys plate', only: 'iPad and Mac', target: 'pln.keys',
      text: 'At the foot of the side list stands the word <b>Keys</b>, and under it a dot with its words. Press <b>Keys</b>. On a keyboard the <b>?</b> key does the same.',
      until: S => S.sheet === 'pln.keys', ok: 'The plate lists every key, with its action beside it. Done closes it, and so does Esc.',
      hint: 'The dot always comes with words: Same on all devices, On its way, iCloud is off, or the words of a problem.',
      robot: [['key', '?']] },
    { kind: 'look', head: 'What each key does', shot: 'pln-04-keys', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'The slate head card says the keys are for an iPad with a keyboard and the Mac. Eight tiles follow: <b>⌘1 … ⌘6</b> open the six pages, <b>⌘N</b> a new session, <b>← →</b> the week or month before or after, <b>⌘T</b> today, <b>Space</b> Done as planned, <b>⌘F</b> the search box, <b>Esc</b> closes a page without saving, and <b>?</b> shows the list.' },
    { kind: 'try', head: 'Step through weeks with the arrows', only: 'iPad and Mac', target: 'pln.next',
      text: 'On the Plan page, press the right arrow key to go to the next week, then the left arrow key to come back.',
      until: S => S.pln_week === '2026-09-21', ok: 'The week after. In Month the same arrows move a month; in Year they do nothing. They never act while you type or while a page lies over the Plan.',
      robot: [['key', 'ArrowRight']] },
    { kind: 'look', head: 'Print from the Plan page', shot: 'pln-05-print', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'The small green <b>Print</b> button sits first among the step buttons. It opens <b>Print the plan</b>: This week, Next week or This month, one page to look at, then Cancel, Save as PDF or the green Print. The Sessions chapter shows the same page.',
      hint: 'Pull the page down to refresh it, on Today and on Plan.' },
    { kind: 'look', head: 'Print the month', shot: 'pln-06-print-month', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'With <b>This month</b> chosen the sheet stands upright: September 2026 as a calendar, a small coloured bar with the sport and length in each day, and at the foot "Total 7h 00m · 11 sessions" with the time per sport. Cancel, Save as PDF and the green Print are under it.' },
    { kind: 'look', head: 'A session takes the whole page', shot: 'pln-07-session-beside', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'Press a session on the board and its page opens over the whole screen, the side list gone: Run, Wednesday 16 September, the title, the grey Why line, <b>Save as favourite</b> and <b>Repeat…</b>, the green <b>Done · 35m</b> with Log details, Missed and Move, and <b>Change</b> at the right.' },
    { kind: 'look', head: 'Where Ask about your plan sits', shot: 'pln-08-week-ask', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'On the Week view the small blue button <b>Ask about your plan</b> stands under the heading, above the line about dragging. The Claude chapter teaches it.' },
    { kind: 'check', head: 'A dot at the foot of the side list', only: 'iPad and Mac', text: 'The dot at the foot says <b>On its way</b>. What does it tell you?',
      answers: ['The plan is travelling through iCloud and is not yet the same everywhere', 'The plan has a problem and nothing is saved', 'iCloud is switched off'], right: 0,
      ok: 'Right. The dot always has its words: Same on all devices, On its way, iCloud is off, or the words of a problem.' },
    { kind: 'check', head: 'Dragging a done session', only: 'iPad and Mac', text: 'You press a session you already did and try to drag it to another day. What happens?',
      answers: ['Nothing: only a session still to do can be lifted', 'It moves and is marked as not done', 'A question asks whether to move it'], right: 0,
      ok: 'Right. A done session, a missed one and a rest day stay where they are.' },
  ],
});
PLN.long = d => { const t = PLN.dt(d); return PLN.wd[t.getUTCDay()] + ' ' + t.getUTCDate() + ' ' + PLN.mo[t.getUTCMonth()]; };
