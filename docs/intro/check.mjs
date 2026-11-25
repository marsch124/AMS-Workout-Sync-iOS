#!/usr/bin/env node
/* Checks the course's chapters without a browser.   node docs/intro/check.mjs          every chapter
                                                      node docs/intro/check.mjs imp      only the chapter with the id "imp"
                                                      node docs/intro/check.mjs exa      the worked example in src/example
   For every step it builds the practice state, draws the window as text, looks for the ring's target, and for a "try" step
   plays the robot's moves and asks the step's own "until" whether it is done. Ends with exit code 1 when something is wrong. */
import fs from 'node:fs'; import path from 'node:path'; import vm from 'node:vm'; import { fileURLToPath } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url)), src = path.join(root, 'src');
const only = process.argv[2] || '';
const read = f => fs.readFileSync(f, 'utf8');
let files = fs.readdirSync(path.join(src, 'chapters')).filter(f => f.endsWith('.js')).sort().map(f => path.join(src, 'chapters', f));
if (only === 'exa') files = [path.join(src, 'example', '99-exa.js')];
else if (only) files = files.filter(f => path.basename(f).replace(/^\d+-/, '').replace(/\.js$/, '') === only);
if (!files.length) { console.error(`No chapter file for "${only}".`); process.exit(1); }
const fail = [];
for (const f of files) { try { new vm.Script(read(f), { filename: f }); } catch (e) { fail.push(`${path.basename(f)}: does not read as code — ${e.message}${e.stack ? ' (' + String(e.stack).split('\n')[0] + ')' : ''}`); } }
if (fail.length) { console.error(fail.join('\n')); process.exit(1); }
const code = [path.join(src, 'icons.js'), path.join(src, 'core.js'), ...files].map(read).join('\n;\n')
  + '\n;globalThis.__T = { CHAPTERS, ICON, stageHTML, stateFor, act, typeIn, dragMove, put: (c, s, st) => { ci = c; si = s; S = st; }, get: () => S };';
vm.runInThisContext(code, { filename: 'course.js' });
const T = globalThis.__T;

const unesc = s => s.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const tags = (html, name) => [...html.matchAll(new RegExp(`<[^<>]*\\b${name}="([^"]*)"[^<>]*>`, 'g'))];
const hasT = (html, t) => tags(html, 'data-t').some(m => unesc(m[1]) === t);
const canPress = (html, a, arg) => tags(html, 'data-act').some(m => m[1] === a && !/\sdisabled[\s>=]/.test(m[0])
  && (arg === undefined || unesc((/\bdata-arg="([^"]*)"/.exec(m[0]) || [0, '\u0000'])[1]) === String(arg)));
const BAD = /undefined|NaN|\[object Object\]/;
const PICTO = /[\u{1F000}-\u{1FAFF}\u{2600}-\u{26FF}\u{2705}\u{274C}\u{2B50}\u{2B06}\u{2B07}]/u;
const RESERVED = new Set(['done', 'cur', 'chap', 'chaps', 'bar', 'rail', 'coach', 'main', 'wrap', 'target', 'finish', 'btn', 'brand', 'ans', 'answers', 'feedback', 'stage', 'stagebox', 'deal', 'say', 'btns', 'eyebrow', 'kind', 'only', 'hint', 'real', 'i', 'n', 'pane', 'pad', 'phone', 'desk', 'padshot']);

let problems = 0, allSteps = 0;
T.CHAPTERS.forEach((c, cix) => {
  const bad = [], say = m => bad.push(m), count = { look: 0, try: 0, check: 0 };
  if (!/^[a-z]{3}$/.test(c.id || '')) say('id must be three small letters');
  if (!c.title) say('no title'); if (!T.ICON[c.icon]) say(`icon "${c.icon}" is not in ICON`);
  if (!c.needs || !c.gives) say('needs and gives (what it needs from him, what he gets) are missing');
  if (!Array.isArray(c.steps) || c.steps.length < 6) say('fewer than 6 steps');
  if (only !== 'exa' && Array.isArray(c.steps) && !c.steps.some(st => st.shot)) say('no step shows a real picture (shot)');
  (c.steps || []).forEach((st, s) => {
    const tag = `step ${s + 1} "${st.head || '?'}"`; allSteps++;
    if (!['look', 'try', 'check'].includes(st.kind)) return say(`${tag}: kind must be look, try or check`);
    count[st.kind]++;
    if (!st.head || !st.text) say(`${tag}: head or text missing`);
    if (st.head && st.head.split(/\s+/).length > 9) say(`${tag}: head longer than 9 words`);
    if (st.text && st.text.replace(/<[^>]+>/g, '').length > 380) say(`${tag}: text longer than 380 characters (${st.text.replace(/<[^>]+>/g, '').length})`);
    if (PICTO.test((st.head || '') + (st.text || '') + (st.hint || ''))) say(`${tag}: an emoji or picture sign in the words`);
    if (st.shot) { if (st.kind !== 'look') say(`${tag}: only a look step may carry a real picture (shot)`);
      else if (!fs.existsSync(path.join(root, 'shots', st.shot + '.jpg'))) say(`${tag}: no picture shots/${st.shot}.jpg`);
      if (st.target) say(`${tag}: a step with a real picture cannot have a ring (target) — the picture is not pressable`); }
    let html = '';
    const draw = when => { try { html = T.stageHTML(); } catch (e) { say(`${tag}: the screen cannot be drawn ${when} — ${e.message}`); html = ''; return false; }
      if (BAD.test(html.replace(/<[^>]*>/g, ' '))) say(`${tag}: the screen shows "undefined", "NaN" or "[object Object]" ${when}`);
      if (PICTO.test(html)) say(`${tag}: an emoji or picture sign on the screen ${when}`); return true; };
    try { T.put(cix, s, T.stateFor(cix, s)); } catch (e) { return say(`${tag}: the state cannot be built — ${e.message}`); }
    if (!draw('at the start')) return;
    const t = typeof st.target === 'function' ? st.target(T.get()) : st.target;
    [].concat(t || []).forEach(n => { if (!hasT(html, n)) say(`${tag}: nothing on the screen carries data-t="${n}"`); });
    if (st.kind !== 'check' && !t && st.kind === 'try') say(`${tag}: a try step needs a target for the ring`);
    if (st.kind === 'try') {
      if (typeof st.until !== 'function') return say(`${tag}: no until(S)`);
      if (!Array.isArray(st.robot) || !st.robot.length) return say(`${tag}: no robot moves`);
      let pre = false; try { pre = !!st.until(T.get()); } catch (e) { say(`${tag}: until fails — ${e.message}`); }
      if (pre) say(`${tag}: already done before anything is pressed`);
      for (const [op, a, b, d] of st.robot) {
        try {
          if (op === 'act') { if (!canPress(html, a, b)) { say(`${tag}: the robot cannot press data-act="${a}"${b !== undefined ? ` data-arg="${b}"` : ''} — not on the screen (or disabled) at that moment`); break; } T.act(a, b === undefined ? undefined : String(b)); }
          else if (op === 'in') { if (!tags(html, 'data-in').some(m => m[1] === a)) { say(`${tag}: no field data-in="${a}" on the screen`); break; } T.typeIn(a, b); }
          else if (op === 'drag') { if (tags(html, 'data-drag').filter(m => m[1] === a).length <= Math.max(b, d)) { say(`${tag}: no row ${Math.max(b, d)} in data-drag="${a}"`); break; } T.dragMove(a, b, d); }
          else if (op === 'key') { if (!(c.actions && c.actions.key)) { say(`${tag}: a key move, but the chapter has no actions.key`); break; } T.act('key', a); }
          else { say(`${tag}: unknown robot move "${op}"`); break; }
        } catch (e) { say(`${tag}: ${op} ${a} fails — ${e.message}`); break; }
        if (!draw(`after ${op} ${a}`)) break;
      }
      let post = false; try { post = !!st.until(T.get()); } catch (e) { say(`${tag}: until fails after the moves — ${e.message}`); }
      if (!post) say(`${tag}: the robot's moves do not finish the step`);
      if (!st.ok) say(`${tag}: no ok sentence`);
    }
    if (st.kind === 'check') {
      if (!Array.isArray(st.answers) || st.answers.length < 2) say(`${tag}: fewer than 2 answers`);
      else if (!(st.right >= 0 && st.right < st.answers.length)) say(`${tag}: right is not one of the answers`);
      if (!st.ok) say(`${tag}: no ok sentence`);
    }
  });
  const cssFile = files.map(f => f.replace(/\.js$/, '.css')).find(f => path.basename(f).includes('-' + c.id + '.') && fs.existsSync(f));
  if (cssFile) {
    const css = read(cssFile).replace(/\/\*[\s\S]*?\*\//g, '').replace(/\{[^{}]*\}/g, '{}');
    for (const m of css.matchAll(/\.([A-Za-z_][\w-]*)/g)) { const n = m[1];
      if (RESERVED.has(n)) say(`css: the class name ".${n}" belongs to the page — rename it to ".${c.id}-${n}"`);
      else if (!n.startsWith(c.id + '-') && !n.startsWith('k-') && !n.startsWith('pad-') && !n.startsWith('phone-')) say(`css: class ".${n}" must start with "${c.id}-"`); }
    if (/(^|[,}])\s*(body|html|button|input|select|svg|table|h1|h2|h3|p|b|\*)\s*[{,]/.test(css)) say('css: a bare tag selector (button, p, …) — put your own class in front');
  }
  problems += bad.length;
  console.log(`${c.id}  ${c.title}: ${(c.steps || []).length} steps (${count.look} look, ${count.try} try, ${count.check} check) — ${bad.length ? bad.length + ' PROBLEM(S)' : 'OK'}`);
  bad.forEach(b => console.log('   · ' + b));
});
console.log(`${T.CHAPTERS.length} chapter(s), ${allSteps} steps, ${problems} problem(s).`);
process.exit(problems ? 1 : 0);
