/* Chapter 4 — A session's page. Everything on the page except logging (chapter 3): the lines under the title, the zones, Change,
   the pool card, favourites, Repeat, Move, the no-gym version, Open Workouts, what a done session shows from the watch, Send.
   Words from SessionView, SessionPurposeLine, PoolCard, Favourites, RepeatSession, NoGymViews, MoveView, SessionEditView,
   DoneSessionGarmin, ShareText (spec S.4, D.5, D.6, D.7, D.9, V.6). */
(() => {
const DAYS = ['Monday 7 September', 'Tuesday 8 September', 'Wednesday 9 September', 'Thursday 10 September', 'Friday 11 September', 'Saturday 12 September', 'Sunday 13 September'];
const POOL = [['Easy technique', null], ['4 × 50 m drill', 200], ['6 × 50 m smooth', 300]];
const ZONEROWS = { 'Z1-Z2': 'Z1 up to 128 bpm · Z2 129–143 bpm' };
const MOVES = [['Squats', '15 reps'], ['Reverse lunges', '8 reps each leg'], ['Push-ups', '10 reps (knees down if needed)'], ['Glute bridge', '15 reps, slow']];

const topRow = (S, done) => `<div class="ses-top">${K.back('Today', 'ses.back')}${K.btn('Send', 'ses.send', { icon: 'share', t: 'ses.send' })}</div>`;

const swim = S => `${topRow(S)}
  <span class="k-line">${K.sport('swim', { size: 40 })}<span class="k-col ses-words"><span class="k-sportword k-sp-swim">Swim</span><span class="k-muted">${DAYS[S.ses_day]}</span></span></span>
  <span class="k-line"><b class="ses-title">${esc(S.ses_title)}</b>${K.btn('Change', 'ses.change', { t: 'ses.change' })}</span>
  <span class="k-muted k-small" data-t="ses.why">Why: a technique swim — smoother strokes first, distance later.</span>
  ${K.btn('Pool card', 'ses.pool', { t: 'ses.poolbtn' })}
  <span class="ses-wrap">${S.ses_fav ? `<b class="k-small" style="color:var(--i-plan)" data-t="ses.fav">In your favourites</b>` : K.btn('Save as favourite', 'ses.fav', { t: 'ses.fav' })}${K.btn('Repeat…', 'ses.repeat', { t: 'ses.repeatbtn' })}</span>
  <span class="ses-wrap">${K.chip(S.ses_min + 'm', { t: 'ses.len' })}${K.chip(S.ses_zone + ' ›', { act: 'ses.zone', t: 'ses.zonepill' })}</span>
  <div class="k-card"><span class="k-cap">Purpose</span><span>${esc(S.ses_purpose)}</span></div>
  <span class="ses-wrap">${K.btn('Done · ' + S.ses_min + 'm', 'ses.note', { main: true, icon: 'check' })}${K.btn('Log details', 'ses.note')}${K.btn('Missed', 'ses.note', { danger: true })}${K.btn('Move', 'ses.move', { t: 'ses.movebtn' })}</span>`;

const strength = S => `${topRow(S)}
  <span class="k-line">${K.sport('strength', { size: 40 })}<span class="k-col ses-words"><span class="k-sportword k-sp-strength">Strength</span><span class="k-muted">Friday 11 September</span></span></span>
  <b class="ses-title">Lower body and core</b>
  <span class="k-muted k-small">Why: strength keeps the engine you build on the road.</span>
  <span class="ses-wrap">${K.chip('30m')}${K.chip('Z2')}</span>
  <button class="k-link" data-act="ses.workouts" data-t="ses.workouts">Open Workouts</button>
  ${K.btn('No-gym version', 'ses.nogym', { t: 'ses.nogym' })}
  <span class="k-muted k-small" data-t="ses.protein">After strength: a meal or snack with 20–30 g of protein within an hour or two.</span>`;

const ride = S => `${topRow(S)}
  <span class="k-line">${K.sport('bike', { size: 40 })}<span class="k-col ses-words"><span class="k-sportword k-sp-bike">Bike</span><span class="k-muted">Saturday 12 September</span></span></span>
  <b class="ses-title">Long ride, steady</b>
  <span class="ses-wrap">${K.chip('2h 30m')}${K.chip('Z2')}</span>
  <span class="k-muted k-small" data-t="ses.fuel">Over 90 minutes: eat and drink as you go — about 30–60 g of carbohydrate an hour.</span>`;

const done = S => `${topRow(S)}
  <span class="k-line">${K.sport('run', { size: 40 })}<span class="k-col ses-words"><span class="k-sportword k-sp-run">Run</span><span class="k-muted">Wednesday 9 September</span></span>${K.done()}</span>
  <b class="ses-title">Easy run + 4x20 s strides</b>
  <span class="k-cap">What you did</span>
  <div class="k-stats">${K.stat('36m', 'Duration')}${K.stat('6.2 km', 'Distance')}${K.stat('138 bpm', 'Heart rate')}${K.stat('4 / 10', 'Effort')}</div>
  <span class="k-cap" data-t="ses.watch">From your watch</span>
  <div class="ses-route"><svg viewBox="0 0 100 40"><path d="M6 30 C20 6 34 6 44 20 S70 36 94 10"/></svg></div>
  <div class="k-card"><span>Average <b>138</b> · Highest <b>156</b> beats</span></div>
  <div class="k-card" data-t="ses.laps"><b>Laps</b><table class="ses-tbl"><tr><th>Lap</th><th>Distance</th><th>Time</th><th>Pulse</th><th>km/h</th></tr>
    <tr><td>1</td><td>1.00 km</td><td>5m 52s</td><td>131</td><td>10.2</td></tr><tr><td>2</td><td>1.00 km</td><td>5m 48s</td><td>136</td><td>10.3</td></tr><tr><td>3</td><td>1.00 km</td><td>5m 49s</td><td>139</td><td>10.3</td></tr></table>
    ${K.btn('Show all 27 laps', 'ses.note2')}</div>
  <div class="k-card" data-t="ses.last"><b>Last time · Wed 2 Sep</b><span class="k-muted k-small">This session ← last time</span>
    <span class="ses-last"><span>Length</span><b>36m</b><span>←</span><span>34m</span></span>
    <span class="ses-last"><span>Distance</span><b>6.2 km</b><span>←</span><span>5.9 km</span></span>
    <span class="ses-last"><span>Average pulse</span><b>138</b><span>←</span><span>141</span></span>
    <span class="ses-last"><span>How hard</span><b>4 of 10</b><span>←</span><span>5 of 10</span></span></div>`;

CHAPTER({
  id: 'ses',
  title: 'A session’s page',
  icon: 'plan',
  needs: 'Nothing: open a session from Today, Sessions or Plan.',
  gives: 'You see why a session is there, what it asks, and every way to change, move, repeat or send it.',
  start: () => ({ device: 'phone', part: 'today', screen: 'ses.swim', sheet: null, ses_day: 3, ses_title: 'Easy technique: 4x50 drill, then 6x50 smooth', ses_min: '30', ses_zone: 'Z1-Z2',
    ses_purpose: 'Feel for the water', ses_fav: false, ses_step: 0, ses_ed_title: '', ses_ed_min: '', ses_ed_tried: false, ses_to: '3', ses_swap: '', ses_until: false,
    ses_added: 0, ses_nogym: false, ses_workouts: false, ses_sent: '', ses_changed: false }),
  screens: {
    'ses.swim': swim, 'ses.strength': strength, 'ses.ride': ride, 'ses.done': done,
    'ses.pool': S => `<div class="ses-pool"><span class="ses-top"><span class="k-col"><span class="k-muted">Whole set</span><b class="ses-big" data-t="ses.total">500 m</b></span>${K.btn('Done', 'ses.pooldone', { main: true, t: 'ses.pooldone' })}</span>
      ${POOL.map((r, i) => `<button class="ses-row${i === S.ses_step ? ' ses-cur' : ''}" data-act="ses.pick" data-arg="${i}">${r[0]}</button>`).join('')}
      <div class="ses-zones"><button data-act="ses.back1" data-t="ses.back1">Back</button><button class="ses-next" data-act="ses.next" data-t="ses.next">Next</button></div></div>`,
  },
  sheets: {
    'ses.zone': S => `<h3>${esc(S.ses_zone)}</h3><span class="k-muted k-small">For you, from Test 2, 2 Sep</span>
      <div class="k-card"><span class="k-cap">Run</span><span>${ZONEROWS['Z1-Z2']}</span></div>
      <span class="k-small"><b>All your zones ›</b></span><div class="k-foot">${K.btn('Done', 'sheet.close', { main: true })}</div>`,
    'ses.edit': S => `<h3>Change session</h3>
      <div class="k-field"><label>Day</label><span>Thu 10 Sep</span></div>
      <div class="k-field"><label>Sport</label><span>Swim</span></div>
      <div class="k-field"><label for="in-ses_ed_title">What you do</label>${K.input('ses_ed_title', S, { t: 'ses.edtitle' })}</div>
      <div class="k-field"><label for="in-ses_ed_min">Length (minutes)</label>${K.input('ses_ed_min', S, { num: true, w: 90, t: 'ses.edmin' })}</div>
      <div class="k-field"><label>Zone or effort</label><span>${esc(S.ses_zone)}</span></div>
      <div class="k-field"><label>Purpose</label><span>${esc(S.ses_purpose)}</span></div>
      ${K.switch(false, 'Key session', 'ses.note')}
      ${K.btn('Take out of the plan', 'ses.note', { danger: true })}
      ${S.ses_ed_tried && !S.ses_ed_title.trim() ? '<span class="ses-bad">Write a few words for the session first.</span>' : ''}
      ${S.ses_ed_tried && S.ses_ed_title.trim() && isNaN(Number(S.ses_ed_min.replace(',', '.'))) ? '<span class="ses-bad">The length must be a number of minutes.</span>' : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'ses.edsave', { main: true, t: 'ses.edsave' })}</div>`,
    'ses.repeat': S => `<h3>Repeat</h3><b>Technique swim · Thu 10 Sep</b>
      <div class="k-field"><label>Repeat</label><span>Every week until Thu 5 Nov</span></div>
      <div class="k-card" data-t="ses.list"><b style="color:var(--i-plan)">7 sessions: Thu 17 Sep, Thu 24 Sep, Thu 8 Oct, Thu 15 Oct, Thu 22 Oct, Thu 29 Oct, Thu 5 Nov</b>
        <span class="k-muted k-small" data-t="ses.leftout">Thu 1 Oct left out — that day already has a Swim session with this title</span>
        <span class="k-muted k-small">They are added together, and one Undo under Changes to the plan takes them all back.</span></div>
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Add 7 sessions', 'ses.repadd', { main: true, t: 'ses.repadd' })}</div>`,
    'ses.move': S => `<h3>Move</h3>
      <div class="k-card"><span class="k-sportword k-sp-swim">Swim</span><b>${esc(S.ses_title)}</b><span class="k-muted k-small">${DAYS[S.ses_day]}</span></div>
      <span class="k-line"><span class="k-cap">Move it to</span>${K.btn('+1 day', 'ses.plus1', { t: 'ses.plus1' })}</span>
      <div class="k-field">${K.select('ses_to', S, DAYS.map((d, i) => [String(i), d]), { t: 'ses.to' })}</div>
      ${K.btn('Move the session', 'ses.moveit', { main: true, t: 'ses.moveit' })}
      <span class="k-muted k-small">${Number(S.ses_to) === S.ses_day ? 'Pick a different day first.' : '+1 moves it straight to tomorrow. Only the date is rewritten either way: the session keeps its place in every weekly total, because your sheet counts by week number and sport, never by date.'}</span>
      <span class="k-cap">Or swap it with</span><span class="k-muted k-small">Exchanges the two days — for when you did one session in the other’s place. Only sessions still to do are offered.</span>
      <button class="ses-pick" data-act="ses.swapask" data-arg="Strength" data-t="ses.swap"><b>Lower body and core</b><span class="k-muted k-small">Fri 11 Sep · in 1 day</span></button>
      ${S.ses_swap ? `<div class="k-band k-needs"><span>Swim → Fri 11 Sep, Strength → Thu 10 Sep</span></div>${K.btn('Swap these two', 'ses.swapdo', { main: true, t: 'ses.swapdo' })}` : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}</div>`,
    'ses.nogym': S => `<div class="k-hero" style="background:var(--ink-strength)"><span class="k-herocap">NO-GYM VERSION</span><b class="k-herotitle">3 rounds</b><span>8 moves · about 30 min planned</span></div>
      <span class="k-small">Warm-up, 5 min: march on the spot, arm circles, leg swings, then 10 slow squats.</span>
      <div class="k-card">${MOVES.map(m => `<span class="k-line"><b>${m[0]}</b><span class="k-muted k-small">${m[1]}</span></span>`).join('')}<span class="k-muted k-small">… and four more moves (plank, side plank, calf raises, superman)</span></div>
      <span class="k-small">Cool-down, 5 min: walk slowly, then stretch calves, thighs, hips and chest; breathe slowly.</span>
      <span class="k-small"><b>3 rounds · 60 seconds rest between rounds</b></span><span class="k-muted k-small">Move at a pace you can hold, and swap any move that feels wrong for an easier one. This changes nothing in your plan: log the strength session as usual.</span>
      <div class="k-foot">${K.btn('Done', 'ses.nogymdone', { main: true, t: 'ses.nogymdone' })}</div>`,
    'ses.send': S => `<h3>Send it to somebody</h3>
      ${S.screen === 'ses.done' ? K.btn('Send what you did', 'ses.sendit', { arg: 'what you did', t: 'ses.sendwhat' }) : ''}
      ${K.btn('Send the whole session', 'ses.sendit', { arg: 'the whole session', t: 'ses.sendall' })}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}</div>`,
  },
  actions: {
    'ses.back'() { toast('Today has its own chapter.'); },
    'ses.note'() { toast('Logging has its own chapter.'); },
    'ses.note2'() { toast('Shows every lap, not only the first twelve.'); },
    'ses.zone'(a, S) { S.sheet = 'ses.zone'; },
    'ses.change'(a, S) { S.ses_ed_title = S.ses_title; S.ses_ed_min = S.ses_min; S.ses_ed_tried = false; S.sheet = 'ses.edit'; },
    'ses.edsave'(a, S) { S.ses_ed_tried = true; const t = S.ses_ed_title.trim(), m = S.ses_ed_min.trim().replace(',', '.');
      if (!t || (m && isNaN(Number(m)))) return; S.ses_title = t; if (m) S.ses_min = m; S.ses_changed = true; S.sheet = null;
      toast('Changed. It stays in Settings › Changes to the plan, where Undo brings it back.'); },
    'ses.pool'(a, S) { S.screen = 'ses.pool'; S.ses_step = 0; },
    'ses.pick'(a, S) { S.ses_step = Number(a); },
    'ses.next'(a, S) { if (S.ses_step < POOL.length - 1) S.ses_step++; },
    'ses.back1'(a, S) { if (S.ses_step > 0) S.ses_step--; },
    'ses.pooldone'(a, S) { S.screen = 'ses.swim'; S.ses_pooled = true; },
    'ses.fav'(a, S) { S.ses_fav = true; },
    'ses.repeat'(a, S) { S.sheet = 'ses.repeat'; },
    'ses.repadd'(a, S) { S.ses_added = 7; S.sheet = null; toast('7 sessions added to the plan.'); },
    'ses.move'(a, S) { S.ses_to = String(S.ses_day); S.ses_swap = ''; S.sheet = 'ses.move'; },
    'ses.plus1'(a, S) { S.ses_day = Math.min(6, S.ses_day + 1); S.sheet = null; },
    'ses.moveit'(a, S) { if (Number(S.ses_to) === S.ses_day) return; S.ses_day = Number(S.ses_to); S.sheet = null; },
    'ses.swapask'(a, S) { S.ses_swap = a; },
    'ses.swapdo'(a, S) { S.ses_day = 4; S.sheet = null; },
    'ses.nogym'(a, S) { S.sheet = 'ses.nogym'; },
    'ses.nogymdone'(a, S) { S.sheet = null; S.ses_nogym = true; },
    'ses.workouts'(a, S) { S.ses_workouts = true; toast('Opens AMS Workout Companion.'); },
    'ses.send'(a, S) { S.sheet = 'ses.send'; },
    'ses.sendit'(a, S) { S.ses_sent = a; S.sheet = null; toast('The share sheet opens with ' + a + '.'); },
  },
  steps: [
    { kind: 'look', head: 'A session’s own page', shot: 'ses-04-planned-swim',
      text: 'Open any session and you get its page. From the top: <b>Send</b> at the right, the sport and the day, the title with <b>Change</b> beside it, a grey <b>Why:</b> line, <b>Pool card</b> (swims only), <b>Save as favourite</b> and <b>Repeat…</b>, the length and zone, a <b>Purpose</b> card, and the four buttons.',
      hint: 'Why: is the app’s own sentence; Purpose is the plan’s word. Over 90 minutes a grey line adds eating and drinking; strength adds protein.', real: 'Today, Sessions or Plan › a session' },
    { kind: 'try', head: 'What does Z1-Z2 mean for you?', target: 'ses.zonepill',
      text: 'The zone pill ends in a small arrow. Press <b>Z1-Z2 ›</b>.', until: S => S.sheet === 'ses.zone',
      ok: 'A plate opens with the zone as your own figures, from the zones table in your plan, and <b>All your zones ›</b>. Done closes it.', robot: [['act', 'ses.zone']] },
    { kind: 'look', head: 'The Change page', shot: 'ses-08-edit',
      text: '<b>Change</b> opens <b>Change session</b> with Cancel and a green Save: Day, Sport, What you do, Length (minutes), Zone or effort and Purpose, the switch <b>Key session</b>, and at the foot a red <b>Take out of the plan</b>.',
      hint: 'Whatever you change is written to the plan and listed in Settings › Changes to the plan, where Undo brings it back.', real: 'Change' },
    { kind: 'try', head: 'Change the session', target: S => S.sheet !== 'ses.edit' ? 'ses.change' : !S.ses_ed_min || S.ses_ed_min === '30' ? 'ses.edmin' : 'ses.edsave',
      text: 'Press <b>Change</b>. Make the length 40 and press <b>Save</b>.', real: 'Change',
      until: S => S.ses_min === '40' && S.sheet === null, ok: 'Saved: the session reads 40m. What you changed is written to the plan and listed in Settings › Changes to the plan, where Undo brings it back.',
      robot: [['act', 'ses.change'], ['in', 'ses_ed_min', '40'], ['act', 'ses.edsave']] },
    { kind: 'try', head: 'Save with no title', set: { sheet: 'ses.edit', ses_ed_title: '', ses_ed_min: '30' }, target: 'ses.edsave',
      text: 'The title box is empty. Press <b>Save</b>.', until: S => S.ses_ed_tried && S.sheet === 'ses.edit',
      ok: 'A red line asks for a few words first. The button stays green and the plan is not touched.', robot: [['act', 'ses.edsave']] },
    { kind: 'look', head: 'The pool card in the water', shot: 'ses-02-pool-card',
      text: 'On a swim, <b>Pool card</b> shows the set in very large type for the pool side: <b>Whole set</b> at the top left (500 m here), one row for each step, the current step filled in blue, and big <b>Back</b> and <b>Next</b> at the foot. <b>Done</b> is the green button at the top right.',
      hint: 'The screen stays lit while it is open.', real: 'A swim › Pool card' },
    { kind: 'try', head: 'The pool card', target: S => S.screen !== 'ses.pool' ? 'ses.poolbtn' : S.ses_step < 2 ? 'ses.next' : 'ses.pooldone',
      text: 'Press <b>Pool card</b>. Press <b>Next</b> twice, then <b>Done</b>.', real: 'A swim › Pool card',
      until: S => S.ses_pooled && S.screen === 'ses.swim', ok: 'The whole set in big type — 500 m — one step per row, the current one in swim blue. The screen stays lit while it is open.',
      robot: [['act', 'ses.pool'], ['act', 'ses.next'], ['act', 'ses.next'], ['act', 'ses.pooldone']] },
    { kind: 'look', head: 'The last step of the set', shot: 'ses-03-pool-step',
      text: 'On the last step the final row, <b>6 × 50 m smooth</b>, is filled in blue. <b>Back</b> is active now and <b>Next</b> has gone pale, because there is no step after it.',
      hint: 'You can also press a row to jump to it.' },
    { kind: 'try', head: 'Save it as a favourite', target: 'ses.fav',
      text: 'Press <b>Save as favourite</b>.', until: S => S.ses_fav, ok: 'It now reads “In your favourites”. A favourite holds the sport, title, purpose, length and zone — no day. On the New session page it is a tile that fills the form.',
      robot: [['act', 'ses.fav']] },
    { kind: 'look', head: 'Favourites on the New session page', shot: 'ses-11-new-favourites',
      text: 'On the <b>New session</b> page, <b>Your favourites</b> are tiles at the top: the sport mark, the title and the length. Press one and it fills the page; the day stays. A line says you can still change everything before Save.',
      hint: 'Settings › Your plan › Favourite sessions renames, removes and arranges them.', real: 'Plan › New session' },
    { kind: 'look', head: 'Repeat on the New session page', shot: 'ses-10-repeat',
      text: 'The row <b>Repeat</b> reads “Every week until” with a date. Below, a blue line lists the dates (7 sessions), and a grey line says which day is left out because it already holds the same session. One Undo takes them all back.',
      hint: 'On an existing session, Repeat… opens a small page with the same list.' },
    { kind: 'try', head: 'Repeat on more days', target: S => S.sheet !== 'ses.repeat' ? 'ses.repeatbtn' : 'ses.repadd',
      text: 'Press <b>Repeat…</b>. The page lists the dates, and a grey line says which day is left out. Press <b>Add 7 sessions</b>.', real: 'Repeat…',
      until: S => S.ses_added === 7, ok: 'Seven sessions are added in one go. One Undo under Changes to the plan takes them all back, except any you have logged since.',
      robot: [['act', 'ses.repeat'], ['act', 'ses.repadd']] },
    { kind: 'look', head: 'The Move page', shot: 'ses-07-move',
      text: '<b>Move</b> opens a page with the session card, <b>MOVE IT TO</b> with a small <b>+1 day</b>, a date and <b>Move the session</b>, and below <b>OR SWAP IT WITH</b>: sessions still to do, nearest first.',
      hint: 'Until you pick a different day, a grey line says so.', real: 'Move' },
    { kind: 'try', head: 'Move it to tomorrow', target: S => S.sheet !== 'ses.move' ? 'ses.movebtn' : 'ses.plus1',
      text: 'Press <b>Move</b>, then <b>+1 day</b>. Only the date is rewritten.', real: 'Move',
      until: S => S.ses_day === 4, ok: 'The session is on Friday 11 September and keeps its place in the week’s totals. <b>Or swap it with</b> exchanges two days.',
      robot: [['act', 'ses.move'], ['act', 'ses.plus1']] },
    { kind: 'try', head: 'No gym today', set: { screen: 'ses.strength' }, target: S => S.sheet !== 'ses.nogym' ? 'ses.nogym' : 'ses.nogymdone',
      text: 'On a strength session press <b>No-gym version</b>, read the circuit, and press <b>Done</b>.', real: 'Strength › No-gym version',
      hint: 'Also on a strength session: a small Open Workouts link, only when AMS Workout Companion is on the same iPhone. And the protein line.',
      until: S => S.ses_nogym, ok: 'A body-weight circuit sized to the planned length. It changes nothing in your plan: you log the strength session as usual.',
      robot: [['act', 'ses.nogym'], ['act', 'ses.nogymdone']] },
    { kind: 'look', head: 'A done session', shot: 'ses-05-done-run',
      text: 'A done session has the green tick at the top right. Under the <b>Purpose</b> card comes <b>How hard was it?</b> (1 to 10) until you answer, then <b>WHAT YOU DID</b> with a pen, and the figures: 31m Duration, 5.2 km Distance, 142 bpm Heart rate.',
      hint: 'The pen is Adjust logged data (chapter 3).' },
    { kind: 'look', head: 'From your watch', shot: 'ses-06-watch',
      text: 'Further down, <b>FROM YOUR WATCH</b> shows the route as a line on a map, the pulse curve with <b>Average 138 · Highest 156 beats</b>, and <b>Laps</b>: Lap, Distance, Time, Pulse and km/h. Above them sits <b>YOUR NOTES ON THIS SESSION</b>.',
      hint: 'Needs your Garmin key, and only appears when Garmin has the workout. It is shown only; nothing is written back.' },
    { kind: 'look', head: 'Last time', shot: 'ses-12-laps-last-time',
      text: 'At the end, <b>Last time · Thu 3 Sep</b> sets this session beside the last one of the same sport and title: Length 31m ← 27m, Distance 5.2 km ← 4.9 km, Average pulse, How hard. The arrow reads “this session ← last time”.',
      hint: 'This card needs no Garmin key: it uses the plan.' },
    { kind: 'try', head: 'Send it to somebody', set: { screen: 'ses.done' }, target: S => S.sheet !== 'ses.send' ? 'ses.send' : 'ses.sendwhat',
      text: 'Press <b>Send</b>. Choose <b>Send what you did</b>.', real: 'Send, top right',
      until: S => S.ses_sent === 'what you did', ok: 'The share sheet opens with a short text and any photos. On a session still to do you get only <b>Send the whole session</b>.',
      robot: [['act', 'ses.send'], ['act', 'ses.sendit', 'what you did']] },
    { kind: 'check', head: 'What does Move write?', text: 'You move a session from Thursday to Friday. What does the app write to your plan?',
      answers: ['The whole session again, on the new day', 'Only the new date', 'Nothing; it is just a reminder'], right: 1,
      ok: 'Right: only the date. The session keeps its week and sport, so the weekly totals do not change.' },
  ],
});
})();
