/* Chapter 14 — Where your plan lives. The plan lives in the app (moved in from Excel), iCloud keeps every device in step
   (Settings › iCloud, the dot, the page an iPad shows before the plan has arrived), what follows him and what is per device,
   the spreadsheet copies, and Settings › Safety copies. Every word is the app's own (SettingsView, MoveInView, ICloudPage,
   WaitingForPlanView, SyncStatus, SafetyCopiesView). Figures are invented. */
const HOM_ROWS = [['Plan days', 13], ['Training sessions', 11], ['Rest days', 2], ['Done', 0], ['Missed', 0], ['Still to come', 3], ['Extra workouts', 1], ['Planned minutes', 280], ['Recorded minutes', 0]];
const HOM_DOT = { off: ['ring', 'iCloud is off'], working: ['needs', 'On its way'], same: ['ok', 'Same on all devices'] };
CHAPTER({
  id: 'hom',
  title: 'Where your plan lives',
  icon: 'cloud',
  needs: 'Nothing to set up once the plan has moved in. An iPad or a Mac needs you signed in to iCloud.',
  gives: 'One plan, in this app, the same on your iPhone, iPad and Mac, with copies you can put back.',
  start: () => ({ part: 'settings', screen: 'hom.settings', hom_lives: false, hom_taken: false, hom_cloud: 'working', hom_wait: 'working',
    hom_stay: false, hom_ask: '', hom_back: false, hom_line: '' }),
  screens: {
    /* Settings › Your plan, on the iPhone. */
    'hom.settings': S => `
      <h1 class="k-h1">Settings</h1>
      <span class="k-cap">Your plan</span>
      <div class="k-card"><b>iCloud</b>${K.mark(...HOM_DOT[S.hom_cloud === 'same' ? 'same' : 'off'])}</div>
      ${S.hom_lives ? `
        <div class="k-card"><b>Lives in this app</b><span class="k-muted k-small">since 16 Sep 2026 · 11 training sessions · 2 rest days · 1 extra workouts</span></div>
        ${K.nav('Safety copies', 'hom.safety', { sub: '2 days, newest 15 Sep', t: 'hom.safety' })}
        <div class="k-card"><b>Spreadsheet copy</b><span class="k-muted k-small">none yet — the first is made with the next change</span></div>
        <div class="k-card"><b>Go back to Excel</b><span class="k-muted k-small">Possible until 7 Oct 2026. Writes the plan as it is now into the Excel file in Dropbox.</span>
          <div>${K.btn('Go back to Excel', 'hom.goback', { danger: true, t: 'hom.goback' })}</div></div>`
      : `<div class="k-card"><b>Move the plan into this app</b><span class="k-muted k-small">Now the plan lives in the Excel file in Dropbox.</span>
          <div>${K.btn('Start', 'hom.start', { t: 'hom.start' })}</div></div>`}`,
    /* The page The plan moves in. */
    'hom.movein': S => S.hom_lives ? `
      <b class="hom-title">The plan moves in</b>
      <b class="k-oktext">Done. The plan lives in this app now.</b>
      <span class="k-muted k-small">Logging, moving and changing sessions now happen here. Nothing is written into your Excel file any more.</span>
      <span class="k-muted k-small">Your Excel file stays in Dropbox, untouched. For three weeks Settings › Go back to Excel can return to it.</span>
      <button class="k-btn k-main k-full" data-act="hom.done" data-t="hom.done"><span>Done</span></button>`
    : `
      <div class="k-top">${K.btn('Cancel', 'hom.cancel', { quiet: true })}<b class="hom-title">The plan moves in</b><span class="k-sp"></span></div>
      ${!S.hom_taken ? `<div class="k-col k-muted k-small" style="gap:3px"><span>Now the plan lives in the Excel file in Dropbox. Here it moves into this app.</span>
          <span>1 · The app takes in the Excel file and counts both sides.</span><span>2 · You look at the counts.</span>
          <span>3 · You tap Make this app the plan’s home. Until then nothing is saved.</span></div>
        <button class="k-btn k-main k-full" data-act="hom.take" data-t="hom.take"><span>Take the plan in and count</span></button>`
      : `<span class="k-cap">Excel and the app, side by side</span>
        <div class="k-card" data-t="hom.proof"><div class="hom-two"><span></span><span class="hom-head">Excel</span><span class="hom-head">App</span><span></span>
          ${HOM_ROWS.map(([l, n]) => `<span class="k-small"><b>${esc(l)}</b></span><span class="k-small k-muted">${num(n)}</span><span class="k-small k-muted">${num(n)}</span><span class="hom-same">same</span>`).join('')}</div></div>
        <b class="k-oktext">Everything matches.</b>
        <button class="k-btn k-main k-full" data-act="hom.home" data-t="hom.home"><span>Make this app the plan’s home</span></button>
        <span class="k-muted k-small">Your Excel file is not changed. You can go back for three weeks.</span>`}`,
    /* Settings › iCloud. */
    'hom.icloud': S => `
      ${K.back('Settings', 'hom.back')}
      <b class="hom-title">iCloud</b>
      <div class="k-line" data-t="hom.dot">${K.mark(...HOM_DOT[S.hom_cloud])}</div>
      <span class="k-muted k-small">${S.hom_cloud === 'same' ? 'Last met iCloud 07:12.' : 'Your plan is on its way between your devices.'}</span>
      <button class="k-btn k-main k-full" data-act="hom.sync" data-t="hom.sync"><span>Sync now</span></button>
      <span class="k-cap">Your devices</span>
      <div class="k-card"><span class="k-small"><b>iPhone · this one</b> · last seen 07:12 · 2.8 (84)</span><span class="k-small"><b>iPad</b> · last seen 07:10 · 2.8 (84)</span></div>
      <span class="k-cap">What is shared</span>
      <span class="k-muted k-small">The plan, everything you log and change, and your morning and how-hard answers are the same on your iPhone, iPad and Mac. Apple Health numbers come from your iPhone. The Training calendar and Dropbox stay on your iPhone.</span>`,
    /* The page an iPad or a Mac shows before the plan has arrived (it stands in for Today). */
    'hom.waiting': S => `
      <div class="hom-center">${icon('plan')}<b style="font-size:20px">Your training plan</b>
        <div class="k-card hom-wait" data-t="hom.waitcard">${S.hom_wait === 'ready' ? K.mark('ok', 'Plan from your iPhone · 11 sessions · last change 07:12') : K.mark('needs', 'Bringing your plan from iCloud…')}</div>
        <span class="k-muted k-small">${S.hom_wait === 'ready' ? 'Opening it now.' : 'Your iPhone, iPad and Mac show the same plan once it is here. Nothing needs choosing on this iPad.'}</span></div>`,
    /* Settings › Safety copies. */
    'hom.safety': S => `
      ${K.back('Settings', 'hom.back')}
      <b class="hom-title">Safety copies</b>
      <span class="k-muted k-small">The plan as it was at the start of each day it changed, kept for 30 days. Put one back if the plan went wrong.</span>
      ${S.hom_line ? `<b class="k-oktext k-small">${esc(S.hom_line)}</b>` : ''}
      ${[['2026-09-15', 'Tue 15 Sep 2026', '11 sessions · 2 done · 1 change so far'], ['2026-09-14', 'Mon 14 Sep 2026', '11 sessions · 1 done · 4 changes so far']].map(([id, t, s]) => `
        <div class="k-card"><b class="k-small">${t}</b><span class="k-muted k-small">${s}</span>
          <div>${K.btn('Put this copy back', 'hom.put', { arg: id, danger: true, t: 'hom.put:' + id })}</div></div>`).join('')}`,
    /* What follows him, what is per device (spec W.1, D.14). */
    'hom.table': S => `
      <h1 class="k-h1">Which device</h1>
      <div class="k-card"><b class="k-oktext">Follows you between devices</b><ul class="hom-list k-small">
        <li>The plan, and everything you log and change</li><li>Your morning and how-hard answers</li><li>Favourite sessions, Away, shoes and bikes, the race page</li><li>The notes beside a log</li></ul></div>
      <div class="k-card"><b>Stays on each device</b><ul class="hom-list k-small">
        <li>Photographs, safety copies, spreadsheet copies</li><li>Reminders and their times, the weather switch</li><li>The Garmin key and the last Garmin answers</li><li>Your weeks with Claude, your last questions, the Claude key and its cost</li></ul></div>
      <div class="k-card" data-t="hom.iphone"><b>On the iPhone only</b><ul class="hom-list k-small">
        <li>Dropbox and the copy in Dropbox</li><li>The Training calendar (it shows in Calendar on your iPad and Mac)</li><li>Apple Health (its numbers arrive on the others, from iPhone)</li><li>Go back to Excel</li></ul></div>`,
  },
  sheets: {
    'hom.goback': S => `<h3>Go back to Excel?</h3>
      <div class="k-foot">${K.btn('Stay in the app', 'hom.stay', { main: true, t: 'hom.stay' })}${K.btn('Go back', 'hom.back-excel', { danger: true })}</div>`,
    'hom.confirm': S => `<h3>Put this copy back?</h3>
      <span>The plan goes back to how it was in this copy: its days, words and lengths, and which sessions are in it — on all your devices. What you logged since then stays. The plan as it is now is kept aside first.</span>
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Put it back', 'hom.confirmput', { danger: true, t: 'hom.confirmput' })}</div>`,
  },
  actions: {
    'hom.back'() { toast('Settings has its own chapter.'); },
    'hom.cancel'() { toast('Cancel leaves the page; nothing is saved.'); },
    'hom.start'(a, S) { S.screen = 'hom.movein'; },
    'hom.take'(a, S) { S.hom_taken = true; },
    'hom.home'(a, S) { S.hom_lives = true; },
    'hom.done'(a, S) { S.screen = 'hom.settings'; },
    'hom.safety'(a, S) { S.screen = 'hom.safety'; },
    'hom.goback'(a, S) { S.sheet = 'hom.goback'; },
    'hom.stay'(a, S) { S.sheet = null; S.hom_stay = true; },
    'hom.back-excel'() { toast('Going back has its own care; here you can only stay.'); },
    'hom.sync'(a, S) { S.hom_cloud = 'same'; },
    'hom.put'(a, S) { S.hom_ask = a; S.sheet = 'hom.confirm'; },
    'hom.confirmput'(a, S) {
      S.sheet = null; S.hom_back = true;
      S.hom_line = S.hom_ask === '2026-09-14' ? 'The plan is back as it was at the start of Mon 14 Sep.' : 'The plan is back as it was at the start of Tue 15 Sep.';
    },
  },
  steps: [
    { kind: 'look', head: 'Your plan lives in this app', shot: 'set-01-top',
      text: 'Under Settings › Your plan you see <b>Lives in this app</b>: since when, and how much it holds. Below it <b>Safety copies</b> and <b>Spreadsheet copy</b>; a copy is also saved every week in Files. On the iPhone, with Dropbox connected, <b>Copy in Dropbox</b> keeps one beside your Excel file.',
      hint: 'A spreadsheet copy never changes after it is made. Only the iPhone writes the copy in Dropbox.', real: 'Settings › Your plan' },
    { kind: 'look', head: 'Safety copies', shot: 'hom-05-safety',
      text: 'Settings › Safety copies: the plan as it was at the start of each day it changed, kept for 30 days. Each day has a row with its counts and a red <b>Put this copy back</b>, as in this picture. Before the first change the page says <b>No safety copies yet.</b>',
      hint: 'Here: Tue 15 Sep 2026 and Mon 14 Sep 2026, each with how many sessions, how many done and how many changes so far.', real: 'Settings › Safety copies' },
    { kind: 'try', head: 'Put a safety copy back', text: 'Press <b>Put this copy back</b> under Mon 14 Sep, read the question, then press <b>Put it back</b>.',
      set: { screen: 'hom.safety', hom_lives: true }, target: S => S.sheet ? 'hom.confirmput' : 'hom.put:2026-09-14', until: S => S.hom_back,
      ok: 'A green line says the plan is back as it was at the start of that day. The plan as it was is kept aside first. On a plan only one device has, everything logged since the copy is taken out; on a shared plan what you logged stays.',
      robot: [['act', 'hom.put', '2026-09-14'], ['act', 'hom.confirmput']], real: 'Settings › Safety copies' },
    { kind: 'look', head: 'iCloud keeps every device in step', shot: 'hom-01-icloud-page',
      text: 'Settings › iCloud. The dot always has its words: grey <b>iCloud is off</b>, amber <b>On its way</b>, green <b>Same on all devices</b>, red with the problem in words. Below: your devices, what is shared, and the copy from before iCloud.',
      hint: 'In this picture the plan has not moved into the app yet, so only your morning answers are shared. With iCloud signed out the dot is grey and there is no Sync now.', real: 'Settings › iCloud' },
    { kind: 'try', head: 'Meet iCloud now', text: 'The plan is on its way. Press <b>Sync now</b>.', set: { screen: 'hom.icloud', hom_cloud: 'working' }, target: 'hom.sync',
      until: S => S.hom_cloud === 'same', ok: 'The dot turns green: Same on all devices, and Last met iCloud shows the time. The app also meets iCloud by itself when you open it, after each change and every half minute while it is open.',
      robot: [['act', 'hom.sync']], real: 'Settings › iCloud' },
    { kind: 'look', head: 'Settings on the iPad and the Mac', shot: 'set-94-pad', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'The same Settings in the wide look, the side list on the left. Under <b>Your plan</b> the second row names the plan\u2019s home; in this picture iCloud is off. An iPad or a Mac that has no plan yet shows <b>Not on this iPad yet</b> there: "Your plan arrives from iCloud by itself. Today says what it is waiting for."',
      hint: 'At the foot of the side list the same dot stands with its words.', real: 'Settings › Your plan' },
    { kind: 'look', head: 'What the waiting page says', shot: 'hom-02-waiting', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'Until the plan arrives, Today is one card with a dot and a line, here amber: <b>Your plan lives on your iPhone. Open Triathlon there once \u2014 it puts the plan in iCloud.</b> Other lines: Bringing your plan from iCloud\u2026; sign in to iCloud; move the plan in from Excel; Update Triathlon on this device.',
      hint: 'Under the card: Nothing needs choosing on this iPad.' },
    { kind: 'look', head: 'The plan has arrived', shot: 'hom-03-waiting-ready', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'The same page with a green dot: <b>Plan from your iPhone</b>, and under it <b>Opening it now.</b> The page then opens as Today by itself. At the foot of the side list the dot with its words stays.' },
    { kind: 'look', head: 'What follows you, what stays', set: { screen: 'hom.table' }, target: 'hom.iphone',
      text: 'The plan and your answers go through your own iCloud to every device. Notes beside the plan, such as favourites and the race page, follow you too. Photographs, copies, reminders and the Claude key stay on one device. Dropbox, the calendar and Apple Health belong to the iPhone.',
      hint: 'iCloud is used only for this app’s own folder; nobody else can see it.' },
    { kind: 'try', head: 'Go back to Excel, and stay', text: 'For three weeks after the move, while Dropbox is connected and no iPad or Mac uses the plan, you can return it to Excel. The red button <b>Go back to Excel</b> asks first. Press it, then press <b>Stay in the app</b>.',
      set: { screen: 'hom.settings', hom_lives: true }, target: S => S.sheet ? 'hom.stay' : 'hom.goback', until: S => S.hom_stay,
      ok: 'Nothing changed. Once your iPad or Mac uses the plan too, the button goes and a grey line says a spreadsheet copy is the way out.',
      robot: [['act', 'hom.goback'], ['act', 'hom.stay']], real: 'Settings › Your plan', only: 'iPhone' },
    { kind: 'look', head: 'Behind you: how the plan moved in', set: { screen: 'hom.settings', hom_lives: false }, target: 'hom.start',
      text: 'Before the move an iPhone showed <b>Move the plan into this app</b> with a small <b>Start</b>. Yours is past it, so you will not see this row again. The next steps show what the move was, in case you meet it on another phone.',
      hint: 'Your Excel file was never changed.', real: 'Settings \u203a Your plan', only: 'iPhone' },
    { kind: 'try', head: 'Start moving the plan in', text: 'Press <b>Start</b>.', target: 'hom.start', until: S => S.screen === 'hom.movein',
      ok: 'The page The plan moves in opens. Until you finish it, nothing is saved.', robot: [['act', 'hom.start']], real: 'Settings › Your plan', only: 'iPhone' },
    { kind: 'try', head: 'Count both sides', text: 'Press <b>Take the plan in and count</b>. The app reads the Excel file and counts the plan twice: as Excel has it, and as the app holds it.',
      set: { screen: 'hom.movein' }, target: 'hom.take', until: S => S.hom_taken,
      ok: 'The counts stand side by side, each with the green word same. If one figure differed, a red line would say Something differs — nothing was changed, and the button below would not show.',
      robot: [['act', 'hom.take']], only: 'iPhone' },
    { kind: 'look', head: 'The proof, as the app shows it', shot: 'hom-04-movein',
      text: 'The page The plan moves in, with Cancel at the top left. A table puts <b>Excel</b> and <b>App</b> side by side for plan days, training sessions, rest days, done, missed and more, each with the green word <b>same</b>. <b>Everything matches.</b> stands under it, then <b>Month by month</b>.',
      hint: 'The big green button, Make this app the plan’s home, is the one step that moves the plan.', only: 'iPhone' },
    { kind: 'try', head: 'Make the app the plan’s home', text: 'The page says <b>Everything matches.</b> Press <b>Make this app the plan’s home</b>.',
      set: { screen: 'hom.movein', hom_taken: true }, target: 'hom.home', until: S => S.hom_lives,
      ok: 'Done. The plan lives in this app now. Logging and changing happen here; nothing is written into Excel any more.',
      robot: [['act', 'hom.home']], only: 'iPhone' },
    { kind: 'check', head: 'Your iPad uses the plan too', text: 'You want to press Go back to Excel on your iPhone. What do you find?',
      answers: ['The red button, for three weeks', 'No button: a grey line says a spreadsheet copy is the way out', 'The button, but only on the Mac'], right: 1,
      ok: 'Right: Your iPad or Mac uses this plan too — a spreadsheet copy is the way out. Going back would leave the iPad or Mac with a plan nobody writes any more.' },
  ],
});
