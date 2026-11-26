# The Triathlon Training Course — how a chapter is written

The course teaches Martin his own app, AMS Triathlon Training 2.12 (88): a chapter rail, a coach card (Look / Try it / Check), **real
pictures of the app** and a **pretend iPhone** (for the Plan page a pretend iPad) that he presses. It is one web page,
`docs/intro/index.html`, put together by `build.py` from `src/`, with the pictures in `shots/` beside it. Nothing in it touches the
real app. **Update the course in the release that changes a taught screen.**

## Files
- `src/icons.js` — the icons (`ICON`). `src/core.js` — the chapter list, the practice state, the device as text, the `K` building blocks.
- `src/ui.js` — the page (rail, coach, presses, typing, drag). `src/page.css`, `src/kit.css` — the look; kit classes start with `k-`.
- `src/chapters/NN-id.js` (+ optional `NN-id.css`) — **one chapter per file pair.** `src/finale.js` — the last page.
- `src/chapters/00-wel.js` (+ `.css`) — the first chapter and **the worked example: read it first**, then `src/example/99-exa.js`
  (typing, choosing, a sheet, a refusal, drag to arrange).
- `shots/<name>.jpg` — real pictures, taken as `PICTURES.md` says; `shots/INDEX-A.md`, `-B.md`, `-C.md` say what is on each.
- `check.mjs` — checks chapters without a browser: `node docs/intro/check.mjs <id>`. `build.py` — makes `index.html`.

## A chapter
```js
CHAPTER({ id, title, icon, needs, gives, start, screens, sheets, actions, steps });
```
- `id` three small letters. **Everything the chapter invents starts with it:** state keys `log_len`, screens `'log.form'`,
  sheets `'log.missed'`, actions `'log.save'`, ring targets `data-t="log.save"`, css classes `.log-row`, own icons `ICON['log-x']`.
- `needs` / `gives`: one or two plain sentences each — what this part of the app needs from Martin, and what he gets out of it.
  They show on the chapter's first step and in a table on the last page.
- `start()` returns the plain data every step of the chapter starts from (no functions, no Dates). Top-level keys the device reads:
  `device` ('phone' = the iPhone with its five tabs, the default; 'pad' = the iPad and Mac look with the side list),
  `part` (which tab or side row is lit, and which colour the page takes: today, plan, sessions, body, progress, settings —
  `plan` exists only on 'pad'), `screen` (name of the screen to draw), `sheet` (name of a sheet over it, or null).
- `screens[name](S)` and `sheets[name](S)` return HTML text. `actions[name](arg, S, element)` only change `S`.
  Special actions: `'in'(key, S)` after typing or choosing, `'drop'(listKey, S)` after a drag, `'key'(key, S)` for a key press
  (e.g. 'ArrowRight', ' ', 'Escape'), `tab(part, S)` / `side(part, S)` if a press on a tab or in the side list should do something
  (default: a friendly note). `toast('words')` shows a short note; `later(fn, ms)` does something a moment later.
- On 'pad', a chapter may also give `sidefoot: S => html` beside `screens`: it is drawn at the foot of the side list (where the real
  app has "Keys" and the dot with its words); it may carry `data-act` and `data-t` like any screen.
- **Every step starts fresh:** state = BASE + `start()` + the step's `set`. Nothing is carried over from the step before, so a step
  that needs "the log form open, 40 typed" says so in its `set`.
- A page opened from another page (a session's page, a Settings page) is just another screen: draw `K.back('Today', '<id>.back')`
  at its top. A page that slides up from the bottom (a form with Cancel and Save, a plate with Done) is a sheet.

## What the HTML may carry
- `data-act="name"` (+ `data-arg="value"`) on anything pressable → `actions[name](arg, S)`.
- `data-in="stateKey"` on an `<input>` / `<select>` (use `K.input`, `K.select`) → `S[stateKey]` follows what he types.
- Drag to arrange: each row `data-drag="listKey" data-i="<index>"` with a grip inside that has `data-grip`; `S[listKey]` is the list
  and is reordered by the page. **Arranging is always drag and drop — never up/down arrow buttons** (his rule).
- `data-t="name"` on the thing a step's ring should point at.
- Building blocks (their use is written above each one in `src/core.js`): `K.btn` (`{ main: true }` = the green main button),
  `K.seg`, `K.stepper`, `K.bar`, `K.mark`, `K.input`, `K.select`, `K.tick`, `K.switch`, `K.sport('run')` (the round sport mark),
  `K.done()` (the green tick circle = done), `K.back`, `K.hero` (head card filled with the part's colour), `K.stat` (figure tile),
  `K.chip`, `K.nav` (a row that opens something), `icon(name)`, `esc(text)`, `dur(35)` → "35m", `dur(65)` → "1h 05m", `num(n)`.
  Kit classes are in `src/kit.css`: `k-h1`, `k-h2`, `k-cap` (small capitals), `k-big`, `k-card`, `k-row`, `k-name`, `k-fig`, `k-line`,
  `k-col`, `k-cols`, `k-stats` (grid of `K.stat`), `k-list`, `k-band` (`k-needs` orange), `k-foot`, `k-field`, `k-pill`, `k-tile`,
  `k-dragrow`, `k-grip`, `k-link`, `k-kbd`, `k-muted`, `k-small`, `k-sportword k-sp-run`, `k-btn k-full`, `k-btn k-out` …
  A page heading is `<h1 class="k-h1">` — it takes the part's colour by itself. A sheet starts with `<h3>` and ends with
  `<div class="k-foot">` holding Cancel and the green main button (`K.btn('Save', …, { main: true })`).
- Never write the closing script tag, never use an emoji or a picture character (✓ ✗ → ★ …): draw marks with `icon()`, `K.done()`
  or `K.mark`. Colours only through the page's variables (`var(--pt)` the part's colour, `var(--win-muted)`, `var(--card)`,
  `var(--sp-run)` …) so day and night both work — never a fixed colour like `#fff` on a page background.

## A step
```js
{ kind: 'look',  head, text, hint?, set?, target?, shot?, real?, only? }
{ kind: 'try',   head, text, hint?, set?, target, until: S => …, ok, robot: [...], real?, only? }
{ kind: 'check', head, text, set?, answers: [...], right: <index>, ok, no? }
```
- `head` at most 9 words. `text` at most 3 short sentences (380 characters); it may use `<b>` for a button's exact name.
- `shot: 'tod-01-morning'` on a **look** step shows that real picture (`shots/tod-01-morning.jpg`) in place of the practice screen.
  The picture cannot be pressed and has no ring, so the words must say where to look ("at the top", "the green card").
  Describe only what that picture really shows — look at it (Read the .jpg) before you write. An iPad picture needs `set: { device: 'pad' }`.
- `target`: a `data-t` name, a list of them, or `S => name` so the ring moves on inside a step with several presses.
- `until(S)` says when a try step is done. `robot` is the list of moves that solves it, used by the checks:
  `['act', 'name', 'arg'?]`, `['in', 'stateKey', 'value']`, `['drag', 'listKey', from, to]`, `['key', 'ArrowRight']`.
- `ok`: one sentence that says what just happened, as the real app would show it.
- `real`: where this is in the real app ("Settings › Reminders"). `only`: "iPad and Mac" / "iPhone" / "Mac" when not everywhere.

## Room
The iPhone's page is **266 wide** (the real one is 390 points: draw everything at about three quarters of real size; the type is
12.5). It scrolls up and down, never sideways — keep what a step points at near the top. A sheet on the iPhone comes from the
bottom, full width, at most 560 tall. The iPad's page (beside the side list) is 868 × 660 with 20 of padding: about 828 wide;
a sheet there is 520 wide. Long words must wrap, not run off: no fixed widths wider than the page, no `white-space: nowrap` on sentences.

## Facts — the course must be exactly true
- Every label, button name, heading, message and number format comes from the app's code, word for word: `App/Sources/*.swift`,
  `Core/Sources/WorkoutCore/*.swift`, the guide `App/Sources/Guide.swift` (How this works, "Signs in this app", What's new),
  `docs/SPECIFICATION.md` (the section "New in 2.12 (88)" and the ones before it), the screen tests in `UITests/`.
  When the guide and the code differ, the code wins — and say so in your report.
- Teach only what 2.12 (88) really does. The iPhone has five tabs (Today, Sessions, Body, Progress, Settings). The iPad and the Mac
  have a side list (Today, Plan, Sessions, Body, Progress, Settings). What belongs to the iPhone only (Dropbox, the Training
  calendar, Apple Health …) is in the specification, section W.1 — say so with `only`.
- The sample is invented. Use the invented plan the pictures show (`UITests/Fixtures/plan.xlsx`, its "today" is Wednesday
  16 September 2026: e.g. the run "Easy run + 4x20 s strides", 35m, Z2) and the app's own DEBUG sample values; otherwise invent
  calm round figures. **Never read or use Martin's real plan or health numbers, never read his real files, and use no names of
  real people.** This repository is public.
- Many things in 2.8 could only be proven on a real device (Garmin's real answers, notifications, Siri, hardware keys).
  Teach what the app shows; do not promise more than the code does.

## Words (Martin is not technical)
- Plain everyday English, British spelling, short sentences, sentence case, calm: no praise, no "!", no doctor talk.
  No computer words (no "sync", "toggle", "modal", "UI", "tap target"): say "in step", "switch", "page", "press". Speak to him: "you".
- Use the app's own words for its things (Today, Sessions, "Not well?", "Week so far", "From your watch", "the shelf" is NOT a
  word he sees — never use it).
- A figure sits right beside its name, on the left — never far right.
- A mark or colour means ONE thing: the white tick in a green circle = done, and nothing else; red = missed or danger;
  orange = needs you; a part's own colour only says "this is that part". The main button is always full colour (green), never grey.
  The app's own sign list is "Signs in this app" in `Guide.swift` — stay with it.

## Depth
A chapter has 9 to 13 steps: start with a look step (best with a real picture) that says what the part is for; use 2 to 5 real
pictures in a chapter; show every button he will really use at least once; give a try step to every core action; show the
guards and refusals too; end with one or two check questions about a consequence ("what happens to … when you …?"), not
about a label.
