/* Chapter 12 — Claude. Settings › Claude: the key, the switch, the meter, the log; Claude among the suggestion's choices;
   "Your week with Claude" on Today; "Ask about your plan"; "Export for Claude". Every word is the app's own (ClaudeSettingsView,
   ClaudeReviewView, ClaudeAskView, SuggestionCard, core ClaudeTrouble / ClaudeReview / ClaudeAsk). All figures and answers are invented. */
const CLA_ARROW = () => icon('right');
const CLA_ILL = /\b(ill|sick|fever|pain|hurt|injur|ache|chest)/i;
const CLA_ANSWER = 'Thursday is the lighter day between the Wednesday run and the long ride on Saturday, so the plan keeps it short and easy. The rule book does not let a suggestion make a session longer. If you want it different, use Move or Change on that session; the app will show one grey line if it breaks a rule, and you can still go on.';
const CLA_DOCTOR = 'That is a question for a doctor. The app’s Stop sign page is under Not well? at the foot of Today.';
const CLA_EXAMPLES = ['Why is Thursday’s ride only 45 minutes?', 'What does this week’s easy week change?', 'Can I move Saturday’s long run to Sunday?'];
const CLA_LINES = ['Most of the planned bike and run minutes were done; the swim was the lightest part.',
  'Mornings were mixed: two Good, two OK, one Tired and two without an answer.',
  'The long ride felt harder than its plan said; the other sessions felt as planned.',
  'One run was missed and one session moved to another day.',
  'Next week starts with a rest day and keeps the same number of sessions.'];
CHAPTER({
  id: 'cla',
  title: 'Claude',
  icon: 'talk',
  needs: 'Nothing. Claude is optional and needs your own Anthropic key; without one the app works by its rules alone.',
  gives: 'Claude may choose among the suggestion’s options, write your week on Sunday and answer a question about your plan. It never changes the plan.',
  start: () => ({ part: 'settings', screen: 'cla.page', cla_key: false, cla_on: false, cla_typed: '', cla_prob: '', cla_card: 'rule',
    cla_touch: false, cla_week: 'before', cla_q: '', cla_items: [], cla_shared: false }),
  screens: {
    /* Settings › Claude, as the real page: a small centred title, what it does, the key, the switch, the month's cost, the log. */
    'cla.page': S => `
      ${K.back('Settings', 'cla.back')}
      <b class="cla-title">Claude</b>
      <div class="k-card k-muted k-small"><p class="cla-line">It picks among the choices the rule book offers and words the reason. It changes nothing; you still tap.</p>
        <p class="cla-line">Nothing else is sent: not your name, notes, session titles, photographs, tests, zones, weight, or the Health and Garmin morning numbers.</p>
        <p class="cla-line">It costs about a dollar a month, never more than 5 US dollars a month. The app stops asking when the month reaches it.</p></div>
      ${S.cla_key ? `<div class="k-card"><b class="k-oktext">Key saved</b><span class="k-muted k-small">••••••••••••</span></div>
        <div><button class="k-btn k-danger" data-act="cla.remove" data-t="cla.remove"><span>Remove the key</span></button></div>`
      : `${K.input('cla_typed', S, { ph: 'Type your Anthropic key', t: 'cla.key' })}
        ${S.cla_prob ? `<span class="k-small k-failtext">${esc(S.cla_prob)}</span>` : ''}
        <div class="k-line">${K.btn('Cancel', 'cla.cancel')}${K.btn('Save', 'cla.save', { main: true, t: 'cla.save' })}</div>`}
      <div class="k-card">${K.switch(S.cla_on, 'Let Claude choose among the suggestions', 'cla.on', { t: 'cla.on', off: !S.cla_key })}
        ${S.cla_key ? '' : '<span class="k-muted k-small">Needs a key first.</span>'}</div>
      <b class="k-small" data-t="cla.month">${S.cla_key ? 'This month: 0.12 US dollars of 5.00 · 6 answers' : 'This month: 0.00 US dollars of 5.00 · 0 answers'}</b>
      <span class="k-cap">What Claude answered</span>
      ${S.cla_key ? `<div class="k-card"><b class="k-small">16 Sep, 07:12 · Chose: Mon swim: no pool while away ${CLA_ARROW()} easy run 35 min</b>
        <span class="k-small">Why: you are away until 19 Sep without a pool; an easy run keeps the day aerobic.</span><span class="k-muted k-small">0.02 US dollars</span></div>`
      : '<span class="k-muted k-small">Nothing yet.</span>'}`,
    /* The same page further down: the export row. */
    'cla.export': S => `
      ${K.back('Settings', 'cla.back')}
      <b class="cla-title">Claude</b>
      <span class="k-cap">Export for Claude</span>
      <div class="k-card"><span class="k-muted k-small">Your season as plain text: the phases, your tests and zones, the last 8 weeks and the next 4. Paste it into the Claude app to talk it over. This sends nothing by itself.</span>
        <div>${K.btn('Share the plan as text', 'cla.share', { t: 'cla.share', icon: 'share' })}</div></div>
      ${S.cla_shared ? `<div class="k-band k-ok">${icon('info')}<span>The usual Send menu opens (Messages, Mail, AirDrop). The text goes nowhere until you choose one.</span></div>` : ''}
      <span class="k-muted k-small">Your key stays on this device only.</span>`,
    /* The suggestion card on Today, with the choices of the rule book. */
    'cla.card': S => `
      <h1 class="k-h1">Today</h1>
      <div class="k-card">
        <b>Mon swim: no pool while away ${CLA_ARROW()} easy run 35 min instead</b>
        <span class="k-muted k-small">Why: you are away until 19 Sep without a pool; an easy run keeps the day aerobic.</span>
        ${S.cla_card === 'picked' ? '<span class="k-muted k-small" data-t="cla.claude">Picked by Claude from the rule book’s choices</span>' : ''}
        <div class="k-line">${K.btn('Take it', 'cla.take', { t: 'cla.take' }).replace('class="k-btn', 'class="cla-blue k-btn')}${K.btn('Keep my plan', 'cla.take').replace('class="k-btn', 'class="cla-blue k-btn')}</div>
        ${S.cla_touch ? `<div class="cla-other"><span class="k-small">Mon swim: no pool while away ${CLA_ARROW()} easy bike 40 min instead</span><b class="k-small" style="color:var(--i-plan)">Take it</b></div>`
          : `<button class="cla-blueword" data-act="cla.other" data-t="cla.other">Other choice</button>`}
        <span class="k-muted k-small">Training suggestion — not medical advice.</span></div>
      ${S.cla_touch ? '<span class="k-muted k-small">You touched the card. A late answer from Claude would now be thrown away.</span>' : ''}`,
    /* Today, Sunday evening: the week card. */
    'cla.week': S => `
      <h1 class="k-h1">Today</h1>
      <div class="k-card" style="padding:0;gap:0;overflow:hidden">
        ${S.cla_week === 'written'
          ? `${K.hero({ cap: 'YOUR WEEK WITH CLAUDE', title: 'What made the long ride feel harder than planned?', t: 'cla.head' })}
            <div class="k-col" style="padding:10px 12px">${CLA_LINES.map(l => `<span class="k-small">${esc(l)}</span>`).join('')}
            <span class="k-muted k-small">Written by Claude from this week’s numbers. Kept under Settings ${CLA_ARROW()} Claude.</span></div>`
          : `${K.hero({ cap: 'YOUR WEEK WITH CLAUDE', lines: ['Five short lines about the week, and one question to think about.'], t: 'cla.head' })}
            <div class="k-col" style="padding:10px 12px"><span class="k-muted k-small">This week’s training numbers and your answers to the two questions — no names, no notes. It counts toward the 5 US dollars a month.</span>
            <button class="k-btn k-main k-full" data-act="cla.write" data-t="cla.write"><span>Write my week</span></button></div>`}</div>`,
    /* Ask about your plan. */
    'cla.ask': S => `
      <div class="k-top"><span class="k-sp"></span><b class="cla-title">Ask about your plan</b><span class="k-sp"></span>${K.btn('Done', 'cla.done')}</div>
      ${K.hero({ cap: 'ASK ABOUT YOUR PLAN', lines: ['Claude explains the plan and the rule book. It never changes anything; to change something you use Move, Change or the suggestion card.'] })}
      <span class="k-muted k-small">Your question, this week and the next two weeks of the plan (day, sport, minutes, effort), the phase, the rule book’s limits in words, and the names of your zones — no figures, no names, no notes. It counts toward the 5 US dollars a month.</span>
      ${K.input('cla_q', S, { ph: CLA_EXAMPLES[0], t: 'cla.field' })}
      <div class="k-col" style="gap:5px">${CLA_EXAMPLES.map((e, i) => K.chip(e, { act: 'cla.ex', arg: i, t: 'cla.ex:' + i }).replace('class="k-chip', 'class="cla-chip k-chip')).join('')}</div>
      <button class="k-btn k-main k-full" data-act="cla.send" data-t="cla.send"${S.cla_q.trim() ? '' : ' disabled'}><span>Ask</span></button>
      ${S.cla_items.length ? `<span class="k-cap">Your last questions</span>
        ${S.cla_items.map((it, i) => `<div class="k-card" data-t="cla.answer:${i}"><span class="k-cap" style="color:var(--i-sessions)">You asked</span><b class="k-small">${esc(it.q)}</b>
          <span class="k-small">${esc(it.a)}</span>${it.local ? '<span class="k-muted k-small">Answered by the app. Nothing was sent.</span>' : ''}</div>`).join('')}
        <div>${K.btn('Clear', 'cla.clear', { danger: true, t: 'cla.clear' })}</div>` : ''}`,
  },
  sheets: {
    'cla.confirm': S => `<h3>Remove the key?</h3>
      <span>Claude stops choosing. The suggestions come from the rule book alone. You can type a key again at any time.</span>
      <div class="k-foot">${K.btn('Keep it', 'sheet.close')}${K.btn('Remove the key', 'cla.confirm', { danger: true, t: 'cla.confirm' })}</div>`,
  },
  actions: {
    'cla.back'() { toast('Settings has its own chapter.'); },
    'cla.cancel'(a, S) { S.cla_typed = ''; S.cla_prob = ''; toast('Cancel clears the field and leaves the page.'); },
    'in'(key, S) { if (key === 'cla_typed') S.cla_prob = ''; },
    'cla.save'(a, S) {
      const key = String(S.cla_typed || '').replace(/\s/g, '');
      if (!key) { S.cla_prob = 'Nothing typed yet. Type your Anthropic key into the field first.'; return; }
      S.cla_key = true; S.cla_typed = ''; S.cla_prob = '';
    },
    'cla.on'(a, S) { if (S.cla_key) S.cla_on = !S.cla_on; },
    'cla.remove'(a, S) { S.sheet = 'cla.confirm'; },
    'cla.confirm'(a, S) { S.cla_key = false; S.cla_on = false; S.sheet = null; },
    'cla.take'() { toast('Taking or keeping a suggestion has its own chapter.'); },
    'cla.other'(a, S) { S.cla_touch = true; },
    'cla.write'(a, S) { S.cla_week = 'written'; },
    'cla.ex'(a, S) { S.cla_q = CLA_EXAMPLES[Number(a)] || ''; },
    'cla.send'(a, S) {
      const q = S.cla_q.trim(); if (!q) return;
      const local = CLA_ILL.test(q);
      S.cla_items.unshift({ q, a: local ? CLA_DOCTOR : CLA_ANSWER, local });
      S.cla_items = S.cla_items.slice(0, 5); S.cla_q = '';
    },
    'cla.clear'(a, S) { S.cla_items = []; },
    'cla.done'() { toast('Done closes the page.'); },
    'cla.share'(a, S) { S.cla_shared = true; },
  },
  steps: [
    { kind: 'look', head: 'Claude is built in, and optional', shot: 'cla-02-page-nokey',
      text: 'Settings › Claude. Without your own Anthropic key nothing happens: the switch says <b>Needs a key first.</b> and the app works by its rules alone. The page says first what would be sent, and the key stays on this device.',
      hint: 'Claude may only choose among options the rule book already made, or write words. It never changes your plan.', real: 'Settings › Claude' },
    { kind: 'try', head: 'Save with nothing typed', text: 'Press <b>Save</b> with the field empty.', target: 'cla.save',
      until: S => !!S.cla_prob, ok: 'A red line says what is missing: Nothing typed yet. Nothing is kept.', robot: [['act', 'cla.save']], real: 'Settings › Claude' },
    { kind: 'try', head: 'Type a key and save it', text: 'Type any key (this is only practice), then press <b>Save</b>.',
      target: S => !S.cla_typed ? 'cla.key' : 'cla.save', until: S => S.cla_key,
      ok: 'The page says Key saved with a row of dots. The real app first asks Anthropic with one tiny test message that holds nothing of yours, and keeps a key only if it is accepted.',
      robot: [['in', 'cla_typed', 'practice-key'], ['act', 'cla.save']] },
    { kind: 'try', head: 'Switch Claude on', text: 'Press the switch <b>Let Claude choose among the suggestions</b>.', set: { cla_key: true }, target: 'cla.on',
      until: S => S.cla_on, ok: 'Claude is on. Under the switch the page counts the month: This month: 0.12 US dollars of 5.00 · 6 answers (invented). It stops asking at 5.00.',
      robot: [['act', 'cla.on']] },
    { kind: 'look', head: 'The key, the cost and the log', shot: 'cla-01-page-key',
      text: 'With a key saved: <b>Key saved</b> in green, <b>Remove the key</b>, the switch, the month line and the list <b>What Claude answered</b>. It shows the last 30 answers: the time, what Claude chose, the reason and the cost. Never your key and never your plan.',
      hint: 'Further down: Your weeks with Claude, Ask about your plan, and Export for Claude.' },
    { kind: 'try', head: 'Take the key away', text: 'Press <b>Remove the key</b>, then <b>Remove the key</b> again to confirm. <b>Keep it</b> would leave everything as it is.',
      set: { cla_key: true, cla_on: true }, target: S => S.sheet ? 'cla.confirm' : 'cla.remove', until: S => !S.cla_key,
      ok: 'The key is gone and the switch is off. The suggestions come from the rule book alone; you can type a key again at any time.',
      robot: [['act', 'cla.remove'], ['act', 'cla.confirm']] },
    { kind: 'look', head: 'When Claude chooses a suggestion', shot: 'cla-03-card-picked',
      text: 'The rule book alone decides that a card exists and what its choices are. Claude may take the first place for another choice and word the reason. The grey line under the reason says so: <b>Picked by Claude from the rule book\u2019s choices</b>. The buttons stay Take it and Keep my plan.',
      hint: 'The card is shown at once. Claude has one try of at most 20 seconds and the card never waits for it.', real: 'Today, the suggestion card' },
    { kind: 'try', head: 'Touch the card', text: 'Press <b>Other choice</b>.', set: { screen: 'cla.card', part: 'today' }, target: 'cla.other',
      until: S => S.cla_touch, ok: 'The other choices show. From now on a late answer from Claude is thrown away, so the words never change under your finger.',
      robot: [['act', 'cla.other']] },
    { kind: 'look', head: 'When Claude cannot choose', shot: 'cla-04-cannot-choose',
      text: 'If Anthropic refuses, the card still works and says so in one grey line under the reason: <b>Claude could not choose: Anthropic no longer accepts your key. Settings \u2192 Claude.</b> The same goes for no credit left and for the month’s 5 US dollars used. Settings › Claude says it too, and the row reads <b>On, but not choosing</b>.',
      hint: 'It clears by itself at the next answer that works, or when you type a new key.' },
    { kind: 'try', head: 'Ask Claude for your week', text: 'On Sunday evening and Monday, Today shows a green card. Press <b>Write my week</b>.',
      set: { screen: 'cla.week', part: 'today', cla_key: true, cla_on: true }, target: 'cla.write', until: S => S.cla_week === 'written',
      ok: 'Five short lines and one question appear. The card says Written by Claude from this week’s numbers. The week is kept on this device under Settings › Claude, one for each week.',
      robot: [['act', 'cla.write']], real: 'Today, Sunday 17:00 to the end of Monday' },
    { kind: 'look', head: 'Your week, in Claude\u2019s words', shot: 'cla-06-week-written',
      text: 'The green card on Today after <b>Write my week</b>: the question in the green head, then five short lines, and a grey line saying it was written by Claude from this week\u2019s numbers and kept under Settings \u203a Claude. Above it stand today\u2019s session card and the week bars.',
      hint: 'The card shows only on Sunday evening and Monday.' },
    { kind: 'look', head: 'Where the Ask button is', shot: 'cla-09-ask-button',
      text: 'On Sessions, in the row of small buttons under the heading: <b>Print</b>, <b>+ Session</b> and <b>Ask about your plan</b>. The same button is on the wide Plan page, and as a row in Settings \u203a Claude. It shows only while Claude is on.',
      real: 'Sessions' },
    { kind: 'try', head: 'Ask about your plan', text: 'Press the first example question, then <b>Ask</b>.',
      set: { screen: 'cla.ask', part: 'sessions', cla_key: true, cla_on: true }, target: S => !S.cla_q ? 'cla.ex:0' : 'cla.send',
      until: S => S.cla_items.some(i => !i.local), ok: 'The answer shows under YOU ASKED. Claude explains only; to change something you use Move, Change or the suggestion card. Here the answer is a fixed sample.',
      robot: [['act', 'cla.ex', 0], ['act', 'cla.send']], real: 'Sessions › Ask about your plan, and Settings › Claude' },
    { kind: 'look', head: 'A question with its answer', shot: 'cla-08-ask-answer',
      text: 'The Ask page: a blue head card, what is sent, the field with three example questions to tap, the <b>Ask</b> button, then under <b>Your last questions</b> a tile YOU ASKED with the question and Claude\u2019s answer, and a red <b>Clear</b>. <b>Done</b> is at the top right.',
      },
    { kind: 'try', head: 'A question about being ill', text: 'Type <b>Is it fine to run when my knee hurts?</b> and press <b>Ask</b>.',
      set: { screen: 'cla.ask', part: 'sessions', cla_key: true, cla_on: true }, target: S => !S.cla_q ? 'cla.field' : 'cla.send',
      until: S => S.cla_items.some(i => i.local), ok: 'The app answers itself: a question for a doctor, and where the Stop sign page is. Nothing was sent, it costs nothing and it is not in the log.',
      robot: [['in', 'cla_q', 'Is it fine to run when my knee hurts?'], ['act', 'cla.send']] },
    { kind: 'try', head: 'Export for Claude', text: 'Press <b>Share the plan as text</b>.', set: { screen: 'cla.export', cla_key: false }, target: 'cla.share',
      until: S => S.cla_shared, ok: 'Your season as plain text goes to the Send menu. The app sends nothing by itself, and this works with no key.',
      robot: [['act', 'cla.share']], real: 'Settings › Claude › Export for Claude' },
    { kind: 'check', head: 'What leaves your iPhone?', text: 'You press Write my week. What does Anthropic get?',
      answers: ['Your name, notes and session titles', 'This week’s sessions and minutes, how hard they felt and your morning words, with your key, and nothing else of you', 'Your Garmin and Health numbers'], right: 1,
      ok: 'Right. Names, notes, titles, photographs, tests, zones, weight and the Garmin and Health numbers never go. An answer that holds a number that was not sent is not shown; Claude is still paid for it, so it is counted.' },
  ],
});
