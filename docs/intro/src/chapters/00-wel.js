/* Chapter 0 — Welcome. It is also the worked example for whoever writes a chapter: a real picture, the pretend iPhone,
   a page opened from another page, the pretend iPad, and a check question. More kinds of moves (typing, choosing, a sheet,
   drag to arrange) are in src/example/99-exa.js. */
CHAPTER({
  id: 'wel',                                   // three small letters; the prefix of every state key, data-t, action and css class
  title: 'Welcome',                            // the name in the chapter rail, at most four words
  icon: 'triathlon',                           // a name from ICON (src/icons.js)
  needs: 'About half an hour, in one go or in pieces. Your place is kept on this device.',
  gives: 'You know where every part of the app is, on the iPhone, the iPad and the Mac.',
  // Where every step of this chapter starts from. Plain data only (text, numbers, true/false, lists, objects) — no functions.
  start: () => ({ device: 'phone', part: 'today', screen: 'wel.today', wel_seen: [], wel_open: false }),
  screens: {
    /* The top of Today, as the real app shows it on the invented plan's Wednesday 16 September. */
    'wel.today': S => `
      <h1 class="k-h1">Today</h1>
      <div class="k-card"><b>This week</b>
        <span class="k-muted">1h 16m of 3h 40m</span>${K.bar(35)}</div>
      <button class="k-card wel-ses" data-act="wel.open" data-t="wel.ses">
        <span class="k-line">${K.sport('run')}<span class="k-col wel-words"><span class="k-sportword k-sp-run">Run</span>
          <b>Easy run + 4x20 s strides</b>
          <span class="k-muted k-small">Why: easy aerobic — builds your base without costing much.</span>
          <span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span></span></span></button>
      <span class="k-muted k-small">10° · feels 6° · breezy 5 m/s · rain likely 15–16</span>`,
    /* A session's own page, opened from Today: the page keeps Today's green, and a back arrow leads back. */
    'wel.session': S => `
      ${K.back('Today', 'wel.back', { t: 'wel.back' })}
      <span class="k-line">${K.sport('run', { size: 40 })}<span class="k-col wel-words"><span class="k-sportword k-sp-run">Run</span>
        <span class="k-muted">Wednesday 16 September</span></span></span>
      <b class="wel-title">Easy run + 4x20 s strides</b>
      <span class="k-muted k-small">Why: easy aerobic — builds your base without costing much.</span>
      <span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span>
      <div class="k-card"><span class="k-cap">Purpose</span><span>Turnover</span></div>
      <div class="k-line">${K.btn('Done · 35m', 'wel.note', { main: true, icon: 'check' })}${K.btn('Log details', 'wel.note')}${K.btn('Move', 'wel.note')}</div>`,
    /* The same app on the iPad and the Mac: a side list instead of the five tabs, with one more page — Plan. */
    'wel.wide': S => `
      <h1 class="k-h1">Today</h1>
      <div class="k-cols">
        <div class="k-card"><span class="k-line">${K.sport('run')}<span class="k-col"><span class="k-sportword k-sp-run">Run</span>
          <b>Easy run + 4x20 s strides</b><span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span></span></span></div>
        <div class="k-card"><b>This week</b><span class="k-muted">1h 16m of 3h 40m</span>${K.bar(35)}</div>
      </div>
      <p class="k-muted">${S.wel_seen.includes('plan') ? 'Plan has its own chapter: the week, the month and the year on one page.' : 'On the left: the side list.'}</p>`,
  },
  // actions[name](arg, S, element): change S, nothing else. The page is drawn again afterwards and "until" is asked.
  actions: {
    'wel.open'(arg, S) { S.screen = 'wel.session'; S.wel_open = true; },
    'wel.back'(arg, S) { S.screen = 'wel.today'; },
    'wel.note'() { toast('Logging has its own chapter.'); },
    // A press on a tab (iPhone) or in the side list (iPad): here the chapter wants to count them. Without these two, a friendly note shows.
    tab(arg, S) { S.part = arg; if (!S.wel_seen.includes(arg)) S.wel_seen.push(arg); S.screen = arg === 'today' ? 'wel.today' : 'wel.other'; },
    side(arg, S) { if (!S.wel_seen.includes(arg)) S.wel_seen.push(arg); },
  },
  steps: [
    { kind: 'look', head: 'Your training, one app', shot: 'wel-01-today',
      text: 'AMS Triathlon Training holds your whole plan up to race day: what to do today, what you did, how your body is doing, and how the season is going. This is the real app, with an invented plan.',
      hint: 'Pictures like this one show the real app. Everywhere else you practise on a copy that you can press.' },
    { kind: 'look', head: 'The practice copy', target: 'wel.ses',
      text: 'This is the practice iPhone. It opens on <b>Today</b>, with today’s session on a card. A yellow ring shows what a step is about.',
      real: 'the app opens on Today' },
    { kind: 'try', head: 'Five tabs along the bottom', text: 'Press <b>Sessions</b>, <b>Body</b>, <b>Progress</b> and <b>Settings</b>, one after the other. Each has its own colour.',
      target: S => ['sessions', 'body', 'progress', 'settings'].filter(p => !S.wel_seen.includes(p)).map(p => 'tab.' + p)[0] || 'tab.today',
      until: S => ['sessions', 'body', 'progress', 'settings'].every(p => S.wel_seen.includes(p)),
      ok: 'Today is green, Sessions blue, Body raspberry, Progress purple, Settings slate grey.',
      robot: [['act', 'tab', 'sessions'], ['act', 'tab', 'body'], ['act', 'tab', 'progress'], ['act', 'tab', 'settings']] },
    { kind: 'try', head: 'Open today’s session', text: 'Press the card <b>Easy run + 4x20 s strides</b>.', target: 'wel.ses',
      until: S => S.wel_open, ok: 'The session’s own page is open. The arrow at the top left leads back to Today.', robot: [['act', 'wel.open']] },
    { kind: 'look', head: 'iPad and Mac: a side list', set: { device: 'pad', screen: 'wel.wide' }, target: 'side.plan', only: 'iPad and Mac',
      text: 'On the iPad and the Mac the five tabs become a list on the left, and there is one more page: <b>Plan</b>, with the week, the month and the year.',
      hint: 'The plan and what you did are the same on every device: they travel through iCloud.' },
    { kind: 'try', head: 'Find the Plan page', set: { device: 'pad', screen: 'wel.wide' }, target: 'side.plan', only: 'iPad and Mac',
      text: 'Press <b>Plan</b> in the side list.', until: S => S.wel_seen.includes('plan'), ok: 'Plan is the page the iPhone does not have.', robot: [['act', 'side', 'plan']] },
    { kind: 'look', head: 'Today on a real iPad', shot: 'tod-90-pad', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'The real app on an iPad. On the left the side list: Today, Plan, Sessions, Body, Progress, Settings, and at its foot <b>Keys</b>. The page beside it is the same Today as on the iPhone, only wider.' },
    { kind: 'check', head: 'Where is the Plan page?', text: 'You want to see the whole month on one page. Where do you look?',
      answers: ['On the iPhone, in a sixth tab', 'On the iPad or the Mac, in the side list', 'Only on paper, after printing'], right: 1,
      ok: 'Right. The iPhone has five tabs; Plan is on the iPad and the Mac.' },
  ],
});
SCREENS['wel.other'] = S => `<h1 class="k-h1">${esc(partName(S.part))}</h1><p class="k-muted">This part has its own chapter. Press the next tab.</p>`;
