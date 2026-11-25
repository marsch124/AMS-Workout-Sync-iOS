/* A worked example of one chapter (not part of the course). It shows the moves the Welcome chapter does not: a sheet with
   typing and choosing, a refusal, drag to arrange, choosing a row. Check it with:  node docs/intro/check.mjs exa
   (All words and figures here are invented for the example — a real chapter takes every word from the app's code.) */
CHAPTER({
  id: 'exa',
  title: 'Kit list',
  icon: 'box',
  needs: 'The things you want with you on race day, typed in once.',
  gives: 'A list you tick off the evening before.',
  start: () => ({ part: 'settings', screen: 'exa.list', exa_rows: [
    { id: 'k1', what: 'Wetsuit', where: 'Swim' },
    { id: 'k2', what: 'Helmet', where: 'Bike' },
    { id: 'k3', what: 'Race belt', where: 'Run' }],
    exa_sel: null, exa_what: '', exa_count: '', exa_where: '', exa_tried: false }),
  screens: {
    'exa.list': S => `
      ${K.back('Settings', 'exa.note')}
      <div class="k-top"><h1 class="k-h1">Kit list</h1><span class="k-sp"></span>${K.btn('Add', 'exa.add', { icon: 'plus', t: 'exa.add' })}</div>
      <div class="k-card"><span class="k-cap">Race day</span>
        ${S.exa_rows.map((r, i) => `<div class="k-dragrow ${S.exa_sel === r.id ? 'exa-on' : ''}" data-drag="exa_rows" data-i="${i}">
          <button class="k-grip" data-grip aria-label="Drag to arrange" data-t="exa.grip:${r.id}">${icon('grip')}</button>
          <button class="exa-pick" data-act="exa.pick" data-arg="${r.id}" data-t="exa.row:${r.id}">
            <span class="k-name">${esc(r.what)}</span><span class="k-muted k-small">${esc(r.where)}</span></button></div>`).join('')}</div>
      <div class="k-card k-plain"><span class="k-cap">Chosen</span>
        ${S.exa_sel ? `<p class="exa-p">${esc(S.exa_rows.find(r => r.id === S.exa_sel).what)} — packed with your ${esc(S.exa_rows.find(r => r.id === S.exa_sel).where.toLowerCase())} things.</p>` : `<p class="exa-p k-muted">Choose a row above.</p>`}</div>`,
  },
  sheets: {
    'exa.page': S => `<h3>New thing</h3>
      <div class="k-field"><label for="in-exa_what">What</label>${K.input('exa_what', S, { ph: 'What is it?', t: 'exa.what' })}</div>
      <div class="k-field"><label for="in-exa_count">How many</label>${K.input('exa_count', S, { num: true, w: 70, t: 'exa.count' })}</div>
      <div class="k-field"><label for="in-exa_where">Goes with</label>${K.select('exa_where', S, [['', 'Choose…'], 'Swim', 'Bike', 'Run'], { t: 'exa.where' })}</div>
      ${S.exa_tried && !S.exa_what ? `<div class="k-band k-needs">${icon('alert')}<span>Say what it is.</span></div>` : ''}
      <div class="k-foot">${K.btn('Cancel', 'sheet.close')}${K.btn('Save', 'exa.save', { main: true, t: 'exa.save' })}</div>`,
  },
  actions: {
    'exa.add'(arg, S) { S.sheet = 'exa.page'; },
    'exa.pick'(arg, S) { S.exa_sel = arg; },
    'exa.note'() { toast('Settings has its own chapter.'); },
    'exa.save'(arg, S) {
      S.exa_tried = true; if (!S.exa_what || !Number(S.exa_count) || !S.exa_where) return;
      S.exa_rows.push({ id: 'new', what: S.exa_what, where: S.exa_where }); S.exa_sel = 'new'; S.sheet = null;
    },
    // 'in'(key, S) is called after typing in a K.input / choosing in a K.select; 'drop'(listKey, S) after a drag; 'key'(key, S) for a key press.
  },
  steps: [
    { kind: 'look', head: 'A list for race day', text: 'Everything you want with you, in the order you pack it.', target: 'exa.add', real: 'Settings › Kit list' },
    { kind: 'try', head: 'Open the page', text: 'Press <b>Add</b>.', target: 'exa.add',
      until: S => S.sheet === 'exa.page', ok: 'The page "New thing" is open.', robot: [['act', 'exa.add']] },
    { kind: 'try', head: 'Type a thing and save it', text: 'Say what it is, how many, and what it goes with, then press <b>Save</b>.',
      set: { sheet: 'exa.page' },
      target: S => !S.exa_what ? 'exa.what' : !Number(S.exa_count) ? 'exa.count' : !S.exa_where ? 'exa.where' : 'exa.save',   // the ring moves on
      until: S => S.exa_rows.length === 4, ok: 'Saved. The new row is at the end of the list.',
      robot: [['in', 'exa_what', 'Gels'], ['in', 'exa_count', '4'], ['in', 'exa_where', 'Bike'], ['act', 'exa.save']] },
    { kind: 'try', head: 'Drag a row to another place', text: 'Press the grip on the left of <b>Race belt</b>, hold, and let go over the first row.',
      hint: 'Arranging is always drag and drop.', target: 'exa.grip:k3',
      until: S => S.exa_rows[0].id === 'k3', ok: 'Race belt is first now.', robot: [['drag', 'exa_rows', 2, 0]] },
    { kind: 'try', head: 'Choose a row', text: 'Press the row <b>Helmet</b>.', target: 'exa.row:k2',
      until: S => S.exa_sel === 'k2', ok: 'Its line shows below.', robot: [['act', 'exa.pick', 'k2']] },
    { kind: 'check', head: 'What does Save need?', text: 'You press Save with nothing typed. What happens?',
      answers: ['An empty row is added', 'An orange line says what is missing, and nothing is saved', 'The page closes'], right: 1,
      ok: 'Right: nothing is saved until the page is complete.' },
  ],
});
