# Proving the native app against the web app

The native app is trusted with the training plan only as far as it can be
shown to do what the web app already does. These tools are that showing.
Both need the web app (`../AMS Workout Sync`) served on
`http://localhost:7810/`, Playwright on `NODE_PATH`, and `CHROME_PATH`
pointing at Chrome — the same setup as the web app's own tests.

```bash
swift build -c release --package-path Core
```

## Stage 1 — reading

```bash
Core/.build/release/plan-dump books/*.xlsx > native.json
node tools/js-dump.js books/*.xlsx > web.json
python3 tools/parity.py web.json native.json        # ends "differences: none"
```

Every session, field by field: date, sport, title, sections, planned
duration and its unit, results, logged, missed — and the layout detected.

## Stage 2 — writing

```bash
Core/.build/release/plan-dump books/*.xlsx > plan.json
python3 tools/make-scenarios.py plan.json books > scenarios.json
Core/.build/release/write-dump scenarios.json native/
node tools/js-write.js scenarios.json web/
python3 tools/write-parity.py scenarios.json web native   # ends "differences: none"
```

Each scenario applies one or more logging steps (full log, one tap, clock
times, decimal commas, junk input, XML specials, emoji, control characters,
a correction over a logged session, missed, three kinds of move, a week of
sessions in one sync) to a fresh copy of a workbook, through each app's own
buildEdits → writeCells → save. The two archives must have the same parts in
the same order with the same headers and CRC; unchanged parts must be the
same compressed bytes; changed parts must be the same bytes once unpacked
(Apple's and the browser's deflate encode identical input differently).

**2026-09-14, first run:** 336 scenarios over his real Ironman and
Pre-Season plans and 16 fixtures — differences: none. A single planted
character in one note was caught. All 336 native outputs pass `unzip -t` and
open in openpyxl.

Not yet covered, and so not yet allowed in the app: extras (appending to the
Extras sheet, creating it), and everything around a sync — the Dropbox
download and upload, the revision check, verify-before-upload, the queue.
