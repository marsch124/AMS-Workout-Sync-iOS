/* Chapter 15 — Settings and the guide. Settings from top to bottom as 2.9 has it (spec D.16), How this works with "Signs in this app",
   What's new and the version, Favourites settings (arranging by drag), and what the system can do with the app (Siri, Spotlight; D.12).
   Every word is the app's own (SettingsView, Guide, FavouritesSettingsView, AppIntents, SystemWords). Figures are invented. */
const SET_ROWS = {
  icloud: ['iCloud', 'iCloud is off', 'Whether the plan is the same on all your devices, and the page to meet iCloud now.', 'Where your plan lives'],
  lives: ['Lives in this app', 'since 16 Sep 2026 · 11 training sessions · 2 rest days', 'Says the plan lives here, not in Excel.', 'Where your plan lives'],
  safety: ['Safety copies', '2 days, newest 15 Sep', 'The plan as it was at the start of each day it changed, kept for 30 days, with a way to put one back.', 'Where your plan lives'],
  sheet: ['Spreadsheet copy', 'last 16 Sep', 'A spreadsheet of the plan to keep or send; the app also saves one every week.', 'Where your plan lives'],
  thursday: ['Thursday rides', 'One easy ride every Thursday, from next Monday to your race', 'It adds one easy ride on every Thursday, from next Monday up to your race, and the page says which.', ''],
  favs: ['Favourite sessions', '3 kept — fill the New session page in one tap', 'The sessions you saved, in your order, arranged by drag; Save as favourite is on a session\u2019s page.', 'A session\u2019s page, and this chapter'],
  changes: ['Changes to the plan', '4 so far', 'Every change to the plan, each with its Undo.', 'Sessions, and The Plan page'],
  suggest: ['Suggestions', 'On — the app suggests, you decide', 'The rule book’s suggestions on Today, on or off.', 'Suggestions and Not well?'],
  away: ['Away', 'Off — for a trip: say what you will have there', 'Tell the app about a trip, so sessions you cannot do there are marked.', 'Reminders and away'],
  race: ['Race', 'Your plan for the day, fuel and kit list', 'Your race page.', 'Race day, shoes and bikes'],
  gear: ['Shoes and bikes', 'Kilometres on each, counted from your logged sessions', 'The kilometres on each pair and bike.', 'Race day, shoes and bikes'],
  photos: ['0 photos · 0.0 MB', 'On this phone only, and in the iPhone’s own backup. Not in iCloud, not in Dropbox.', 'The photographs kept with sessions: Save all writes them into one zip, Bring in a zip takes one back.', 'Logging a session'],
  health: ['Apple Health', 'Let the app read your workouts, heart rate and distances, and the log form can fill itself from what your Garmin sent to Health. Optional.', 'Lets the log form fill itself from Health. Read only, never written.', 'Garmin and Health'],
  garmin: ['Garmin · not connected', 'Overnight HRV, sleep, Body Battery and stress from your Garmin watch', 'Your own key, and the Garmin numbers on Today and Body.', 'Garmin and Health'],
  claude: ['Claude', 'Off · lets Claude choose among the suggestions, and shares your plan as text', 'Optional, needs your own key.', 'Claude'],
  neighbours: ['Today’s session is shared', 'This app also tells Deck Mate and PARAGON today’s session: its sport, length and whether it is done, and this week’s hours. Nothing else. Deck Mate may log today’s session as done, only as planned, and only when you press its key.', 'What your two neighbour apps, Deck Mate and PARAGON, are told: today’s session and this week’s hours, on this device. Nothing else.', 'Today'],
  reminders: ['Reminders', 'Off — evening, Sunday, missed session', 'Three notices made on your phone.', 'Reminders and away'],
  weather: ['Weather and daylight on Today', 'For an outdoor session: the forecast and when it gets dark. Your place is asked only when Today first needs it, and only a rounded place, about 10 km wide, is sent.', 'A switch for the grey weather line on Today. Only a rounded place is sent for it.', 'Today'],
  calendar: ['Not in your calendar', 'Put every session from today onwards into a Training calendar at 06:00.', 'iPhone only: it puts your sessions into a Training calendar at 06:00, each as long as it is planned, and keeps them right when sessions move.', ''],
  dropbox: ['Not connected', 'Only needed for going back to Excel.', 'iPhone only: the link to the Excel file in Dropbox.', 'Where your plan lives'],
};
const SET_GROUPS = {
  'set.l1': [['Your plan', ['icloud', 'lives', 'safety', 'sheet', 'thursday', 'favs', 'changes', 'suggest', 'away']]],
  'set.l2': [['Race and kit', ['race', 'gear']], ['Photos', ['photos']], ['Apple Health', ['health']], ['Garmin', ['garmin']], ['Claude', ['claude']]],
  'set.l3': [['Your two neighbour apps', ['neighbours']], ['Reminders', ['reminders']], ['Weather', ['weather']], ['Calendar', ['calendar']], ['Dropbox', ['dropbox']]],
};
const SET_SIGNS = {
  tick: 'Green tick: done, and nothing else.',
  red: 'Red: missed, taken away, or a warning.',
  moon: 'Moon: a rest day.',
  dot: 'Green dot, Same on all devices: the plan here is the same as on your other devices. It is a dot, not a tick: the green tick still means done and nothing else. The dot always comes with its words.',
  blue: 'Blue: changing the plan — Move (with +1 day to put it on tomorrow), Change, + Session.',
  main: 'Full green button: the main step on that screen.',
};
const SET_FAVS = [
  { id: 'f1', sport: 'bike', what: 'Aerobic ride, steady Z2', sub: '1h 00m · Z2 · Bike' },
  { id: 'f2', sport: 'run', what: 'Easy run', sub: '40m · Z1–Z2 · Run' },
  { id: 'f3', sport: 'swim', what: 'Drills and 6 x 200', sub: '45m · Z2 · Swim' }];
const SET_FOUND = [
  ['Wed 16 Sep · Run · 35 min', 'Easy run + 4x20 s strides · To do'], ['Sat 19 Sep · Bike · 1 h 5 min', 'Steady aerobic ride · To do'],
  ['Sun 20 Sep · Run · 40 min', 'Easy run, flat route · To do'], ['Mon 14 Sep · Swim · 35 min', 'Technique: 8x50 drills + 6x100 easy · Done']];
const SET_PHRASES = [['What’s my session today in Triathlon', 'Today: Run, 35 min.'], ['What’s my session tomorrow in Triathlon', 'Tomorrow is a rest day.'],
  ['Log today’s run as done in Triathlon', 'Logged: Run · 35 min'], ['How is my week in Triathlon', 'This week: 1 h 16 min done of 3 h 40 min planned.']];

CHAPTER({
  id: 'set',
  title: 'Settings and the guide',
  icon: 'strength',
  needs: 'Nothing. Settings is where every part of the app keeps its switches and lists.',
  gives: 'You know what each Settings row is for, where to read the guide and the version, and what Siri and Spotlight can do.',
  start: () => ({ part: 'settings', screen: 'set.l1', set_pick: '', set_seen: [], set_favs: structuredClone(SET_FAVS), set_rm: '', set_q: '', set_said: '' }),
  screens: {
    /* A part of the Settings list. Pressing a row says what is behind it. */
    'set.l1': S => setList(S, 'set.l1', true), 'set.l2': S => setList(S, 'set.l2', false), 'set.l3': S => setList(S, 'set.l3', false),
    'set.guide': S => `
      ${K.back('Settings', 'set.back')}
      <b class="set-title">How this works</b>
      <p class="set-part">What this app is</p>
      <p class="set-line k-small">This app is called AMS Triathlon Training; under its icon on the home screen it reads Triathlon. It used to be called Workout Sync. It is the same app with the same data, and there is nothing to set up again.</p>
      <p class="set-part">Where the plan lives</p>
      <p class="set-part">The same plan on all your devices</p>
      <p class="set-part">Notes that travel beside the plan</p>
      <p class="set-part">Today</p>
      <span class="k-muted k-small">One long page: each part has a green heading and the page ends with</span>
      <p class="set-part" data-t="set.signsh">Signs in this app</p>`,
    'set.signs': S => `
      ${K.back('Settings', 'set.back')}
      <p class="set-part">Signs in this app</p>
      <b class="k-small">Six of the signs</b>
      <span class="k-small k-muted">Press each sign to read its one meaning.</span>
      <button class="set-sign ${S.set_seen.includes('tick') ? 'set-on' : ''}" data-act="set.sign" data-arg="tick" data-t="set.sign:tick"><span>${K.done()}</span><span class="k-small">The white tick in a green circle</span></button>
      <button class="set-sign ${S.set_seen.includes('red') ? 'set-on' : ''}" data-act="set.sign" data-arg="red" data-t="set.sign:red"><span class="set-red">Missed</span><span class="k-small">Red</span></button>
      <button class="set-sign ${S.set_seen.includes('moon') ? 'set-on' : ''}" data-act="set.sign" data-arg="moon" data-t="set.sign:moon"><span>${K.sport('rest')}</span><span class="k-small">The moon</span></button>
      <button class="set-sign ${S.set_seen.includes('dot') ? 'set-on' : ''}" data-act="set.sign" data-arg="dot" data-t="set.sign:dot"><span>${K.mark('ok')}</span><span class="k-small">The dot of the iCloud line</span></button>
      <button class="set-sign ${S.set_seen.includes('blue') ? 'set-on' : ''}" data-act="set.sign" data-arg="blue" data-t="set.sign:blue"><span class="set-moveword">Move</span><span class="k-small">Blue words and outline</span></button>
      <button class="set-sign ${S.set_seen.includes('main') ? 'set-on' : ''}" data-act="set.sign" data-arg="main" data-t="set.sign:main"><span class="set-mainword">Done</span><span class="k-small">The full green button</span></button>
      ${S.set_said ? `<div class="k-card"><span class="k-small">${esc(SET_SIGNS[S.set_said])}</span></div>` : ''}
      <span class="k-muted k-small">${S.set_seen.length} of 6 read</span>`,
    'set.new': S => `
      ${K.back('Settings', 'set.back')}
      <b class="set-title">What’s new</b>
      <div class="k-card"><b>2.9 (85)</b><span class="k-muted k-small">26 November 2026</span>
        <b class="k-small">Body gets the Garmin Board’s missing cards: training load, fitness, gym sessions, workouts this month, sleep debt, weight, energy and water</b>
        <span class="k-small">Body · New: a part Training under the tiles. Now: under the tiles a small heading Training with four cards, in the look of the tiles. Where: Body, under the tiles.</span>
        <span class="k-small">Body · New: Sleep debt. Now: the 7 nights against what you need, seven slim bars each with a thin grey outline behind it for that night’s need, and a page with each night. Shown only: sleep never leads to a suggestion, and it is never red.</span></div>
      <div class="k-card"><b>2.8 (84)</b><span class="k-muted k-small">25 November 2026</span>
        <b class="k-small">Forty-one things you picked: Body in more depth, reminders, away mode, a race page, notes beside a log, Garmin on a done session, and Claude on your week</b>
        <span class="k-small">Today and reminders · New: Week so far. A card above Tomorrow: for each sport of the plan this week, the time done of the time planned (1h 20m of 2h 30m) with a slim bar. Done is the sport’s full colour, the rest pale.</span>
        <span class="k-small">Body · New: Share. A raspberry button near the foot of Body turns the page into one picture, in the look you see now, and hands it to the share sheet. It leaves the app only if you choose a place there.</span></div>
      <span class="k-muted k-small">Every version stays on this page, newest first.</span>`,
    /* Settings › Favourite sessions. */
    'set.fav': S => `
      <div class="k-top">${K.btn('Done', 'set.done', { quiet: true })}<b class="set-title">Favourite sessions</b><span class="k-sp"></span></div>
      <div class="set-blue"><b style="font-size:19px">${S.set_favs.length === 1 ? '1 favourite' : S.set_favs.length + ' favourites'}</b><span class="k-small">Kept for the New session page, and on all your devices.</span></div>
      <div class="k-card">${S.set_favs.map((f, i) => `<div class="k-dragrow set-fav" data-drag="set_favs" data-i="${i}">
        <button class="k-grip" data-grip aria-label="Drag to arrange" data-t="set.grip:${f.id}">${icon('grip')}</button>
        ${K.sport(f.sport, { size: 26 })}
        <span class="set-favw"><b class="k-small">${esc(f.what)}</b><span class="k-muted k-small">${esc(f.sub)}</span>
          <span class="set-btns">${K.btn('Rename', 'set.rename', { t: 'set.rename:' + f.id })}${K.btn('Remove', 'set.remove', { arg: f.id, danger: true, t: 'set.remove:' + f.id })}</span></span></div>`).join('')}</div>
      <span class="k-muted k-small">Drag the three lines to put your favourites in order. The first is shown first on the New session page.</span>`,
    /* What the system can do with the app. */
    'set.system': S => `
      <h1 class="k-h1">Siri and Spotlight</h1>
      <span class="k-cap">Siri</span>
      <div class="k-col" style="gap:5px">${SET_PHRASES.map((p, i) => `<button class="k-btn set-say" data-act="set.say" data-arg="${i}" data-t="set.say:${i}"><span>${esc(p[0])}</span></button>`).join('')}</div>
      ${S.set_said ? `<div class="k-card"><span class="k-cap">Siri says</span><b class="k-small">${esc(S.set_said)}</b></div>` : ''}
      <span class="k-cap">Spotlight</span>
      ${K.input('set_q', S, { ph: 'Search', t: 'set.search' })}
      ${S.set_q.trim().length > 1 ? SET_FOUND.filter(r => (r[0] + ' ' + r[1]).toLowerCase().includes(S.set_q.trim().toLowerCase()))
        .map((r, i) => `<button class="set-res" data-act="set.open" data-t="set.res:${i}"><b class="k-small">${esc(r[0])}</b><span class="k-muted k-small">${esc(r[1])}</span></button>`).join('') || '<span class="k-muted k-small">No session found.</span>' : '<span class="k-muted k-small">Type a sport, a weekday or a word of a title.</span>'}`,
  },
  sheets: {
    'set.removeq': S => `<h3>Remove this favourite?</h3><span>Sessions already in your plan stay as they are.</span>
      <div class="k-foot">${K.btn('Keep it', 'sheet.close')}${K.btn('Remove', 'set.removeok', { danger: true, t: 'set.removeok' })}</div>`,
  },
  actions: {
    'set.back'() { toast('Settings has its own page; here the ring shows the way.'); },
    'set.pick'(a, S) { S.set_pick = a; },
    'set.guide'(a, S) { S.screen = 'set.guide'; },
    'set.new'(a, S) { S.screen = 'set.new'; },
    'set.sign'(a, S) { S.set_said = a; if (!S.set_seen.includes(a)) S.set_seen.push(a); },
    'set.done'() { toast('Done closes the page. Escape does the same on a Mac.'); },
    'set.rename'() { toast('Rename asks for a new name, then Save or Cancel.'); },
    'set.remove'(a, S) { S.set_rm = a; S.sheet = 'set.removeq'; },
    'set.removeok'(a, S) { S.set_favs = S.set_favs.filter(f => f.id !== S.set_rm); S.sheet = null; },
    'set.say'(a, S) { S.set_said = SET_PHRASES[Number(a)][1]; },
    'set.open'() { toast('A tap opens that session.'); },
  },
  steps: [
    { kind: 'look', head: 'Settings, from the top', shot: 'set-01-top',
      text: 'The first group is <b>Your plan</b>: <b>iCloud</b> with its dot, <b>Lives in this app</b>, <b>Safety copies</b>, <b>Spreadsheet copy</b> with <b>Save a copy now</b>, <b>Copy in Dropbox</b> and <b>Thursday rides</b>. Each row says in a line what is behind it.',
      hint: 'Where your plan lives teaches the first five.', real: 'Settings, the last tab on the bar' },
    { kind: 'try', head: 'Press a row to learn what it is', text: 'Press <b>Safety copies</b>. Under the list, a card says what is behind the row and which chapter teaches it.',
      set: { screen: 'set.l1' }, target: 'set.row:safety', until: S => S.set_pick === 'safety',
      ok: 'The plan as it was at the start of each day it changed, kept for 30 days. Where your plan lives teaches it.', robot: [['act', 'set.pick', 'safety']] },
    { kind: 'look', head: 'Changes, suggestions, away, zones', shot: 'set-02-middle',
      text: 'Further down: <b>Changes to the plan</b>, <b>Suggestions</b> and <b>Away</b>, then a grey line about going back to Excel, <b>Your zones</b> and <b>Colours and shapes</b>, the key to the week card, also one tap away on Today.',
      hint: 'Taught in Sessions and The Plan page; Suggestions and Not well?; Reminders and away; Tests, zones and steadiness; Today.' },
    { kind: 'look', head: 'Race, photos, Health, Garmin', shot: 'set-03-lower',
      text: '<b>Race</b> and <b>Shoes and bikes</b>, then <b>Photos</b>: on this phone only, with <b>Save all</b> and <b>Bring in a zip</b>. Then <b>Apple Health</b> with <b>Connect</b>, and <b>Garmin</b>. Extra workouts sit between the zones and Race.',
      hint: 'Taught in Race day, shoes and bikes; Logging a session; Garmin and Health.' },
    { kind: 'try', head: 'Garmin, Claude and the rest', text: 'Press the row <b>Claude</b>.', set: { screen: 'set.l2' }, target: 'set.row:claude', until: S => S.set_pick === 'claude',
      ok: 'Optional, and it needs your own key. Its own chapter teaches it. Garmin has one too, and Apple Health follows it.', robot: [['act', 'set.pick', 'claude']] },
    { kind: 'look', head: 'The foot of Settings', shot: 'set-06-foot',
      text: 'Below Claude: <b>Your two neighbour apps</b>, <b>Reminders</b>, <b>Weather</b>, <b>Calendar</b> and <b>Dropbox</b> (the last two are on the iPhone only). Then <b>This app</b>, with <b>How this works</b> and <b>What’s new</b>; What’s new reads the version under its name, here AMS Triathlon Training 2.9 (85).',
      hint: 'On an iPad and a Mac the word Keys at the foot of the side list shows every key.', real: 'Settings, at the foot' },
    { kind: 'try', head: 'Open How this works', text: 'Press <b>How this works</b>.', set: { screen: 'set.l3' }, target: 'set.row:guide', until: S => S.screen === 'set.guide',
      ok: 'One long page. Each part has a green heading; the last part is Signs in this app.', robot: [['act', 'set.guide']] },
    { kind: 'try', head: 'Read six signs', text: 'Press each of the six signs: the tick, red, the moon, the dot, blue and the green button.',
      set: { screen: 'set.signs' }, target: S => ['tick', 'red', 'moon', 'dot', 'blue', 'main'].filter(x => !S.set_seen.includes(x)).map(x => 'set.sign:' + x)[0] || 'set.sign:tick',
      until: S => S.set_seen.length === 6, ok: 'Each sign means one thing in the whole app. The tick means done and nothing else; the dot of the iCloud line always has its words beside it.',
      robot: [['act', 'set.sign', 'tick'], ['act', 'set.sign', 'red'], ['act', 'set.sign', 'moon'], ['act', 'set.sign', 'dot'], ['act', 'set.sign', 'blue'], ['act', 'set.sign', 'main']],
      real: 'How this works › Signs in this app' },
    { kind: 'try', head: 'See what is new', text: 'Press <b>What’s new</b>. Every version stands there, newest first.', set: { screen: 'set.l3' }, target: 'set.row:new', until: S => S.screen === 'set.new',
      ok: 'The entry 2.9 (85), 26 November 2026, says every new, changed and fixed thing, in plain words.', robot: [['act', 'set.new']] },
    { kind: 'look', head: 'Your favourite sessions', shot: 'set-04-favourites',
      text: 'Settings \u203a Your plan \u203a Favourite sessions. A blue card counts them (here 3 favourites, kept for the New session page and on all your devices). Each row has three lines at the left, the session\u2019s mark, its name, length, zone and sport, and the small buttons <b>Rename</b> and <b>Remove</b>.',
      hint: 'Done is at the top left.', real: 'Settings \u203a Your plan \u203a Favourite sessions' },
    { kind: 'try', head: 'Arrange your favourites', text: 'Put your finger on the three lines at the left of <b>Drills and 6 x 200</b>, drag up over the first row and let go.',
      hint: 'Arranging is always drag and drop.', set: { screen: 'set.fav' }, target: 'set.grip:f3', until: S => S.set_favs[0].id === 'f3',
      ok: 'The first favourite is shown first on the New session page. The order follows you to your other devices.', robot: [['drag', 'set_favs', 2, 0]], real: 'Settings › Your plan › Favourite sessions' },
    { kind: 'try', head: 'Remove a favourite', text: 'Press <b>Remove</b> under <b>Easy run</b>, then <b>Remove</b> again to confirm. <b>Keep it</b> would leave it.',
      set: { screen: 'set.fav' }, target: S => S.sheet ? 'set.removeok' : 'set.remove:f2', until: S => !S.set_favs.some(f => f.id === 'f2'),
      ok: 'The favourite is gone. Sessions already in your plan stay as they are.', robot: [['act', 'set.remove', 'f2'], ['act', 'set.removeok']] },
    { kind: 'try', head: 'Siri and Spotlight', text: 'Press <b>How is my week in Triathlon</b>, then type <b>run</b> in the search field. Which phrases and results show depends on your device, and Siri needs the phone unlocked.',
      set: { screen: 'set.system' }, target: S => !S.set_said ? 'set.say:3' : 'set.search', until: S => S.set_said !== '' && S.set_q.toLowerCase().includes('run'),
      ok: 'Siri answers in one sentence. Spotlight lists sessions of the next 14 days still to do and of the last 14 days done; a tap opens that session. Both are made on your device and changed by nothing you say.',
      robot: [['act', 'set.say', 3], ['in', 'set_q', 'run']], real: 'Siri and Spotlight, outside the app' },
    { kind: 'check', head: 'Log today’s run by voice', text: 'You say <b>Log today’s run as done in Triathlon</b>. When does it log anything?',
      answers: ['Even with the phone locked, for every run today', 'Phone unlocked, and exactly one run today that is still open and has a length', 'Only on an iPad'], right: 1,
      ok: 'Right. With none, two, one already done or missed, or no length, it logs nothing, changes nothing and says why.' },
  ],
});
function setList(S, id, withHead) {
  const picked = S.set_pick ? SET_ROWS[S.set_pick] : null;
  const row = key => {
    const r = SET_ROWS[key];
    if (key === 'weather') return `<div class="k-card"><b class="k-small">${esc(r[0])}</b><span class="k-muted k-small">${esc(r[1])}</span></div>`;
    return K.nav(r[0], 'set.pick', { arg: key, sub: r[1], t: 'set.row:' + key });
  };
  const extra = id === 'set.l3' ? `<span class="k-cap">This app</span>${K.nav('How this works', 'set.guide', { sub: 'The week strip, logging, syncing and what keeps your plan safe', t: 'set.row:guide' })}
      ${K.nav('What’s new', 'set.new', { sub: 'AMS Triathlon Training 2.9 (85)', t: 'set.row:new' })}` : '';
  return `${withHead ? '<h1 class="k-h1">Settings</h1>' : ''}
    ${picked ? `<div class="k-band k-ok" data-t="set.card">${icon('info')}<span class="k-small"><b>${esc(picked[0])}</b> — ${esc(picked[2])} ${picked[3] ? 'Taught in: ' + esc(picked[3]) + '.' : ''}</span></div>` : ''}
    ${SET_GROUPS[id].map(([g, keys]) => `<span class="k-cap">${esc(g)}</span>${keys.map(row).join('')}`).join('')}${extra}`;
}
