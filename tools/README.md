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

**Second run, same day:** the first 336 never reached several branches —
his plans and every openpyxl fixture already carry fullCalcOnLoad, no
formulas in result columns, text dates, minutes, kilometres. So
`tools/make-edge-books.py` builds eight workbooks that do: no calcPr, calcPr
without the flag, formulas + calcChain in the result columns, date-styled
dates and a "Logged on" column with hours and metres, the 1904 date system,
h:mm:ss durations, one row per section, a stale dimension with self-closed
rows. Reading: differences none. Writing, all books together: **513
scenarios, differences: none**, with each branch confirmed hit (chain
removed, flag added both ways, 1904 serials, time fractions, metres,
section groups, dimension widened). One harness fault found on the way: a
step without a log time lets each writer stamp "now", so every step now
carries one.

**Extras (2026-09-15):** `make-scenarios.py` adds six extras scenarios per
workbook — one extra (creating the sheet where there is none), three in one
sync, a genuine repeat (same day, activity and length, its own ref), a replay
(same ref twice, written once), two without refs (the pre-v1.55.0 shape), and
extras mixed with logs. Both writers create the sheet (four parts: sheet XML,
[Content_Types], rels, workbook.xml), append to his real Extras sheet, add the
Ref heading to a ten-column sheet, and leave a foreign "Extras" sheet alone.
**651 scenarios, 182 with extras: differences none.**

Still outside these tools: the sync itself. `Core/.build/release/sync-check
<xlsx> <dir>` covers that against a file-backed Dropbox — a queue of four in
one upload, a conflict retried, a second conflict refused, a reworded row
followed, a row changed to another sport refused, one bad entry not blocking
the rest, verify refusing bad bytes, the overlay and swap list, and extras
appended without doubling.

## Progress — the figures

```bash
Core/.build/release/stats-dump books/*.xlsx > native-stats.json
node tools/js-dump.js books/*.xlsx > web-stats.json      # carries a `stats` block from AmsSync.stats()
python3 tools/stats-parity.py web-stats.json native-stats.json
```

Kept / missed / unanswered, streaks, by sport, missed-or-moved, the trends
(distance per heartbeat, then against now) and twelve weeks of load, from the
same workbooks on the same day. **2026-09-15: 23 workbooks, differences none**
(season-underway.xlsx reaches "enough" for all three trend sports). The road
card is native-only arithmetic (the web app keeps it inside ui.js); its parts
— race day, phases, days between — are simple and read-checked.

## Zones — the Test Results & Zones sheet

```bash
Core/.build/release/zones-dump books/*.xlsx > zones-native.json
python3 tools/zones-parity.py zones-native.json books/*.xlsx
```

`Core/Sources/WorkoutCore/Zones.swift` reads the sheet by its shape (the
"Test block" heading row, the "CURRENT" row, the row with "ZONES" in it, the
"ABBREVIATIONS" row) and cuts the tables down to what a session's intensity
names. `tools/zones-parity.py` is a second reader written apart, in openpyxl,
plus the same worked examples. **2026-09-16: his plan, the TEST copy and 23
fixture workbooks, differences none** (the fixtures have no zones sheet; both
sides read nothing).

## The Training calendar

Not a parity check — the web app only exported a week as a file — but the
simulator can prove it: `xcrun simctl privacy <udid> grant calendar
com.schabbauer.AMSWorkoutSync`, launch with `SIMCTL_CHILD_AMSWS_CALENDAR=1`,
then read the simulator's calendar database:

```bash
sqlite3 ~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Calendar/Calendar.sqlitedb \
  "select datetime(i.start_date+978307200,'unixepoch'), i.all_day, i.summary from CalendarItem i join Calendar c on c.ROWID=i.calendar_id where c.title='Training' order by i.start_date limit 8;"
```

2026-09-16: 413 events from today to the end of the plan, the second session
of a day starting when the first ends, rest days all-day, and a second launch
left the count at 413.
