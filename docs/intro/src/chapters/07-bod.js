/* Chapter 7 — Body. The Body tab: the Body Battery card with its curve, the workouts drawn on it, the week, the range switch, the six tiles,
   a tile's days in numbers, Share, how often Garmin is read, and the two empty states. All figures are invented (the app's own sample day,
   Wednesday 16 September). Words are the app's own: BodyView.swift, BodyPage.swift, BodyMore.swift, BodyTap.swift. */

/* ---- The sample day, as the app's own invented Garmin day has it ---- */
const BOD_TODAY = [[0, 38], [1, 46], [2, 55], [3, 63], [4, 71], [5, 78], [6, 82], [6.5, 80], [7, 74], [7.5, 66], [8, 58], [8.5, 55], [9.5, 53],
  [10.5, 50], [11.5, 47], [12.5, 44], [13.5, 40]];
const BOD_YEST = [[0, 24], [1, 31], [2, 39], [3, 47], [4, 54], [5, 60], [6, 64], [7, 66], [8, 63], [9.5, 60], [11, 57], [12.5, 54], [14, 51],
  [15.5, 49], [17, 47], [17.5, 43], [18, 36], [18.5, 30], [19.5, 28], [21, 27], [22, 29], [23, 33], [23.9, 37]];
/* Workouts on the curve: start hour, end hour, the words above the bar. */
const BOD_WK = [{ a: 6.75, b: 7.75, label: 'Run −17' }, { a: 12, b: 12.75, label: 'Strength −6' }];
/* The week card: weekday letter, highest, lowest (Saturday had no readings). */
const BOD_WEEK = [['T', 76, 22], ['F', 85, 30], ['S', 68, 18], ['S', null, null], ['M', 81, 26], ['T', 64, 24], ['W', 82, 38]];

const bodFmt = {
  sleep: v => dur(Math.round(v * 60)), hrv: v => `${Math.round(v)} ms`, resting: v => `${Math.round(v)} beats`,
  stress: v => `${Math.round(v)} average`, steps: v => `${num(v).replace(/ /g, ',')} steps`, intensity: v => `${Math.round(v)} min`,
};
const bodPlain = {
  sleep: v => dur(Math.round(v * 60)), hrv: v => `${Math.round(v)} ms`, resting: v => `${Math.round(v)} beats`,
  stress: v => `${Math.round(v)}`, steps: v => num(v).replace(/ /g, ','), intensity: v => `${Math.round(v)} a day`,
};
/* Six tiles in the app's order. days = last seven days, oldest first, null = no reading. weeks = twelve weekly averages, oldest first. */
const BOD_INST = [
  { id: 'sleep', name: 'Sleep', fig: '7h 18m', unit: '', note: '7-night average 7h 13m', days: [6.8, 7.4, null, 7.2, 8.0, 6.6, 7.3],
    weeks: [7.1, 6.9, 7.0, 7.2, 6.8, 7.0, 6.6, 7.1, 7.2, 6.8, 7.1, 7.2] },
  { id: 'hrv', name: 'HRV', fig: '64', unit: 'ms', note: 'your normal 52–68', days: [58, 61, 57, 63, 66, 60, 64], band: [52, 68],
    weeks: [60, 62, 59, 63, 61, 64, 62, 60, 63, 65, 61, 64] },
  { id: 'resting', name: 'Resting pulse', fig: '47', unit: 'beats', note: 'your normal 49', days: [49, 48, 50, 47, 48, 49, 47], band: [46.6, 50.4],
    weeks: [47, 48, 47, 46, 47, 48, 47, 46, 47, 48, 47, 47] },
  { id: 'stress', name: 'Stress', fig: '26', unit: 'average', note: 'highest today 71', days: [32, 29, 35, 27, 30, 33, 26],
    weeks: [29, 31, 30, 28, 32, 30, 29, 31, 30, 28, 31, 26] },
  { id: 'steps', name: 'Steps', fig: '9,300', unit: 'steps', note: '7-day average 8,400', days: [7400, 9900, 6100, 10200, 8600, 7300, 9300],
    weeks: [8700, 9100, 8400, 8800, 9000, 8500, 8900, 8600, 8700, 8200, 8800, 9300] },
  { id: 'intensity', name: 'Intensity minutes', fig: '60', unit: 'of 150', note: 'moderate 30 · vigorous 15', days: [20, 0, 45, 30, 0, 35, 25],
    weeks: [28, 31, 26, 33, 29, 30, 27, 31, 32, 34, 19, 22] },
];
/* The Mondays of the last twelve weeks, oldest first: the day of the month, and the words a numbers page uses. */
const BOD_MON = [[29, 'Mon 29 Jun'], [6, 'Mon 6 Jul'], [13, 'Mon 13 Jul'], [20, 'Mon 20 Jul'], [27, 'Mon 27 Jul'], [3, 'Mon 3 Aug'], [10, 'Mon 10 Aug'],
  [17, 'Mon 17 Aug'], [24, 'Mon 24 Aug'], [31, 'Mon 31 Aug'], [7, 'Mon 7 Sep'], [14, 'Mon 14 Sep']];
const BOD_DAYS = [['Thu 10 Sep'], ['Fri 11 Sep'], ['Sat 12 Sep'], ['Sun 13 Sep'], ['Mon 14 Sep'], ['Tue 15 Sep'], ['Wed 16 Sep']];
const bodInst = id => BOD_INST.find(i => i.id === id);
const bodSpanTitle = s => ({ '7': '7 days', '4w': '4 weeks', '12w': '12 weeks' })[s];
const bodAvg = v => { const x = v.filter(n => n != null); return x.reduce((a, b) => a + b, 0) / x.length; };

/* How tall each bar stands (the app's own rule: measured from a little under the lowest, his normal taken in). */
function bodHeights(vals, band) {
  const v = vals.filter(x => x != null);
  const hi = Math.max(...v, band ? band[1] : -Infinity), lo = Math.min(...v, band ? band[0] : Infinity);
  const floor = lo * 0.6, f = x => (hi > floor ? Math.min(1, Math.max(0, (x - floor) / (hi - floor))) : 1);
  return { h: vals.map(x => (x == null ? null : Math.max(0.15, f(x)))), band: band ? [f(band[0]), f(band[1])] : null };
}

/* One tile's slim bars with the letters under them. */
function bodBars(inst, span) {
  const wk = span !== '7', n = span === '4w' ? 4 : 12;
  const vals = wk ? inst.weeks.slice(12 - n) : inst.days;
  const { h, band } = bodHeights(vals, inst.band);
  const names = wk ? BOD_MON.slice(12 - n).map(m => m[0]) : BOD_WEEK.map(d => d[0]);
  const last = vals.length - 1;
  return `<div class="bod-bars${wk && n === 4 ? ' bod-four' : ''}">${band ? `<span class="bod-norm" style="bottom:${Math.round(band[0] * 100)}%;height:${Math.max(8, Math.round((band[1] - band[0]) * 100))}%"><i>normal</i></span>` : ''}
    ${vals.map((x, i) => {
      const lab = !wk || n === 4 || (last - i) % 3 === 0 ? names[i] : '';
      return `<span class="bod-col">${h[i] == null ? '<u>–</u>' : `<b style="height:${Math.round(h[i] * 100)}%"></b>`}<em class="${i === last ? 'bod-today' : ''}">${lab}</em></span>`;
    }).join('')}</div>`;
}

/* A tile's figure and its grey line, for the chosen span. */
function bodTileText(inst, span) {
  if (span === '7') return { fig: inst.fig, unit: inst.unit, note: inst.note };
  const n = span === '4w' ? 4 : 12;
  return { fig: inst.fig, unit: inst.unit, note: `${n}-week average ${bodPlain[inst.id](bodAvg(inst.weeks.slice(12 - n)))}` };
}

/* The Body Battery curve as a picture: today's white line ending in a dot, yesterday's thin dark line, the workouts as white bars. */
function bodCurve(S) {
  const X = h => (2 + 236 * h / 24).toFixed(1), Y = v => (104 - 74 * v / 100).toFixed(1), top = 30;
  const path = pts => pts.map((p, i) => (i ? 'L' : 'M') + X(p[0]) + ' ' + Y(p[1])).join(' ');
  const lastP = BOD_TODAY[BOD_TODAY.length - 1];
  const area = path(BOD_TODAY) + ` L${X(lastP[0])} 104 L${X(0)} 104 Z`;
  return `<svg class="bod-svg" viewBox="0 0 240 120" aria-hidden="true">
    ${[0, 50, 100].map(v => `<path d="M2 ${Y(v)} L238 ${Y(v)}" stroke="currentColor" stroke-opacity=".22" fill="none"/>`).join('')}
    ${[0, 6, 12, 18, 24].map(h => `<text x="${h === 0 ? 2 : h === 24 ? 238 : X(h)}" y="117" font-size="8" fill="currentColor" fill-opacity=".8" text-anchor="${h === 0 ? 'start' : h === 24 ? 'end' : 'middle'}">${String(h).padStart(2, '0')}</text>`).join('')}
    ${BOD_WK.map(w => `<path d="M${X(w.a)} ${top} L${X(w.b)} ${top}" stroke="currentColor" stroke-width="3" stroke-linecap="round" fill="none"/>
      <path d="M${X(w.a)} ${top} L${X(w.a)} 104 M${X(w.b)} ${top} L${X(w.b)} 104" stroke="currentColor" stroke-opacity=".55" fill="none"/>
      <text x="${((+X(w.a) + +X(w.b)) / 2).toFixed(1)}" y="${top - 6}" font-size="8" font-weight="700" fill="currentColor" text-anchor="middle">${w.label}</text>`).join('')}
    ${S.bod_noy ? '' : `<path d="${path(BOD_YEST)}" class="bod-yline" fill="none" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>`}
    <path d="${area}" fill="currentColor" fill-opacity=".2"/>
    <path d="${path(BOD_TODAY)}" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <circle cx="${X(lastP[0])}" cy="${Y(lastP[1])}" r="4.5" fill="currentColor"/></svg>`;
}

/* The head card. */
function bodHero(S) {
  const taps = BOD_WK.map((w, i) => {
    const c = (2 + 236 * (w.a + w.b) / 48) / 240 * 100, wide = Math.max(15, (236 * (w.b - w.a) / 24 + 8) / 240 * 100);
    return `<button class="bod-tap" style="left:${(c - wide / 2).toFixed(1)}%;width:${wide.toFixed(1)}%" data-act="bod.wk" data-arg="${i}" data-t="bod.wk:${i}" aria-label="${w.label}. Opens it."></button>`;
  }).join('');
  return K.hero({ t: 'bod.hero', html: `
    <span class="k-line bod-capline"><span class="k-herocap">BODY BATTERY</span><span class="k-sp"></span>${S.bod_noy ? '' : `<span class="bod-yes"><i class="bod-ysample"></i>yesterday</span>`}</span>
    <span class="k-line bod-figs"><span class="bod-now"><b>40</b> now</span>
      <span class="bod-side"><span>Highest today 82</span><span>2 workouts took 23</span><span>${S.bod_noy ? 'Charged +44 overnight' : 'Charged +55 overnight'}</span></span></span>
    <div class="bod-curve">${bodCurve(S)}${taps}</div>` });
}

/* The week card: seven small curves, the weekday letter, the highest, the lowest. */
function bodWeek() {
  const mini = (hi, lo, now) => {
    const y = v => (20 - 18 * v / 100).toFixed(1);
    const d = now ? `M2 ${y(38)} L10 ${y(hi)} L16 ${y(lo + 10)} L18 ${y(lo + 8)}` : `M2 ${y(lo)} L10 ${y(hi)} L28 ${y(lo + 4)}`;
    return `<svg viewBox="0 0 30 22" class="bod-mini"><path d="${d}" fill="none" stroke="var(--pc)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>${now ? `<circle cx="18" cy="${y(lo + 8)}" r="2" fill="var(--pc)"/>` : ''}</svg>`;
  };
  return `<div class="bod-card" data-t="bod.week"><span class="bod-cap">BODY BATTERY · LAST 7 DAYS</span>
    <div class="bod-weekrow">${BOD_WEEK.map((d, i) => `<span class="bod-day">${d[1] == null ? '<u>–</u>' : mini(d[1], d[2], i === 6)}
      <em class="${i === 6 ? 'bod-today' : ''}">${d[0]}</em><b>${d[1] ?? ' '}</b><small>${d[2] ?? ' '}</small></span>`).join('')}</div>
    <span class="k-muted bod-tiny">Under each day: the highest, then the lowest.</span></div>`;
}

/* The heading with the day and when Garmin was last read. */
function bodHeading(S) {
  return `<h1 class="k-h1 bod-h1" data-act="bod.pull" data-t="bod.head">Body</h1>
    <span class="k-muted k-small bod-read">${S.bod_mode === 'full' ? `Wed 16 Sep · read ${S.bod_pulled ? '13:41' : '13:36'}` : ''}</span>`;
}

function bodTiles(S) {
  return `<div class="bod-range-wrap"><div class="bod-range">${['7', '4w', '12w'].map(s =>
      `<button class="${S.bod_span === s ? 'bod-on' : ''}" data-act="bod.span" data-arg="${s}" data-t="bod.span:${s}">${bodSpanTitle(s)}</button>`).join('')}</div>
    ${S.bod_span !== '7' ? `<span class="k-muted bod-tiny">Each bar is one week's average, named by its Monday's date.</span>` : ''}</div>
    <div class="bod-tiles">${BOD_INST.map(i => { const t = bodTileText(i, S.bod_span); return `
      <button class="bod-tile bod-c-${i.id}" data-act="bod.tile" data-arg="${i.id}" data-t="bod.tile:${i.id}">
        <span class="bod-tname">${i.name.toUpperCase()}</span>
        <span class="bod-fig"><b>${t.fig}</b>${t.unit ? `<span>${t.unit}</span>` : ''}</span>
        <span class="k-muted bod-note">${t.note}</span>${bodBars(i, S.bod_span)}</button>`; }).join('')}</div>`;
}

/* ---- New in 2.9 (85): the Training part under the tiles. The app's own invented figures (the picture switch AMSWS_FAKE_GARMIN). ---- */
const BOD_GYM = [
  { day: 'Mon 14 Sep', len: '1h 04m', kg: '4,320', counts: '4 machines · 11 sets · felt good · 2 days ago', vs: 'vs the one before: +2 sets · −17 min · +640 kg', m: [0, 1, 2, 3], w: 100 },
  { day: 'Fri 11 Sep', len: '1h 21m', kg: '3,680', counts: '3 machines · 9 sets · felt ok · 5 days ago', m: [0, 1, 2], w: 85 },
  { day: 'Mon 7 Sep', len: '1h 02m', kg: '2,950', counts: '3 machines · 9 sets · felt great · 9 days ago', m: [1, 2, 3], w: 68 },
  { day: 'Thu 3 Sep', len: '55m', kg: '1,980', counts: '2 machines · 6 sets · 13 days ago', m: [0, 1], w: 46 },
];
const BOD_MACH = [['Leg press', 'best 90 kg × 10'], ['Chest press', 'best 40 kg × 12'], ['Seated row', 'best 37.5 kg × 10'], ['Exercise bike', '15 min · level 6']];
/* Workouts this month, newest first: tag, tag colour class, day and time, name, length, distance, pulse. */
const BOD_MONTH = [
  ['Breathing', 'g', 'Wed 16 · 18:17', 'Sample Breathing', '1h 14m', '', ''], ['Ride', 'ride', 'Wed 16 · 07:18', 'Sample Trainer', '1h 21m', '23.0 km', '144 bpm'],
  ['Hike', 'g', 'Tue 15 · 18:15', 'Sample Hike', '1h 00m', '16.0 km', '132 bpm'], ['Run', 'run', 'Tue 15 · 07:16', 'Sample Easy Run', '1h 07m', '18.0 km', '136 bpm'],
  ['Walk', 'g', 'Mon 14 · 18:13', 'Sample Walk', '46m', '11.0 km', '124 bpm'], ['Strength', 'str', 'Mon 14 · 07:14', 'Sample Strength', '53m', '', '128 bpm'],
  ['Swim', 'swim', 'Sun 13 · 18:11', 'Sample Swim', '32m', '5.5 km', '116 bpm'], ['Ride', 'ride', 'Sun 13 · 07:12', 'Sample Ride', '39m', '8.0 km', '120 bpm'],
  ['Run', 'run', 'Sat 12 · 07:10', 'Sample Run', '25m', '3.0 km', '112 bpm'],
];
const bodMonthRow = (w, i, act) => `<${act ? 'button data-act="bod.mrow" data-arg="' + i + '" data-t="bod.mrow:' + i + '"' : 'div'} class="bod-mrow">
  <span class="k-line bod-mtop"><i class="bod-tag bod-tag-${w[1]}">${w[0].toUpperCase()}</i><span class="k-muted k-small">${w[2]}</span></span>
  <b>${w[3]}</b><span class="k-muted k-small">${[w[4], w[5], w[6]].filter(Boolean).join(' · ')}</span></${act ? 'button' : 'div'}>`;

function bodTraining(S) {
  const g = BOD_GYM[S.bod_gym || 0], latest = !S.bod_gym;
  return `<h2 class="k-h2 bod-part">Training</h2>
    <div class="bod-two">
      <button class="bod-tile bod-c-load" data-act="bod.load" data-t="bod.load"><span class="bod-tname">TRAINING LOAD</span>
        <span class="bod-fig"><b>288</b><span>7 days</span></span><span class="k-muted bod-note">4-week average 252 · ratio 1.14</span>
        <b class="bod-word">Productive</b><span class="bod-scale"><i class="bod-steady"></i><u></u></span></button>
      <div class="bod-tile bod-c-fitness" data-t="bod.fitness"><span class="bod-tname">FITNESS</span>
        <span class="bod-fig"><b>52</b><span>fitness age</span></span><span class="k-muted bod-note bod-wrap">Real age 58 · 6 years younger</span>
        <span class="k-muted bod-note bod-wrap">VO2 max: Garmin does not share it yet</span></div></div>
    <div class="bod-card bod-gym bod-c-gym" data-t="bod.gym"><span class="bod-cap">GYM SESSIONS</span>
      <span class="bod-fig"><b>${g.kg}</b><span>kg</span></span>
      <span class="k-muted k-small">${g.day} · City Gym · ${g.len}</span><span class="k-muted k-small">${g.counts}</span>
      ${g.vs ? `<span class="k-muted k-small">${g.vs}</span>` : ''}
      <div class="k-col bod-mach">${g.m.map(k => `<span><b>${BOD_MACH[k][0]}</b> <span class="k-muted">· ${BOD_MACH[k][1]}${latest && k === 0 ? ' · new best' : ''}</span></span>`).join('')}</div>
      ${BOD_GYM.map((r, i) => `<button class="bod-grow${(S.bod_gym || 0) === i ? ' bod-sel' : ''}" data-act="bod.gym" data-arg="${i}" data-t="bod.grow:${i}">
        <span><b>${r.day}</b> <span class="k-muted">City Gym · ${r.len}</span> <b>${r.kg} kg</b></span><i style="width:${r.w}%"></i></button>`).join('')}
      ${latest ? '' : `<button class="k-link bod-back" data-act="bod.gymback" data-t="bod.gymback">Back to the latest</button>`}
      <span class="k-muted bod-tiny">Tap a session to see it here.</span></div>
    <div class="bod-card bod-month bod-c-month" data-t="bod.month"><span class="bod-cap">WORKOUTS · SEPTEMBER</span>
      <span class="bod-fig"><b>9</b><span>this month</span></span><span class="k-muted k-small">7h 57m · 84.5 km</span>
      ${BOD_MONTH.slice(0, 6).map((w, i) => bodMonthRow(w, i, true)).join('')}
      <button class="k-link" data-act="bod.all" data-t="bod.all">All 9 workouts</button>
      <span class="k-muted bod-tiny">Tap a workout to open it.</span></div>`;
}

/* The Health part: sleep debt (slept, need in minutes; null = no watch), weight, energy, water. */
const BOD_NIGHTS = [['Thu 10 Sep', 'T', 408, 480], ['Fri 11 Sep', 'F', 444, 480], ['Sat 12 Sep', 'S', null, 460], ['Sun 13 Sep', 'S', 432, 500],
  ['Mon 14 Sep', 'M', 480, 480], ['Tue 15 Sep', 'T', 396, 460], ['Wed 16 Sep', 'W', 438, 480]];
const bodHM = m => `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`;
function bodHealth(S) {
  return `<h2 class="k-h2 bod-part">Health</h2>
    <button class="bod-card bod-btn bod-c-sleep" data-act="bod.sleepdebt" data-t="bod.sleepdebt"><span class="bod-cap">SLEEP DEBT</span>
      <span class="bod-fig"><b>−4h 42m</b><span>7 nights</span></span>
      <span class="k-muted k-small">Need about 8h a night · 1 night without the watch. Tap for each night.</span>
      <span class="bod-nights">${BOD_NIGHTS.map((n, i) => `<span class="bod-night"><span class="bod-need">${n[2] == null ? '<u>–</u>' : `<b style="height:${Math.round(100 * Math.min(1, n[2] / n[3]))}%"></b>`}</span><em class="${i === 6 ? 'bod-today' : ''}">${n[1]}</em></span>`).join('')}</span></button>
    <div class="bod-card bod-c-weight" data-t="bod.weight"><span class="bod-cap">WEIGHT</span><span class="bod-fig"><b>72.2</b><span>kg</span></span>
      <span class="k-muted k-small">Weighed Tue 15 Sep · +0.4 kg in 90 days · goal 78.0 kg. Tap for each weigh-in.</span></div>
    <div class="bod-two"><div class="bod-tile bod-c-energy"><span class="bod-tname">ENERGY</span><span class="bod-fig"><b>2,480</b><span>kcal</span></span><span class="k-muted bod-note bod-wrap">Active 520 · resting 1,960</span></div>
      <div class="bod-tile bod-c-water"><span class="bod-tname">WATER</span><span class="bod-fig"><b>1,250</b><span>ml</span></span><span class="k-muted bod-note bod-wrap">Goal 3,000 ml · 42%</span>
        <span class="bod-scale bod-water"><i></i></span></div></div>`;
}

CHAPTER({
  id: 'bod',
  title: 'Body',
  icon: 'body',
  needs: 'A Garmin key saved in Settings (the chapter Garmin and Health shows how), and a watch that has sent its numbers to Garmin.',
  gives: 'One page, raspberry at its top and a colour of its own on every card, for what your watch keeps about you: Body Battery through the day, six tiles with their days, and every workout one press from its page.',
  start: () => ({ part: 'body', screen: 'bod.page', bod_mode: 'full', bod_span: '7', bod_noy: false, bod_low: false, bod_pulled: false, bod_shared: false,
    bod_peek: null, bod_plate: false, bod_gym: 0, bod_from: '', bod_loadseen: false, bod_all: false, bod_mopen: false, bod_slept: false }),
  screens: {
    'bod.page': S => S.bod_mode === 'nokey' ? SCREENS['bod.nokey'](S) : S.bod_mode === 'empty' ? SCREENS['bod.empty'](S) : `
      ${S.bod_low ? '' : `${bodHeading(S)}
      <span class="k-muted k-small bod-calm">2 of 3 in your normal range · Body Battery on waking above it</span>
      ${bodHero(S)}${bodWeek()}`}
      ${bodTiles(S)}
      <div class="bod-sharebox"><button class="bod-share" data-act="bod.share" data-t="bod.share">${icon('share')}<span>Share</span></button>
        <span class="k-muted bod-tiny">The picture shows your Garmin numbers of today.</span>
        <span class="k-muted bod-tiny bod-foot" data-t="bod.foot">Tap a workout or a tile for more.<br>From your Garmin watch · shown only, it changes no plan.</span></div>`,
    /* 2.9 (85): the page lower down, the Training part. */
    'bod.train': S => `${bodTraining(S)}${bodHealth(S)}`,
    /* A strength session's page with the small GYM block (2.9). */
    'bod.gymblock': S => `
      ${K.back('Today', 'bod.back', { t: 'bod.back' })}
      <span class="k-line">${K.sport('strength', { size: 40 })}<span class="k-col"><span class="k-sportword k-sp-strength">Strength</span><span class="k-muted">Monday 14 September</span></span></span>
      <b class="bod-sestitle">Strength A</b>
      <div class="bod-card bod-gym" data-t="bod.gymblk"><span class="bod-cap">GYM</span>
        <span class="k-muted k-small">City Gym · 1h 04m · 4 machines · 11 sets · 4,320 kg</span>
        <div class="k-col bod-mach">${BOD_MACH.map((m, k) => `<span><b>${m[0]}</b> <span class="k-muted">· ${m[1]}</span></span>`).join('')}</div></div>
      <span class="k-muted k-small">Only a strength session shows it, and only when the gym file has a session on that day.</span>`,
    'bod.nokey': S => `${bodHeading(S)}
      <div class="bod-card bod-msg"><span>Connect your Garmin key to see your body's numbers here.</span>
        <button class="bod-share bod-wide" data-act="bod.connect" data-t="bod.connect"><span>Open Garmin settings</span></button></div>`,
    'bod.empty': S => `${bodHeading(S)}
      <div class="bod-card bod-msg" data-t="bod.empty"><span>No numbers from Garmin yet. Wear the watch, sync it in Garmin Connect, then pull down here.</span></div>`,
    /* A session's page, opened from the curve: it keeps Today's green; the way back is Body's. */
    'bod.session': S => `
      ${K.back('Body', 'bod.back', { t: 'bod.back' })}
      <span class="k-line">${K.sport('run', { size: 40 })}<span class="k-col"><span class="k-sportword k-sp-run">Run</span>
        <span class="k-muted">Wednesday 16 September</span></span></span>
      <b class="bod-sestitle">Easy run + 4x20 s strides</b>
      <span class="k-muted k-small">Why: easy aerobic — builds your base without costing much.</span>
      <span class="k-line">${K.chip('35m')}${K.chip('Z2')}</span>
      <div class="k-card"><span class="k-cap">Purpose</span><span>Turnover</span></div>
      <span class="k-muted k-small">Nothing was logged by pressing the bar.</span>`,
    /* The Garmin page, opened right here from "Open Garmin settings". */
    'bod.garmin': S => `
      ${K.back('Body', 'bod.back', { t: 'bod.back' })}
      <b class="bod-gtitle">Garmin</b>
      <span class="k-muted k-small">Your Garmin watch knows things Apple Health does not hand over: overnight HRV, sleep, Body Battery and stress. Make a personal key once in your Garmin Connect account at connect.garmin.com, paste it here once, and Today and the Body page show those numbers beside your own normal.</span>
      <span class="k-in bod-fake">Paste your Garmin key</span>
      <div class="k-line">${K.btn('Cancel', 'bod.back')}${K.btn('Save', 'bod.keyhelp', { main: true })}</div>
      <span class="k-muted k-small">The key stays on this device only. The numbers are shown, they never change your plan.</span>`,
  },
  sheets: {
    /* A tile's days in numbers, newest first. */
    'bod.peek': S => {
      const i = bodInst(S.bod_peek), wk = S.bod_span !== '7', n = S.bod_span === '4w' ? 4 : 12;
      const rows = wk
        ? i.weeks.slice(12 - n).map((v, k) => [k === n - 1 ? 'This week' : 'From ' + BOD_MON[12 - n + k][1], bodPlain[i.id](v)]).reverse()
        : i.days.map((v, k) => [k === 6 ? (i.id === 'sleep' || i.id === 'hrv' ? 'Last night' : 'Today') : BOD_DAYS[k][0], v == null ? null : bodFmt[i.id](v)]).reverse();
      const note = [wk ? "Each row is one week's average of the days with a reading, named by its Monday." : '', i.id === 'intensity' ? 'A vigorous minute counts twice, as Garmin counts it.' : ''].filter(Boolean).join(' ');
      return `<div class="bod-sh bod-c-${i.id}"><h3>${i.name}${wk ? ' · ' + bodSpanTitle(S.bod_span) : ' · last 7 days'}</h3>
        <div class="k-col">${rows.map(r => `<div class="bod-prow"><span class="k-muted">${r[0]}</span><b class="${r[1] == null ? 'bod-none' : ''}">${r[1] ?? 'no reading'}</b></div>`).join('')}</div>
        ${note ? `<span class="k-muted k-small">${note}</span>` : ''}
        <div class="k-foot">${K.btn('Done', 'bod.done', { main: true, t: 'bod.done' })}</div></div>`;
    },
    /* A workout the plan and the extras have no page for: its own facts. */
    'bod.plate': S => `<h3>Strength</h3>
      <div class="k-col"><div class="bod-prow"><span class="k-muted">Started</span><b>12:00</b></div>
        <div class="bod-prow"><span class="k-muted">Lasted</span><b>45m</b></div>
        <div class="bod-prow"><span class="k-muted">Body Battery</span><b>−6</b></div></div>
      <span class="k-muted k-small">Not in your plan and not among your extras for this day.</span>
      <div class="k-foot">${K.btn('Done', 'bod.done', { main: true, t: 'bod.done' })}</div>`,
    /* 2.9 (85): the 12 weeks of load, the whole month's workouts. */
    'bod.load': S => `<div class="bod-sh bod-c-load"><h3>Training load</h3>
      <span class="bod-cap">WEEKLY LOAD · LAST 12 WEEKS</span>
      <div class="bod-wbars">${[62, 100, 90, 82, 78, 96, 80, 70, 62, 100, 48, 92].map((h, i) => `<span><b style="height:${h * .6}px" class="${i === 11 ? 'bod-now' : ''}"></b><em>${i === 11 ? 'now' : 11 - i}</em></span>`).join('')}</div>
      <span class="k-muted k-small">Each bar is 7 days of load; the numbers count the weeks back from now.</span>
      <b>Productive · ratio 1.14</b>
      <span class="k-muted k-small">The ratio sets the last 7 days against your usual week of the past 4 weeks. Around 0.8 to 1.3 is a steady week.</span>
      <span class="k-muted k-small">This week is close to your usual.</span>
      <span class="k-muted k-small">The words are the Garmin Board’s own reading, not Garmin’s.</span>
      <div class="k-foot">${K.btn('Done', 'bod.done', { main: true, t: 'bod.done' })}</div></div>`,
    'bod.month': S => `<div class="bod-sh bod-c-month"><h3>Workouts · September</h3>
      <div class="k-col bod-mlist">${BOD_MONTH.map((w, i) => bodMonthRow(w, i, false)).join('')}</div>
      <div class="k-foot">${K.btn('Done', 'bod.done', { main: true, t: 'bod.done' })}</div></div>`,
    'bod.sleep': S => `<div class="bod-sh bod-c-sleep"><h3>Sleep debt · last 7 nights</h3>
      <div class="k-col">${BOD_NIGHTS.slice().reverse().map(n => `<div class="bod-prow"><span class="k-muted">${n[0]}</span><b class="${n[2] == null ? 'bod-none' : ''}">${n[2] == null ? 'no reading' : bodHM(n[2]) + ' of ' + bodHM(n[3])}</b></div>`).join('')}</div>
      <span class="k-muted k-small">Sleep and naps against the need Garmin gives for each night (8h where it gives none). A night without the watch is left out.</span>
      <div class="k-foot">${K.btn('Done', 'bod.done', { main: true, t: 'bod.done' })}</div></div>`,
    'bod.keyhelp': S => `<h3>Garmin has its own chapter</h3>
      <span>The key goes in once, on the page Settings › Garmin. The chapter Garmin and Health shows it step by step.</span>
      <div class="k-foot">${K.btn('Done', 'sheet.close', { main: true })}</div>`,
  },
  actions: {
    'bod.wk'(arg, S) { if (arg === '0') { S.screen = 'bod.session'; S.bod_session = true; } else { S.sheet = 'bod.plate'; S.bod_plate = true; } },
    'bod.back'(arg, S) { S.screen = S.bod_mode === 'nokey' ? 'bod.nokey' : S.bod_from === 'train' ? 'bod.train' : 'bod.page'; },
    'bod.tile'(arg, S) { S.bod_peek = arg; S.sheet = 'bod.peek'; },
    'bod.span'(arg, S) { S.bod_span = arg; },
    'bod.done'(arg, S) { S.sheet = null; },
    'bod.share'(arg, S) { S.bod_shared = true; toast('The share sheet opens with the page as one picture.'); },
    'bod.pull'(arg, S) { S.bod_pulled = true; toast('Reading from Garmin…'); },
    'bod.connect'(arg, S) { S.screen = 'bod.garmin'; S.bod_garmin = true; },
    'bod.load'(arg, S) { S.sheet = 'bod.load'; S.bod_loadseen = true; },
    'bod.gym'(arg, S) { S.bod_gym = +arg; },
    'bod.gymback'(arg, S) { S.bod_gym = 0; },
    'bod.all'(arg, S) { S.sheet = 'bod.month'; S.bod_all = true; },
    'bod.mrow'(arg, S) { S.bod_mopen = true; toast('It opens the way a press on the curve does.'); },
    'bod.sleepdebt'(arg, S) { S.sheet = 'bod.sleep'; S.bod_slept = true; },
    'bod.keyhelp'(arg, S) { S.sheet = 'bod.keyhelp'; },
  },
  steps: [
    { kind: 'look', head: 'Your watch’s numbers, on one page', shot: 'bod-01-top',
      text: 'Body shows what your Garmin watch keeps about you. At the top: the day and when it was read, one grey line about your normal range, then the raspberry Body Battery card. Nothing here changes your plan.',
      hint: 'The grey line counts three numbers against your own normal: HRV, resting pulse and Body Battery on waking. It gives no advice. On the iPad and the Mac, Body is its own row in the side list.',
      real: 'the Body tab' },
    { kind: 'look', head: 'Reading the Body Battery card', target: 'bod.hero',
      text: 'The big number is Body Battery now, with the day’s highest, what the workouts took, and how far it charged overnight. The white line is today and ends in a white dot: now. The thin dark line is yesterday, named by the word at the top right.',
      hint: 'A white bar over the curve is a workout, with its name and its cost: Run −17 and Strength −6 make “2 workouts took 23”. The scale along the foot is the hour, 00 to 24.' },
    { kind: 'try', head: 'Press a workout on the curve', target: 'bod.wk:0',
      text: 'Your plan has a run on this day. Press the white bar <b>Run −17</b>, or anywhere in the column under its words.',
      until: S => S.screen === 'bod.session', ok: 'The run’s own page opens, as from Today. The arrow at the top leads back to Body. Nothing was logged.',
      robot: [['act', 'bod.wk', '0']], real: 'Body › a workout on the curve' },
    { kind: 'look', head: 'The run’s page, opened from Body', shot: 'bod-06-workout',
      text: 'This is what opens after a press on the run: the plan’s own session page, with a round arrow at the top left that leads back to Body. The Body tab stays lit below. Nothing is logged by the press.',
      hint: 'The page looks as it does from Today; only the way back belongs to Body.' },
    { kind: 'try', head: 'A workout your plan does not have', target: 'bod.wk:1',
      text: 'The strength workout from the watch has no session in the plan and no extra. Press <b>Strength −6</b>.',
      until: S => S.sheet === 'bod.plate', ok: 'A small plate shows the workout’s own facts: Started, Lasted and Body Battery. Done closes it.',
      robot: [['act', 'bod.wk', '1']] },
    { kind: 'look', head: 'The plate, and what opens first', shot: 'bod-07-workout-b',
      text: 'A press opens the first page that fits: a session of that sport planned that day, then an extra of that kind, then a looser match (a walk or hike may be the run), and last this plate. Only the same day counts, and a rest day never matches.',
      hint: 'Pressing only opens a page. It logs nothing and changes no plan. “no cost from Garmin” stands where Garmin gave no Body Battery cost.' },
    { kind: 'look', head: 'Six tiles', shot: 'bod-02-tiles',
      text: 'Under the range switch stand six tiles: Sleep, HRV, Resting pulse, Stress, Steps and Intensity minutes. Each has its own colour, on a pale ground of it: Sleep indigo, HRV teal, Resting pulse fuchsia, Stress amber, Steps lime, Intensity minutes blue. The figure keeps the text colour; then one grey line and seven slim bars. A small dash means no reading that day, never a zero.',
      hint: 'The grey box marked “normal” behind HRV and Resting pulse is your own normal. The bold green letter under the last bar is today. The week card above shows the last 7 days of Body Battery.' },
    { kind: 'try', head: 'Open a tile in numbers', set: { bod_low: true }, target: 'bod.tile:resting',
      text: 'Press the <b>Resting pulse</b> tile.',
      until: S => S.bod_peek === 'resting', ok: 'Its last 7 days in numbers, newest first. The first row says Today; a day without a reading says no reading.',
      robot: [['act', 'bod.tile', 'resting']] },
    { kind: 'look', head: 'A tile’s days in numbers', shot: 'bod-04-peek-sleep',
      text: 'A plate rises over the page: Sleep · last 7 days. The first row says Last night, then one row for each earlier day, newest first. A day without a reading says no reading. Done closes it.',
      hint: 'Resting pulse and Stress say Today in the first row; Sleep and HRV say Last night.' },
    { kind: 'try', head: 'Longer views: 12 weeks', set: { bod_low: true }, target: 'bod.span:12w',
      text: 'Press <b>12 weeks</b> in the switch above the tiles.',
      until: S => S.bod_span === '12w', ok: 'Each bar is one week’s average, named by its Monday’s date; the last, in bold green, is this week so far. The grey line now gives the 12-week average.',
      hint: 'Garmin is asked for the older days only when you pick a longer view, at most once in 30 minutes for each view. 4 weeks works the same way. 7 days brings the daily bars back.',
      robot: [['act', 'bod.span', '12w']] },
    { kind: 'look', head: 'The page on 4 weeks', shot: 'bod-08-range-4w',
      text: 'With 4 weeks chosen, every tile shows four bars, one for each week, named by its Monday’s day of the month: 24, 31, 7 and 14. The grey line gives the 4-week average. The note under the switch says what a bar is.' },
    { kind: 'look', head: 'Under the tiles: Training', shot: 'bod-12-training',
      text: 'Scroll past the six tiles to a raspberry heading, <b>Training</b>. First <b>Training load</b> and <b>Fitness</b> side by side, then the wide <b>Gym sessions</b> card. Training load is the last 7 days (288), the 4-week average and the ratio, with a word: here Productive.',
      hint: 'The word is the Garmin Board’s own reading: Recovery, Maintaining, Productive or Overreaching. Only Overreaching is red. Fitness sets Garmin’s fitness age against your real age; VO2 max shows only when a workout holds it.', real: 'Body, under the tiles' },
    { kind: 'try', head: 'Open the training load', set: { screen: 'bod.train' }, target: 'bod.load',
      text: 'Press the <b>Training load</b> card.',
      until: S => S.sheet === 'bod.load', ok: 'A page rises with twelve weekly bars. The last, in full colour, is this week so far. It only shows; it gives no advice.',
      robot: [['act', 'bod.load']], real: 'Body › Training load' },
    { kind: 'look', head: 'Twelve weeks of load', shot: 'bod-13-load-sheet',
      text: 'The page <b>Training load</b> has twelve slim bars, one for each week; the numbers count the weeks back, and <b>now</b> is this week. Under them: <b>Productive · ratio 1.14</b> and three calm sentences. Around 0.8 to 1.3 is a steady week. <b>Done</b> closes it.' },
    { kind: 'try', head: 'Look at an older gym session', set: { screen: 'bod.train' }, target: 'bod.grow:1',
      text: 'In the <b>Gym sessions</b> card, press the row <b>Fri 11 Sep</b>.',
      until: S => S.bod_gym === 1, ok: 'The card now shows that session: its kilograms, place, length and machines. The row is shaded. <b>Back to the latest</b> brings the newest one back.',
      hint: 'The card shows the gym sessions you log in the Workout Companion app. It has no page of its own; the six latest sit under it as rows, each with a slim bar for its kilograms.',
      robot: [['act', 'bod.gym', '1']], real: 'Body › Gym sessions' },
    { kind: 'look', head: 'Before the gym folder is chosen', shot: 'bod-19-gym-nofolder',
      text: 'Until you choose the folder, the Gym sessions card is small: a grey line says: “Your gym sessions come from the Workout Companion app. Tap Choose folder and pick AMS Workout Companion app to Garmin in iCloud Drive — once.” Under it a button, <b>Choose folder</b>. Workouts · September stands right under the card.',
      hint: 'The app only reads that folder and writes nothing in it. The choice stays on this device: the iPad and the Mac each need their own.', real: 'Body › Gym sessions' },
    { kind: 'look', head: 'The gym block on a strength session', set: { screen: 'bod.gymblock' }, target: 'bod.gymblk',
      text: 'Open a strength session on a day you trained in the gym and a small <b>GYM</b> block shows that day’s place, length, machines, sets, kilograms and each machine’s best set. Other kinds of session show nothing, and so does a strength day with no gym session.' },
    { kind: 'look', head: 'Workouts this month', shot: 'bod-14-month',
      text: 'The wide card <b>Workouts · September</b> counts the month: 9 workouts, 7h 57m and 84.5 km. Under it the newest six, each with a coloured tag for its sport, day and time, name, length, distance and pulse. The rows above are the gym sessions.',
      hint: 'A workout of Garmin’s that your plan does not have is here too; a grey tag means a sport with no colour in the plan. A press on a row opens the workout as a press on the curve does, and changes nothing.', real: 'Body › Workouts' },
    { kind: 'try', head: 'See the whole month', set: { screen: 'bod.train' }, target: 'bod.all',
      text: 'Press <b>All 9 workouts</b>.',
      until: S => S.sheet === 'bod.month', ok: 'A page lists the month’s workouts, newest first. <b>Done</b> closes it; a press on a row closes it and opens that workout.',
      hint: 'The button shows only when the month has more than six workouts.',
      robot: [['act', 'bod.all']], real: 'Body › All workouts' },
    { kind: 'look', head: 'Health: four more cards', shot: 'bod-16-health',
      text: 'Below Training comes a raspberry heading, <b>Health</b>: <b>Sleep debt</b> with its seven bars, <b>Weight</b> with a thin line, then <b>Energy</b> (today’s calories) and <b>Water</b> with a slim bar against Garmin’s goal. All four are only shown.',
      hint: 'Energy grows through the day. Water is what you logged in Garmin Connect: the app does not log it. A card with nothing yet says in one grey line what is missing, never a zero.', real: 'Body, under Training' },
    { kind: 'try', head: 'Open the sleep debt', set: { screen: 'bod.train' }, target: 'bod.sleepdebt',
      text: 'Press the <b>Sleep debt</b> card.',
      until: S => S.sheet === 'bod.sleep', ok: 'Each of the 7 nights, newest first: what you slept of what you needed. A night without the watch says no reading and is left out. Sleep never leads to a suggestion.',
      hint: 'The thin grey outline behind each bar is that night’s need. A dash is a night with no reading. Naps count; where Garmin gives no need, 8 hours is used.',
      robot: [['act', 'bod.sleepdebt']], real: 'Body › Sleep debt' },
    { kind: 'look', head: 'Weight: every weigh-in', shot: 'bod-18-weight-sheet',
      text: 'A press on the <b>Weight</b> card opens a page with each weigh-in of the last 90 days, newest first, each day beside its kilograms. The card itself gives the latest, its day, the change in 90 days and Garmin’s goal when it has one.',
      hint: 'It is never red and gives no advice.' },
    { kind: 'check', head: 'What does the app do with the gym folder?', text: 'You choose the folder AMS Workout Companion app to Garmin once. What does the app do with what is in it?',
      answers: ['It reads the gym sessions and writes nothing in it', 'It writes your plan into it', 'It sends the sessions to Garmin'], right: 0,
      ok: 'Right: it only reads, and the choice stays on this device.' },
    { kind: 'try', head: 'Share the page', set: { bod_low: true }, target: 'bod.share',
      text: 'Press <b>Share</b>, near the foot.',
      until: S => S.bod_shared, ok: 'The page becomes one picture, in the look you see now, day or night. It leaves the app only where you choose to send it.',
      hint: 'The foot says: Tap a workout or a tile for more. From your Garmin watch · shown only, it changes no plan.',
      robot: [['act', 'bod.share']] },
    { kind: 'try', head: 'Read Garmin now', target: 'bod.head',
      text: 'In the real app you pull the page down. Here, press the heading <b>Body</b>.',
      until: S => S.bod_pulled, ok: 'Garmin was read at once: the line under the heading now says read 13:41.',
      hint: 'Without a pull the page reads when you open it and when the app comes to the front, at most once in 30 minutes. A pull ignores the 30 minutes.',
      robot: [['act', 'bod.pull']] },
    { kind: 'look', head: 'No key, or no numbers yet', shot: 'bod-11-empty',
      text: 'With no Garmin key the page says so and offers one button, <b>Open Garmin settings</b>. With a key but nothing read yet it says: No numbers from Garmin yet. Wear the watch, sync it in Garmin Connect, then pull down here.',
      hint: 'A day without yesterday’s readings simply has no thin dark line and no word “yesterday”.' },
    { kind: 'try', head: 'Open Garmin settings from here', set: { bod_mode: 'nokey', screen: 'bod.nokey' }, target: 'bod.connect',
      text: 'Press <b>Open Garmin settings</b>.',
      until: S => S.screen === 'bod.garmin', ok: 'The Garmin page opens right here on Body. It is the same page as Settings › Garmin: the chapter Garmin and Health teaches it.',
      robot: [['act', 'bod.connect']], real: 'Body › Open Garmin settings' },
    { kind: 'look', head: 'Body on the iPad and the Mac', shot: 'bod-92-pad', set: { device: 'pad' }, only: 'iPad and Mac',
      text: 'The same page in the wide look: <b>Body</b> lit in the side list, the curve across the top, the seven days under it, and the six tiles three in a row. Everything presses as on the iPhone.' },
    { kind: 'check', head: 'What opens for a workout?', text: 'You press a workout on the curve. Your plan has no session of that sport that day, and you added no extra for it. What opens?',
      answers: ['Its session page', 'A small plate with Started, Lasted and Body Battery', 'Nothing: the bar only shows'], right: 1,
      ok: 'Right: the workout’s own facts from Garmin, and nothing is logged.' },
  ],
});
