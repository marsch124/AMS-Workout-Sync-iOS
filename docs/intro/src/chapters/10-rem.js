/* Chapter 10 — Reminders and away. Settings › Reminders (three reminders, the iOS question, the notice and its buttons, the Sunday card,
   the refused line), the weather switch beside it, and Settings › Away (a trip, what you have there, what Today and the cards say,
   taking the trip away). All state keys start with rem_, screens with rem., actions with rem. */
CHAPTER({
  id: 'rem',
  title: 'Reminders and away',
  icon: 'bell',
  needs: 'Which reminders you want and at what time, and for a trip: the days, and what you will have there (pool, bike, gym, open water).',
  gives: 'A word the evening before, on Sunday and the morning after a missed session; and a plan that knows when you cannot swim, ride or lift. You still decide every change.',
  start: () => ({
    part: 'settings', screen: 'rem.settings',
    rem_ev: false, rem_evt: '20:00', rem_su: false, rem_sut: '18:00', rem_mi: false, rem_mit: '08:00',
    rem_perm: 'unasked', rem_saved: false, rem_tested: false, rem_opened: false, rem_seen: [], rem_card: true, rem_wx: true, rem_wxtouched: false,
    rem_aw_on: false, rem_aw_from: 'Mon 21 Sep', rem_aw_until: 'Wed 23 Sep', rem_aw_pool: false, rem_aw_bike: false, rem_aw_gym: false, rem_aw_ow: false,
    rem_aw_saved: false, rem_aw_gone: false, rem_take: false, rem_keep: false,
  }),
  screens: {
    /* The middle of Settings: Your plan (Suggestions, Away) and the Reminders group with the Weather switch under it. */
    'rem.settings': S => {
      const any = S.rem_saved && (S.rem_ev || S.rem_su || S.rem_mi);
      return `
      <h1 class="k-h1">Settings</h1>
      <span class="k-cap">Your plan</span>
      ${K.nav('Suggestions', 'rem.note', { sub: 'On — the app suggests, you decide' })}
      ${K.nav('Away', 'rem.openaway', { t: 'rem.awayrow', sub: S.rem_aw_saved ? `Until ${S.rem_aw_until} — sessions you cannot do there are marked` : 'Off — for a trip: say what you will have there' })}
      <span class="k-cap">Reminders</span>
      ${K.nav('Reminders', 'rem.open', { t: 'rem.row', sub: any ? 'On — evening, Sunday, missed session' : 'Off — evening, Sunday, missed session' })}
      <span class="k-cap">Weather</span>
      <div class="k-card">${K.switch(S.rem_wx, 'Weather and daylight on Today', 'rem.wx', { t: 'rem.wx' })}
        <span class="k-muted k-small">For an outdoor session: the forecast and when it gets dark. Your place is asked only when Today first needs it, and only a rounded place, about 10 km wide, is sent.</span></div>`; },

    /* Settings › Reminders */
    'rem.page': S => {
      const block = (title, sw, tkey, times, sends, id, label) => `<div class="k-card"><b>${title}</b>
        ${K.switch(S['rem_' + id], 'Switch on', 'rem.sw', { arg: id, t: 'rem.sw.' + id })}
        <div class="k-line ${S['rem_' + id] ? '' : 'rem-off'}"><span class="k-muted">${label}</span>${K.select(tkey, S, times, { t: 'rem.t.' + id })}</div>
        <span class="k-muted k-small">${sends}</span></div>`;
      const n = [S.rem_ev, S.rem_su, S.rem_mi].filter(Boolean).length;
      return `
      <div class="k-top">${K.btn('Cancel', 'rem.cancel', { t: 'rem.cancel' })}<span class="k-sp"></span>${K.btn('Save', 'rem.save', { t: 'rem.save' })}</div>
      <h1 class="k-h1">Reminders</h1>
      ${K.hero({ cap: 'REMINDERS', title: n + ' switched on', lines: ['On this iPhone only'], t: 'rem.head' })}
      ${S.rem_perm === 'refused' ? `<div class="k-card" data-t="rem.refused"><span>Notifications are switched off for this app in iOS, so no reminder can appear. Nothing else is affected.</span>
        ${K.btn('Open iOS settings', 'rem.ios', { t: 'rem.ios' })}</div>` : ''}
      ${block('Evening reminder', 0, 'rem_evt', ['19:00', '20:00', '21:00', '22:00'], 'Tomorrow’s session in one line, like “Tomorrow: Run · 45 min easy”. Tapping it opens Today.', 'ev', 'Sent at')}
      ${block('Sunday card', 0, 'rem_sut', ['17:00', '18:00', '19:00', '20:00'], 'On Sunday evening: “Next week: 7 sessions · 8h 40m”. From then until Monday morning Today shows next week day by day, with a Close button.', 'su', 'Sent at')}
      ${block('Missed session', 0, 'rem_mit', ['07:00', '08:00', '09:00', '10:00'], 'The morning after a planned session that is neither logged nor marked missed: “Yesterday’s Run was not logged.” with Skip it, Move to today (when your plan allows it) and It is done. Each one is your own tap.', 'mi', 'Asked at')}
      ${K.btn('Send a test now', 'rem.test', { main: true, t: 'rem.test' })}
      <span class="k-muted k-small">Nothing is sent while the stop sign or an illness is on. These switches belong to this iPhone: your other devices have their own. Reminders are worked out on the device from your plan; nothing goes through a server.</span>`; },

    /* What a notice looks like when it arrives. rem_note: 'evening' | 'missed' | 'test' */
    'rem.notice': S => `
      <h1 class="k-h1">A notice arrives</h1>
      <div class="k-card rem-notice"><span class="k-cap">Triathlon</span><b>${S.rem_note === 'missed' ? 'Training' : 'Training'}</b>
        <span>${S.rem_note === 'missed' ? 'Yesterday’s Run was not logged.' : S.rem_note === 'test' ? 'This is a test. Your reminders will look like this.' : 'Tomorrow: Run · 45 min easy'}</span></div>
      ${S.rem_note === 'missed' ? `<div class="k-col">
        ${K.btn('Skip it', 'rem.answer', { arg: 'skip', t: 'rem.a.skip' })}
        ${K.btn('Move to today', 'rem.answer', { arg: 'move', t: 'rem.a.move' })}
        ${K.btn('It is done', 'rem.answer', { arg: 'done', t: 'rem.a.done' })}</div>
        <span class="k-muted k-small">${S.rem_seen.includes('skip') ? 'Skip it: the session is marked missed, as with the Missed button. ' : ''}${S.rem_seen.includes('move') ? 'Move to today: the session moves to today, as with the Move button. ' : ''}${S.rem_seen.includes('done') ? 'It is done: the app opens that session with its log form.' : ''}</span>` : `<span class="k-muted k-small">Tapping it opens Today.</span>`}`,

    /* Today on the Sunday evening: the card for next week */
    'rem.sunday': S => `
      <h1 class="k-h1">Today</h1>
      ${S.rem_card ? `<div class="rem-sun" data-t="rem.card">
        <div class="rem-sunhead"><span class="rem-sunrow"><b>NEXT WEEK</b><button class="rem-close" data-act="rem.close" data-t="rem.close">Close</button></span>
          <span class="rem-sunrow"><span class="rem-bigfig">4</span><b>sessions</b><span class="rem-bigfig rem-fig2">2h 45m</span></span><b>Build</b></div>
        <div class="rem-sunbody">
          ${[['Mon', 'swim', 'Endurance swim', '40m'], ['Tue', 'run', 'Easy run + 4x20 s strides', '35m'], ['Thu', 'bike', 'Easy ride', '1h'], ['Sat', 'strength', 'Strength', '30m']].map(r => `<span class="k-line"><b class="rem-day">${r[0]}</b>${K.sport(r[1])}<span class="k-col rem-words"><b>${r[2]}</b><span class="k-muted k-small">${r[3]}</span></span></span>`).join('')}</div></div>` : `<p class="k-muted">The card is put away until next Sunday.</p>`}
      <div class="k-card"><b>This week</b><span class="k-muted">1h 16m of 3h 40m</span>${K.bar(35)}</div>`,

    /* Settings › Away */
    'rem.away': S => {
      const miss = [['pool', 'pool'], ['bike', 'bike'], ['gym', 'gym'], ['ow', 'open water']].filter(x => !S['rem_aw_' + x[0]]).map(x => 'no ' + x[1]).join(', ');
      const shown = S.rem_aw_on ? 'Away until ' + S.rem_aw_until : 'Not away';
      const sub = S.rem_aw_on ? (miss ? miss[0].toUpperCase() + miss.slice(1) : 'You have everything there') : 'Switch it on for a trip, and say what you will have there';
      return `
      <div class="k-top">${K.btn('Cancel', 'rem.awcancel', { t: 'rem.awcancel' })}<span class="k-sp"></span>${K.btn('Save', 'rem.awsave', { t: 'rem.awsave' })}</div>
      <h1 class="k-h1">Away</h1>
      ${K.hero({ cap: 'AWAY', title: shown, lines: [sub], t: 'rem.awhead' })}
      <div class="k-card">${K.switch(S.rem_aw_on, 'I am away', 'rem.awsw', { t: 'rem.awsw' })}
        <div class="k-field ${S.rem_aw_on ? '' : 'rem-off'}"><label for="in-rem_aw_from">From</label>${K.select('rem_aw_from', S, ['Mon 21 Sep', 'Tue 22 Sep'], { t: 'rem.awfrom' })}</div>
        <div class="k-field ${S.rem_aw_on ? '' : 'rem-off'}"><label for="in-rem_aw_until">Until</label>${K.select('rem_aw_until', S, ['Tue 22 Sep', 'Wed 23 Sep', 'Sun 27 Sep'], { t: 'rem.awuntil' })}</div>
        <span class="k-muted k-small">Until is your last day away. Sessions you cannot do there get a grey note, and the app may suggest a swap; nothing in your plan changes until you tap Take it.</span></div>
      <div class="k-card ${S.rem_aw_on ? '' : 'rem-off'}"><span class="k-cap rem-slate">What I have there</span>
        ${K.switch(S.rem_aw_pool, 'Pool', 'rem.awhas', { arg: 'pool', t: 'rem.awhas.pool' })}
        ${K.switch(S.rem_aw_bike, 'Bike (or turbo)', 'rem.awhas', { arg: 'bike', t: 'rem.awhas.bike' })}
        ${K.switch(S.rem_aw_gym, 'Gym', 'rem.awhas', { arg: 'gym', t: 'rem.awhas.gym' })}
        ${K.switch(S.rem_aw_ow, 'Open water', 'rem.awhas', { arg: 'ow', t: 'rem.awhas.ow' })}
        <span class="k-muted k-small">Switch on only what you will really have. Everything left off counts as missing.</span></div>`; },

    /* Today on Monday 21 September, inside the trip (no pool, no gym) */
    'rem.todayaway': S => `
      <h1 class="k-h1">Today</h1>
      <button class="rem-line" data-act="rem.awayline" data-t="rem.awline">Away until Wed 23 Sep · no pool, no gym, no open water</button>
      <div class="k-card"><span class="k-line">${K.sport('swim')}<span class="k-col rem-words"><span class="k-sportword k-sp-swim">Swim</span><b>Endurance swim</b>
        <span class="k-line">${K.chip('40m')}${K.chip('Z2')}${K.chip('No pool while away', { t: 'rem.chip' })}</span></span></span></div>
      ${S.rem_take ? `<div class="k-card" data-t="rem.cardtaken"><span class="k-line"><b>Changed —</b><span class="k-link">Undo</span></span><span class="k-muted k-small">Mon swim: no pool while away ${icon('right')} easy run 40 min (swim moves to Thu)</span></div>`
        : S.rem_keep ? `<p class="k-muted k-small" data-t="rem.cardkept">The card is gone and nothing in your plan changed. Settings › Suggestions keeps your answer, Kept my plan.</p>`
        : `<div class="k-card" data-t="rem.sugg"><b>Mon swim: no pool while away ${icon('right')} easy run 40 min (swim moves to Thu)</b>
        <span class="k-muted k-small">Why: you are away until 23 Sep without a pool; an easy run keeps the day aerobic.</span>
        <div class="k-line">${K.btn('Take it', 'rem.take', { t: 'rem.take' })}${K.btn('Keep my plan', 'rem.keep', { t: 'rem.keep' })}</div>
        <span class="k-link rem-other">Other choice</span></div>`}
      <div class="k-card"><span class="k-line">${K.sport('strength')}<span class="k-col rem-words"><span class="k-sportword k-sp-strength">Strength</span><b>Strength</b>
        <span class="k-line">${K.chip('30m')}${K.chip('No gym while away', { t: 'rem.chipgym' })}</span></span></span></div>`,
  },
  sheets: {
    /* iOS's own question, asked when the first reminder is switched on */
    'rem.ask': S => `<h3>Allow notifications?</h3>
      <p class="k-muted">This is iOS asking, not the app: may Triathlon send you notices?</p>
      <div class="k-foot">${K.btn('Don’t Allow', 'rem.deny', { t: 'rem.deny' })}${K.btn('Allow', 'rem.allow', { main: true, t: 'rem.allow' })}</div>`,
  },
  actions: {
    'rem.note'() { toast('Suggestions has its own chapter.'); },
    'rem.open'(arg, S) { S.screen = 'rem.page'; },
    'rem.cancel'(arg, S) { S.screen = 'rem.settings'; },
    'rem.sw'(arg, S) {
      const k = 'rem_' + arg;
      S[k] = !S[k];
      if (S[k] && S.rem_perm === 'unasked') S.sheet = 'rem.ask';
    },
    'rem.allow'(arg, S) { S.rem_perm = 'ok'; S.sheet = null; },
    'rem.deny'(arg, S) { S.rem_perm = 'refused'; S.sheet = null; },
    'rem.save'(arg, S) { S.rem_saved = true; S.screen = 'rem.settings'; toast('Saved. The Settings row says what is on.'); },
    'rem.test'(arg, S) { S.rem_tested = true; if (S.rem_perm === 'unasked') { S.sheet = 'rem.ask'; } else { toast('A test notice arrives: “This is a test. Your reminders will look like this.”'); } },
    'rem.ios'(arg, S) { S.rem_opened = true; toast('iOS Settings opens on this app. Switch Notifications on there.'); },
    'rem.answer'(arg, S) { if (!S.rem_seen.includes(arg)) S.rem_seen.push(arg); },
    'rem.close'(arg, S) { S.rem_card = false; },
    'rem.wx'(arg, S) { S.rem_wx = !S.rem_wx; S.rem_wxtouched = true; },
    'rem.openaway'(arg, S) { S.screen = 'rem.away'; },
    'rem.awcancel'(arg, S) { S.screen = 'rem.settings'; },
    'rem.awsw'(arg, S) { S.rem_aw_on = !S.rem_aw_on; },
    'rem.awhas'(arg, S) { const k = 'rem_aw_' + arg; S[k] = !S[k]; },
    'rem.awsave'(arg, S) {
      if (S.rem_aw_on) { S.rem_aw_saved = true; S.rem_aw_gone = false; toast('Saved. Away is on and follows you to your other devices.'); }
      else if (S.rem_aw_saved) { S.rem_aw_saved = false; S.rem_aw_gone = true; toast('The trip is taken away.'); }
      S.screen = 'rem.settings';
    },
    'rem.awayline'() { toast('This opens the Away page.'); },
    'rem.take'(arg, S) { S.rem_take = true; },
    'rem.keep'(arg, S) { S.rem_keep = true; },
  },
  steps: [
    { kind: 'look', head: 'Two ways the app looks after you', target: 'rem.row', real: 'Settings › Reminders, Settings › Away',
      text: 'Reminders can tell you about tomorrow, about next week and about a session you forgot to log. Away tells the plan you are on a trip. Both are in Settings, and both are off until you switch them on.' },
    { kind: 'try', head: 'Open Reminders', text: 'Press <b>Reminders</b>.', target: 'rem.row',
      until: S => S.screen === 'rem.page', ok: 'The page is open. At the top is a slate card that counts the switches that are on, and says it is for this iPhone only.', robot: [['act', 'rem.open']] },
    { kind: 'look', head: 'Three reminders', shot: 'rem-01-reminders',
      text: 'There are three: <b>Evening reminder</b>, <b>Sunday card</b> and <b>Missed session</b>. Each has its switch, its time and a line that says what it sends. At the top, the slate card counts the switches that are on, for this iPhone only.',
      hint: 'They start at 20:00, 18:00 and 08:00. The green button sends a test at once.' },
    { kind: 'try', head: 'Switch one on and let iOS ask', set: { screen: 'rem.page' },
      text: 'Switch on <b>Evening reminder</b>. The first switch you turn on makes iOS ask whether the app may send notices. Press <b>Allow</b>.',
      target: S => S.sheet ? 'rem.allow' : 'rem.sw.ev',
      until: S => S.rem_ev && S.rem_perm === 'ok', ok: 'iOS has your answer. The time can be changed now; before, it was greyed.', robot: [['act', 'rem.sw', 'ev'], ['act', 'rem.allow']] },
    { kind: 'try', head: 'Choose when it comes', set: { screen: 'rem.page', rem_ev: true, rem_perm: 'ok' },
      text: 'Choose <b>21:00</b> for the evening reminder.', target: 'rem.t.ev',
      until: S => S.rem_evt === '21:00', ok: 'It now arrives at 21:00, with tomorrow’s session in one line.', robot: [['in', 'rem_evt', '21:00']] },
    { kind: 'look', head: 'What the evening notice says', set: { screen: 'rem.notice', rem_note: 'evening' },
      text: 'The title is <b>Training</b> and the line is tomorrow’s session: sport, length and how hard. Two sessions read “Tomorrow: Swim 40 min · Strength 30 min”; a rest day reads “Tomorrow: rest day”. Seven evenings are laid ahead.' },
    { kind: 'try', head: 'The missed-session question', set: { screen: 'rem.notice', rem_note: 'missed' }, target: S => ['skip', 'move', 'done'].filter(a => !S.rem_seen.includes(a)).map(a => 'rem.a.' + a)[0] || 'rem.a.skip',
      text: 'The morning after a session you neither logged nor marked missed, this comes. Press <b>Skip it</b>, <b>Move to today</b> and <b>It is done</b>, one after the other.',
      hint: 'Move to today is left out when your plan does not allow it. Up to three sessions are asked each morning.',
      until: S => ['skip', 'move', 'done'].every(a => S.rem_seen.includes(a)), ok: 'Each button is your own tap: skip marks it missed, move brings it to today, done opens the session with its log form.',
      robot: [['act', 'rem.answer', 'skip'], ['act', 'rem.answer', 'move'], ['act', 'rem.answer', 'done']] },
    { kind: 'try', head: 'The Sunday card on Today', set: { part: 'today', screen: 'rem.sunday' }, target: 'rem.close',
      text: 'The Sunday reminder says “Next week: 7 sessions · 8h 40m”. From then until Monday morning Today shows next week day by day in a blue card. Press <b>Close</b> to put it away.',
      until: S => !S.rem_card, ok: 'The card is put away until next Sunday. It shows only while the Sunday switch is on.', robot: [['act', 'rem.close']] },
    { kind: 'look', head: 'When iOS has said no', shot: 'rem-02-refused',
      text: 'If you told iOS no, or notices are switched off for the app, a calm line at the top says so: no reminder can appear, nothing else is affected. Its button <b>Open iOS settings</b> takes you to this app’s page there.' },
    { kind: 'try', head: 'Test it, then save', set: { screen: 'rem.page', rem_ev: true, rem_su: true, rem_perm: 'ok' }, target: S => S.rem_tested ? 'rem.save' : 'rem.test',
      text: 'Press <b>Send a test now</b>: a notice arrives at once, so you see how they look. Then press <b>Save</b>. Cancel would leave everything as it was.',
      until: S => S.rem_tested && S.rem_saved, ok: 'Saved. The Settings row now says On, and Today shows the Sunday card on Sundays.', robot: [['act', 'rem.test'], ['act', 'rem.save']] },
    { kind: 'try', head: 'The weather switch', set: { screen: 'rem.settings' }, target: 'rem.wx',
      text: 'Under Reminders is <b>Weather and daylight on Today</b>, on from the start. For an outdoor session Today shows the forecast and when it gets dark. Switch it off.',
      hint: 'Your place is asked once, when Today first needs it, and only a rounded place, about 10 km wide, is sent.',
      until: S => !S.rem_wx, ok: 'Today shows no weather line now. Like the reminders, this switch belongs to this device.', robot: [['act', 'rem.wx']] },
    { kind: 'look', head: 'The Away page', shot: 'rem-03-away-page', real: 'Settings › Your plan › Away',
      text: 'The slate card says <b>Away until</b> and what you lack there (here no pool, no gym). Under it: the switch <b>I am away</b>, <b>From</b> and <b>Until</b> (your last day away), and four switches for what you have: Pool, Bike (or turbo), Gym and Open water.',
      hint: 'There is also a small Away button at the top of Settings › Suggestions.' },
    { kind: 'try', head: 'Tell the app you are away', set: { screen: 'rem.settings' }, text: 'Press <b>Away</b>. Switch on <b>I am away</b>, then say what you will have there: switch on <b>Bike (or turbo)</b>. Then press <b>Save</b>.',
      target: S => S.screen === 'rem.settings' ? 'rem.awayrow' : !S.rem_aw_on ? 'rem.awsw' : !S.rem_aw_bike ? 'rem.awhas.bike' : 'rem.awsave',
      hint: 'Left off counts as missing: here no pool, no gym, no open water.',
      until: S => S.rem_aw_saved && S.rem_aw_bike, ok: 'The Away row now says Until Wed 23 Sep. The trip is kept for all your devices, and nothing in your plan has changed.',
      robot: [['act', 'rem.openaway'], ['act', 'rem.awsw'], ['act', 'rem.awhas', 'bike'], ['act', 'rem.awsave']] },
    { kind: 'look', head: 'Today while away', shot: 'rem-05-today-away',
      text: 'Under the heading one grey line says <b>Away until</b> and what is missing; press it to open the page. Below, the app has a suggestion for a swim you cannot do: an easy run instead. Further down, a session you cannot do carries a grey note such as <b>No pool while away</b>.' },
    { kind: 'try', head: 'A suggestion, and you decide', set: { part: 'today', screen: 'rem.todayaway' }, target: 'rem.take',
      text: 'The app may suggest what to do with a session you cannot do: an easy swap, a later day or rest. Nothing changes until you press <b>Take it</b>. <b>Keep my plan</b> is an answer too. Press <b>Take it</b>.',
      until: S => S.rem_take, ok: 'The plan has changed, and says so. Undo is there until the end of the day. The easy week and the limits still apply: some trips give a note and no card.', robot: [['act', 'rem.take']] },
    { kind: 'look', head: 'Strength without a gym', shot: 'rem-06-nogym',
      text: 'A strength session without a gym gets the grey note and no card, because there is nothing to swap. Its own page has a button <b>No-gym version</b>: a circuit with no equipment, shown here. It changes nothing in your plan. “A session’s page” teaches it.' },
    { kind: 'try', head: 'Take the trip away', set: { screen: 'rem.away', rem_aw_on: true, rem_aw_saved: true, rem_aw_bike: true }, target: S => S.rem_aw_on ? 'rem.awsw' : 'rem.awsave',
      text: 'Back home? Open the Away page, switch <b>I am away</b> off and press <b>Save</b>.',
      until: S => S.rem_aw_gone, ok: 'The trip is gone from every device. The notes and the grey line go with it.', robot: [['act', 'rem.awsw'], ['act', 'rem.awsave']] },
    { kind: 'check', head: 'A trip with no pool', text: 'You set Away for Monday to Wednesday and leave Pool and Open water off. What changes in your plan?',
      answers: ['The Monday swim is swapped for an easy run', 'Nothing, until you press Take it on a card', 'Every swim in those days is moved to Thursday'], right: 1,
      ok: 'Right. The swim gets a grey note, and the app may offer a swap. Only your Take it changes the plan.' },
    { kind: 'check', head: 'What follows you', text: 'You set both on your iPhone: the evening reminder at 21:00 and an Away trip. What do your iPad and Mac have?',
      answers: ['Both', 'The reminder only', 'The Away trip only: each device has its own reminders'], right: 2,
      ok: 'Right. Reminders and the weather switch belong to one device. Away travels with you.' },
  ],
});
