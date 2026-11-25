/* Chapter 11 — Race day, shoes and bikes. The race page (opened from Progress; its head card and headings are the race's red, its buttons the plan's blue),
   and Settings › Race and kit › Shoes and bikes. State keys rac_, screens rac., actions rac. The race is the app's own invented sample:
   "Half-distance triathlon", 228 days ahead of Wednesday 16 September 2026, which is Sunday 2 May 2027. */
const RAC_GROUPS = [['before', 'Before', ['Race number', 'Timing chip', 'Sun cream', 'Watch charged']], ['swim', 'Swim', ['Wetsuit', 'Goggles', 'Swim cap', 'Spare goggles']],
  ['bike', 'Bike', ['Helmet', 'Bike shoes', 'Bottles', 'Gels', 'Sunglasses']], ['run', 'Run', ['Running shoes', 'Race belt', 'Cap', 'Gels for the run']],
  ['after', 'After', ['Dry clothes', 'Flip-flops', 'Towel', 'Recovery drink']]];
const RAC_LEGS = [['swim', 'Swim', false], ['t1', 'T1', true], ['bike', 'Bike', false], ['t2', 'T2', true], ['run', 'Run', false]];
const racPad = n => String(n).padStart(2, '0');
/* "1:10" or "70" -> seconds for a leg; "4:30" -> seconds for a change-over; empty -> null; not a time -> false */
function racParse(text, co) {
  const t = String(text || '').trim().toLowerCase(); if (!t) return null;
  if (t.includes(':')) { const p = t.split(':').map(x => parseInt(x, 10)); if (p.some(isNaN)) return false;
    if (p.length === 2) return co ? p[0] * 60 + p[1] : p[0] * 3600 + p[1] * 60; if (p.length === 3) return p[0] * 3600 + p[1] * 60 + p[2]; return false; }
  const n = Number(t); return isNaN(n) ? false : Math.round(n * 60);
}
function racWords(s, co) {
  const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
  if (co) return h > 0 ? `${h}h ${racPad(m)}m` : m > 0 ? (sec > 0 ? `${m}m ${racPad(sec)}s` : `${m}m`) : `${sec}s`;
  return h > 0 ? `${h}h ${racPad(m)}m` : `${m}m`;
}
const racGrams = (rows, leg) => rows.filter(r => r.leg === leg).reduce((a, r) => a + r.carbs, 0);
const racPacked = S => RAC_GROUPS.reduce((n, g) => n + S['rac_k_' + g[0]].filter(i => S.rac_packed.includes(i.id)).length, 0);
const racTotal = S => RAC_GROUPS.reduce((n, g) => n + S['rac_k_' + g[0]].length, 0);
const racN = n => Number(n).toLocaleString('en-GB');
const racBtn = (label, a, o = {}) => `<button class="rac-btn${o.main ? ' rac-main' : ''}${o.danger ? ' rac-danger' : ''}" data-act="${a}"${o.arg !== undefined ? ` data-arg="${esc(o.arg)}"` : ''}${o.t ? ` data-t="${o.t}"` : ''}>${esc(label)}</button>`;

CHAPTER({
  id: 'rac',
  title: 'Race day, shoes and bikes',
  icon: 'race',
  needs: 'Your own times for the five parts of the day, the fuel you will take, and the kit you want packed; and your shoes and bikes, with the kilometres they already have.',
  gives: 'A race page that adds up your times, your grams and your packing, and a count of the kilometres on each pair of shoes and each bike, from the sessions you log.',
  start: () => {
    const s = {
      part: 'progress', screen: 'rac.progress',
      rac_p: { swim: null, t1: null, bike: null, t2: null, run: null }, rac_pn: { swim: '', bike: '', run: '' },
      rac_t_swim: '', rac_t_t1: '', rac_t_bike: '', rac_t_t2: '', rac_t_run: '', rac_n_swim: '', rac_n_bike: '', rac_n_run: '',
      rac_fuel: [{ id: 'f1', leg: 'before', when: 'Breakfast, 3 h before', what: 'porridge and banana', carbs: 90 },
        { id: 'f2', leg: 'bike', when: 'every 20 min', what: '1 gel', carbs: 198 },
        { id: 'f3', leg: 'bike', when: 'from the second hour', what: '1 bar', carbs: 60 },
        { id: 'f4', leg: 'run', when: 'every 5 km', what: '1 gel', carbs: 88 }],
      rac_fe: [], rac_r_leg: 'bike', rac_r_when: '', rac_r_what: '', rac_r_g: '',
      rac_packed: [], rac_tried: false, rac_listsaved: false,
      rac_g: [{ id: 'g1', name: 'Blue runners', kind: 'Running shoes', on: true, since: 'Wed 8 Jul', km: 412, words: 'No runs logged yet', limit: 700 },
        { id: 'g2', name: 'Grey trainers', kind: 'Running shoes', on: false, since: '', km: 730, words: 'No runs logged yet', limit: 700 },
        { id: 'g3', name: 'Road bike', kind: 'Bike', on: true, since: 'Sat 28 Feb', km: 1200, words: 'No rides logged yet', limit: 4000 }],
      rac_gname: '', rac_gkind: 'Running shoes', rac_gstart: '', rac_glimit: '', rac_gnow: true, rac_gask: '', rac_gedit: '',
      rac_pace_done: false, rac_asked: false,
    };
    RAC_GROUPS.forEach(g => { s['rac_k_' + g[0]] = g[2].map((n, i) => ({ id: g[0] + '-' + i, name: n })); s['rac_e_' + g[0]] = []; });
    return s;
  },
  screens: {
    /* Progress, "The race" opened: the way in */
    'rac.progress': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card"><span class="k-line"><b>The race</b></span>
        <span>Half-distance triathlon</span>
        <button class="k-link rac-link" data-act="rac.open" data-t="rac.link">Open your race page ${icon('right')}</button>
        <span class="k-muted">Sunday 2 May 2027</span>${K.bar(32)}</div>
      <div class="k-card"><b>So far</b><span class="k-muted">The rest of Progress has its own chapter.</span></div>`,

    /* The race page, over Progress (a sheet in the real app, so it has Done) */
    'rac.page': S => {
      const p = S.rac_p, typed = RAC_LEGS.filter(l => p[l[0]] != null), total = typed.reduce((a, l) => a + p[l[0]], 0);
      const fin = !typed.length ? `<span class="k-muted">Type your five times to see your planned finish.</span>`
        : `<span class="k-line" data-t="rac.finish"><span class="k-muted">${typed.length === 5 ? 'Planned finish' : 'So far'}</span><b class="rac-fin">${dur(Math.round(total / 60))}</b>${typed.length < 5 ? `<span class="k-muted k-small">${typed.length} of 5 times typed</span>` : ''}</span>`;
      const dist = { swim: '1.9 km', bike: '90 km', run: '21.1 km' };
      const tile = l => `<button class="rac-tile" data-act="rac.pace" data-t="rac.leg.${l[0]}"><span class="rac-tn">${l[1].toUpperCase()}</span>
        ${p[l[0]] != null ? `<b>${racWords(p[l[0]], l[2])}</b>` : `<span class="k-muted">Not typed</span>`}${dist[l[0]] ? `<span class="k-muted k-small">${dist[l[0]]}</span>` : ''}
        ${S.rac_pn[l[0]] ? `<span class="k-small">${esc(S.rac_pn[l[0]])}</span>` : ''}</button>`;
      const rows = S.rac_fuel, ph = (leg, sec) => sec && racGrams(rows, leg) > 0 ? Math.round(racGrams(rows, leg) * 3600 / sec) : null;
      const sum = (leg, name, sec) => `<div class="rac-tile" data-t="rac.sum.${leg}"><span class="rac-tn">${name.toUpperCase()}</span><b>${racGrams(rows, leg)} g</b>
        ${leg === 'before' ? '' : ph(leg, sec) ? `<span class="k-small"><b>${ph(leg, sec)} g an hour</b></span><span class="k-muted rac-tiny">from your times</span>` : `<span class="k-muted rac-tiny">Type your ${leg} time for grams an hour</span>`}</div>`;
      return `
      <div class="k-top"><span class="k-sp"></span>${racBtn('Done', 'rac.close', { t: 'rac.done' })}</div>
      <h1 class="k-h1 rac-h1">Race</h1>
      <div class="rac-head" data-t="rac.head"><span class="rac-cap">RACE</span><b class="rac-title">Half-distance triathlon</b><span>Sun 2 May 2027</span>
        <span class="k-line"><b class="rac-days">228 days</b><b>32 weeks and 4 days</b></span></div>
      <b class="rac-h2">Your plan for the day</b>${fin}
      <div class="k-cols k-even">${RAC_LEGS.map(tile).join('')}</div>
      <span class="k-muted k-small">Your own times, added up. The app works out no pace and no speed.</span>
      ${racBtn('Type your times', 'rac.pace', { main: true, t: 'rac.pacebtn' })}
      <b class="rac-h2">Fuel plan</b>
      <div class="k-grid3">${sum('before', 'Before', 0)}${sum('bike', 'Bike', p.bike)}${sum('run', 'Run', p.run)}</div>
      ${rows.map((r, i) => `<div class="rac-frow" data-t="rac.frow.${i}"><span class="k-line"><b>${r.carbs} g</b><span>${esc(r.what)}</span></span>
        <span class="k-muted k-small">${{ before: 'Before', bike: 'Bike', run: 'Run' }[r.leg]}${r.when ? ' · ' + esc(r.when) : ''}</span></div>`).join('')}
      <div class="k-line">${racBtn('Add a row', 'rac.fadd', { main: true, t: 'rac.fadd' })}${racBtn('Arrange or change', 'rac.fopen', { t: 'rac.fopen' })}</div>
      <span class="k-line"><b class="rac-h2">Kit checklist</b><b data-t="rac.count">packed ${racPacked(S)} of ${racTotal(S)}</b></span>
      ${RAC_GROUPS.map(g => `<div class="rac-kgroup"><span class="rac-tn">${g[1].toUpperCase()}</span>
        ${S['rac_k_' + g[0]].map(i => `<button class="rac-tick" data-act="rac.tick" data-arg="${i.id}" data-t="rac.tick:${i.id}">${S.rac_packed.includes(i.id) ? `<span class="rac-on">${icon('check')}</span>` : `<span class="rac-ring"></span>`}<span>${esc(i.name)}</span></button>`).join('')}</div>`).join('')}
      <span class="k-muted k-small">A tick means packed.</span>
      <div class="k-line">${racBtn('Untick all', 'rac.untickask', { danger: true, t: 'rac.untick' })}${racBtn('Change the list', 'rac.lopen', { t: 'rac.lopen' })}</div>`;
    },

    /* Settings › Race and kit › Shoes and bikes */
    'rac.gear': S => {
      const inUse = S.rac_g.filter(g => g.on).length, aside = S.rac_g.length - inUse;
      const bar = g => g.limit ? (g.km > g.limit ? `<span class="k-muted k-small">Past the ${g.limit} km you set.</span>`
        : `<span class="rac-gbar"><i style="width:${Math.max(3, Math.round(g.km / g.limit * 100))}%"></i></span><b class="k-small">${racN(g.km)} of ${racN(g.limit)} km</b>`) : '';
      return `
      <div class="k-top">${K.back('Settings', 'rac.note')}</div>
      <h1 class="k-h1">Shoes and bikes</h1>
      ${K.hero({ cap: 'SHOES AND BIKES', title: inUse + ' in use', lines: aside ? [aside + ' put aside'] : [], t: 'rac.ghead' })}
      ${S.rac_g.map(g => `<div class="rac-gtile" data-t="rac.g.${g.id}"><span class="rac-gk">${g.kind.toUpperCase()}</span>
        <b>${esc(g.name)} · ${g.km} km</b>
        <span class="k-muted k-small">${g.on ? 'In use since ' + g.since : 'Not in use now'}</span><span class="k-muted k-small">${g.words}</span>${bar(g)}
        <span class="k-line">${g.kind === 'Other' ? '' : g.on ? `<button class="rac-small" data-act="rac.aside" data-arg="${g.id}" data-t="rac.aside.${g.id}">Put aside</button>` : `<button class="rac-small" data-act="rac.use" data-arg="${g.id}" data-t="rac.use.${g.id}">Use from today</button>`}
        <button class="rac-small" data-act="rac.gchange" data-arg="${g.id}" data-t="rac.change.${g.id}">Change</button></span></div>`).join('')}
      ${K.btn('Add shoes or a bike', 'rac.gadd', { main: true, t: 'rac.gadd' })}`;
    },
  },
  sheets: {
    'rac.pace': S => {
      const bad = RAC_LEGS.filter(l => racParse(S['rac_t_' + l[0]], l[2]) === false).map(l => l[0]);
      const ps = RAC_LEGS.map(l => racParse(S['rac_t_' + l[0]], l[2])).filter(v => typeof v === 'number'), sum = ps.reduce((a, b) => a + b, 0);
      return `<h3>Your times</h3>
      <span class="k-muted k-small">Type the time you plan for each part. Legs as hours and minutes (1:10), change-overs as minutes and seconds (4:30). Leave a box empty to leave it out.</span>
      ${RAC_LEGS.map(l => `<div class="k-field"><label for="in-rac_t_${l[0]}">${l[1]}</label><span class="k-col">${K.input('rac_t_' + l[0], S, { ph: l[2] ? 'e.g. 4:30' : 'e.g. 1:10', t: 'rac.t.' + l[0] })}
        ${l[2] ? '' : K.input('rac_n_' + l[0], S, { ph: 'How you will hold it, e.g. pulse Z2', t: 'rac.n.' + l[0] })}
        ${bad.includes(l[0]) ? '<span class="k-muted k-small">That is not a time yet.</span>' : ''}</span></div>`).join('')}
      ${ps.length ? `<b>Planned finish ${dur(Math.round(sum / 60))}</b>` : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'rac.psave', { main: true, t: 'rac.psave', off: bad.length > 0 })}</div>`;
    },
    'rac.row': S => `<h3>New fuel row</h3>
      ${K.seg([['before', 'Before'], ['bike', 'Bike'], ['run', 'Run']], S.rac_r_leg, 'rac.rleg', 'rac.rleg')}
      <div class="k-field"><label for="in-rac_r_when">When</label>${K.input('rac_r_when', S, { ph: 'e.g. every 20 min', t: 'rac.rwhen' })}</div>
      <div class="k-field"><label for="in-rac_r_what">What</label>${K.input('rac_r_what', S, { ph: 'e.g. 1 gel', t: 'rac.rwhat' })}</div>
      <div class="k-field"><label for="in-rac_r_g">Carbohydrate, grams in all</label>${K.input('rac_r_g', S, { num: true, ph: 'e.g. 198', t: 'rac.rg' })}</div>
      <span class="k-muted k-small">The grams for this row over the whole part, as you will take them.</span>
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'rac.rsave', { main: true, t: 'rac.rsave' })}</div>`,
    'rac.fuel': S => `<h3>Fuel plan</h3>
      <span class="k-muted k-small">Hold the three lines and drag a row to where it belongs. Tap a row to change it.</span>
      <div class="k-card">${S.rac_fe.map((r, i) => `<div class="k-dragrow" data-drag="rac_fe" data-i="${i}">
        <button class="k-grip" data-grip aria-label="Drag to arrange" data-t="rac.fgrip:${i}">${icon('grip')}</button>
        <button class="rac-pick" data-act="rac.fchange" data-t="rac.fchange:${i}"><span>${r.carbs} g ${esc(r.what)}</span><span class="k-muted k-small">${{ before: 'Before', bike: 'Bike', run: 'Run' }[r.leg]}${r.when ? ' · ' + esc(r.when) : ''}</span></button>
        <button class="rac-rm" data-act="rac.frm" data-arg="${r.id}" data-t="rac.frm:${i}">Remove</button></div>`).join('')}</div>
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'rac.fsave', { main: true, t: 'rac.fsave' })}</div>`,
    'rac.list': S => `<h3>Kit checklist</h3>
      <span class="k-muted k-small">Hold the three lines and drag an item to where it belongs. Rename it in its box.</span>
      ${RAC_GROUPS.map(g => `<div class="rac-kgroup"><span class="rac-tn">${g[1].toUpperCase()}</span>
        ${S['rac_e_' + g[0]].map((i, n) => `<div class="k-dragrow" data-drag="rac_e_${g[0]}" data-i="${n}"><button class="k-grip" data-grip aria-label="Drag to arrange" data-t="rac.lgrip.${g[0]}:${n}">${icon('grip')}</button>
          <span class="k-name rac-pick">${esc(i.name) || '<span class="k-muted">Item</span>'}</span><button class="rac-rm" data-act="rac.lrm" data-arg="${i.id}" data-t="rac.lrm:${i.id}">Remove</button></div>`).join('')}
        <button class="rac-add" data-act="rac.ladd" data-arg="${g[0]}" data-t="rac.ladd.${g[0]}">Add to ${g[1].toLowerCase()}</button></div>`).join('')}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'rac.lsave', { main: true, t: 'rac.lsave' })}</div>`,
    'rac.untick': S => `<h3>Untick all ${racPacked(S)} packed items?</h3>
      <div class="k-foot">${K.btn('Keep them', 'sheet.close')}${K.btn('Untick all', 'rac.unticknow', { danger: true, t: 'rac.unticknow' })}</div>`,
    /* Shoes and bikes: add (rac_gedit '') or change (an id) */
    'rac.gform': S => `<h3>${S.rac_gedit ? 'Change' : 'New'}</h3>
      <div class="k-field"><label for="in-rac_gname">Name</label>${K.input('rac_gname', S, { ph: 'e.g. Blue runners', t: 'rac.gname' })}</div>
      <div class="k-field"><label for="in-rac_gkind">Kind</label>${K.select('rac_gkind', S, ['Running shoes', 'Bike', 'Other'], { t: 'rac.gkind' })}</div>
      ${S.rac_gedit ? '' : `<div class="k-card">${K.switch(S.rac_gnow, 'In use now', 'rac.gnow', { t: 'rac.gnow' })}</div>`}
      <div class="k-field"><label for="in-rac_gstart">Kilometres it already had</label>${K.input('rac_gstart', S, { num: true, ph: '0', t: 'rac.gstart' })}</div>
      <div class="k-field"><label for="in-rac_glimit">Look at it again at … km (optional)</label>${K.input('rac_glimit', S, { num: true, ph: 'e.g. 700', t: 'rac.glimit' })}</div>
      ${S.rac_gedit ? `<div class="k-line"><button class="rac-small" data-act="rac.gask" data-arg="retire" data-t="rac.retire">Retire</button><button class="rac-small rac-rm" data-act="rac.gask" data-arg="remove" data-t="rac.remove">Remove</button></div>` : ''}
      ${S.rac_gask === 'remove' ? `<div class="k-band k-needs" data-t="rac.askbox"><span>Remove ${esc(S.rac_gname)}? It is taken off all your devices and cannot be brought back.</span></div><div class="k-line">${racBtn('Remove', 'rac.gdo', { danger: true, arg: 'remove', t: 'rac.gdo' })}${racBtn('Keep it', 'rac.gask', { arg: '' })}</div>` : ''}
      ${S.rac_gask === 'retire' ? `<div class="k-band k-needs" data-t="rac.askbox"><span>Retire ${esc(S.rac_gname)}? It moves to Retired with its final figure.</span></div><div class="k-line">${racBtn('Retire', 'rac.gdo', { arg: 'retire', t: 'rac.gdo' })}${racBtn('Keep using it', 'rac.gask', { arg: '' })}</div>` : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'rac.gsave', { main: true, t: 'rac.gsave', off: !S.rac_gname.trim() })}</div>`,
  },
  actions: {
    'rac.note'() { toast('Settings has its own chapter.'); },
    'rac.open'(arg, S) { S.screen = 'rac.page'; },
    'rac.close'(arg, S) { S.screen = 'rac.progress'; },
    'rac.pace'(arg, S) { S.sheet = 'rac.pace'; },
    'rac.psave'(arg, S) {
      RAC_LEGS.forEach(l => { const v = racParse(S['rac_t_' + l[0]], l[2]); S.rac_p[l[0]] = typeof v === 'number' ? v : null; });
      ['swim', 'bike', 'run'].forEach(k => { S.rac_pn[k] = S['rac_n_' + k].trim(); });
      S.rac_pace_done = true; S.sheet = null;
    },
    'rac.fadd'(arg, S) { S.sheet = 'rac.row'; },
    'rac.rleg'(arg, S) { S.rac_r_leg = arg; },
    'rac.rsave'(arg, S) { S.rac_fuel.push({ id: 'n' + S.rac_fuel.length, leg: S.rac_r_leg, when: S.rac_r_when.trim(), what: S.rac_r_what.trim(), carbs: parseInt(S.rac_r_g, 10) || 0 }); S.sheet = null; },
    'rac.fopen'(arg, S) { S.rac_fe = S.rac_fuel.map(r => ({ ...r })); S.sheet = 'rac.fuel'; },
    'rac.fchange'() { toast('The row opens with Cancel and Save, as Add a row does.'); },
    'rac.frm'(arg, S) { S.rac_fe = S.rac_fe.filter(r => r.id !== arg); },
    'rac.fsave'(arg, S) { S.rac_fuel = S.rac_fe.map(r => ({ ...r })); S.sheet = null; },
    'rac.tick'(arg, S) { const i = S.rac_packed.indexOf(arg); if (i < 0) S.rac_packed.push(arg); else S.rac_packed.splice(i, 1); },
    'rac.untickask'(arg, S) { if (S.rac_packed.length) S.sheet = 'rac.untick'; else toast('Untick all is greyed while nothing is packed.'); },
    'rac.unticknow'(arg, S) { S.rac_packed = []; S.sheet = null; },
    'rac.lopen'(arg, S) { RAC_GROUPS.forEach(g => { S['rac_e_' + g[0]] = S['rac_k_' + g[0]].map(i => ({ ...i })); }); S.sheet = 'rac.list'; },
    'rac.lrm'(arg, S) { RAC_GROUPS.forEach(g => { S['rac_e_' + g[0]] = S['rac_e_' + g[0]].filter(i => i.id !== arg); }); },
    'rac.ladd'(arg, S) { S['rac_e_' + arg].push({ id: arg + '-new' + S['rac_e_' + arg].length, name: '' }); },
    'rac.lsave'(arg, S) { RAC_GROUPS.forEach(g => { S['rac_k_' + g[0]] = S['rac_e_' + g[0]].map(i => ({ ...i })); }); S.rac_listsaved = true; S.sheet = null; },
    'rac.aside'(arg, S) { const g = S.rac_g.find(x => x.id === arg); if (g) g.on = false; },
    'rac.use'(arg, S) { const g = S.rac_g.find(x => x.id === arg); if (!g) return; S.rac_g.forEach(x => { if (x.kind === g.kind) x.on = false; }); g.on = true; g.since = 'Wed 16 Sep'; },
    'rac.gadd'(arg, S) { S.rac_gedit = ''; S.rac_gname = ''; S.rac_gkind = 'Running shoes'; S.rac_gstart = ''; S.rac_glimit = ''; S.rac_gnow = true; S.rac_gask = ''; S.sheet = 'rac.gform'; },
    'rac.gnow'(arg, S) { S.rac_gnow = !S.rac_gnow; },
    'rac.gchange'(arg, S) {
      const g = S.rac_g.find(x => x.id === arg); if (!g) return;
      S.rac_gedit = arg; S.rac_gname = g.name; S.rac_gkind = g.kind; S.rac_gstart = String(g.km); S.rac_glimit = g.limit ? String(g.limit) : ''; S.rac_gask = ''; S.sheet = 'rac.gform';
    },
    'rac.gask'(arg, S) { S.rac_gask = arg; },
    'rac.gdo'(arg, S) { if (arg === 'remove') S.rac_g = S.rac_g.filter(x => x.id !== S.rac_gedit); else { const g = S.rac_g.find(x => x.id === S.rac_gedit); if (g) { g.on = false; g.name += ' (retired)'; } } S.sheet = null; },
    'rac.gsave'(arg, S) {
      const km = parseFloat(S.rac_gstart) || 0, lim = parseFloat(S.rac_glimit) || 0;
      if (S.rac_gedit) { const g = S.rac_g.find(x => x.id === S.rac_gedit); if (g) { g.name = S.rac_gname.trim(); g.kind = S.rac_gkind; g.km = km; g.limit = lim; } }
      else {
        if (S.rac_gnow && S.rac_gkind !== 'Other') S.rac_g.forEach(x => { if (x.kind === S.rac_gkind) x.on = false; });
        S.rac_g.push({ id: 'g' + (S.rac_g.length + 1) + 'n', name: S.rac_gname.trim(), kind: S.rac_gkind, on: S.rac_gnow, since: 'Wed 16 Sep', km, limit: lim, words: S.rac_gkind === 'Other' ? 'Counts only the kilometres you gave it' : (S.rac_gkind === 'Bike' ? 'No rides logged yet' : 'No runs logged yet') });
      }
      S.sheet = null;
    },
  },
  steps: [
    { kind: 'look', head: 'Your race page', target: 'rac.link', real: 'Progress › The race › Open your race page',
      text: 'The race page is where you write your own race day: your times, your fuel and your packing. Open <b>The race</b> in Progress and press <b>Open your race page</b>. It is also in Settings under Race and kit, and, on an iPad or Mac, on the Plan page under To the race.' },
    { kind: 'try', head: 'Open the race page', text: 'Press <b>Open your race page</b>.', target: 'rac.link',
      until: S => S.screen === 'rac.page', ok: 'The page opens over Progress. <b>Done</b> at the top closes it again.', robot: [['act', 'rac.open']] },
    { kind: 'look', head: 'The race and the days to go', shot: 'rac-01-race',
      text: 'At the top the red card is the race: its name from your plan, the day, and a big count of the days to go with the weeks beside it. Below it, <b>Your plan for the day</b> holds <b>Planned finish</b> and five tiles. Red here means the race and nothing else.',
      hint: 'In race week the card counts days only; on the day it says Today; after it, Done and the date.' },
    { kind: 'try', head: 'Open Type your times', set: { screen: 'rac.page' }, target: 'rac.pacebtn',
      text: 'Under <b>Your plan for the day</b> are five tiles: Swim, T1, Bike, T2 and Run, each <b>Not typed</b> still. Press <b>Type your times</b>.',
      until: S => S.sheet === 'rac.pace', ok: 'The page “Your times” is open, with Cancel and Save.', robot: [['act', 'rac.pace']] },
    { kind: 'look', head: 'The page Your times', shot: 'rac-04-pacing',
      text: 'This is <b>Your times</b>, with Cancel and Save. One box for each part: swim, T1, bike, T2 and run, and under swim, bike and run a line for how you will hold it, such as “by feel”. At the bottom it shows the planned finish as you type.' },
    { kind: 'try', head: 'Type your five times', set: { screen: 'rac.page', sheet: 'rac.pace' },
      text: 'Legs as hours and minutes, change-overs as minutes and seconds: swim <b>0:40</b>, T1 <b>4:30</b>, bike <b>3:15</b>, T2 <b>2:30</b>, run <b>2:05</b>. Add “by feel” beside the swim if you like. Press <b>Save</b>.',
      target: S => ['swim', 't1', 'bike', 't2', 'run'].map(k => ['rac.t.' + k, S['rac_t_' + k]]).filter(x => !x[1]).map(x => x[0])[0] || 'rac.psave',
      until: S => RAC_LEGS.every(l => S.rac_p[l[0]] != null), ok: 'The tiles show your times and the page adds them up: Planned finish 6h 07m. Half-distance shows its distances too.',
      robot: [['in', 'rac_t_swim', '0:40'], ['in', 'rac_n_swim', 'by feel'], ['in', 'rac_t_t1', '4:30'], ['in', 'rac_t_bike', '3:15'], ['in', 'rac_t_t2', '2:30'], ['in', 'rac_t_run', '2:05'], ['act', 'rac.psave']] },
    { kind: 'look', head: 'What the page adds up', shot: 'rac-02-fuel',
      text: 'Under <b>Fuel plan</b> three tiles add your grams for Before, Bike and Run. Bike and Run also say “g an hour”, worked from your own time for that part. Below are your rows, each with its grams for the whole part.',
      hint: 'The page works out no pace and no speed, and makes no prediction: it adds what you typed.' },
    { kind: 'try', head: 'Add a fuel row', set: { screen: 'rac.page', rac_p: { swim: 2400, t1: 270, bike: 11700, t2: 150, run: 7500 } }, target: S => S.sheet ? (!S.rac_r_what ? 'rac.rwhat' : !S.rac_r_g ? 'rac.rg' : 'rac.rsave') : 'rac.fadd',
      text: 'The <b>Fuel plan</b> has a tile for Before, Bike and Run, and your rows. Press <b>Add a row</b>, say what (1 gel), and the grams for the whole part (60), with the part Run, then <b>Save</b>.',
      until: S => S.rac_fuel.length === 5, ok: 'The run grams now add up in its tile, and “g an hour” is worked from your own run time. A row’s grams are for the whole part.',
      robot: [['act', 'rac.fadd'], ['act', 'rac.rleg', 'run'], ['in', 'rac_r_what', '1 gel'], ['in', 'rac_r_g', '60'], ['act', 'rac.rsave']] },
    { kind: 'try', head: 'Arrange or change the rows', set: { screen: 'rac.page', sheet: 'rac.fuel', rac_fe: [{ id: 'f1', leg: 'before', when: 'Breakfast, 3 h before', what: 'porridge and banana', carbs: 90 }, { id: 'f2', leg: 'bike', when: 'every 20 min', what: '1 gel', carbs: 198 }, { id: 'f3', leg: 'bike', when: 'from the second hour', what: '1 bar', carbs: 60 }, { id: 'f4', leg: 'run', when: 'every 5 km', what: '1 gel', carbs: 88 }] },
      text: '<b>Arrange or change</b> opens the rows. Press the three lines on the left of the bar row, hold, and let go over the first bike row. Then press <b>Save</b>.',
      hint: 'Arranging is always drag and drop. Tap a row to change it; Remove takes one out.', target: S => S.rac_fe[1].id === 'f3' ? 'rac.fsave' : 'rac.fgrip:2',
      until: S => S.rac_fuel[1].id === 'f3', ok: 'The bar now comes before the gel. Nothing is kept until Save.', robot: [['drag', 'rac_fe', 2, 1], ['act', 'rac.fsave']] },
    { kind: 'look', head: 'The kit checklist', shot: 'rac-03-kit',
      text: 'The <b>Kit checklist</b> has five groups: Before, Swim, Bike, Run and After. The count beside the heading says how many are packed. A green circle with a tick means packed, an empty grey circle means not yet.' },
    { kind: 'try', head: 'Pack your kit', set: { screen: 'rac.page' }, target: 'rac.tick:swim-0',
      text: 'The <b>Kit checklist</b> starts with 21 things in five groups: Before, Swim, Bike, Run and After. Press a thing to pack it: <b>Wetsuit</b>, <b>Goggles</b> and <b>Helmet</b>.',
      until: S => ['swim-0', 'swim-1', 'bike-0'].every(i => S.rac_packed.includes(i)), ok: 'Each packed thing gets a green circle with a tick, and the count says packed 3 of 21. Here the tick means packed.',
      robot: [['act', 'rac.tick', 'swim-0'], ['act', 'rac.tick', 'swim-1'], ['act', 'rac.tick', 'bike-0']] },
    { kind: 'try', head: 'Untick all', set: { screen: 'rac.page', rac_packed: ['swim-0', 'swim-1', 'bike-0'] }, target: S => S.sheet ? 'rac.unticknow' : 'rac.untick',
      text: 'After the race, or to start again, press <b>Untick all</b>. It asks first: “Untick all 3 packed items?”. Press <b>Untick all</b> again.',
      until: S => S.rac_packed.length === 0, ok: 'Every tick is gone and the list itself is as it was. <b>Keep them</b> would have left the ticks.', robot: [['act', 'rac.untickask'], ['act', 'rac.unticknow']] },
    { kind: 'look', head: 'The page Kit checklist', shot: 'rac-06-list-edit',
      text: 'Each group is a box. Every item has three lines on its left to drag it, a name box, and a red <b>Remove</b>. At the foot of each box is a blue <b>Add to</b> button, such as Add to bike. Cancel and Save are at the top.' },
    { kind: 'try', head: 'Change the list', set: { screen: 'rac.page', sheet: 'rac.list', rac_e_bike: [{ id: 'bike-0', name: 'Helmet' }, { id: 'bike-1', name: 'Bike shoes' }, { id: 'bike-2', name: 'Bottles' }, { id: 'bike-3', name: 'Gels' }, { id: 'bike-4', name: 'Sunglasses' }] },
      text: '<b>Change the list</b> is your own list: rename, <b>Remove</b>, <b>Add to bike</b> and drag within a group. Drag the three lines of <b>Sunglasses</b> up to the top of the bike group. Then press <b>Save</b>.',
      target: S => S.rac_e_bike[0].id === 'bike-4' ? 'rac.lsave' : 'rac.lgrip.bike:4',
      until: S => S.rac_k_bike[0].id === 'bike-4', ok: 'Sunglasses come first in Bike. An item moves only inside its group.', robot: [['drag', 'rac_e_bike', 4, 0], ['act', 'rac.lsave']] },
    { kind: 'look', head: 'The race page on the iPad', shot: 'rac-95-pad', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'On the wide screen the five parts of the day stand in one row: Swim, T1, Bike, T2 and Run. The fuel rows run the full width, and the kit list shows its groups side by side.' },
    { kind: 'look', head: 'Shoes and bikes', shot: 'rac-07-gear', real: 'Settings › Race and kit › Shoes and bikes',
      text: 'In Settings, under Race and kit, <b>Shoes and bikes</b> counts the kilometres on each pair and each bike. The slate card says how many are in use. Each one is a tile: kind, name and kilometres, since when, and a bar to a limit you set.' },
    { kind: 'try', head: 'Add a pair of shoes', set: { part: 'settings', screen: 'rac.gear' },
      text: 'In Settings press <b>Add shoes or a bike</b>. Type the name <b>Trail shoes</b>, keep the kind Running shoes and press <b>Save</b>.',
      target: S => S.sheet ? (!S.rac_gname ? 'rac.gname' : 'rac.gsave') : 'rac.gadd',
      until: S => S.rac_g.length === 4, ok: 'A new tile. “In use now” was on, so the Blue runners were put aside the same day: of the same kind, only one is in use.',
      robot: [['act', 'rac.gadd'], ['in', 'rac_gname', 'Trail shoes'], ['act', 'rac.gsave']] },
    { kind: 'try', head: 'Put aside, use from today', set: { part: 'settings', screen: 'rac.gear' }, target: S => S.rac_g[0].on ? 'rac.aside.g1' : 'rac.use.g2',
      text: 'On the Blue runners press <b>Put aside</b>. They now read <b>Not in use now</b>. Then press <b>Use from today</b> on the Grey trainers.',
      until: S => !S.rac_g[0].on && S.rac_g[1].on, ok: 'The Grey trainers are in use from today, and today’s date is what counts: a run logged on a day counts for the pair in use that day.',
      robot: [['act', 'rac.aside', 'g1'], ['act', 'rac.use', 'g2']] },
    { kind: 'look', head: 'The kilometres, and the limit', set: { part: 'settings', screen: 'rac.gear' }, target: 'rac.g.g1',
      text: 'A tile shows its starting kilometres plus the distance of each done run (for shoes) or ride (for a bike) logged on the days it was in use. A run with no distance counts nothing, and the tile says so. A limit you set shows as a bar; past it one grey line says <b>Past the 700 km you set.</b>, with no red.' },
    { kind: 'look', head: 'The change page', shot: 'rac-08-gear-change',
      text: 'The page <b>Change</b> holds the name, the kind (Running shoes, Bike or Other), since when, the kilometres it already had and the limit. Below are <b>Retire</b> and a red <b>Remove</b>. Cancel and Save are at the top.' },
    { kind: 'try', head: 'Change, Retire and Remove', set: { part: 'settings', screen: 'rac.gear' }, target: S => S.sheet ? (S.rac_gask ? 'rac.gdo' : 'rac.remove') : 'rac.change.g2',
      text: 'Press <b>Change</b> on the Grey trainers. The page has Cancel and Save, and below it <b>Retire</b> and <b>Remove</b>. Press <b>Remove</b>, read the question, and press <b>Remove</b> once more.',
      hint: 'Retire keeps the final figure under Retired. Remove cannot be brought back.',
      until: S => !S.rac_g.some(g => g.id === 'g2'), ok: 'The pair is gone from the list and from your other devices.', robot: [['act', 'rac.gchange', 'g2'], ['act', 'rac.gask', 'remove'], ['act', 'rac.gdo', 'remove']] },
    { kind: 'check', head: 'Which pair gets the run?', text: 'The Blue runners are in use. On Monday you press Use from today on the Grey trainers and log a run on Tuesday. Where do the kilometres go?',
      answers: ['To the Blue runners, they were first', 'To the Grey trainers; the Blue runners were put aside that Monday', 'Half to each'], right: 1,
      ok: 'Right. A run counts for the pair that is in use on the day it was run. Nothing is chosen beside the log itself.' },
    { kind: 'check', head: 'Two devices, one kit list', text: 'You tick Helmet on your iPhone and change the list on your iPad, both without a connection. What happens when they meet?',
      answers: ['Both changes are kept', 'The later one wins, and the other is lost', 'The iPhone always wins'], right: 1,
      ok: 'Right. The checklist is one entry holding the items and the ticks, so the later change wins whole.' },
  ],
});
