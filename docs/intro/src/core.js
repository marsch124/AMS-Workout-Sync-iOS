/* core.js — the part of the course that needs no screen: the list of chapters, the practice copy's state,
   and the pretend iPhone (or iPad) as one piece of HTML text. check.mjs runs this part without a browser. */
const CHAPTERS = [], SCREENS = {}, SHEETS = {};
let FINALE = null;
function CHAPTER(c) { CHAPTERS.push(c); Object.assign(SCREENS, c.screens || {}); Object.assign(SHEETS, c.sheets || {}); }

const esc = s => String(s ?? '').replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));
const icon = (n, cls = 'i') => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${ICON[n] || ICON.dot}"/></svg>`;
/* A whole number with a thin gap between thousands, and a real minus sign. */
const num = n => (n < 0 ? '−' : '') + Math.abs(Math.round(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const kr = n => num(n) + ' kr';

/* The app's parts, with the app's names. The iPhone has five tabs along the bottom; the iPad and the Mac have a side list with
   one more page, "Plan". Each part has its own colour, as in the app. */
const PARTS = [['today', 'Today', 'swim'], ['plan', 'Plan', 'plan'], ['sessions', 'Sessions', 'bike'], ['body', 'Body', 'body'],
  ['progress', 'Progress', 'run'], ['settings', 'Settings', 'strength']];
const PHONE_TABS = ['today', 'sessions', 'body', 'progress', 'settings'];   // the iPhone's five tabs, in the app's order
const partName = id => (PARTS.find(p => p[0] === id) || [0, id])[1];
/* A length the way the app writes it: 35m, 1h 05m. */
const dur = min => { const m = Math.round(min), h = Math.floor(m / 60); return h > 0 ? `${h}h ${String(m % 60).padStart(2, '0')}m` : `${m}m`; };

/* ---------- The practice copy ---------- */
let S = {}, ci = 0, si = 0;
const BASE = () => ({ device: 'phone', part: 'today', screen: null, sheet: null, wide: false, toast: '', shot: null });
/* A step always starts from the same place: BASE, then the chapter's start(), then the step's own set. Plain data only. */
function stateFor(c, s) {
  const ch = CHAPTERS[c], st = ch.steps[s];
  return structuredClone({ ...BASE(), ...(ch.start ? ch.start() : {}), ...(typeof st.set === 'function' ? st.set() : st.set || {}), shot: st.shot || null });
}
let toastHook = null, laterImpl = fn => fn();
function toast(t) { S.toast = t; if (toastHook) toastHook(); }
function later(fn, ms) { return laterImpl(fn, ms); }

const GLOBAL_ACTIONS = {
  side(arg) { if (arg !== S.part) toast(`${partName(arg)} has its own chapter. Here, follow the yellow ring.`); },
  tab(arg) { if (arg !== S.part) toast(`${partName(arg)} has its own chapter. Here, follow the yellow ring.`); },
  'sheet.close'() { S.sheet = null; },
};
function act(name, arg, el) {
  const c = CHAPTERS[ci], fn = (c && c.actions && c.actions[name]) || GLOBAL_ACTIONS[name];
  if (fn) fn(arg, S, el);
}
function typeIn(key, value) { S[key] = value; act('in', key); }
function dragMove(key, from, to) {
  const a = S[key]; if (!Array.isArray(a) || from === to || from < 0 || to < 0 || from >= a.length || to >= a.length) return;
  a.splice(to, 0, a.splice(from, 1)[0]); act('drop', key);
}

/* ---------- Building blocks every chapter may use ---------- */
const attr = o => `${o.arg !== undefined ? ` data-arg="${esc(o.arg)}"` : ''}${o.t ? ` data-t="${esc(o.t)}"` : ''}${o.off ? ' disabled' : ''}`;
const K = {
  /* K.btn('Import', 'imp.open', { main: true, icon: 'import', t: 'imp.open', arg: 'x', off: false, quiet: false, danger: false }) */
  btn: (label, a, o = {}) => `<button class="k-btn${o.main ? ' k-main' : ''}${o.quiet ? ' k-quiet' : ''}${o.danger ? ' k-danger' : ''}" data-act="${a}"${attr(o)}>${o.icon ? icon(o.icon) : ''}<span>${esc(label)}</span></button>`,
  /* K.seg([['month', 'Month'], ['year', 'Year']], S.bud_view, 'bud.view') — each choice gets data-t "bud.view:month" */
  seg: (opts, cur, a, t) => `<div class="k-seg"${t ? ` data-t="${t}"` : ''}>${opts.map(o => { const [id, label] = Array.isArray(o) ? o : [o, o];
    return `<button class="${id === cur ? 'k-on' : ''}" data-act="${a}" data-arg="${esc(id)}" data-t="${a}:${esc(id)}">${esc(label)}</button>`; }).join('')}</div>`,
  /* K.stepper('November 2026', 'rep.month') — the framed ‹ › buttons; they call the action with "-1" or "1" */
  stepper: (title, a) => `<div class="k-stepper"><button data-act="${a}" data-arg="-1" data-t="${a}:prev" aria-label="Earlier">${icon('left')}</button><b>${esc(title)}</b><button data-act="${a}" data-arg="1" data-t="${a}:next" aria-label="Later">${icon('right')}</button></div>`,
  /* K.bar(72) filled share in the part's colour; over 100 shows the overflow in red; { pace: 80 } adds today's tick */
  bar: (pct, o = {}) => `<span class="k-bar${pct > 100 ? ' k-over' : ''}"><i style="width:${Math.max(0, Math.min(100, pct > 100 ? 10000 / pct : pct))}%"></i>${o.pace != null ? `<u style="left:${o.pace}%"></u>` : ''}</span>`,
  /* K.mark('ok' | 'needs' | 'fail' | 'ring' | 'grey', 'words') — green dot = all is well, orange = needs you, red = failed or over, grey ring = behind / open */
  mark: (kind, words) => `<span class="k-mark k-${kind}"><i></i>${words ? `<span>${esc(words)}</span>` : ''}</span>`,
  /* K.input('cash_what', S, { ph: 'What was it?', t: 'cash.what', w: 220, num: false }) — typing sets S.cash_what */
  input: (key, st, o = {}) => `<input class="k-in" id="in-${key}" data-in="${key}" value="${esc(st[key] ?? '')}" placeholder="${esc(o.ph || '')}"${o.t ? ` data-t="${o.t}"` : ''}${o.num ? ' inputmode="numeric"' : ''}${o.w ? ` style="width:${o.w}px"` : ''} autocomplete="off">`,
  /* K.select('cash_line', S, [['', 'Choose…'], ['food', 'Food']], { t: 'cash.line' }) — choosing sets S.cash_line */
  select: (key, st, opts, o = {}) => `<select class="k-in" id="in-${key}" data-in="${key}"${o.t ? ` data-t="${o.t}"` : ''}>${opts.map(x => { const [id, label] = Array.isArray(x) ? x : [x, x];
    return `<option value="${esc(id)}"${String(st[key] ?? '') === String(id) ? ' selected' : ''}>${esc(label)}</option>`; }).join('')}</select>`,
  /* K.tick(S.dec_always, 'Always file Greenmarket like this', 'dec.always', { t: 'dec.always' }) — a tick box; the action flips the value */
  tick: (on, label, a, o = {}) => `<button class="k-tick${on ? ' k-on' : ''}" role="checkbox" aria-checked="${on ? 'true' : 'false'}" data-act="${a}"${attr(o)}><span class="k-box">${on ? icon('check') : ''}</span><span>${esc(label)}</span></button>`,
};

/* ---------- Building blocks for this app's look ---------- */
/* K.sport('run', { size: 34 }) — the round tinted mark of a sport, as on a session's card. Sports: swim, bike, brick, run, strength,
   rowing, mobility, race, rest, other (rest draws the moon, brick the bike). */
const SPORT_ICON = { swim: 'swim', bike: 'bike', brick: 'bike', run: 'run', strength: 'strength', rowing: 'rowing', mobility: 'mobility', race: 'race', rest: 'moon', other: 'other' };
K.sport = (id, o = {}) => `<span class="k-sport k-sp-${SPORT_ICON[id] ? id : 'other'}"${o.size ? ` style="width:${o.size}px;height:${o.size}px"` : ''}${o.t ? ` data-t="${esc(o.t)}"` : ''}>${icon(SPORT_ICON[id] || 'other')}</span>`;
/* K.done() — the white tick in a green circle: this session is DONE. It means nothing else in the whole app. { t } for the ring. */
K.done = (o = {}) => `<span class="k-done"${o.t ? ` data-t="${esc(o.t)}"` : ''} aria-label="Done">${icon('check')}</span>`;
/* K.back('Today', 'ses.back') — the back arrow at the top of a page that was opened from another page. */
K.back = (label, a, o = {}) => `<button class="k-back" data-act="${a}"${attr(o)}>${icon('back')}<span>${esc(label)}</span></button>`;
/* K.hero({ cap: 'THIS WEEK', title: '4 of 7 sessions', lines: ['3h 10m of 6h 20m'], t }) — the head card filled with the part's colour, white words. */
K.hero = (o = {}) => `<div class="k-hero"${o.t ? ` data-t="${esc(o.t)}"` : ''}>${o.cap ? `<span class="k-herocap">${esc(o.cap)}</span>` : ''}${o.title ? `<b class="k-herotitle">${esc(o.title)}</b>` : ''}${(o.lines || []).map(l => `<span>${esc(l)}</span>`).join('')}${o.html || ''}</div>`;
/* K.stat('36m', 'Duration', { act, arg, t }) — a white tile: the figure, and its name right under it in small type. */
K.stat = (fig, name, o = {}) => `<${o.act ? `button data-act="${o.act}"` : 'div'} class="k-stat"${attr(o)}><b>${esc(fig)}</b><span>${esc(name)}</span></${o.act ? 'button' : 'div'}>`;
/* K.chip('Z2') — a small grey pill with a word or a figure in it (35m, Z2). { act, arg, t } makes it pressable. */
K.chip = (text, o = {}) => `<${o.act ? `button data-act="${o.act}"` : 'span'} class="k-chip"${attr(o)}>${esc(text)}</${o.act ? 'button' : 'span'}>`;
/* K.switch(S.rem_on, 'Reminders', 'rem.on', { t }) — a switch with its name on the left; the action flips the value. */
K.switch = (on, label, a, o = {}) => `<button class="k-switch${on ? ' k-on' : ''}" role="switch" aria-checked="${on ? 'true' : 'false'}" data-act="${a}"${attr(o)}><span>${esc(label)}</span><i></i></button>`;
/* K.nav('Easy run', 'ses.open', { arg, t, sub: 'Wed 16 Sep', lead: K.sport('run') }) — a row that opens something: words on the left, a small arrow on the right. */
K.nav = (label, a, o = {}) => `<button class="k-nav" data-act="${a}"${attr(o)}>${o.lead || ''}<span class="k-navw"><span>${esc(label)}</span>${o.sub ? `<small>${esc(o.sub)}</small>` : ''}</span>${icon('right')}</button>`;

/* ---------- The pretend iPhone and iPad ---------- */
function shotHTML() {
  return `<div class="k-shotwrap"><img class="k-shot" src="shots/${esc(S.shot)}.jpg" alt="A picture of the real app with an invented plan" draggable="false"><span class="k-shotnote">Picture not found: ${esc(S.shot)}</span></div>`;
}
function sideHTML() {
  return `<div class="pad-side"><div class="pad-app">Triathlon</div>${PARTS.map(([id, t]) =>
    `<button class="pad-part${S.part === id ? ' k-on' : ''}" data-part="${id}" data-act="side" data-arg="${id}" data-t="side.${id}"><span>${t}</span></button>`).join('')}
    <div class="pad-foot">${CHAPTERS[ci] && CHAPTERS[ci].sidefoot ? CHAPTERS[ci].sidefoot(S) : ''}<span>Practice copy</span></div></div>`;
}
function stageHTML() {
  const body = S.screen && SCREENS[S.screen] ? SCREENS[S.screen](S) : '<p class="k-muted">Nothing to show here.</p>';
  const sheet = S.sheet && SHEETS[S.sheet] ? `<div class="k-dim" data-part="${S.part}"><div class="k-sheet${S.wide ? ' k-wide' : ''}" role="dialog">${SHEETS[S.sheet](S)}</div></div>` : '';
  const toastBox = S.toast ? `<div class="k-toast">${esc(S.toast)}</div>` : '';
  if (S.device === 'pad') {
    if (S.shot) return `<div class="desk desk-pad"><div class="padshot">${shotHTML()}</div></div>`;
    return `<div class="pad">${sideHTML()}<div class="pad-body" data-part="${S.part}"><div class="pane">${body}</div></div>${sheet}</div>${toastBox}`;
  }
  if (S.shot) return `<div class="desk"><div class="phone phone-shot">${shotHTML()}</div></div>`;
  return `<div class="desk"><div class="phone"><div class="phone-body" data-part="${S.part}"><div class="pane">${body}</div></div>
    <div class="phone-tabs">${PHONE_TABS.map(id => { const p = PARTS.find(x => x[0] === id);
      return `<button class="${S.part === id ? 'k-on' : ''}" data-part="${id}" data-act="tab" data-arg="${id}" data-t="tab.${id}">${icon(p[2])}<span>${p[1]}</span></button>`; }).join('')}</div>${sheet}</div></div>${toastBox}`;
}
