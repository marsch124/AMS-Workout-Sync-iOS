/* Chapter 1 — Today. Everything on the first page, top to bottom. All words are the app's own (TodayView, FeelViews,
   TodayWeather, WeekSoFarStrip, MorningNumbersView, ExtraViews, SundayCardView); the plan is the invented one (Wednesday 16 September). */
ICON['tod-bad'] = 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17 M8 16.4c.9-1.6 2.2-2.4 4-2.4s3.1.8 4 2.4 M9 8.5v2.4 M15 8.5v2.4';
ICON['tod-tired'] = 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17 M7.6 10h2.6 M13.8 10h2.6 M8.7 16c1-.8 2.1-1.2 3.3-1.2s2.3.4 3.3 1.2';
ICON['tod-ok'] = 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17 M9 8.5v2.4 M15 8.5v2.4 M8.4 15.4h7.2';
ICON['tod-good'] = 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17 M9 8.5v2.4 M15 8.5v2.4 M8 14.2c.9 1.7 2.3 2.6 4 2.6s3.1-.9 4-2.6';
ICON['tod-great'] = 'M12 3.5a8.5 8.5 0 1 0 0 17a8.5 8.5 0 1 0 0-17 M9 7.8v2.8 M15 7.8v2.8 M7.2 13.3h9.6c-.4 2.7-2.2 4.3-4.8 4.3s-4.4-1.6-4.8-4.3z';

const TOD_FEELS = [['bad', 'Bad'], ['tired', 'Tired'], ['ok', 'OK'], ['good', 'Good'], ['great', 'Great']];
const todFeelWord = f => f === 'ok' ? 'OK' : String(f).toLowerCase();

/* One column of the week card: blocks from the bottom up. [colour, height, kind, tick] */
const todBlock = ([c, h, kind, tick]) => `<span class="tod-b ${kind ? 'tod-' + kind : ''}" style="--c:var(--sp-${c});height:${h}px">${tick ? `<i>${icon('check')}</i>` : ''}</span>`;
const TOD_WEEK = [
  [['swim', 24, '', true]], [['bike', 40, '', true], ['rest', 22, 'dot', true]], [['run', 24, 'todo']], [], [['rest', 3, 'restday']],
  [['bike', 50, 'todo']], [['run', 30, 'todo']],
];
const todWeek = S => `<div class="k-card tod-card" data-act="tod.key" data-t="tod.week">
    <div class="tod-weekhead"><b>This week</b><button class="tod-key" data-act="tod.key" data-t="tod.keybtn">${S.tod_key ? 'Hide key' : 'Key'}</button></div>
    <span class="k-fig k-muted">1h 15m of 3h 40m</span>${K.bar(34, { pace: 52 })}
    <div class="tod-cols">${TOD_WEEK.map(col => `<div class="tod-col">${col.length && col[0][2] === 'restday' ? '<span class="tod-rest"></span>' : col.map(todBlock).join('')}</div>`).join('')}</div>
    <div class="tod-days">${['M', 'T', '<b>W</b>', 'T', 'F', 'S', 'S'].map(d => `<span>${d}</span>`).join('')}</div>
    ${S.tod_key ? `<div class="tod-keyrow" data-t="tod.keyrows">
      <span><i class="tod-swatch" style="--c:var(--sp-run)"></i>Recorded</span><span><i class="tod-swatch tod-todo" style="--c:var(--sp-run)"></i>Still to do</span>
      <span><i class="tod-swatch tod-dot" style="--c:var(--sp-rest)"></i>Extra, outside the plan</span><span><i class="tod-swatch" style="--c:var(--sp-rest);height:3px"></i>Rest day</span></div>` : ''}
  </div>`;

const todSession = (S, label = 'Run', title = 'Easy run + 4x20 s strides', why = true, chips = ['35m', 'Z2'], sport = 'run', act = true, t = 'tod.ses') =>
  `<${act ? 'button' : 'div'} class="k-card tod-card" ${act ? `data-act="tod.open" data-t="${t}"` : ''}>
    <span class="k-line">${K.sport(sport)}<span class="k-col tod-words"><span class="k-sportword k-sp-${sport}">${label}</span>
      <b class="tod-title">${esc(title)}</b>${why ? '<span class="k-muted k-small">Why: easy aerobic — builds your base without costing much.</span>' : ''}
      <span class="k-line">${chips.map(c => K.chip(c)).join('')}</span></span></span></${act ? 'button' : 'div'}>`;

const todWeather = `<span class="k-muted k-small" data-t="tod.weather">10° · feels 6° · breezy 5 m/s · rain likely 15–16<br>Light until 19:05</span>`;

const todSoFar = `<div class="k-card" data-t="tod.sofar"><span class="tod-head">WEEK SO FAR</span>
    ${[['bike', 'Bike', '42m of 1h 50m', 38], ['run', 'Run', '0m of 1h 15m', 0], ['swim', 'Swim', '33m of 35m', 94]].map(([s, n, f, p]) =>
      `<span class="tod-srow" style="--c:var(--sp-${s});--ink:var(--ink-${s})"><span class="k-line">${icon(s)}<b>${n}</b><span class="k-muted k-small">${f}</span></span>
        <span class="tod-sbar"><i style="width:${p}%"></i></span></span>`).join('')}</div>`;

const todExtraCard = x => `<button class="k-card tod-card" data-act="tod.note" data-t="tod.extracard">
    <span class="k-line"><span class="k-sport k-sp-rest">${icon('walk')}</span><span class="k-col tod-words"><span class="tod-ex">EXTRA · WALK</span>
    <b class="tod-title">${esc(x.what || 'Walk')}</b><span class="k-line">${K.chip(dur(x.min))}${x.train ? `<span class="k-chip">${icon('counts')}Counts as training</span>` : ''}</span></span></span></button>`;

const todGarmin = `<button class="tod-g" data-act="tod.plate" data-t="tod.garmin">
    <span class="tod-gline"><span>HRV </span><b>64</b><span class="k-oktext"> (+3)</span> · <span>Sleep </span><b>7h 20m</b> · <span>Resting </span><b>47</b><span class="k-oktext"> (−2)</span> · <span>Body Battery </span><b>71</b></span>
    <span class="tod-gdot"><i></i>Garmin · this morning, read 07:12</span></button>`;

CHAPTER({
  id: 'tod',
  title: 'Today',
  icon: 'today',
  needs: 'One tap in the morning if you want to say how you feel. Nothing else: Today fills itself from your plan.',
  gives: 'The whole day on one page: how you feel, the week so far, today’s session with its weather, what you missed, and tomorrow.',
  start: () => ({ device: 'phone', part: 'today', screen: 'tod.today', sheet: null,
    tod_feel: null, tod_changing: false, tod_from: null, tod_key: false, tod_extras: [], tod_garmin_line: false, tod_plateseen: false,
    tod_what: '', tod_dur: '', tod_count: 'no', tod_tried: false, tod_sunday: true, tod_back: false }),
  screens: {
    /* The top of Today, in the app's order: heading, morning line, the question, the week card, today's session and its weather,
       extras, the Garmin line, Week so far. */
    'tod.today': S => {
      const answered = S.tod_feel && !S.tod_changing;
      return `
      <div class="tod-toprow"><h1 class="k-h1">Today</h1></div>
      ${S.tod_from && S.tod_feel ? `<span class="tod-line" data-t="tod.line">Feeling <b>${todFeelWord(S.tod_feel)}</b> — from ${esc(S.tod_from)}</span>
        <span class="k-muted k-small" data-t="tod.fromnote">Answered in ${esc(S.tod_from)} — change it there.</span>`
        : answered ? `<button class="tod-line" data-act="tod.change" data-t="tod.line">Feeling <b>${todFeelWord(S.tod_feel)}</b></button>` : ''}
      ${S.tod_garmin_line ? todGarmin : ''}
      ${!S.tod_from && (!S.tod_feel || S.tod_changing) ? `<div class="k-card" data-t="tod.ask"><b class="k-small">How do you feel?</b>
        <div class="tod-faces">${TOD_FEELS.map(([id, w]) => `<button class="tod-face ${S.tod_feel === id ? 'tod-on' : ''}" data-act="tod.feel" data-arg="${id}" data-t="tod.f:${id}">${icon('tod-' + id)}<span>${w}</span></button>`).join('')}</div></div>` : ''}
      ${todWeek(S)}
      ${todSession(S)}
      ${todWeather}
      ${S.tod_extras.length ? `<span class="tod-grey">Extra, outside the plan</span>${S.tod_extras.map(todExtraCard).join('')}` : ''}
      ${todSoFar}`;
    },
    /* A session's own page, opened from the card. */
    'tod.session': S => `
      ${K.back('Today', 'tod.back', { t: 'tod.back' })}
      <span class="k-line">${K.sport('run', { size: 40 })}<span class="k-col tod-words"><span class="k-sportword k-sp-run">Run</span><span class="k-muted">Wednesday 16 September</span></span></span>
      <b class="tod-title">Easy run + 4x20 s strides</b>
      <span class="k-muted k-small">Why: easy aerobic — builds your base without costing much.</span>
      <span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span>
      <p class="k-muted k-small">Logging a session has its own chapter.</p>`,
    /* Further down Today: the Sunday card, what is behind you, tomorrow, the grey pill at the foot. */
    'tod.lower': S => `
      ${S.tod_sunday ? `<div class="tod-sun" data-t="tod.sunday"><div class="tod-sunhead"><div class="k-line"><span class="k-small"><b>NEXT WEEK</b></span><button data-act="tod.close" data-t="tod.close">Close</button></div>
          <span><span class="tod-sunbig">6</span> <b>sessions</b> &nbsp; <b>4h 55m</b></span></div>
        ${[['Mon', 'swim', 'Easy swim, steady', '40m'], ['Tue', 'bike', 'Steady aerobic ride', '1h 00m'], ['Wed', 'run', 'Easy run', '35m']].map(([d, s, t, l]) =>
          `<div class="tod-sunrow"><span class="tod-sunday">${d}</span>${K.sport(s)}<span class="k-col" style="gap:0"><b class="k-small">${t}</b><span class="k-muted k-small">${l}</span></span></div>`).join('')}</div>` : ''}
      <span class="tod-grey" data-t="tod.behind">Behind you, not recorded</span>
      <div class="k-card"><span class="k-line">${K.sport('swim')}<span class="k-col tod-words"><span class="k-sportword k-sp-swim">Swim</span>
        <b class="tod-title">Easy technique: 4x50 drill, then 6x50 smooth</b><span class="k-line">${K.chip('Wed 9 Sep')}${K.chip('30m')}${K.chip('Z1-Z2')}</span></span></span></div>
      <div class="tod-toprow"><span class="tod-tomtab" data-t="tod.tomorrow">TOMORROW</span><button class="tod-pill" data-act="tod.extraopen" data-t="tod.extra">${icon('plus')}Extra workout</button></div>
      <div class="tod-tom" style="margin-top:-6px">${todSession(S, 'Bike', 'Steady aerobic ride, flat to rolling', false, ['1h 00m', 'Z2'], 'bike', true, 'tod.tomses')}</div>
      <div class="tod-foot"><button class="k-pill k-grey" data-act="tod.note" data-t="tod.notwell">Not well?</button></div>`,
  },
  sheets: {
    'tod.extraform': S => `<h3>Extra workout</h3>
      <div class="k-field"><label>What kind of thing</label><span class="k-chip">${icon('walk')}Walk</span></div>
      <div class="k-field"><label for="in-tod_what">What it was</label>${K.input('tod_what', S, { ph: 'e.g. Dog walk along the river', t: 'tod.what' })}</div>
      <div class="k-field"><label for="in-tod_dur">Duration</label>${K.input('tod_dur', S, { ph: 'e.g. 35', num: true, w: 80, t: 'tod.dur' })}</div>
      <span class="k-muted k-small">Just a number means minutes. Or 1:15, 1h20, 90min.</span>
      <div class="k-field"><label>Counts as training?</label>${K.seg([['no', 'No'], ['yes', 'Yes']], S.tod_count, 'tod.count', 'tod.countseg')}</div>
      <span class="k-muted k-small">${S.tod_count === 'yes' ? 'Yes — count it as training' : 'No — it does not add load'}</span>
      ${S.tod_tried && !S.tod_what && !S.tod_dur ? `<div class="k-band k-fail">${icon('alert')}<span>Give it at least a duration — "35", or 1:15 — or a word about what it was.</span></div>` : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'tod.save', { main: true, t: 'tod.save' })}</div>`,
    'tod.plate': S => `<h3>Garmin, this morning</h3>
      <span class="tod-gdot"><i></i>From this morning · read 07:12 from Garmin</span>
      <div class="tod-plate k-list">
        ${[['HRV overnight', '64 ms', '(+3)', 'Normal 61 over 13 days'], ['Sleep last night', '7h 20m', '', 'Normal 7h 06m over 13 days'], ['Resting heart rate', '47 bpm', '(−2)', 'Normal 49 over 13 days'],
          ['Body Battery on waking', '71', '', 'Normal 68 over 9 days'], ['Stress yesterday', '28', '', 'Normal 31 over 13 days']].map(([n, v, d, norm]) =>
          `<div class="k-card"><span class="k-line"><span class="k-muted">${n}</span><b class="k-fig">${v}</b><span class="k-oktext k-small">${d}</span></span><span class="k-muted k-small">${norm}</span></div>`).join('')}
      </div>
      <span class="k-muted k-small">Shown only. These numbers never change your plan.</span>
      <div class="k-foot">${K.btn('Done', 'tod.plateclose', { t: 'tod.platedone', main: true })}</div>`,
  },
  actions: {
    'tod.feel'(arg, S) { S.tod_feel = arg; S.tod_changing = false; },
    'tod.change'(arg, S) { S.tod_changing = true; },
    'tod.key'(arg, S, el) { S.tod_key = !S.tod_key; },
    'tod.open'(arg, S) { S.screen = 'tod.session'; S.tod_back = false; },
    'tod.back'(arg, S) { S.screen = 'tod.today'; S.tod_back = true; },
    'tod.close'(arg, S) { S.tod_sunday = false; },
    'tod.extraopen'(arg, S) { S.sheet = 'tod.extraform'; },
    'tod.count'(arg, S) { S.tod_count = arg; },
    'tod.save'(arg, S) {
      S.tod_tried = true;
      const m = /^(\d+)(?::(\d+))?/.exec(String(S.tod_dur).trim());
      const minutes = m ? (m[2] !== undefined ? Number(m[1]) * 60 + Number(m[2]) : Number(m[1])) : 0;
      if (!minutes && !String(S.tod_what).trim()) return;
      S.tod_extras.push({ what: String(S.tod_what).trim(), min: minutes, train: S.tod_count === 'yes' });
      S.sheet = null; S.screen = 'tod.today';
    },
    'tod.plate'(arg, S) { S.sheet = 'tod.plate'; },
    'tod.plateclose'(arg, S) { S.sheet = null; S.tod_plateseen = true; },
    'tod.note'() { toast('This one has its own chapter. Here, follow the yellow ring.'); },
  },
  steps: [
    { kind: 'look', head: 'Today, from the top down', shot: 'tod-01-morning',
      text: 'Today is the page the app opens on. At the top: the heading, then the white card <b>How do you feel?</b> with five faces, the <b>This week</b> card, and today’s session. Under them, a small <b>+ Extra workout</b> pill and the first of the sessions behind you.',
      hint: 'You never have to do anything here. Every card is there to read.' },
    { kind: 'try', head: 'Answer the morning question', target: 'tod.f:good',
      text: 'Under the heading a card asks <b>How do you feel?</b> Press <b>Good</b>.',
      until: S => S.tod_feel === 'good', ok: 'The card is gone until tomorrow. The morning line now says Feeling good.', robot: [['act', 'tod.feel', 'good']],
      real: 'Today, top', hint: 'Five faces: Bad, Tired, OK, Good, Great. Answered once a day. It is never written into the plan. With suggestions on, two poor mornings in a row (Bad or Tired) can bring a card; there is no score.' },
    { kind: 'try', head: 'Change your answer', set: { tod_feel: 'ok' }, target: S => S.tod_changing ? 'tod.f:great' : 'tod.line',
      text: 'Press the words <b>Feeling OK</b> under the heading. The question comes back with your answer outlined. Press <b>Great</b>.',
      until: S => S.tod_feel === 'great' && !S.tod_changing, ok: 'The line says Feeling great. A later tap on a face replaces the earlier one: there is one answer a day.',
      robot: [['act', 'tod.change'], ['act', 'tod.feel', 'great']] },
    { kind: 'try', head: 'Open the key under This week', target: 'tod.keybtn', set: { tod_feel: 'good' },
      text: 'The card draws the week: a column a day, a block a session. Press <b>Key</b> to see what the blocks mean.',
      until: S => S.tod_key, ok: 'Solid = recorded, lighter = still to do, dotted = an extra outside the plan, a flat line = a rest day. The key lists Missed too. Pressing the card does the same.',
      robot: [['act', 'tod.key']], real: 'Today › This week › Key',
      hint: 'The thin bar at the right is how much of the planned week is recorded; its small notch is where the week should stand once tonight is done.' },
    { kind: 'try', head: 'Open today’s session', target: 'tod.ses', set: { tod_feel: 'good' },
      text: 'The card shows the sport’s mark, the title, a grey <b>Why:</b> line, and chips for the length and the zone. Press the card.',
      until: S => S.screen === 'tod.session', ok: 'The session’s own page opens. The arrow at the top left leads back to Today.', robot: [['act', 'tod.open']] },
    { kind: 'look', head: 'The weather line under a run', shot: 'tod-02-session-weather',
      text: 'Right under the Run card, one grey line gives the forecast for the hours of the run (or of daylight, if the plan has no start time), and when it gets dark: here “10° · feels 6° · breezy 5 m/s · rain likely 15–16” and “Light until 19:05”. It shows only for an outdoor session, never for a pool swim, strength or a rest day.',
      hint: 'The first time, iOS asks to use your place while the app is open. Say no, or have no network, and the line is simply not there. Settings › Weather switches it off.' },
    { kind: 'look', head: 'Week so far, per sport', shot: 'tod-03-week-so-far',
      text: 'The card <b>WEEK SO FAR</b> lists each sport the plan has this week: its mark, its name, and the time done of the time planned right beside it, like “Bike 42m of 1h 50m”. The slim bar is the sport’s full colour where it is done and pale where it is still to come.',
      hint: 'Extras that count as training add to the done time of their own sport, never to what is planned.' },
    { kind: 'look', head: 'Sunday evening: next week', shot: 'tod-04-sunday-card',
      text: 'If you switched it on in Settings › Reminders, a blue card <b>NEXT WEEK</b> appears from Sunday evening until Monday morning: the number of sessions and their time, then a row for each with its weekday, sport mark, title and length. Below it stands <b>BEHIND YOU, NOT RECORDED</b>.',
      hint: '<b>Close</b>, at the top right of the blue card, puts it away until next Sunday.' },
    { kind: 'look', head: 'Behind you, not recorded', shot: 'tod-05-lower',
      text: 'Sessions of the last seven days that have no log stand here as ordinary cards, each with its day as the first chip: “Thu 10 Sep”, then the length and the zone. Press one to open it and log it or mark it missed. A day still ahead of you is shown under TOMORROW on its own pale ground.',
      hint: 'Nothing here is a warning. It is only what has no mark yet.' },
    { kind: 'look', head: 'The foot of Today', shot: 'tod-07-foot',
      text: 'Near the foot: the small <b>+ Extra workout</b> pill at the right, the <b>WEEK SO FAR</b> card, and last of all, centred, the small grey pill <b>Not well?</b>. It stands quietly at the bottom on purpose; the next chapter explains it.',
      hint: 'With a plan for tomorrow, the Extra workout pill stands beside the word TOMORROW instead.' },
    { kind: 'try', head: 'Add an extra workout', set: { screen: 'tod.lower', tod_feel: 'good' }, target: S => S.sheet ? (!S.tod_what ? 'tod.what' : !S.tod_dur ? 'tod.dur' : 'tod.save') : 'tod.extra',
      text: 'Next to <b>TOMORROW</b> stands a small <b>Extra workout</b> pill. Press it, say what it was (“Dog walk”), type <b>35</b> for the minutes, and press <b>Save</b>.',
      until: S => S.tod_extras.length === 1, ok: 'Back on Today, a card under “Extra, outside the plan” shows the walk with its 35m. It sits outside the plan: the plan does not change.',
      robot: [['act', 'tod.extraopen'], ['in', 'tod_what', 'Dog walk'], ['in', 'tod_dur', '35'], ['act', 'tod.save']],
      real: 'Today › Extra workout',
      hint: 'Press Save with nothing typed and a red line asks for at least a duration, or a word about what it was.' },
    { kind: 'try', head: 'Garmin’s numbers from this morning', set: { tod_feel: 'good', tod_garmin_line: true }, target: S => S.sheet ? 'tod.platedone' : 'tod.garmin', only: 'a device with a Garmin key saved',
      text: 'With a Garmin key saved (Settings › Garmin), a grey line under the morning line gives HRV, Sleep, Resting and Body Battery. HRV and Resting have how far they sit from your own normal in brackets. Press the line.',
      until: S => !!S.tod_plateseen, ok: 'A small plate shows each number with your own normal, and says the numbers are shown only and never change your plan. Done closes it.',
      robot: [['act', 'tod.plate'], ['act', 'tod.plateclose']] },
    { kind: 'look', head: 'Garmin’s plate, and pulling down', shot: 'tod-08-garmin-plate',
      text: 'The plate that opens from the Garmin line shows five numbers, each with your own normal under it: HRV overnight, Sleep last night, Resting heart rate, Body Battery on waking and Stress yesterday. It ends with “Shown only. These numbers never change your plan.” Done closes it.',
      hint: 'Pull Today down to read the plan again. On an iPad or Mac that still shows an old Excel plan, the right of the heading says “The plan is on its way from iCloud”; with your plan in the app, nothing stands there.' },
    { kind: 'check', head: 'You answered in another app', set: { tod_from: 'Magic Morning', tod_feel: 'good' },
      text: 'You answered the morning question in Magic Morning. You open Today. What does it show?',
      answers: ['The question again, to be answered a second time', 'A grey line “Feeling good — from Magic Morning” and no question; you change it in Magic Morning', 'Nothing about your answer at all'], right: 1,
      ok: 'Right. The answer is taken over, the question is not asked twice, and the grey words under it say where to change it. The iPad and the Mac say the same.' },
    { kind: 'check', head: 'A walk that does not add load', set: { screen: 'tod.today', tod_feel: 'good', tod_extras: [{ what: 'Dog walk', min: 35, train: false }] },
      text: 'You saved a 35 minute walk and left Counts as training on No. What changes on Today?',
      answers: ['The walk adds 35 minutes to Week so far', 'It shows as an extra card and a dotted block; the week’s hours and Week so far stay as they were', 'The plan gets a new session'], right: 1,
      ok: 'Right. An extra marked Yes only adds small blocks beside the week’s thin bar, and done time to the same sport’s row in Week so far when the plan has that sport. It never adds planned time, and the plan itself is never changed.' },
  ],
});
