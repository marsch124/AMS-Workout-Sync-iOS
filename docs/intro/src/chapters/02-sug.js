/* Chapter 2 — Suggestions and Not well?. Words from SuggestionCard, StopSignView, ReturnLadderCard, PlanChangesView, MoveView,
   RuleBookWords and RuleBookHealth. The plan is the invented one (Wednesday 16 September). Cards are made on the iPhone only. */
const SUG_HEAD = 'Wed run: 35 min → rest';
const SUG_OTHER = 'Wed run: 35 → 25 min, easy';
const SUG_OTHER2 = 'Wed run swaps with Sat bike';
const SUG_WHY = 'Why: you felt tired two mornings running.';

const sugSession = S => S.sug_state === 'taken' && S.sug_took === 0
  ? `<div class="k-card"><span class="k-line">${K.sport('rest')}<b class="k-muted">rest (your choice)</b></span></div>`
  : `<div class="k-card"><span class="k-line">${K.sport('run')}<span class="k-col sug-words"><span class="k-sportword k-sp-run">Run</span>
      <b class="sug-title">Easy run + 4x20 s strides</b><span class="k-line">${K.chip(S.sug_state === 'taken' && S.sug_took === 1 ? '25m' : '35m')}${K.chip('Z2')}</span></span></span></div>`;

const sugStairs = `<div class="sug-boxed" data-t="sug.stairs"><span class="k-cap" style="color:var(--i-today)">THE WAY BACK</span><div class="sug-stairs">
    ${[['Rest', 'Rest until 48 hours completely symptom-free. Your guide asks you to respect this strictly.', true],
      ['Two easy days', 'Two extra easy days, as your guide says after fever or chest symptoms.'], ['Week 1 back', 'Week 1 back: about half, all easy, no key sessions.'],
      ['Week 2 back', 'Week 2 back: about three quarters, one quality session mid-week.'], ['Back on your plan', 'Back on your plan.']]
      .map(([t, w, now], i) => `<div class="sug-stair ${now ? 'sug-now' : ''}" style="margin-left:${i * 8}px"><div><b>${t}</b><span>${w}</span></div></div>`).join('')}</div></div>`;

CHAPTER({
  id: 'sug',
  title: 'Suggestions and Not well?',
  icon: 'firstaid',
  needs: 'Nothing. A card comes only now and then; you answer it, or ignore it.',
  gives: 'A calm second opinion on your plan, with every change yours to take or leave, and a quiet way to pause everything when you are ill.',
  start: () => ({ device: 'phone', part: 'today', screen: 'sug.today', sheet: null,
    sug_state: 'open', sug_other: false, sug_took: 0, sug_paused: false, sug_ill: null, sug_undone: false, sug_askundo: false,
    sug_day: 'wed', sug_moved: false }),
  screens: {
    /* Today's top with the rule book's card directly under the morning line, today's session, and the grey pill at the foot. */
    'sug.today': S => `
      <div class="sug-top"><h1 class="k-h1">Today</h1></div>
      <span class="sug-grey">Feeling <b>tired</b></span>
      ${S.sug_paused ? `<span class="sug-grey" data-t="sug.ladderline">Suggestions are paused — Stop sign</span>`
        : S.sug_state === 'open' ? `<div class="sug-card" data-t="sug.card">
            <span class="sug-head">${SUG_HEAD}</span><span class="sug-why">${SUG_WHY}</span>
            <div class="sug-btns"><button class="sug-eq" data-act="sug.take" data-arg="0" data-t="sug.take">Take it</button><button class="sug-eq" data-act="sug.keep" data-t="sug.keep">Keep my plan</button></div>
            ${S.sug_other ? `<div class="sug-orow" data-t="sug.orow"><span>${SUG_OTHER}</span><button data-act="sug.take" data-arg="1" data-t="sug.take1">Take it</button></div><div class="sug-orow"><span>${SUG_OTHER2}</span><button data-act="sug.take" data-arg="2" data-t="sug.take2">Take it</button></div>`
              : `<button class="sug-other" data-act="sug.other" data-t="sug.other">Other choice</button>`}
            <span class="sug-foot">Training suggestion — not medical advice.</span></div>`
        : S.sug_state === 'taken' ? `<div class="sug-card" data-t="sug.changed"><div class="sug-changed"><b class="k-small">Changed —</b><button class="sug-undo" data-act="sug.todayundo" data-t="sug.undo">Undo</button></div>
            <span class="k-muted k-small">${[SUG_HEAD, SUG_OTHER, SUG_OTHER2][S.sug_took]}</span></div>` : ''}
      ${sugSession(S)}
      <div class="sug-pillrow"><button class="sug-pill" data-act="sug.notwell" data-t="sug.notwell">Not well?</button></div>`,
    /* Settings › Changes to the plan */
    'sug.changes': S => `
      ${K.back('Settings', 'sug.note')}
      <h1 class="k-h1">Changes to the plan</h1>
      <div class="sug-boxed" data-t="sug.chrow" style="${S.sug_undone ? 'opacity:.7' : ''}">
        <div class="sug-rowhead"><span class="sug-kind">CHANGED</span><span class="k-muted k-small">16 Sep 2026, 09:12</span><span class="k-sp"></span>
          ${S.sug_undone ? '<b class="k-small k-muted" data-t="sug.undone">Undone</b>' : '<button class="sug-chbtn" data-act="sug.chundo" data-t="sug.chundo">Undo</button>'}</div>
        <b class="k-small">Easy run + 4x20 s strides</b>
        <span class="k-muted k-small">Suggestion: ${SUG_HEAD}</span></div>`,
  },
  sheets: {
    'sug.plate': S => `<h3>Not well?</h3>
      <button class="sug-row" data-act="sug.stoprow" data-t="sug.stoprow"><b>Stop sign</b><span>Chest pain, unusual breathlessness, dizziness, a racing or uneven heartbeat. Opens the stop sign and pauses suggestions.</span></button>
      <button class="sug-row" data-act="sug.illrow" data-t="sug.illrow"><b>I’m ill</b><span>A cold, fever or stomach bug. Opens the illness questions and the steps back.</span></button>
      <div class="k-foot">${K.btn('Done', 'sheet.close', { main: true })}</div>`,
    'sug.stop': S => `<h3>Stop sign</h3>
      <div class="sug-boxed"><span class="sug-stopt">Stop training now.</span>
        <span>Chest pain or pressure · unusual breathlessness · dizziness or fainting · a racing or uneven heartbeat.</span>
        <span>These need a doctor to look at them before you train again. If it is strong or does not pass, call 112.</span>
        <span class="k-muted k-small">The app pauses all training suggestions until you tap "A doctor has seen me".</span>
        <span class="k-muted k-small"><i>Training app, not medical advice.</i></span>
        ${S.sug_paused ? `<span class="k-line"><b class="k-small" data-t="sug.pausedword">Paused</b><button class="sug-ok" data-act="sug.doctor" data-t="sug.doctor">A doctor has seen me</button></span>
          <button class="sug-quiet" data-act="sug.mistake" data-t="sug.mistake">Opened by mistake</button>` : '<b class="k-small k-oktext">Not paused.</b>'}</div>
      <div class="k-foot">${K.btn('Done', 'sheet.close', { main: true, t: 'sug.stopdone' })}</div>`,
    'sug.ill': S => `<h3>I’m ill</h3>
      <div class="sug-boxed">
        ${S.sug_ill ? `<span data-t="sug.step">Rest until 48 hours completely symptom-free. Your guide asks you to respect this strictly.</span>
          <span class="k-line"><span class="k-small">Symptom-free since</span><span class="k-chip">today</span>${K.btn('Save', 'sug.note')}</span>
          <button class="sug-quiet" data-act="sug.illmistake" data-t="sug.illmistake">I tapped this by mistake</button>`
        : `<b class="k-small">Fever, or chest / body aches?</b>
          <div class="sug-sel"><button class="sug-ok" data-act="sug.ill" data-arg="fever" data-t="sug.yes">Yes</button><button class="sug-ok" data-act="sug.ill" data-arg="cold" data-t="sug.no">No, a cold above the neck</button></div>`}</div>
      ${S.sug_ill ? sugStairs : ''}
      <div class="k-foot">${K.btn('Done', 'sheet.close', { main: true })}</div>`,
    'sug.move': S => `<h3>Move</h3>
      <div class="k-card"><span class="k-line">${K.sport('run')}<b class="k-small">Easy run + 4x20 s strides</b></span></div>
      <span class="k-cap">Move it to</span>
      <div class="sug-sel">${K.select('sug_day', S, [['wed', 'Wed 16 Sep'], ['thu', 'Thu 17 Sep'], ['fri', 'Fri 18 Sep']], { t: 'sug.moveday' })}</div>
      ${S.sug_day === 'wed' ? '<span class="k-muted k-small">Pick a different day first.</span>' : ''}
      ${S.sug_day === 'fri' ? '<span class="k-muted k-small" data-t="sug.ownnote">Friday is your rest day.</span>' : ''}
      ${S.sug_day === 'thu' ? '<span class="k-muted k-small">That makes two hard days in a row.</span>' : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Move the session', 'sug.movedo', { main: true, t: 'sug.movedo' })}</div>`,
    'sug.undoask': S => `<h3>Undo this change?</h3>
      <div class="k-foot">${K.btn('Keep it', 'sug.keepit')}${K.btn('Undo', 'sug.undoyes', { main: true, t: 'sug.undoyes' })}</div>`,
  },
  actions: {
    'sug.take'(arg, S) { S.sug_state = 'taken'; S.sug_took = Number(arg); },
    'sug.keep'(arg, S) { S.sug_state = 'kept'; },
    'sug.other'(arg, S) { S.sug_other = true; },
    'sug.todayundo'(arg, S) { S.sug_state = 'open'; S.sug_other = false; },
    'sug.chundo'(arg, S) { S.sheet = 'sug.undoask'; },
    'sug.keepit'(arg, S) { S.sheet = null; },
    'sug.undoyes'(arg, S) { S.sug_undone = true; S.sheet = null; },
    'sug.notwell'(arg, S) { S.sheet = 'sug.plate'; },
    'sug.stoprow'(arg, S) { S.sheet = 'sug.stop'; S.sug_paused = true; },
    'sug.doctor'(arg, S) { S.sug_paused = false; },
    'sug.mistake'(arg, S) { S.sug_paused = false; S.sheet = null; },
    'sug.illrow'(arg, S) { S.sheet = 'sug.ill'; },
    'sug.ill'(arg, S) { S.sug_ill = arg; },
    'sug.illmistake'(arg, S) { S.sug_ill = null; },
    'sug.movedo'(arg, S) { if (S.sug_day === 'wed') { toast('Pick a different day first.'); return; } S.sug_moved = true; S.sheet = null; toast('Moved. The grey line did not stop it.'); },
    'sug.note'() { toast('That page has its own chapter.'); },
  },
  steps: [
    { kind: 'look', head: 'A second opinion, never an order', shot: 'sug-01-card',
      text: 'Now and then a white card appears on Today, under the morning question. It comes from a fixed rule book written from your own training guide: never a coach, never medical advice. A bold line says the change, a grey line starting <b>Why:</b> says the reason, and two buttons with the same blue outline answer it: <b>Take it</b> and <b>Keep my plan</b>.',
      hint: 'Neither button is filled: saying no weighs as much as saying yes. If you have saved a key and switched Claude on, Claude may choose among the rule book’s options; it never makes up a new one. Only the iPhone makes cards.' },
    { kind: 'look', head: 'Other choice shows more ways', shot: 'sug-02-other',
      text: 'The blue words <b>Other choice</b>, under the two buttons, open up to two more rows in grey, each with its own blue <b>Take it</b>. Here they are “Wed run: 35 → 25 min, easy” and “Wed run swaps with Sat bike”. Each passed the same checks as the first line.',
      hint: 'The tiny grey words at the foot, Training suggestion — not medical advice., are on every card.' },
    { kind: 'look', head: 'Most days there is no card', set: { sug_state: 'kept' },
      text: 'One card a day at most, two in any seven days, never two open at once, none in race week. It reads your morning answers, how hard sessions felt, and the minutes done. It never reads your sleep, resting pulse or HRV. After Keep my plan it leaves that subject alone for days.',
      hint: 'A quiet Today is normal. The grey pill at the foot is there when you need it.' },
    { kind: 'try', head: 'See the other choice', target: 'sug.other',
      text: 'On the practice card, press the small blue word <b>Other choice</b>.',
      until: S => S.sug_other, ok: 'Two more ways to answer the same thing appear, each with its own Take it.',
      robot: [['act', 'sug.other']] },
    { kind: 'try', head: 'Take the suggestion', target: 'sug.take',
      text: 'Press <b>Take it</b> on the first line.',
      until: S => S.sug_state === 'taken', ok: 'The card’s place now reads Changed — with a small Undo, for the rest of the day. Today’s run has become rest (your choice): the change went into your plan like any change you make yourself.',
      robot: [['act', 'sug.take', '0']], real: 'Today › suggestion card' },
    { kind: 'try', head: 'Find it again, and undo it', set: { screen: 'sug.changes', part: 'settings', sug_state: 'taken' }, target: S => S.sheet ? 'sug.undoyes' : 'sug.chundo',
      text: 'A taken suggestion is listed under Changes to the plan with its reason, starting <b>Suggestion:</b>. Press <b>Undo</b>, then <b>Undo</b> again to confirm.',
      until: S => S.sug_undone, ok: 'The row says Undone and the run is back. Undo works only while nobody has changed that session since; then the page says Changed again since.',
      robot: [['act', 'sug.chundo'], ['act', 'sug.undoyes']], real: 'Settings › Your plan › Changes to the plan',
      hint: 'The rule book remembers an undone card as Keep my plan.' },
    { kind: 'try', head: 'Open Not well? and the Stop sign', target: S => S.sheet === 'sug.plate' ? 'sug.stoprow' : 'sug.notwell',
      text: 'At the very foot of Today stands a small grey pill, <b>Not well?</b>. Press it, then press <b>Stop sign</b>.',
      until: S => S.sheet === 'sug.stop' && S.sug_paused, ok: 'Opening the page paused every suggestion at once, as its words say. The page’s words are fixed, and Stop training now. is the only red heading there.',
      robot: [['act', 'sug.notwell'], ['act', 'sug.stoprow']], real: 'Today, the last thing on the page',
      hint: '“Opened by mistake” takes it back, but only on the same day.' },
    { kind: 'look', head: 'The real Stop sign page', shot: 'sug-03-stop',
      text: 'This is the page. Stop training now. is in red, then the signs, then that these need a doctor before you train again, and that you should call 112 if it is strong or does not pass. At the foot of the card: <b>Paused</b>, the button <b>A doctor has seen me</b>, and the grey <b>Opened by mistake</b>.',
      hint: 'The words are fixed. The app adds no advice of its own and reads no watch number.' },
    { kind: 'try', head: 'The only way out of a pause', set: { sheet: 'sug.stop', sug_paused: true }, target: 'sug.doctor',
      text: 'The page says <b>Paused</b>. No number and no waiting ends it. Press <b>A doctor has seen me</b>.',
      until: S => !S.sug_paused, ok: 'The pause is over and cards may come again. While paused, Today has no card and one grey line: Suggestions are paused — Stop sign.',
      robot: [['act', 'sug.doctor']] },
    { kind: 'try', head: 'I’m ill, and the steps back', target: S => S.sheet === 'sug.ill' ? 'sug.yes' : S.sheet === 'sug.plate' ? 'sug.illrow' : 'sug.notwell',
      text: 'A cold never has to read the stop sign. Press <b>Not well?</b>, then <b>I’m ill</b>, and answer <b>Yes</b> to the fever question.',
      until: S => S.sug_ill === 'fever', ok: 'The page gives the first step, Rest, and draws The way back under it: Rest, Two easy days, Week 1 back, Week 2 back, Back on your plan. When it has passed you pick the day in Symptom-free since and press Save.',
      robot: [['act', 'sug.notwell'], ['act', 'sug.illrow'], ['act', 'sug.ill', 'fever']], real: 'Today › Not well? › I’m ill',
      hint: 'No card comes while you are resting. Without fever, a cold above the neck means easy only and shorter until it has gone.' },
    { kind: 'look', head: 'The way back, on Today', shot: 'sug-05-ladder',
      text: 'While you are coming back, <b>THE WAY BACK</b> stands on Today under your session. The step you are on is filled green, a step behind carries the white tick in the green circle, and a step ahead is pale. It only shows what the rule book does; it changes nothing.',
      hint: 'It stays for the week after you are back on your plan.' },
    { kind: 'look', head: 'Something hurts?', shot: 'sug-06-hurts',
      text: 'After you log a session of today or yesterday, its page asks <b>Something hurts?</b> once, under <b>How hard was it?</b>: Calf, Achilles, Knee, Other, Nothing hurts. Calf, Achilles or Knee can bring a card for the next easy run: a row, an easy spin, or rest.',
      hint: 'It is not under Not well?: it sits on the session’s page. The app never says what is wrong.' },
    { kind: 'try', head: 'Go against the rule book', set: { sheet: 'sug.move' }, target: S => S.sug_day === 'wed' ? 'sug.moveday' : 'sug.movedo',
      text: 'Move today’s run to <b>Fri 18 Sep</b>, then press <b>Move the session</b>.',
      until: S => S.sug_moved, ok: 'One calm grey line said Friday is your rest day, and the move was made all the same. The rule book never blocks your own edit, never turns red and never asks a question.',
      robot: [['in', 'sug_day', 'fri'], ['act', 'sug.movedo']], real: 'Session page › Move',
      hint: 'The same line shows on the Change page, and on iPad and Mac when you drag a session to another day.' },
    { kind: 'look', head: 'Settings › Suggestions', shot: 'sug-07-settings-log',
      text: 'The page has one switch, <b>Suggest changes to my plan</b>, four answers as switches, and <b>What was suggested</b>: every card, newest first, with your answer in words (Taken, Kept my plan, No answer, Put away — the plan had changed, Taken, then undone). Cancel leaves it as it was; Save keeps it.',
      hint: 'The cards and your answers stay on the device where you tapped them.', real: 'Settings › Your plan › Suggestions' },
    { kind: 'check', head: 'You leave a card alone', text: 'A card is open on Today and you do not answer it all day. What happens to your plan?',
      answers: ['The suggestion is made for you at midnight', 'Nothing changes; the card closes at the end of the day of its first session and counts as Keep my plan', 'The card stays open until you answer'], right: 1,
      ok: 'Right. The app suggests, you decide: nothing in your plan changes until you press Take it.' },
  ],
});
