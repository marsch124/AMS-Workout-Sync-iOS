/* Chapter 5 — Sessions: the list on the iPhone's Sessions tab (and the Sessions row on the iPad and the Mac).
   Sources: PlanTab, SessionSearch, PlanPrint, PlanChangesView, SessionEditView, Favourites, Components; Core SessionSearch, PlanOverview. */
const LST = {
  today: '2026-09-16',
  sports: { swim: 'Swim', bike: 'Bike', run: 'Run', strength: 'Strength', mobility: 'Mobility', brick: 'Brick', race: 'Race', rest: 'Rest', other: 'Other' },
  css: { swim: 'sw', bike: 'bi', run: 'ru', strength: 'st', mobility: 'mo' },
  wd: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
  mo: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
  dt: d => { const [y, m, n] = d.split('-').map(Number); return new Date(Date.UTC(y, m - 1, n)); },
  key: dt => dt.toISOString().slice(0, 10),
  add: (d, n) => { const t = LST.dt(d); t.setUTCDate(t.getUTCDate() + n); return LST.key(t); },
  short: d => { const t = LST.dt(d); return LST.wd[t.getUTCDay()].slice(0, 3) + ' ' + t.getUTCDate() + ' ' + LST.mo[t.getUTCMonth()].slice(0, 3); },
  long: d => { const t = LST.dt(d); return LST.wd[t.getUTCDay()] + ' ' + t.getUTCDate() + ' ' + LST.mo[t.getUTCMonth()]; },
  fold: s => String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/ß/g, 'ss'),
  words: q => LST.fold(q).split(/[ ,\t]+/).filter(Boolean),
  dateWords: d => { const t = LST.dt(d), w = LST.wd[t.getUTCDay()], m = LST.mo[t.getUTCMonth()];
    return `${w} ${w.slice(0, 3)} ${m} ${m.slice(0, 3)} ${t.getUTCFullYear()} ${t.getUTCDate()} ${d}`; },
  fields: w => [['Notes', w.notes || ''], ['Title', w.title], ['Sport', LST.sports[w.sport] + ' ' + w.sport], ['Date', LST.dateWords(w.day)]],
  matches: (ws, w) => { const hs = LST.fields(w).map(f => LST.fold(f[1])); return ws.length > 0 && ws.every(x => hs.some(h => h.includes(x))); },
  found: (ws, w) => {
    if (w.notes && ws.some(x => LST.fold(w.notes).includes(x))) return 'Notes: ' + w.notes;
    const where = LST.fields(w).filter(f => ['Title', 'Sport', 'Date'].includes(f[0]) && ws.some(x => LST.fold(f[1]).includes(x))).map(f => f[0].toLowerCase());
    return where.length ? 'Found in the ' + where.join(' and ') : '';
  },
  groupOf: w => w.st === 'done' ? 'Done' : w.st === 'missed' ? 'Missed' : 'To come',
  /* The four lists */
  list: (S, r) => S.lst_ses.filter(w => r === 'all' ? true : r === 'upcoming' ? w.st === 'todo' : w.st === r),
  count: (S, r) => LST.list(S, r === 'all' ? 'all' : r).length,
  card: (w, showDay) => `<div class="k-card lst-card ${w.st === 'done' ? 'lst-done' : w.st === 'missed' ? 'lst-miss' : ''}">
      ${K.sport(w.sport)}<span class="lst-words"><span class="k-sportword k-sp-${w.sport}">${esc(LST.sports[w.sport])}</span>
      <b class="lst-title">${esc(w.title)}</b>
      <span class="k-line">${showDay ? K.chip(LST.short(w.day)) : ''}${w.min ? K.chip(dur(w.min)) : ''}${w.zone ? K.chip(w.zone) : ''}${w.st === 'missed' ? '<span class="k-chip lst-missed">Missed</span>' : ''}</span></span>
      ${w.st === 'done' ? K.done() : ''}</div>`,
  /* The paper */
  items: (S, from, to) => S.lst_ses.filter(w => w.day >= from && w.day <= to),
  paperItem: w => `<div class="lst-p-item lst-${LST.css[w.sport] || 'st'}"><i></i><span><b>${esc(LST.sports[w.sport])}${w.min ? ' ' + dur(w.min) : ''}</b>${esc(w.title)}<em>${[w.min ? dur(w.min) : '', w.zone].filter(Boolean).join(' · ')}</em></span></div>`,
  totals: (its) => { const per = {}; its.forEach(w => { per[w.sport] = (per[w.sport] || 0) + (w.min || 0); });
    const order = ['swim', 'bike', 'run', 'strength', 'mobility'], keys = Object.keys(per).sort((a, b) => (order.indexOf(a) + 99) % 99 - (order.indexOf(b) + 99) % 99);
    return `<div class="lst-p-tot">Total ${dur(its.reduce((a, w) => a + (w.min || 0), 0))} · ${its.length} sessions${keys.map(k => `<span>${LST.sports[k]} ${dur(per[k])}</span>`).join('')}</div>`; },
  paper: (S) => {
    const k = S.lst_print;
    if (k === 'this-month') {
      const first = '2026-09-01', last = '2026-09-30', its = LST.items(S, first, last);
      const days = []; for (let i = 0; i < 35; i++) days.push(LST.add('2026-08-31', i));
      return `<div class="lst-paper lst-m"><div class="lst-p-head">September 2026<small>This month</small></div>
        <div class="lst-p-month">${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(d => `<div class="lst-h">${d}</div>`).join('')}
        ${days.map(d => { const inM = d.startsWith('2026-09'); return `<div class="${inM ? '' : 'lst-out'}">${+d.slice(8)}${inM ? LST.items(S, d, d).map(LST.paperItem).join('') : ''}</div>`; }).join('')}</div>${LST.totals(its)}</div>`;
    }
    const start = k === 'this-week' ? '2026-09-14' : '2026-09-21', end = LST.add(start, 6), its = LST.items(S, start, end);
    return `<div class="lst-paper lst-w"><div class="lst-p-head">${LST.short(start)} – ${LST.short(end)} 2026<small>${k === 'this-week' ? 'This week' : 'Next week'}</small></div>
      <div class="lst-p-week">${[0, 1, 2, 3, 4, 5, 6].map(i => { const d = LST.add(start, i), ws = LST.items(S, d, d);
        return `<div><div class="lst-d">${LST.short(d)}</div>${ws.length ? ws.map(LST.paperItem).join('') : '<span style="color:#666">Rest</span>'}</div>`; }).join('')}</div>${LST.totals(its)}</div>`;
  },
};

CHAPTER({
  id: 'lst',
  title: 'Sessions',
  icon: 'bike',
  needs: 'Nothing but your plan.',
  gives: 'Every session of the plan in one list, a way to find one by a word, a session of your own in a minute, the plan on paper, and a way back from any change.',
  start: () => ({ device: 'phone', part: 'sessions', screen: 'lst.list', lst_range: 'upcoming', lst_seen: [], lst_query: '', lst_can: true,
    lst_ses: [
      { id: 's1', day: '2026-09-09', sport: 'swim', title: 'Easy technique: 4x50 drill, then 6x50 smooth', min: 30, zone: 'Z1-Z2', st: 'done', notes: '' },
      { id: 's2', day: '2026-09-09', sport: 'mobility', title: 'Hips and T-spine', min: 15, zone: '', st: 'done', notes: '' },
      { id: 's3', day: '2026-09-12', sport: 'bike', title: 'Steady aerobic ride, flat to rolling', min: 60, zone: 'Z2', st: 'done', notes: 'Calf felt tight on the climb' },
      { id: 's4', day: '2026-09-13', sport: 'run', title: 'Easy run + strides', min: 35, zone: 'Z2', st: 'done', notes: '' },
      { id: 's5', day: '2026-09-13', sport: 'strength', title: 'Squat, hinge, press, row', min: 30, zone: 'RPE 7', st: 'missed', notes: '' },
      { id: 's6', day: '2026-09-14', sport: 'swim', title: 'Technique: 8x50 drills + 6x100 easy', min: 35, zone: 'Z1-Z2', st: 'done', notes: '' },
      { id: 's7', day: '2026-09-15', sport: 'bike', title: 'Easy spin, cadence 90+', min: 45, zone: 'Z1', st: 'done', notes: '' },
      { id: 's8', day: '2026-09-16', sport: 'run', title: 'Easy run + 4x20 s strides', min: 35, zone: 'Z2', st: 'todo', notes: '' },
      { id: 's9', day: '2026-09-19', sport: 'bike', title: 'Steady aerobic ride', min: 65, zone: 'Z2', st: 'todo', notes: '' },
      { id: 's10', day: '2026-09-20', sport: 'run', title: 'Easy run, flat route', min: 40, zone: 'Z2', st: 'todo', notes: '' }],
    lst_changes: [
      { id: 'c2', kind: 'change', at: '14 Sep 2026 at 18:20', title: 'Steady aerobic ride', sid: 's9', before: 'Thu 17 Sep · 1h 00m', after: 'Sat 19 Sep · 1h 05m', undone: false, back: { day: '2026-09-17', min: 60 } },
      { id: 'c1', kind: 'change', at: '13 Sep 2026 at 20:05', title: 'Steady aerobic ride', sid: 's9', before: 'Thu 17 Sep · 45m', after: 'Thu 17 Sep · 1h 00m', undone: false, back: null }],
    lst_undo: '', lst_print: 'this-week',
    lst_day: '2026-09-17', lst_sport: 'run', lst_title: '', lst_min: '', lst_zone: '', lst_purpose: '', lst_key: false, lst_problem: '', lst_added: false }),
  screens: {
    'lst.list': S => {
      const searching = LST.words(S.lst_query).length > 0;
      const head = `<h1 class="k-h1">Sessions</h1>
        <div class="k-line" data-t="lst.buttons">${K.btn('Print', 'lst.printopen', { out: true, t: 'lst.print' })}${S.lst_can ? K.btn('+ Session', 'lst.add', { t: 'lst.add' }) : ''}${K.btn('Ask about your plan', 'lst.ask', { t: 'lst.ask' })}</div>
        <div class="lst-search">${K.input('lst_query', S, { ph: 'Search sessions', t: 'lst.search' })}${S.lst_query ? K.btn('Clear', 'lst.clear', { t: 'lst.clear' }) : ''}</div>`;
      if (searching) {
        const ws = LST.words(S.lst_query), hits = S.lst_ses.filter(w => LST.matches(ws, w)).sort((a, b) => a.day !== b.day ? (a.day < b.day ? 1 : -1) : (a.id < b.id ? -1 : 1));
        const groups = ['To come', 'Done', 'Missed'].map(g => [g, hits.filter(w => LST.groupOf(w) === g)]).filter(g => g[1].length);
        return head + (groups.length ? '' : `<p class="lst-empty" data-t="lst.empty">Nothing found for '${esc(S.lst_query.trim())}'.</p>`)
          + groups.map(([g, list]) => `<div class="lst-day">${g}</div>` + list.map(w => `<div data-t="lst.hit">${LST.card(w, true)}<div class="lst-found">${esc(LST.found(ws, w))}</div></div>`).join('')).join('');
      }
      const r = S.lst_range, rows = LST.list(S, r), newest = r === 'done' || r === 'missed';
      const days = [...new Set(rows.map(w => w.day))].sort(); if (newest) days.reverse();
      const n = k => LST.count(S, k), done = n('done'), missed = n('missed'), todo = n('upcoming'), total = Math.max(1, done + missed + todo);
      const empty = { upcoming: 'Nothing left in the plan.', done: 'Nothing recorded yet.', missed: 'Nothing marked missed.', all: 'The plan is empty.' }[r];
      return head + `<div class="lst-filters">${[['upcoming', 'Upcoming'], ['done', 'Done'], ['missed', 'Missed'], ['all', 'All']].map(([id, t]) =>
        `<button class="lst-filt${r === id ? ' k-on' : ''}" data-act="lst.range" data-arg="${id}" data-t="lst.range:${id}"><span>${t}</span><b>${id === 'all' ? done + missed + todo : n(id)}</b></button>`).join('')}</div>
        <div class="lst-bar" data-t="lst.bar">${done ? `<i class="lst-b-done" style="width:${100 * done / total}%"></i>` : ''}${missed ? `<i class="lst-b-missed" style="width:${100 * missed / total}%"></i>` : ''}${todo ? `<i class="lst-b-todo" style="width:${100 * todo / total}%"></i>` : ''}</div>`
        + (days.length ? '' : `<p class="lst-empty">${empty}</p>`)
        + days.map(d => `<div class="lst-day">${LST.long(d)}</div>` + rows.filter(w => w.day === d).map(w => `<div data-t="lst.row:${w.id}">${LST.card(w, false)}</div>`).join('')).join('');
    },
    'lst.changes': S => `${K.back('Settings', 'lst.settings', { t: 'lst.back' })}
      <h1 class="k-h1">Changes to the plan</h1>
      ${S.lst_changes.length ? '' : '<p class="lst-empty">No changes yet. Open a session and tap Change.</p>'}
      ${S.lst_changes.map((c, i) => {
        const newest = S.lst_changes.findIndex(x => x.sid === c.sid) === i;
        const word = { add: 'Added', remove: 'Taken out', change: 'Changed' }[c.kind];
        return `<div class="lst-chg${c.undone ? ' lst-u' : ''}" data-t="lst.chg:${c.id}">
          <span class="k-line"><span class="lst-kind${c.kind === 'remove' ? ' lst-rem' : ''}">${word}</span><span class="lst-grey">${esc(c.at)}</span><span class="k-sp"></span>
          ${c.undone ? '<b class="lst-grey">Undone</b>' : newest ? K.btn('Undo', 'lst.undoask', { arg: c.id, t: 'lst.undo:' + c.id }).replace('class="k-btn', `class="k-btn lst-undo${c.kind === 'add' ? ' lst-danger' : ''}`) : '<span class="lst-grey" data-t="lst.older">Changed again since</span>'}</span>
          <b>${esc(c.title)}</b>
          ${c.before ? `<span class="lst-grey">Before: ${esc(c.before)}</span>` : ''}${c.after ? `<span class="lst-grey">Now: ${esc(c.after)}</span>` : ''}</div>`; }).join('')}`,
  },
  sheets: {
    'lst.new': S => {
      const favs = [['f1', 'bike', 'Aerobic ride, steady Z2', '1h 00m'], ['f2', 'run', 'Easy run', '40m'], ['f3', 'swim', 'Drills and 6 x 200', '45m']];
      return `<div class="lst-top">${K.btn('Cancel', 'sheet.close', { quiet: true, t: 'lst.cancel' })}<h3>New session</h3><span></span></div>
        <b class="k-small" style="color:var(--pt)">Your favourites</b>
        <div class="lst-favs">${favs.map(([id, sp, t, l]) => `<button class="lst-fav" data-act="lst.fav" data-arg="${id}" data-t="lst.fav:${id}">${K.sport(sp, { size: 26 })}<span><b class="k-small">${esc(t)}</b><small>${l}</small></span></button>`).join('')}</div>
        <span class="k-muted k-small">Tap one to fill the page. You can still change everything before Save.</span>
        <div class="k-field"><label for="in-lst_day">Day</label>${K.select('lst_day', S, [0, 1, 2, 3, 4, 5, 6].map(i => [LST.add('2026-09-17', i), LST.short(LST.add('2026-09-17', i))]), { t: 'lst.day' })}</div>
        <div class="k-field"><label for="in-lst_sport">Sport</label>${K.select('lst_sport', S, Object.entries(LST.sports), { t: 'lst.sport' })}</div>
        <div class="k-field"><label for="in-lst_title">What you do</label>${K.input('lst_title', S, { ph: 'What the session is', t: 'lst.title' })}</div>
        <div class="k-field"><label for="in-lst_min">Length (minutes)</label>${K.input('lst_min', S, { ph: '40', num: true, w: 70, t: 'lst.min' })}</div>
        <div class="k-field"><label for="in-lst_zone">Zone or effort</label>${K.input('lst_zone', S, { ph: 'Like Z2 or Z4–Z5', t: 'lst.zone' })}</div>
        <div class="k-field"><label for="in-lst_purpose">Purpose</label>${K.input('lst_purpose', S, { ph: 'What it is for', t: 'lst.purpose' })}</div>
        ${K.switch(S.lst_key, 'Key session', 'lst.keyflip')}
        <span class="k-small"><b>Repeat</b> <span class="k-muted">Does not repeat · Every week until…</span></span>
        <div class="lst-sticky">${S.lst_problem ? `<div class="lst-line-bad" data-t="lst.problem">${esc(S.lst_problem)}</div>` : ''}
        <div class="k-foot">${K.btn('Save', 'lst.save', { main: true, t: 'lst.save' })}</div></div>`;
    },
    'lst.print': S => `<h3 style="text-align:center">Print the plan</h3>
      <div class="lst-choices" data-t="lst.choices">${[['this-week', 'This week'], ['next-week', 'Next week'], ['this-month', 'This month']].map(([id, t]) =>
        `<button class="${S.lst_print === id ? 'k-on' : ''}" data-act="lst.printkind" data-arg="${id}" data-t="lst.kind:${id}">${t}</button>`).join('')}</div>
      <div class="lst-paperbox" data-t="lst.paper">${LST.paper(S)}</div>
      <span class="k-muted k-small">Drag the page to read it. The printout is the whole page.</span>
      <div class="k-line">${K.btn('Cancel', 'sheet.close', { quiet: true, t: 'lst.pcancel' })}<span class="k-sp"></span>${K.btn('Save as PDF', 'lst.pdf', { t: 'lst.pdf' })}${K.btn('Print', 'lst.printdo', { main: true, t: 'lst.printdo' })}</div>`,
    'lst.undo': S => { const c = S.lst_changes.find(x => x.id === S.lst_undo) || {};
      return `<h3>Undo this change?</h3>${c.kind === 'add' ? '<span>The session is taken out of the plan again.</span>' : ''}
        <div class="k-foot">${K.btn('Keep it', 'lst.undono', { t: 'lst.keep' })}${K.btn('Undo', 'lst.undoyes', { main: true, t: 'lst.undoyes' })}</div>`; },
  },
  actions: {
    'lst.range'(arg, S) { S.lst_range = arg; if (!S.lst_seen.includes(arg)) S.lst_seen.push(arg); },
    'lst.clear'(arg, S) { S.lst_query = ''; },
    'lst.ask'() { toast('Ask about your plan has its own chapter.'); },
    'lst.add'(arg, S) { S.sheet = 'lst.new'; },
    'lst.keyflip'(arg, S) { S.lst_key = !S.lst_key; },
    'lst.fav'(arg, S) {
      const f = { f1: ['bike', 'Aerobic ride, steady Z2', '60', 'Z2', 'Steady, no efforts'], f2: ['run', 'Easy run', '40', 'Z1–Z2', 'Conversational'], f3: ['swim', 'Drills and 6 x 200', '45', 'Z2', 'Warm-up, drills, 6 x 200 steady'] }[arg];
      [S.lst_sport, S.lst_title, S.lst_min, S.lst_zone, S.lst_purpose] = f;
    },
    'lst.save'(arg, S) {
      const title = S.lst_title.trim(), typed = String(S.lst_min).trim().replace(',', '.');
      if (!title) { S.lst_problem = 'Write a few words for the session first.'; return; }
      if (typed && isNaN(Number(typed))) { S.lst_problem = 'The length must be a number of minutes.'; return; }
      S.lst_ses.push({ id: 'new1', day: S.lst_day, sport: S.lst_sport, title, min: typed ? Number(typed) : 0, zone: S.lst_zone, st: 'todo', notes: '' });
      S.lst_changes.unshift({ id: 'c3', kind: 'add', at: '16 Sep 2026 at 09:41', title, sid: 'new1', before: '', after: LST.short(S.lst_day) + (typed ? ' · ' + dur(Number(typed)) : ''), undone: false, back: null });
      S.lst_problem = ''; S.lst_added = true; S.sheet = null; S.lst_range = 'upcoming';
    },
    'lst.printopen'(arg, S) { S.sheet = 'lst.print'; },
    'lst.printkind'(arg, S) { S.lst_print = arg; },
    'lst.pdf'() { toast('The share sheet opens here, with the page as a PDF.'); },
    'lst.printdo'() { toast('The system print panel opens here.'); },
    'lst.settings'() { toast('Settings has its own chapter.'); },
    'lst.undoask'(arg, S) { S.lst_undo = arg; S.sheet = 'lst.undo'; },
    'lst.undono'(arg, S) { S.sheet = null; },
    'lst.undoyes'(arg, S) {
      const c = S.lst_changes.find(x => x.id === S.lst_undo); S.sheet = null; if (!c) return;
      c.undone = true;
      if (c.kind === 'add') S.lst_ses = S.lst_ses.filter(w => w.id !== c.sid);
      else if (c.back) { const w = S.lst_ses.find(x => x.id === c.sid); if (w) { w.day = c.back.day; w.min = c.back.min; } }
    },
  },
  steps: [
    { kind: 'look', head: 'Every session, one list', shot: 'lst-01-sessions', real: 'the Sessions tab; on the iPad and the Mac the Sessions row',
      text: 'The real Sessions tab. Under the heading stand two small word buttons, <b>Print</b> and <b>+ Session</b>, a box <b>Search sessions</b>, and four lists with their numbers: <b>Upcoming</b> (chosen, 11), <b>Done</b>, <b>Missed</b> and <b>All</b>. Under them the plan is listed a day at a time, from <b>Wednesday 9 September</b>.',
      hint: 'The season, the month and the year are not here. They are on the Plan page, which only the iPad and the Mac have.' },
    { kind: 'look', head: 'Three small buttons under the heading', target: 'lst.buttons',
      text: '<b>Print</b> puts a week or a month on paper. <b>+ Session</b> adds a session of your own. <b>Ask about your plan</b> shows only when Claude is switched on, and has its own chapter.',
      real: 'Sessions, under the heading' },
    { kind: 'try', head: 'Open the other lists', text: 'Press <b>Done</b>, then <b>Missed</b>. The number under each word is the length of its list.',
      target: S => ['done', 'missed'].filter(r => !S.lst_seen.includes(r)).map(r => 'lst.range:' + r)[0] || 'lst.range:upcoming',
      until: S => S.lst_seen.includes('done') && S.lst_seen.includes('missed'),
      ok: 'Done reads backwards from now, newest day first. Missed does too. Upcoming and All read forwards.',
      robot: [['act', 'lst.range', 'done'], ['act', 'lst.range', 'missed']] },
    { kind: 'look', head: 'The marks on a row', shot: 'lst-06-done-list',
      text: 'This is the <b>Done</b> list. A session you did has a green frame and the white tick in a green circle. The dotted frame with a paler tick is an extra you added yourself, here a dog walk. A session marked missed has the red word <b>Missed</b> and a red frame. The small pen on a row opens what you logged, to change it.',
      hint: 'The bar under the four lists says it too: solid is done, hatched is missed, light is still to come. Rest days are counted nowhere.' },
    { kind: 'try', head: 'Find a session by a word', text: 'Press the box <b>Search sessions</b> and type <b>calf</b>.',
      target: 'lst.search', until: S => LST.fold(S.lst_query).trim() === 'calf',
      ok: 'The four lists are gone and the answer is in groups: To come, Done, Missed. The grey line under a row says where the word was found: "Notes: …".',
      hint: 'Every word you type has to be found. It looks in the title, the description, your notes, the sport and the date, so Sat, November or 2026-09-12 work too.',
      robot: [['in', 'lst_query', 'calf']] },
    { kind: 'look', head: 'What a search shows', shot: 'lst-02-search',
      text: 'The real search with the word <b>run</b>. The four lists have gone. Under the box, the group <b>To come</b> holds run sessions, newest day first, each with the day as its first grey pill. The grey line under a row says where the word was found: "Found in the title and sport".' },
    { kind: 'try', head: 'A word that finds nothing', set: { lst_query: 'swim' }, text: 'Change the word to <b>xyz</b>. Then press <b>Clear</b> to get the lists back.',
      target: S => S.lst_query === 'xyz' ? 'lst.clear' : 'lst.search', until: S => S.lst_query === '',
      ok: 'With nothing found the page says so in one grey line. Clear empties the box and the four lists come back.',
      robot: [['in', 'lst_query', 'xyz'], ['act', 'lst.clear']] },
    { kind: 'look', head: 'The same search on the iPad and the Mac', shot: 'lst-91-pad', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'This is the Sessions row on an iPad, with the word <b>ride</b> typed in. The box has <b>Clear</b> at its right. Under it stand four finds in a group headed <b>To come</b>, each with its grey line, here "Found in the title". Under the heading stand <b>Print</b> and <b>+ Session</b>, as on the iPhone.',
      hint: 'On an iPad with a keyboard and on the Mac, \u2318F puts the cursor in the search box.' },
    { kind: 'try', head: 'Add a session of your own', text: 'Press <b>+ Session</b>.', target: 'lst.add',
      until: S => S.sheet === 'lst.new', ok: 'The page <b>New session</b> opens. Cancel is at the top, the full-colour Save at the bottom.',
      robot: [['act', 'lst.add']] },
    { kind: 'try', head: 'Start from a favourite', set: { sheet: 'lst.new' }, target: 'lst.fav:f2',
      text: 'At the top are your favourites, saved from a session’s page with <b>Save as favourite</b>. Press <b>Easy run</b>.',
      until: S => S.lst_title === 'Easy run', ok: 'The page is filled in: sport, words, 40 minutes, zone and purpose. You can still change anything before Save.',
      hint: 'Further down, Repeat adds the session on more days, every week until a date.',
      robot: [['act', 'lst.fav', 'f2']] },
    { kind: 'try', head: 'Save: the page asks for words', set: { sheet: 'lst.new' },
      text: 'Press <b>Save</b> with nothing typed and read the red line. Then type <b>Easy run</b> in <b>What you do</b> and press <b>Save</b> again.',
      target: S => S.lst_problem && !S.lst_title ? 'lst.title' : 'lst.save', until: S => S.lst_added,
      ok: 'Easy run is in the plan, on Thursday 17 September, and under Upcoming. The change is listed under Changes to the plan.',
      hint: 'A length that is not a number is refused too: "The length must be a number of minutes."',
      robot: [['act', 'lst.save'], ['in', 'lst_title', 'Easy run'], ['act', 'lst.save']] },
    { kind: 'look', head: 'Print: the choices', shot: 'lst-03-print',
      text: 'The page <b>Print the plan</b> opens over the list. Three choices: <b>This week</b> (chosen), <b>Next week</b>, <b>This month</b>. Under them a sheet of paper, Mon 14 Sep – Sun 20 Sep 2026, a column for each day with SWIM, BIKE and RUN entries. The foot says "Total 3h 40m · 5 sessions" and the time per sport.' },
    { kind: 'look', head: 'What the paper shows', shot: 'lst-04-print-month',
      text: 'The page <b>Print the plan</b> with <b>This month</b> chosen. Under it a sheet of paper: September 2026 as a calendar, black on white, each session a small coloured bar with its sport, its length and its title in grey. The page is bigger than the screen, so you drag it to read. At the foot: Cancel, <b>Save as PDF</b> and the green <b>Print</b>.',
      hint: 'This week and Next week print as a landscape sheet with a column for each day.' },
    { kind: 'try', head: 'Print the month', set: { sheet: 'lst.print' }, target: 'lst.kind:this-month',
      text: 'On the <b>Print the plan</b> page, choose <b>This month</b>. The page shows one A4 sheet in black on white: a week lies down with a column per day, a month stands up as a calendar. Each session has its sport in words, its length and zone, and the foot adds up the time.',
      until: S => S.lst_print === 'this-month', ok: 'September 2026 as a calendar, with the total at the foot. Print opens the system print panel, Save as PDF the share sheet.',
      hint: 'Print is on the Sessions page and, on the iPad and the Mac, on the Plan page too.',
      robot: [['act', 'lst.printkind', 'this-month']] },
    { kind: 'look', head: 'Changes to the plan', shot: 'lst-05-changes', real: 'Settings › Changes to the plan',
      text: 'This is the page <b>Changes to the plan</b> in Settings, while nothing has been changed: "No changes yet. Open a session and tap Change." Every change you make later is listed here, newest first.' },
    { kind: 'try', head: 'Undo a change', set: { part: 'settings', screen: 'lst.changes' }, target: S => S.sheet ? 'lst.undoyes' : 'lst.undo:c2',
      text: 'Settings › <b>Changes to the plan</b> lists every change, newest first, with Before and Now. Press <b>Undo</b> on the top one and answer the question.',
      real: 'Settings › Changes to the plan', until: S => S.lst_changes[0].undone,
      ok: 'The change stays in the list, marked <b>Undone</b>, and the ride is back on Thursday. What you logged since stays.',
      robot: [['act', 'lst.undoask', 'c2'], ['act', 'lst.undoyes']] },
    { kind: 'check', head: 'The older change has no Undo', set: { part: 'settings', screen: 'lst.changes' }, text: 'The second change to the same ride says <b>Changed again since</b>. Why is there no Undo?',
      answers: ['Only the newest change to a session can be undone', 'It was made on another device', 'Changes older than a week are locked'], right: 0,
      ok: 'Right. An older one would quietly take the later ones with it.' },
    { kind: 'check', head: 'Undoing an added session', text: 'You undo a change that says <b>Added</b>. What happens to that session?',
      answers: ['It is taken out of the plan again', 'It is marked missed', 'It stays and only the entry is hidden'], right: 0,
      ok: 'Right. The question says so first: the session is taken out of the plan again.' },
  ],
});
