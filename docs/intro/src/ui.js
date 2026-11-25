/* ui.js — the course itself: chapter rail, coach card, the pretend iPhone or iPad on the page. */
const stage = document.getElementById('stage'), coach = document.getElementById('coach'), fin = document.getElementById('finish');
const KEY = 'triathlon-course';
const store = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch {} } };
const readList = k => { try { return JSON.parse(store.get(k) || '[]'); } catch { return []; } };
let doneCh = new Set(readList(KEY + '-done'));
let solved = false, robotMode = false;
const timers = [];
laterImpl = (fn, ms) => { if (robotMode) return fn(); const h = setTimeout(() => { fn(); paint(); checkSolved(); }, ms); timers.push(h); return h; };
const clearTimers = () => { while (timers.length) clearTimeout(timers.pop()); };
toastHook = () => { paint(); clearTimeout(toastHook.h); toastHook.h = setTimeout(() => { S.toast = ''; paint(); }, 2800); };

const step = () => CHAPTERS[ci] && CHAPTERS[ci].steps[si];
const totalSteps = () => CHAPTERS.reduce((n, c) => n + c.steps.length, 0);

/* ---------- The pretend window on the page ---------- */
function paint(fresh) {
  const keep = sel => { const e = stage.querySelector(sel); return e ? e.scrollTop : 0; };
  const a = fresh ? 0 : keep('.pane'), b = fresh ? 0 : keep('.k-sheet');
  stage.innerHTML = stageHTML(); fit();
  const p = stage.querySelector('.pane'); if (p) p.scrollTop = a;
  const s = stage.querySelector('.k-sheet'); if (s) s.scrollTop = b;
  markTarget();
}
function reveal(el) {
  const box = el.closest('.k-sheet') || el.closest('.pane'); if (!box || box === el) return;
  const k = box.getBoundingClientRect().height / box.offsetHeight || 1, a = el.getBoundingClientRect(), b = box.getBoundingClientRect();
  if (a.top < b.top || a.bottom > b.bottom) box.scrollTop += (a.top - b.top) / k - 70;
}
function markTarget() {
  stage.querySelectorAll('.target').forEach(e => e.classList.remove('target'));
  const st = step(); if (!st || (solved && st.kind !== 'look')) return;
  const t = typeof st.target === 'function' ? st.target(S) : st.target;
  [].concat(t || []).forEach((n, i) => { const el = stage.querySelector(`[data-t="${CSS.escape(n)}"]`); if (el) { el.classList.add('target'); if (i === 0) reveal(el); } });
}
function checkSolved() {
  const st = step(); if (!st || solved || st.kind !== 'try' || !st.until) return;
  let ok = false; try { ok = !!st.until(S); } catch { ok = false; }
  if (ok) succeed(st.ok || 'Done.');
}
function succeed(msg) {
  solved = true;
  const fb = document.getElementById('fb'); if (fb) { fb.innerHTML = icon('check') + '<span>' + esc(msg).replace(/&lt;(\/?)b&gt;/g, '<$1b>') + '</span>'; fb.className = 'feedback'; }
  const nx = document.getElementById('next'); if (nx) { nx.disabled = false; nx.focus({ preventScroll: true }); }
  markTarget();
}

stage.addEventListener('click', e => {
  const el = e.target.closest('[data-act]'); if (!el || el.disabled || !stage.contains(el)) return;
  act(el.dataset.act, el.dataset.arg, el); paint(); checkSolved();
});
function setIn(el) {
  const k = el.dataset.in, text = el.tagName === 'INPUT' && el.type !== 'checkbox';
  let pos = null; try { pos = el.selectionStart; } catch {}
  typeIn(k, el.type === 'checkbox' ? el.checked : el.value); paint();
  const n = stage.querySelector(`[data-in="${CSS.escape(k)}"]`);
  if (n && text) { n.focus({ preventScroll: true }); try { if (pos != null) n.setSelectionRange(pos, pos); } catch {} }
  checkSolved();
}
stage.addEventListener('input', e => { const el = e.target.closest('[data-in]'); if (el && el.tagName !== 'SELECT' && el.type !== 'checkbox') setIn(el); });
stage.addEventListener('change', e => { const el = e.target.closest('select[data-in], input[type="checkbox"][data-in]'); if (el) setIn(el); });

/* Drag to arrange: press the grip of a row, let go over another row of the same list. */
let drag = null;
const rowAt = e => { const el = document.elementFromPoint(e.clientX, e.clientY); return el && el.closest ? el.closest(`[data-drag="${CSS.escape(drag.key)}"]`) : null; };
stage.addEventListener('pointerdown', e => {
  const g = e.target.closest('[data-grip]'), row = g && g.closest('[data-drag]'); if (!row) return;
  e.preventDefault(); drag = { key: row.dataset.drag, from: +row.dataset.i }; row.classList.add('k-dragging');
});
window.addEventListener('pointermove', e => { if (!drag) return; stage.querySelectorAll('.k-dropat').forEach(x => x.classList.remove('k-dropat')); const r = rowAt(e); if (r) r.classList.add('k-dropat'); });
window.addEventListener('pointerup', e => { if (!drag) return; const r = rowAt(e), d = drag; drag = null; if (r) dragMove(d.key, d.from, +r.dataset.i); paint(); checkSolved(); });

document.addEventListener('keydown', e => {
  if (/INPUT|SELECT|TEXTAREA/.test(e.target.tagName) || e.metaKey || e.ctrlKey || e.altKey) return;
  const c = CHAPTERS[ci];
  if (c && c.actions && c.actions.key && fin.hidden) {
    const before = JSON.stringify(S); act('key', e.key);
    if (JSON.stringify(S) !== before) { e.preventDefault(); paint(); checkSolved(); return; }
  }
  if (e.key === 'Enter') { const n = document.getElementById('next'); if (n && !n.disabled && document.activeElement !== n) n.click(); }
});

/* ---------- Rail, coach, moving on ---------- */
function renderRail() {
  const total = totalSteps(), before = CHAPTERS.slice(0, ci).reduce((n, c) => n + c.steps.length, 0) + (ci < CHAPTERS.length ? si : 0);
  document.getElementById('rail').innerHTML = `<div class="brand"><span class="apptile">${icon('triathlon')}</span><div><h1>Triathlon Training Course</h1><small>${CHAPTERS.length} chapters · ${total} steps · your pace</small></div></div>
    <div class="chaps">${CHAPTERS.map((c, i) => `<button class="chap ${i === ci ? 'cur' : ''} ${doneCh.has(c.id) ? 'done' : ''}" data-ch="${i}">${icon(c.icon)}<span>${esc(c.title)}</span><span class="n">${doneCh.has(c.id) ? icon('check') : c.steps.length}</span></button>`).join('')}
    <button class="chap ${ci === CHAPTERS.length ? 'cur' : ''}" data-ch="${CHAPTERS.length}">${icon('trophy')}<span>${esc(FINALE ? FINALE.title : 'On your own devices')}</span></button></div>
    <div class="bar"><i style="width:${Math.round(100 * Math.min(before, total) / Math.max(total, 1))}%"></i></div>
    <p class="railnote">Everything here is a practice copy with an invented plan. Nothing changes in your real app or your real plan.</p>`;
}
document.getElementById('rail').addEventListener('click', e => { const b = e.target.closest('[data-ch]'); if (b) goChapter(+b.dataset.ch); });

function goChapter(i, s = 0) { ci = Math.max(0, Math.min(i, CHAPTERS.length)); si = s; renderStep(); }
function renderStep() {
  clearTimers(); renderRail();
  store.set(KEY + '-at', JSON.stringify([ci, si]));
  if (ci >= CHAPTERS.length) { coach.hidden = true; document.getElementById('stagebox').hidden = true; document.querySelector('.main').classList.remove('dev-phone'); renderFinish(); return; }
  coach.hidden = false; fin.hidden = true; document.getElementById('stagebox').hidden = false;
  const c = CHAPTERS[ci], st = c.steps[si];
  S = stateFor(ci, si); solved = st.kind === 'look';
  const kind = st.shot ? 'Look · the real app' : { look: 'Look', try: 'Try it', check: 'Check' }[st.kind];
  const first = si === 0 && (c.needs || c.gives);
  coach.innerHTML = `<div class="eyebrow">${icon(c.icon)}<span>${esc(c.title)}</span><span class="kind">${kind} · step ${si + 1} of ${c.steps.length}</span>${st.only ? `<span class="only">${esc(st.only)}</span>` : ''}</div>
    <div class="say"><h2>${esc(st.head)}</h2><p>${st.text}</p>${st.hint ? `<p class="hint">${st.hint}</p>` : ''}
      ${first ? `<div class="deal">${c.needs ? `<div><b>What it needs from you</b><span>${c.needs}</span></div>` : ''}${c.gives ? `<div><b>What you get</b><span>${c.gives}</span></div>` : ''}</div>` : ''}
      ${st.real ? `<p class="real">${icon('pin')}<span>In your real app: ${esc(st.real)}</span></p>` : ''}</div>
    <div class="btns">${ci + si > 0 ? '<button class="btn ghost" id="back">Back</button>' : ''}${st.kind === 'try' ? '<button class="btn ghost" id="again">Start this step again</button>' : ''}<button class="btn main-b" id="next" ${solved ? '' : 'disabled'}>${si === c.steps.length - 1 ? 'Finish chapter' : 'Next'}</button></div>
    ${st.kind === 'check' ? `<div class="answers">${st.answers.map((a, i) => `<button class="ans" data-a="${i}">${esc(a)}</button>`).join('')}</div>` : ''}
    <p class="feedback" id="fb"></p>`;
  paint(true);
  if (st.kind === 'check') coach.querySelectorAll('.ans').forEach(b => b.onclick = () => {
    const fb = document.getElementById('fb');
    if (+b.dataset.a === st.right) { coach.querySelectorAll('.ans').forEach(x => x.disabled = true); b.classList.add('right'); succeed(st.ok || 'Right.'); }
    else { b.classList.add('wrong'); fb.textContent = st.no || 'Not quite. Try another answer.'; fb.className = 'feedback no'; }
  });
  document.getElementById('next').onclick = next;
  const bk = document.getElementById('back'); if (bk) bk.onclick = back;
  const ag = document.getElementById('again'); if (ag) ag.onclick = renderStep;
}
function next() {
  const c = CHAPTERS[ci];
  if (si < c.steps.length - 1) { si++; renderStep(); return; }
  doneCh.add(c.id); store.set(KEY + '-done', JSON.stringify([...doneCh]));
  goChapter(ci + 1);
}
function back() { if (si > 0) { si--; renderStep(); } else if (ci > 0) goChapter(ci - 1, CHAPTERS[ci - 1].steps.length - 1); }

function renderFinish() {
  fin.hidden = false;
  const F = FINALE || { title: 'On your own devices', lead: '', groups: [] };
  let ticks = readList(KEY + '-real'), n = 0;
  const deal = CHAPTERS.filter(c => c.needs || c.gives);
  fin.innerHTML = `<h2>${esc(F.heading || F.title)}</h2>${F.lead ? `<p class="lead">${F.lead}</p>` : ''}
    ${F.groups.map(g => `<section class="fgroup"><h3>${esc(g.title)}</h3>${g.note ? `<p class="fnote">${g.note}</p>` : ''}
      ${g.items.map(t => { const id = n++; return `<label><input type="checkbox" id="real-${id}" data-i="${id}" ${ticks.includes(id) ? 'checked' : ''}><span>${t}</span></label>`; }).join('')}</section>`).join('')}
    ${deal.length ? `<section class="fgroup"><h3>The whole deal on one page</h3><div class="dealwrap"><table class="dealtable"><thead><tr><th>Part</th><th>What it needs from you</th><th>What you get</th></tr></thead><tbody>
      ${deal.map(c => `<tr><th>${icon(c.icon)}<span>${esc(c.title)}</span></th><td>${c.needs || ''}</td><td>${c.gives || ''}</td></tr>`).join('')}</tbody></table></div></section>` : ''}
    <div class="fbtns"><button class="btn main-b" id="restart">Start the course again</button></div>`;
  fin.querySelectorAll('input').forEach(c => c.onchange = () => { const i = +c.dataset.i; ticks = ticks.filter(x => x !== i); if (c.checked) ticks.push(i); store.set(KEY + '-real', JSON.stringify(ticks)); });
  document.getElementById('restart').onclick = () => goChapter(0);
}

/* Fit the pretend device into its box: the iPhone's stage is 360 × 660 and sits beside the coach, the iPad's is 1040 × 660 under it. */
function fit() {
  const box = document.getElementById('stagebox'), pad = S && S.device === 'pad', w = pad ? 1040 : 360;
  document.querySelector('.main').classList.toggle('dev-phone', !pad && ci < CHAPTERS.length);
  box.style.aspectRatio = w + ' / 660'; stage.style.width = w + 'px';
  stage.style.transform = `scale(${box.clientWidth / w})`;
}
stage.addEventListener('error', e => { if (e.target.classList && e.target.classList.contains('k-shot')) e.target.closest('.k-shotwrap').classList.add('k-noshot'); }, true);
new ResizeObserver(fit).observe(document.getElementById('stagebox'));

/* The test robot: walks every step in the real page and lists what does not work. Run  await __robot()  in the console. */
window.__robot = async (from = 0, to = CHAPTERS.length) => {
  const out = []; robotMode = true;
  for (let c = from; c < to; c++) for (let s = 0; s < CHAPTERS[c].steps.length; s++) {
    ci = c; si = s; renderStep();
    const st = step(), tag = `${CHAPTERS[c].id} ${s + 1}`;
    const need = n => { const el = stage.querySelector(`[data-t="${CSS.escape(n)}"]`); if (!el) out.push(`${tag}: nothing carries the ring "${n}"`); return el; };
    const t = typeof st.target === 'function' ? st.target(S) : st.target; [].concat(t || []).forEach(need);
    const wide = e => e && e.scrollWidth > e.clientWidth + 2;
    const look = () => { if (wide(stage.querySelector('.pane'))) out.push(`${tag}: the page is too wide`); if (wide(stage.querySelector('.k-sheet'))) out.push(`${tag}: the sheet is too wide`);
      const sh = stage.querySelector('.k-sheet'); if (sh && sh.offsetHeight > 640) out.push(`${tag}: the sheet is too tall`);
      const im = stage.querySelector('.k-shot'); if (st.shot && (!im || stage.querySelector('.k-noshot'))) out.push(`${tag}: the picture ${st.shot} is missing`); };
    look();
    if (st.kind === 'try') {
      for (const [op, a, b, d] of st.robot || []) {
        if (op === 'act') { const el = [...stage.querySelectorAll(`[data-act="${CSS.escape(a)}"]`)].find(x => b === undefined || x.dataset.arg === String(b));
          if (!el || el.disabled) { out.push(`${tag}: cannot press ${a} ${b ?? ''}`); break; } el.dispatchEvent(new MouseEvent('click', { bubbles: true })); }
        else if (op === 'in') { const el = stage.querySelector(`[data-in="${CSS.escape(a)}"]`); if (!el) { out.push(`${tag}: no field ${a}`); break; }
          el.value = b; el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true })); }
        else if (op === 'drag') { dragMove(a, b, d); paint(); checkSolved(); }
        else if (op === 'key') { document.dispatchEvent(new KeyboardEvent('keydown', { key: a, bubbles: true })); }
        look();
      }
      if (!solved) out.push(`${tag}: the robot's steps do not finish it`);
    }
    if (st.kind === 'check') { const b = coach.querySelectorAll('.ans')[st.right]; if (b) b.click(); if (!solved) out.push(`${tag}: the right answer does not unlock Next`); }
    await new Promise(r => setTimeout(r, 0));
  }
  robotMode = false; return out;
};

const at = (() => { try { return JSON.parse(store.get(KEY + '-at') || '[0,0]'); } catch { return [0, 0]; } })();
if (at[0] < CHAPTERS.length && CHAPTERS[at[0]] && at[1] < CHAPTERS[at[0]].steps.length) goChapter(at[0], at[1]); else goChapter(0);
fit();
