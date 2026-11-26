/* Chapter 13 — Garmin and Health. Where the numbers come from: Settings › Garmin (the key), the morning numbers on Today and their plate,
   Apple Health (iPhone), the Training calendar the iPhone writes, and the two neighbour apps. Taught only as far as the screens say it:
   Garmin's real answers could not be proven before the release. Words from GarminSettingsView, MorningNumbersView, SettingsView,
   SessionView, Neighbours, TodayView. All figures are invented. */

/* A row in Settings: the title, a grey line, at most one small button on the right. */
function garRow(title, sub, o = {}) {
  return `<div class="gar-row${o.t ? ' gar-press' : ''}"${o.act ? ` data-act="${o.act}"` : ''}${o.t ? ` data-t="${o.t}"` : ''}>
    <span class="k-col gar-words"><b>${esc(title)}</b><span class="k-muted k-small">${esc(sub)}</span></span>
    ${o.btn ? `<button class="k-btn ${o.danger ? 'k-danger' : 'k-out'} gar-small" data-act="${o.btn[1]}" data-t="${o.btn[2] || ''}">${esc(o.btn[0])}</button>` : ''}
    ${o.chev ? icon('right') : ''}</div>`;
}

/* The Garmin line on Today: names grey, figures bold, a bracket on HRV and Resting. */
function garLine() {
  return `<span class="gar-line"><span class="k-muted">HRV </span><b>64</b> <span class="k-oktext">(+3)</span><span class="k-muted"> · Sleep </span><b>7h 20m</b><span class="k-muted"> · Resting </span><b>47</b> <span class="k-oktext">(−2)</span><span class="k-muted"> · Body Battery </span><b>71</b></span>`;
}

/* One card on the plate: the name first and the figure right beside it, the normal under it. */
function garCard(name, fig, brk, under) {
  return `<div class="k-card gar-card"><span class="k-line gar-fig"><span class="k-muted">${name}</span><b>${fig}</b>${brk ? `<span class="k-oktext">${brk}</span>` : ''}</span>
    <span class="k-muted k-small">${under}</span></div>`;
}

CHAPTER({
  id: 'gar',
  title: 'Garmin and Health',
  icon: 'watch',
  needs: 'For the Garmin numbers: a personal key made once in your Garmin Connect account. Apple Health and the calendar each ask iOS for permission.',
  gives: 'You know where each number comes from, what the app reads and when, and what it never does with them: they are shown, they never change your plan.',
  start: () => ({ device: 'phone', part: 'settings', screen: 'gar.settings', gar_saved: false, gar_key: '', gar_tried: false, gar_problem: '',
    gar_removed: false, gar_health: 'off', gar_cal: false, gar_allday: false, gar_low: false, gar_logged: false, gar_plate: false }),
  screens: {
    /* Settings, as far as this chapter needs it: Apple Health, Garmin, and (scrolled down) Calendar. */
    'gar.settings': S => S.gar_low ? `
      <h1 class="k-h1">Settings</h1>
      <span class="k-cap">Calendar</span>
      ${S.gar_cal ? `${garRow('96 sessions and rest days in your Training calendar', 'Updated just now · from today to the end of the plan', { btn: ['Take them out', 'gar.caloff', 'gar.caloff'], danger: true })}
        <div class="k-card"><div class="k-line">${K.seg([['time', 'At a time'], ['all', 'All day']], S.gar_allday ? 'all' : 'time', 'gar.kind', 'gar.kind')}</div>
          ${S.gar_allday ? '' : `<span class="k-line k-small"><span>The day’s first session starts at</span><span class="k-fig">06:00</span></span>`}</div>
        <span class="k-muted k-small">${S.gar_allday
          ? 'Every session from today to the end of the plan, as an all-day event on its day — the heading carries the sport and its length. The Training calendar is the app’s own: from today onwards it holds the plan and nothing else, and Take them out removes the calendar.'
          : 'Every session from today to the end of the plan, each as long as it is planned, one after the other on a day with two; a rest day is an all-day event. Six in the morning stays six in the morning wherever the phone is. The Training calendar is the app’s own: from today onwards it holds the plan and nothing else, and Take them out removes the calendar.'}</span>`
      : garRow('Not in your calendar', 'Put every session from today onwards into a Training calendar at 06:00, each as long as it is planned, and keep them right when sessions move.', { btn: ['Put them in', 'gar.calon', 'gar.calon'] })}` : `
      <h1 class="k-h1">Settings</h1>
      <span class="k-cap">Apple Health</span>
      ${S.gar_health === 'on'
        ? `${garRow('In use', 'The log form offers the day’s workouts from Health to fill the boxes. Health is only read, never written.', { btn: ['Stop', 'gar.healthoff', 'gar.healthoff'], danger: true })}
           <span class="k-muted k-small">Stop means the app never asks Health for anything again. To also take the permission away, open the Health app → your picture → Apps → Triathlon.</span>`
        : S.gar_health === 'stopped'
        ? garRow('Not in use', 'The app does not read Health. The permission may still be granted in the Health app.', { btn: ['Use again', 'gar.healthon', 'gar.healthagain'] })
        : garRow('Not connected', 'Let the app read your workouts, heart rate and distances, and the log form can fill itself from what your Garmin sent to Health. Optional.', { btn: ['Connect', 'gar.healthon', 'gar.healthon'] })}
      <span class="k-cap">Garmin</span>
      ${garRow(S.gar_saved ? 'Garmin · connected' : 'Garmin · not connected',
        S.gar_saved ? 'Today and Body show your Garmin numbers' : 'Overnight HRV, sleep, Body Battery and stress from your Garmin watch', { act: 'gar.open', t: 'gar.row', chev: true })}`,
    /* The Garmin page. */
    'gar.page': S => `
      ${K.back('Settings', 'gar.back', { t: 'gar.back' })}
      <b class="gar-title">Garmin</b>
      ${S.gar_saved ? `
        <div class="k-card"><b class="k-oktext" data-t="gar.status">Connected</b><span class="k-muted k-small">••••••••••••</span><span class="k-muted k-small">Last read 07:12</span></div>
        <div class="k-line">${K.btn('Read again now', 'gar.again', { t: 'gar.again' })}${K.btn('Remove the key', 'gar.remove', { t: 'gar.remove', danger: true })}</div>`
      : `
        <span class="k-muted k-small">Your Garmin watch knows things Apple Health does not hand over: overnight HRV, sleep, Body Battery and stress. Make a personal key once in your Garmin Connect account at connect.garmin.com, paste it here once, and Today and the Body page show those numbers beside your own normal.</span>
        ${K.input('gar_key', S, { ph: 'Paste your Garmin key', t: 'gar.key' })}
        ${S.gar_problem ? `<span class="k-failtext k-small">${esc(S.gar_problem)}</span>` : ''}
        <div class="k-line">${K.btn('Cancel', 'gar.back')}${K.btn('Save', 'gar.save', { main: true, t: 'gar.save' })}</div>`}
      <span class="k-muted k-small">The key stays on this device only. The numbers are shown, they never change your plan.</span>`,
    /* The top of Today, as it is with a key saved. */
    'gar.today': S => `
      <h1 class="k-h1">Today</h1>
      <button class="gar-linebtn" data-act="gar.line" data-t="gar.line">${garLine()}
        <span class="k-line k-small k-muted"><i class="gar-dot"></i>Garmin · this morning, read 07:12</span></button>
      <div class="k-card"><span class="k-line">${K.sport('run')}<span class="k-col"><span class="k-sportword k-sp-run">Run</span><b>Easy run + 4x20 s strides</b>
        <span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span></span></span></div>`,
    /* A session marked done with one tap, whose watch numbers are not in yet. */
    'gar.done': S => `
      ${K.back('Today', 'gar.note', { t: 'gar.back2' })}
      <span class="k-line">${K.sport('run', { size: 40 })}<span class="k-col"><span class="k-sportword k-sp-run">Run</span><span class="k-muted">Wednesday 16 September</span></span></span>
      <b class="gar-sestitle">Easy run + 4x20 s strides</b>
      <span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span>
      <div class="k-card"><span class="k-cap">What you did</span><span class="k-line">${K.done()}<span>Done as planned · 35m</span></span></div>
      <div class="k-line"><button class="k-btn k-out" data-act="gar.fill" data-t="gar.fill">${icon('heart')}<span>Fill from Garmin</span></button></div>`,
    /* Today's morning answer from a neighbour, and the stretching line in the Load card. */
    'gar.feel': S => `
      <h1 class="k-h1">Today</h1>
      <span class="gar-feel" data-t="gar.feel"><span class="k-muted">Feeling </span><b>good</b><span class="k-muted"> — from Magic Morning</span></span>
      <span class="k-muted k-small gar-pad">Answered in Magic Morning — change it there.</span>
      <span class="k-cap">On Progress, in the Load card</span>
      <div class="k-card"><span class="k-muted k-small" data-t="gar.stretch">Stretching: 4 of the last 7 mornings</span></div>`,
    /* A strength session with a note from Workouts. */
    'gar.strength': S => `
      ${K.back('Today', 'gar.note', { t: 'gar.back2' })}
      <span class="k-line">${K.sport('strength', { size: 40 })}<span class="k-col"><span class="k-sportword k-sp-strength">Strength</span><span class="k-muted">Wednesday 16 September</span></span></span>
      <b class="gar-sestitle">Strength A</b>
      ${S.gar_logged
        ? `<span class="k-line">${K.done()}<span class="k-muted k-small" data-t="gar.logged">Logged from Workouts</span></span>`
        : `<span class="k-line"><span class="k-muted k-small">Done in Workouts at 07:40 · 35 min</span>${K.btn('Log it', 'gar.logit', { main: true, t: 'gar.logit' })}</span>`}
      <button class="gar-quiet" data-act="gar.note">Open Workouts</button>`,
  },
  sheets: {
    'gar.remove': S => `<h3>Remove the key?</h3>
      <span>Today and Body stop showing Garmin numbers. You can paste a key again at any time.</span>
      <div class="k-foot">${K.btn('Keep it', 'sheet.close')}${K.btn('Remove the key', 'gar.remove2', { danger: true, t: 'gar.remove2' })}</div>`,
    'gar.plate': S => `<h3>Garmin, this morning</h3>
      <span class="k-line k-small k-muted"><i class="gar-dot"></i>From this morning · read 07:12 from Garmin</span>
      ${garCard('HRV overnight', '64 ms', '(+3)', 'Normal 61 over 13 days · Garmin’s balanced range 52–68')}
      ${garCard('Sleep last night', '7h 20m', '', 'Normal 7h 06m over 13 days')}
      ${garCard('Resting heart rate', '47 bpm', '(−2)', 'Normal 49 over 13 days')}
      ${garCard('Body Battery on waking', '71', '', 'Normal 68 over 9 days')}
      ${garCard('Stress yesterday', '28', '', 'Normal 31 over 13 days')}
      <span class="k-muted k-small">Your watch last sent its numbers to Garmin at 07:05.</span>
      <span class="k-muted k-small">Shown only. These numbers never change your plan.</span>
      <div class="k-foot">${K.btn('Done', 'gar.plateoff', { main: true, t: 'gar.plateoff' })}</div>`,
  },
  actions: {
    'gar.open'(arg, S) { S.screen = 'gar.page'; },
    'gar.back'(arg, S) { S.screen = 'gar.settings'; },
    'gar.note'() { toast('That page has its own chapter.'); },
    'gar.save'(arg, S) {
      S.gar_tried = true;
      const key = String(S.gar_key || '').replace(/\s/g, '');
      if (!key) { S.gar_problem = 'Nothing typed yet. Paste your Garmin key into the field first.'; return; }
      S.gar_saved = true; S.gar_key = ''; S.gar_problem = '';
    },
    'gar.again'() { toast('Reading…'); },
    'gar.remove'(arg, S) { S.sheet = 'gar.remove'; },
    'gar.remove2'(arg, S) { S.sheet = null; S.gar_saved = false; S.gar_removed = true; },
    'gar.line'(arg, S) { S.sheet = 'gar.plate'; S.gar_plate = true; },
    'gar.plateoff'(arg, S) { S.sheet = null; },
    'gar.healthon'(arg, S) { S.gar_health = 'on'; },
    'gar.healthoff'(arg, S) { S.gar_health = 'stopped'; },
    'gar.calon'(arg, S) { S.gar_cal = true; },
    'gar.caloff'(arg, S) { S.gar_cal = false; },
    'gar.kind'(arg, S) { S.gar_allday = arg === 'all'; },
    'gar.fill'() { toast('The log form has its own chapter.'); },
    'gar.logit'(arg, S) { S.gar_logged = true; },
  },
  steps: [
    { kind: 'look', head: 'Where the numbers come from', shot: 'gar-01-page-saved',
      text: 'Today’s Garmin line and the Body page get their numbers from your Garmin watch, through one personal key. Once the key is saved, Settings › Garmin says Connected, shows the key only as dots, and says when it was last read. Read again now asks Garmin at once. The numbers are only shown: they never change your plan.',
      hint: 'The key stays on the device where you pasted it. An iPad or a Mac that should show the numbers needs its own key. The app only asks Garmin for numbers; nothing of your plan, notes or answers is sent to it.', real: 'Settings › Garmin' },
    { kind: 'look', head: 'Gym sessions: choose a folder once', shot: 'gar-07-gym-choose',
      text: 'With a key saved, the Garmin page has a second part, <b>Gym sessions</b>: “From the Workout Companion app, as on your Garmin Board.” and “Where: iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training › AMS Workout Companion app to Garmin”. Press <b>Choose the folder</b> once and pick that folder; it sits in iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training. Body’s Gym sessions card then fills.',
      hint: 'The app only reads the folder and writes nothing in it. The choice stays on this device: the iPad and the Mac each choose their own. The Gym sessions card on Body offers the same choice.', real: 'Settings › Garmin › Gym sessions' },
    { kind: 'look', head: 'Once the folder is chosen', shot: 'gar-08-gym-chosen',
      text: 'After the choice the part shows the folder’s name, <b>AMS Workout Companion app to Garmin</b>, and the day of the newest session: Newest session: Mon 14 Sep. A small <b>Change</b> button picks another folder.' },
    { kind: 'look', head: 'The page before a key is set', shot: 'gar-02-page-nokey',
      text: 'Before a key is set, the page says what the key is for. You make it once in your Garmin Connect account at connect.garmin.com and paste it in the field. Cancel closes the page; Save keeps the key.' },
    { kind: 'try', head: 'Open the Garmin page', target: 'gar.row',
      text: 'Press the row <b>Garmin · not connected</b>.',
      until: S => S.screen === 'gar.page', ok: 'The Garmin page opens: a grey paragraph about the key, a field, Cancel and Save.',
      robot: [['act', 'gar.open']], real: 'Settings › Garmin' },
    { kind: 'try', head: 'Save with nothing typed', set: { screen: 'gar.page' }, target: 'gar.save',
      text: 'Press <b>Save</b> with the field empty.',
      until: S => S.gar_tried && !S.gar_saved, ok: 'Nothing is saved. A red line says: Nothing typed yet. Paste your Garmin key into the field first.',
      robot: [['act', 'gar.save']] },
    { kind: 'try', head: 'Paste a key and save it', set: { screen: 'gar.page' }, target: S => (!S.gar_key ? 'gar.key' : 'gar.save'),
      text: 'Type any word into the field (in the real app you paste your key there), then press <b>Save</b>. This practice copy is not connected to Garmin.',
      until: S => S.gar_saved, ok: 'The page says Connected: the key is shown only as dots, with Last read 07:12 under it, and two buttons, Read again now and Remove the key.',
      hint: 'A key Garmin refuses says “Garmin did not accept this key.” in red; no connection says “Could not reach Garmin. Try again in a moment.” Nothing is saved then. While it checks, Save says Checking….',
      robot: [['in', 'gar_key', 'practice-key'], ['act', 'gar.save']] },
    { kind: 'try', head: 'Take the key away again', set: { screen: 'gar.page', gar_saved: true }, target: S => (S.sheet ? 'gar.remove2' : 'gar.remove'),
      text: 'Press <b>Remove the key</b>. The page asks first: press <b>Remove the key</b> once more.',
      until: S => S.gar_removed, ok: 'The key is gone and the page asks for one again. Today and Body stop showing Garmin numbers. Keep it would have left everything as it was.',
      robot: [['act', 'gar.remove'], ['act', 'gar.remove2']] },
    { kind: 'look', head: 'The Garmin line on Today', shot: 'gar-03-today-numbers',
      text: 'With a key, a line sits under the heading: HRV, Sleep, Resting and Body Battery. HRV and Resting carry a bracket, how far they sit from your own normal: green the good way, red the other, grey when it is as usual. The dot under it is green for “this morning” and grey for older numbers.',
      hint: 'Sleep and Body Battery carry no bracket. Where Garmin has a number that Apple Health also has, only Garmin’s shows, so one thing is never two numbers side by side.', real: 'Today' },
    { kind: 'try', head: 'Open the plate', set: { part: 'today', screen: 'gar.today' }, target: 'gar.line',
      text: 'Press the Garmin line.',
      until: S => S.sheet === 'gar.plate', ok: 'The plate lists five numbers, each with your normal and how many days it stands on, and when your watch last sent its numbers to Garmin. Done closes it.',
      hint: 'A number Garmin has not given yet says none yet. Your normal is the average of up to 14 earlier days, so it needs a few mornings first. Between midnight and four, the night that last ended still counts as last night.',
      robot: [['act', 'gar.line']] },
    { kind: 'look', head: 'The plate, as it looks', shot: 'gar-04-plate',
      text: 'The plate is titled Garmin, this morning. Five cards, each with its name first and the figure beside it: HRV overnight, Sleep last night, Resting heart rate, Body Battery on waking and Stress yesterday. Under each stands your normal and over how many days.' },
    { kind: 'try', head: 'Connect Apple Health', only: 'iPhone', target: S => (S.gar_health === 'on' ? 'gar.healthoff' : 'gar.healthon'),
      text: 'Under Apple Health, press <b>Connect</b>.',
      until: S => S.gar_health === 'on', ok: 'Health is In use. The log form can offer the day’s workouts from Health. Health is only read, never written.',
      hint: 'iOS asks for permission first. The app reads workouts, heart rate, distances, sleep, resting heart rate and HRV. On the Mac this row says From your iPhone: the iPhone puts its numbers in iCloud, and they show there with where they came from.',
      robot: [['act', 'gar.healthon']], real: 'Settings › Apple Health' },
    { kind: 'look', head: 'Fill from Garmin, and the heart', shot: 'gar-06-health-logform',
      text: 'On a session you marked done with one tap, a small <b>Fill from Garmin</b> stays until your watch’s numbers are in. It opens the log form. At the top, under FROM APPLE HEALTH, stand the day’s workouts that Health holds, the matching sport first, each with a <b>Use</b> button.',
      hint: 'The small heart on a session’s buttons means one thing: Apple Health holds numbers from your watch. With a Garmin key, a done session’s page may also show From your watch: the route, the pulse and the laps. Those pages have their own chapters.', only: 'iPhone' },
    { kind: 'try', head: 'Put the plan in your calendar', only: 'iPhone', set: { gar_low: true }, target: S => (S.gar_cal ? 'gar.caloff' : 'gar.calon'),
      text: 'Press <b>Put them in</b>.',
      until: S => S.gar_cal, ok: 'The Training calendar now holds every session from today on. The row says how many, and when it was updated.',
      hint: 'If iOS does not let the app write to your calendar, the row says Not allowed and offers Open Settings. Only the iPhone writes it; on the iPad and the Mac it appears in Calendar through iCloud, and Settings says Kept by your iPhone.',
      robot: [['act', 'gar.calon']], real: 'Settings › Calendar' },
    { kind: 'look', head: 'Two neighbour apps', set: { part: 'today', screen: 'gar.feel' }, target: 'gar.feel',
      text: 'Your neighbour apps can leave notes for this one on your iPhone: Workouts (AMS Workout Companion) and Magic Morning (AMS Magic Morning Routine). A morning answer given there shows on Today as Feeling good — from Magic Morning, and is changed there. Their stretching is counted in the Load card.',
      hint: 'Until the matching versions of those apps are installed, none of this shows. The notes stay on this iPhone. A note never writes to your plan by itself.' },
    { kind: 'try', head: 'Log a strength session done in Workouts', only: 'iPhone', set: { part: 'today', screen: 'gar.strength' }, target: 'gar.logit',
      text: 'Press <b>Log it</b>.',
      until: S => S.gar_logged, ok: 'The session is logged with the minutes Workouts noted, and says Logged from Workouts. Nothing is logged without your press.',
      hint: 'A note is used once. The small grey Open Workouts shows on a strength session only when Workouts is installed.',
      robot: [['act', 'gar.logit']] },
    { kind: 'check', head: 'Workouts noted a strength session', text: 'Workouts has noted today’s strength session, and you do nothing in this app. What happens to your plan?',
      answers: ['The session is logged as done by itself', 'Nothing changes until you press Log it', 'The session is marked missed'], right: 1,
      ok: 'Right. The only things that come in from the neighbours are the morning answer, the stretching count and a session you log with Log it.' },
  ],
});
