/* Chapter 8 — Progress, first half: the head card, Load, the season letters, Month in review, Your bests.
   All figures are invented. The words are the app's own (ProgressView, LoadViews, MonthReview, PersonalBests). */
const PRO_WEEKS = [['27 Jul', 1500, 0], ['3 Aug', 1800, 0], ['10', 1200, 400], ['17', 2100, 0], ['24', 1600, 0], ['31', 1900, 500], ['7 Sep', 2000, 0], ['now', 600, 0]];
const PRO_MONTHS = ['August 2026', 'July 2026', 'June 2026'];
const proFig = n => n == null ? '—' : String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
/* The weeks as the Load card draws them: the Health workout, once he gave it a number, adds to this week outside the plan. */
function proWeeks(S) { return PRO_WEEKS.map((w, i) => ({ l: w[0], a: w[1], o: w[2] + (i === 7 && S.pro_hard ? 90 * S.pro_hard : 0) })); }
CHAPTER({
  id: 'pro',
  title: 'Progress',
  icon: 'progress',
  needs: 'Nothing: Progress only shows. It is worked out from your sessions each time you open it. The Health workout questions are the one thing you can answer.',
  gives: 'You can read every figure on the top half of Progress: what it counts and what it does not.',
  start: () => ({ part: 'progress', screen: 'pro.top', pro_race: false, pro_hw: true, pro_ask: false, pro_hard: 0,
    pro_month: 0, pro_list: false, pro_tab: 'month' }),
  screens: {
    /* The head card: the road to the race. */
    'pro.top': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card pro-road" data-t="pro.head">
        <div class="k-top"><span class="pro-clock"><b>4</b><span class="k-muted">days to go</span></span><span class="k-sp"></span>
          <button class="pro-racebtn" data-act="pro.race" data-t="pro.race">${icon('race')}<span>The race</span></button></div>
        ${S.pro_race ? `<span>Sprint triathlon (invented)</span><span class="pro-link">Open your race page ›</span>` : ''}
        <span class="k-muted">Sunday 20 September 2026</span>
        <div class="pro-phases"><i class="pro-p1" style="flex:5"></i><i class="pro-p2" style="flex:5"></i><i class="pro-p3" style="flex:3"></i><i class="pro-p4" style="flex:2"><u></u></i></div>
        <span class="k-muted k-small">You are in <b>Taper</b></span>
        <div class="k-grid3" data-t="pro.figs">
          <div class="k-col"><b class="pro-n">10</b><span class="k-muted k-small">done so far, of 11 in the plan</span></div>
          <div class="k-col"><b class="pro-n">6h 17m</b><span class="k-muted k-small">banked of 7h 00m due</span></div>
          <div class="k-col"><b class="pro-n">7h 00m</b><span class="k-muted k-small">the whole build</span></div></div>
      </div>
      <div class="k-card"><b class="k-h2">So far</b><span class="k-small">Of the 11 sessions due up to yesterday, 10 were done.</span>
        <div class="k-grid3"><div class="k-col"><b class="pro-n">10</b><span class="k-muted k-small">done</span></div>
          <div class="k-col"><b class="pro-n">1</b><span class="k-muted k-small">missed</span></div>
          <div class="k-col"><b class="pro-n">0</b><span class="k-muted k-small">unanswered</span></div></div></div>`,
    /* The Load card. */
    'pro.load': S => {
      const w = proWeeks(S), tot = x => x.a + x.o, tallest = Math.max(...w.map(tot));
      const usual = w.slice(3, 7).reduce((s, x) => s + tot(x), 0) / 4;
      const unanswered = S.pro_hard ? 8 : 9;
      return `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card"><b class="k-h2">Load</b>
        <div class="k-grid3" data-t="pro.loadfigs">
          <div class="k-col"><b class="pro-n" data-t="pro.thisweek">${proFig(tot(w[7]))}</b><span class="k-muted k-small">this week so far</span></div>
          <div class="k-col"><b class="pro-n">${proFig(tot(w[6]))}</b><span class="k-muted k-small">last week</span></div>
          <div class="k-col"><b class="pro-n">${proFig(usual)}</b><span class="k-muted k-small">usual week</span></div></div>
        <div class="pro-bars" data-t="pro.bars">${w.map(x => `<div class="pro-bcol"><div class="pro-bstack">
          ${x.o ? `<i class="pro-dot" style="height:${Math.max(5, 70 * x.o / tallest)}px"></i>` : ''}<i class="pro-solid" style="height:${Math.max(5, 70 * x.a / tallest)}px"></i></div>
          <span class="k-muted pro-lab">${x.l}</span></div>`).join('')}</div>
        <div class="k-line k-small k-muted" data-t="pro.key"><span class="k-line"><i class="pro-solid pro-sw"></i>In the plan</span>
          <span class="k-line"><i class="pro-dot pro-sw"></i>Outside the plan (hikes, gym)</span></div>
        <span class="k-muted k-small">Load = minutes × how hard (1–10). A 60-minute run at 5 counts 300. Hikes and gym sessions come from Apple Health. ${unanswered} of 21 had no number from you: counted from the plan's zone, or as 3 (easy).</span>
        ${S.pro_hw && !S.pro_hard ? `<div class="k-col"><div class="k-line"><span class="k-small">Mon 14 Sep · Hike · 1h 30m</span><span class="k-sp"></span>
          ${S.pro_ask ? '' : K.btn('How hard?', 'pro.ask', { t: 'pro.how' })}</div>
          ${S.pro_ask ? `<div class="pro-effort" data-t="pro.effort">${[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => `<button data-act="pro.hard" data-arg="${n}" data-t="pro.hard:${n}">${n}</button>`).join('')}</div>
            <div class="k-line k-small k-muted"><span>1 very easy</span><span class="k-sp"></span><span>7 hard</span><span class="k-sp"></span><span>10 all out</span></div>` : ''}</div>` : ''}
        ${S.pro_hard ? `<span class="k-small k-oktext">Your ${S.pro_hard} is kept. The hike now counts ${proFig(90 * S.pro_hard)} in this week's dotted bar.</span>` : ''}
      </div>`;
    },
    /* The season bars with their letters (iPad and Mac, the Plan page). */
    'pro.season': S => `
      <h1 class="k-h1">Plan</h1>
      <div class="k-card"><div class="pro-season" data-t="pro.sbars">${[['', 5], ['', 6], ['', 6], ['E', 3], ['', 6], ['', 7], ['E', 4], ['T', 3], ['', 5]].map(([l, h]) =>
        `<div class="pro-scol">${l ? `<b class="pro-sl">${l}</b>` : '<b class="pro-sl">&nbsp;</b>'}<i style="height:${h * 9}px"></i></div>`).join('')}</div>
        <span class="k-muted k-small" data-t="pro.skey">E = easy week · T = test week · Tap a bar to see its week</span></div>`,
    /* The cards between the head card and Load, and below Time in zones, as the code words them. */
    'pro.trend': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card" data-t="pro.trendcard"><b class="k-h2">Is it working?</b>
        <span class="k-small">How far you travel per heartbeat, then against now. Going faster at the same heart rate moves it; so does the same speed at a lower one. Both are fitness.</span>
        <b style="color:var(--ink-run)">Runs</b>
        <div class="k-line"><span class="k-col"><span class="k-muted k-small">then</span><b class="pro-n">6:00 /km</b><span class="k-muted k-small">at 140 bpm</span></span>
          <b class="k-oktext" style="font-size:22px">${icon('up')}</b>
          <span class="k-col"><span class="k-muted k-small">now</span><b class="pro-n">5:46 /km</b><span class="k-muted k-small">at 140 bpm</span></span></div>
        <b class="k-small">+4% · Better — you are covering more ground for the same heartbeats.</b>
        <span class="k-muted k-small">10 logged easy sessions, the first 5 against the last 5.</span>
        <span class="k-muted k-small">Heart rate answers to heat, sleep, coffee and stress as well as to training, so this is worth reading over months rather than weeks.</span></div>`,
    'pro.form': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card" data-t="pro.formcard"><b class="k-h2">Fitness and freshness</b>
        <span class="k-small">Each session costs something — an hour at your threshold heart rate is 100, and an easy hour far less. Six weeks of that is fitness; the last week is fatigue.</span>
        <div class="k-grid3"><div class="k-col"><b class="pro-n">42</b><span class="k-muted k-small">fitness</span></div>
          <div class="k-col"><b class="pro-n">55</b><span class="k-muted k-small">fatigue of the last week</span></div>
          <div class="k-col"><b class="pro-n">-13</b><span class="k-muted k-small">building</span></div></div>
        <div class="k-line k-small k-muted"><span class="k-line"><i class="pro-solid pro-sw"></i>fitness</span><span class="k-line"><i class="pro-dot pro-sw"></i>fatigue</span></div>
        <span class="k-muted k-small">Under zero means you are carrying fatigue, which is where the work gets done; over zero is rested.</span></div>`,
    'pro.weeks': S => {
      const w = [[3, 4], [4, 4], [3.5, 4.5], [5, 5], [2, 5], [4.5, 5], [5.5, 5.5], [4, 5], [5, 5.5], [5, 5.5], [3, 5], [5.5, 6]];
      return `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card" data-t="pro.weekscard"><b class="k-h2">Twelve weeks</b>
        <span class="k-small">51h 00m of 60h 30m asked for over the last twelve finished weeks — 84%.</span>
        <div class="pro-bars">${w.map(([a, p]) => `<div class="pro-bcol"><div class="pro-bstack" style="position:relative"><i class="pro-solid" style="height:${a * 11}px;opacity:.6"></i><u style="position:absolute;left:0;right:0;bottom:${p * 11}px;height:2px;background:var(--win-fg)"></u></div></div>`).join('')}</div>
        <span class="k-muted k-small">Each column is a week with training in it: the hours you did, with a line across it where the plan asked you to reach. Only weeks that are over are counted.</span></div>`;
    },
    'pro.mix': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card" data-t="pro.mixcard"><b class="k-h2">Where the hours went</b>
        <span class="k-small">The same twelve weeks, by sport. Hours rather than sessions.</span>
        ${[['Run', 'run', 38, '19h 20m', 'plan 33% +5', 1], ['Bike', 'bike', 34, '17h 20m', 'plan 35%', 0], ['Swim', 'swim', 18, '9h 10m', 'plan 17%', 0], ['Strength', 'strength', 10, '5h 10m', 'plan 15% -5', 1]].map(([n, k, pc, h, pl, red]) =>
          `<div class="k-line"><i class="pro-sw" style="background:var(--sp-${k});border-radius:50%;width:10px;height:10px"></i><span style="width:62px">${n}</span><b style="width:36px">${pc}%</b><span class="k-muted" style="width:62px">${h}</span><span class="k-small ${red ? 'k-failtext' : 'k-muted'}">${pl}</span></div>`).join('')}
        <span class="k-muted k-small">Run and Strength sit five points or more from the share the plan asked for. That is worth knowing rather than worth worrying about: a block often leans on purpose.</span></div>`,
    'pro.consist': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card" data-t="pro.consistcard"><b class="k-h2">Consistency</b><span class="k-small">4 in a row right now.</span>
        <div class="k-grid3"><div class="k-col"><b class="pro-n">4</b><span class="k-muted k-small">in a row now</span></div>
          <div class="k-col"><b class="pro-n">9</b><span class="k-muted k-small">most in a row</span></div>
          <div class="k-col"><b class="pro-n">92%</b><span class="k-muted k-small">of those answered</span></div></div></div>`,
    'pro.sport': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card" data-t="pro.sportcard"><b class="k-h2">Which sport runs behind</b><span class="k-small">Swim is furthest behind, at 75% of its sessions kept.</span>
        ${[['Swim', 'swim', 75, '6/8'], ['Bike', 'bike', 92, '11/12'], ['Run', 'run', 100, '14/14'], ['Strength', 'strength', 88, '7/8']].map(([n, k, pc, c]) =>
          `<div class="k-line"><i class="pro-sw" style="background:var(--sp-${k});border-radius:50%;width:10px;height:10px"></i><span style="width:62px">${n}</span><b style="width:40px">${pc}%</b><span class="k-muted k-small" style="width:40px">${c}</span><span class="pro-slim" style="flex:1"><i style="width:100%;background:var(--card-2)"></i><i style="width:${pc}%;background:var(--sp-${k})"></i></span></div>`).join('')}</div>`,
    'pro.moves': S => `
      <h1 class="k-h1">Progress</h1>
      <div class="k-card" data-t="pro.movescard"><b class="k-h2">Missed, or moved</b><span class="k-small">2 sessions were moved rather than lost, against 1 missed outright.</span>
        <div class="k-grid3"><div class="k-col"><b class="pro-n">2</b><span class="k-muted k-small">moved and kept</span></div>
          <div class="k-col"><b class="pro-n">1</b><span class="k-muted k-small">missed</span></div></div>
        <span class="k-muted k-small">Counted from this app's own list of moves since Mon 3 Aug, kept on this device only.</span></div>`,
    /* Month in review */
    'pro.month': S => {
      const m = PRO_MONTHS[S.pro_month], newest = S.pro_month === 0;
      return `
      <div class="pro-head" data-t="pro.mhead"><span class="pro-cap">${newest ? 'MONTH IN REVIEW' : 'AN EARLIER MONTH'}</span><b class="pro-month">${m}</b></div>
      <div class="pro-grid">
        <div class="pro-tile" data-t="pro.hours"><span class="pro-tn">HOURS</span><b class="pro-big">14h 20m</b><span class="k-muted k-small">done of 16h 40m planned</span></div>
        <div class="pro-tile"><span class="pro-tn">SESSIONS</span><b class="pro-big">7</b><span class="k-muted k-small">done of 8 planned</span></div>
        <div class="pro-tile" data-t="pro.followed"><span class="pro-tn">PLAN FOLLOWED</span><b class="pro-big">88 <small>%</small></b><span class="k-muted k-small">7 of 8 sessions, as on the Plan page</span></div>
        <div class="pro-tile"><span class="pro-tn">LONGEST SESSION</span><b class="pro-big">2h 30m</b><span class="k-muted k-small">Bike · Wed 9 Sep</span></div></div>
      <div class="pro-tile"><span class="pro-tn">HOURS PER SPORT</span>
        ${[['Swim', 'swim', 2.5, 3], ['Bike', 'bike', 6.5, 7.5], ['Run', 'run', 5.3, 6.2]].map(([n, k, d, p]) => `<div class="k-col" style="gap:2px"><span><b>${n}</b> <span class="k-muted k-small">${dur(d * 60)} of ${dur(p * 60)}</span></span>
          <span class="pro-slim"><i style="width:${100 * p / 7.5}%;background:var(--sp-${k});opacity:.25"></i><i style="width:${100 * d / 7.5}%;background:var(--sp-${k})"></i></span></div>`).join('')}</div>
      <div class="pro-tile" data-t="pro.felt"><span class="pro-tn">HOW YOU FELT</span>
        <span class="k-line"><span>Bad <b>0</b></span><span>Tired <b>1</b></span><span>OK <b>3</b></span><span>Good <b>4</b></span><span>Great <b>1</b></span></span>
        <span class="k-muted k-small">mornings answered, by word</span></div>
      <span class="k-muted k-small" data-t="pro.closing">7 of 8 sessions done, 14h 20m of 16h 40m planned. Longest: Bike, Wed 9 Sep, 2h 30m.</span>
      <div class="k-line"><button class="pro-pdf" data-act="pro.note" data-t="pro.pdf"><span>Report as PDF</span>${icon('share')}</button>
        <button class="pro-earlier" data-act="pro.earlier" data-t="pro.earlier">${S.pro_list ? 'Hide months' : 'Earlier months'}</button></div>
      ${S.pro_list ? `<div class="pro-list" data-t="pro.months">${PRO_MONTHS.map((x, i) => `<button data-act="pro.pick" data-arg="${i}" data-t="pro.pick:${i}"><span ${i === S.pro_month ? 'style="font-weight:700"' : ''}>${x}</span></button>`).join('')}</div>` : ''}`;
    },
    /* Your bests */
    'pro.bests': S => `
      <b class="pro-h" style="color:var(--pt)">Your bests</b>
      <div class="pro-grid">
        <div class="pro-tile" data-t="pro.ride"><span class="pro-tn">LONGEST RIDE</span><span class="k-line"><b class="pro-big">2h 30m</b><b class="k-small">62.4 km</b></span><span class="k-muted k-small">Wed 9 Sep</span>
          <span class="k-muted k-small">Farthest: 64.0 km, Sat 29 Aug</span></div>
        <div class="pro-tile"><span class="pro-tn">LONGEST RUN</span><span class="k-line"><b class="pro-big">1h 10m</b><b class="k-small">12 km</b></span><span class="k-muted k-small">Sun 6 Sep</span></div>
        <div class="pro-tile"><span class="pro-tn">LONGEST SWIM</span><span class="k-line"><b class="pro-big">45m</b><b class="k-small">1,800 m</b></span><span class="k-muted k-small">Tue 1 Sep</span></div>
        <div class="pro-tile" data-t="pro.week"><span class="pro-tn">BIGGEST WEEK</span><b class="pro-big">6h 40m</b><span class="k-muted k-small">Week of Mon 24 Aug</span></div>
        <div class="pro-tile" data-t="pro.row"><span class="pro-tn">LONGEST ROW OF WEEKS</span><b class="pro-big">3 <small>weeks</small></b><span class="k-muted k-small">Ending the week of Mon 31 Aug</span></div></div>`
  },
  actions: {
    'pro.race'(a, S) { S.pro_race = !S.pro_race; },
    'pro.ask'(a, S) { S.pro_ask = true; },
    'pro.hard'(a, S) { S.pro_hard = Number(a); S.pro_ask = false; },
    'pro.earlier'(a, S) { S.pro_list = !S.pro_list; },
    'pro.pick'(a, S) { S.pro_month = Number(a); S.pro_list = false; },
    'pro.note'() { toast('The report has its own chapter, the next one.'); },
  },
  steps: [
    { kind: 'look', head: 'The Progress tab', shot: 'pro-01-top', text: 'Progress only shows: it suggests nothing and changes nothing in the plan. Nothing on it is stored in the plan; every figure is worked out from your sessions each time it opens. At the top, the head card (<b>4 days to go</b>), then <b>Is it working?</b>, then <b>Load</b>. The next chapter reads tests, zones and steady weeks.',
      real: 'the Progress tab (purple)' },
    { kind: 'look', head: 'The head card: the road to the race', target: 'pro.head', text: 'The big number is the time to the race: weeks to go, or days to go from 21 days out. Under it, the day of the race, then the phases of your build as one bar, with a thin green line for today. The words under the bar say which phase you are in.' },
    { kind: 'try', head: 'Ask what the race is', target: 'pro.race', text: 'Press <b>The race</b>, the button with the flag.', until: S => S.pro_race,
      ok: 'The race’s own words open, and <b>Open your race page ›</b> takes you to the race page. It has its own chapter.', robot: [['act', 'pro.race']] },
    { kind: 'look', head: 'The three figures under the bar', target: 'pro.figs',
      text: 'Left: sessions done so far, of all in the plan. Middle: time you did, against the time the plan asked for up to now. Right: every planned hour up to the race. A red line appears only when sessions behind you were never recorded. The card So far, lower down, counts done, missed and unanswered.' },
    { kind: 'look', head: 'Is it working?', set: { screen: 'pro.trend' }, target: 'pro.trendcard',
      text: 'This card compares the first half of a sport’s logged sessions with the last half (easy ones, effort 5 or less, when there are 8 of them): how far you travel per heartbeat. An arrow up is better, down is a little lower, across is steady. Until 8 sessions of a sport carry a distance, a time and a heart rate, it says there is not enough yet.' },
    { kind: 'look', head: 'Fitness and freshness', set: { screen: 'pro.form' }, target: 'pro.formcard',
      text: 'Each session is turned into what it cost, so an easy hour counts far less than an hour at threshold. Fitness is six weeks of that, fatigue is the last week, and the third figure is the difference: under zero you are carrying work, over zero you are rested.',
      hint: 'The words under the third figure are deep in it, building, holding, fresh or very fresh. It describes; it advises nothing.' },
    { kind: 'look', head: 'The Load card', shot: 'pro-02-load',
      text: 'Load is minutes times how hard, 1 to 10: a 60-minute run at 5 counts 300. Figures: this week so far (467), last week and your usual week. Eight weekly bars, the last <b>now</b>: solid is the plan, dotted is outside it, like a hike. The last line says how many had no number from you.',
      hint: 'Without a number from you, a session counts by the plan’s zone (Z1 2, Z2 3, Z3 5, Z4 7, Z5 9), and with no zone it counts 3, easy.' },
    { kind: 'try', head: 'Give a hike its number', set: { screen: 'pro.load' }, target: S => S.pro_ask ? 'pro.effort' : 'pro.how',
      text: 'Under the card a Health workout has no number yet. Press <b>How hard?</b>, then press <b>6</b>.', until: S => S.pro_hard === 6,
      ok: 'Your 6 is kept. The hike counts 90 × 6 = 540 in this week’s dotted bar, and the line above says one fewer was guessed.', robot: [['act', 'pro.ask'], ['act', 'pro.hard', '6']] },
    { kind: 'look', head: 'Time in zones', shot: 'tst-04-zones-card',
      text: 'Under Load, <b>Time in zones · this week</b>: Z1 to Z5 with the minutes beside each name, and last week in words. A grey line says what the plan asked for, only when this week’s sessions name zones. The minutes are the pulse zones as Garmin counted them, and the card shows only when a Garmin key is saved and Garmin has sent them.' },
    { kind: 'look', head: 'Twelve weeks', set: { screen: 'pro.weeks' }, target: 'pro.weekscard',
      text: 'Each purple column is the hours you did in a week; the dark line across it is the hours the plan asked for. The sentence at the top is the total, as a percentage. Only weeks that are over count, so this week never shows its remaining sessions as hours missed.' },
    { kind: 'look', head: 'Where the hours went', shot: 'pro-02-load',
      text: 'Lower on the same picture: the hours of the twelve weeks by sport, as one coloured bar and a row each. Beside each name: its share, its time, and the share the plan asked for. A red figure like +5 would mark a sport five points or more away; here the line says the balance is within five points on every sport.' },
    { kind: 'look', head: 'Consistency', set: { screen: 'pro.consist' }, target: 'pro.consistcard',
      text: 'In a row now is how many sessions in a row you have done, counting back from the last one due. Most in a row is the longest such run. The last figure is the share of the sessions you answered that were done. A missed or unanswered session ends a run.' },
    { kind: 'look', head: 'Which sport runs behind', set: { screen: 'pro.sport' }, target: 'pro.sportcard',
      text: 'Each sport with the share of its planned sessions kept, and done over planned beside it. The sentence names the sport furthest behind, only when it has at least 3 planned sessions and is below 100%.' },
    { kind: 'look', head: 'Missed, or moved', set: { screen: 'pro.moves' }, target: 'pro.movescard',
      text: 'Moved and kept counts sessions you moved to another day instead of losing; missed counts the ones lost outright. The app remembers its own moves, on this device only.' },
    { kind: 'look', head: 'Easy and test weeks: the letters E and T', set: { device: 'pad', part: 'plan', screen: 'pro.season' }, target: 'pro.skey', only: 'iPad and Mac',
      text: 'On the Plan page of an iPad or Mac, the season bars carry a small <b>E</b> over an easy week and a <b>T</b> over a test week. On wide bars the words Easy and Test stand there instead. A test week always shows its letter. The key names only the letters that occur in your plan.', real: 'Plan page, season bars' },
    { kind: 'look', head: 'Month in review', set: { screen: 'pro.month' }, shot: 'pro-04-month-review',
      text: 'The purple head card names the last finished month and appears from the 1st; the picture counts September 2026. Tiles: Hours 5h 53m done of 7h 00m, Sessions 10 of 11, Plan followed 91 %, Longest session 1h 02m (a ride). Under them, hours per sport and <b>How you felt</b>, counting mornings by word, then <b>Report as PDF</b>.' },
    { kind: 'try', head: 'Go to an earlier month', set: { screen: 'pro.month' }, target: S => S.pro_list ? 'pro.pick:1' : 'pro.earlier',
      text: 'Press <b>Earlier months</b>, then press <b>July 2026</b>.', until: S => S.pro_month === 1,
      ok: 'The head card now reads AN EARLIER MONTH. Every finished month back to the plan’s first is in that list.', robot: [['act', 'pro.earlier'], ['act', 'pro.pick', '1']] },
    { kind: 'look', head: 'Your bests', shot: 'pro-05-bests',
      text: 'Longest ride, run and swim by time, with the distance beside it and the date: here a ride of 1h 02m, 28.4 km. The grey <b>Farthest</b> line shows only when another session went farther (42 km). Pressing a ride, run or swim tile opens that session. <b>Biggest week</b> and <b>Longest row of weeks</b> come from logged, not-missed plan sessions, never extras.' },
    { kind: 'look', head: 'The lower block of Progress', shot: 'pro-03-new-cards',
      text: 'Further down the page: <b>Steady weeks</b> with its row of squares, then <b>Your bests</b>, then <b>Tests</b> with the threshold pulse. The next chapter reads Steady weeks and Tests. At the very foot a grey line says the figures are worked out each time the page opens: nothing here is stored in the plan, and nothing here changes it.' },
    { kind: 'check', head: 'A hike with no number', text: 'Apple Health holds a 90-minute hike that is in neither the plan nor your extras, and you never answered How hard?. What does the Load card do with it?',
      answers: ['Leaves it out', 'Counts it in a dotted bar as 3, which is easy, and says so', 'Asks the plan for a zone'], right: 1,
      ok: 'Right. It counts in the dotted bar with 3 for easy, and the card says how many were counted that way.' },
    { kind: 'check', head: 'What goes into Your bests?', text: 'You did a long hike as an extra workout, and a ride you marked missed. Which of these can become a best?',
      answers: ['Both', 'Only the hike', 'Neither: only logged sessions of the plan that were not missed'], right: 2,
      ok: 'Right. Extras and missed sessions are never in the bests.' },
  ],
});
