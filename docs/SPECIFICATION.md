# AMS Triathlon Training — Specification

> **Name note.** This app was called **Workout Sync** up to version 1.1 (72). From 1.2 (73) the shown name is **AMS Triathlon Training**. It is the same app: same bundle id `com.schabbauer.AMSWorkoutSync`, same URL scheme `amsworkoutsync://`, same repository. Source file names, the Xcode target and the Swift package still say "WorkoutSync" or "WorkoutCore". Where this document quotes a text the app shows, the quote is what the code says today (version 1.2 (73)); section 12.6 records the texts that were renamed in 1.2 and the places that keep the old word on purpose.

This document describes the app **as the code is today** (2.14 build 90, 26 November 2026; the last sections, "New in 2.6" to "New in 2.14", are the newest and win where they differ). Sections 1 to 15 were written for 1.2, where the plan lives in Excel; **from 2.0 the plan may instead live in the app — read the last section, "New in 2.0 (74)", beside every section that speaks of the workbook, Dropbox or waiting to sync.** **From 2.2 the app also runs on iPad and Mac and shares the plan through iCloud; sections 1.2 (iPhone only, portrait only) and 2 (the bottom bar) describe the iPhone, and the last section, "New in 2.2 (76)", describes the rest.** **From 2.3 the app can suggest changes by a fixed rule book, can ask Claude to pick among them (optional, off until a key is typed), and talks to two neighbour apps; the last section, "New in 2.3 (77)", describes them.** Where a code comment and the code disagree, the code wins. Every rule names the file that holds it. All examples are invented.

Source layout:

| Folder | Holds |
|---|---|
| `App/Sources` | the SwiftUI app (iPhone) |
| `Core/Sources/WorkoutCore` | the rules library (a Swift package): zip, xlsx, mapping, plan, writer, edits, extras, sync, stats, effort, load, zones |
| `Core/Sources/*` (other folders) | seven Mac command-line checks: `plan-dump`, `write-dump`, `sync-check`, `form-check`, `stats-dump`, `zones-dump`, `soak` |
| `Core/Tests/WorkoutCoreTests` | model tests (XCTest, eleven files) and one fixture workbook |
| `UITests` | UI tests and an invented fixture workbook |
| `tools` | parity checks against the older web app, icon scripts, export options |
| `project.yml` | XcodeGen project description |

---

## 1. What the app is for

### 1.1 Purpose

A training plan lives in an Excel workbook (`.xlsx`) in the user's Dropbox. The app:

1. reads the workbook and shows the week, the day, every session and some progress figures;
2. lets the user say what was done (a session as planned, a session with details, a missed session, a moved or swapped session, an extra workout the plan did not ask for);
3. writes that back **into the cells that already exist**, and nowhere else, keeping every other part of the workbook byte for byte as it was.

The plan is built for swim, bike, run, strength and mobility, with bricks (bike plus run) and a race. It is a triathlon plan, but the reader is generic: any workbook whose headings the mapping can recognise works (section 4).

### 1.2 Platform

| Item | Value | Source |
|---|---|---|
| Device | iPhone only (`TARGETED_DEVICE_FAMILY: "1"`) | `project.yml` |
| Orientation | Portrait only | `project.yml`, `Info.plist` |
| Minimum iOS | 17.0 | `project.yml`; `Core/Package.swift` also says macOS 14 for the Mac checks |
| Language | English only; dates are formatted with locale `en_GB`, time zone UTC | `Theme.swift` (`Dates`) |
| UI toolkit | SwiftUI, with Swift Charts on Progress | |
| Swift | `SWIFT_VERSION 5.0` for the app; package tools version 5.9 | |
| Category | `public.app-category.healthcare-fitness` | `project.yml` |
| Entitlement | HealthKit (read only; `com.apple.developer.healthkit` and an empty access list) | `AMSWorkoutSync.entitlements` |
| Permissions text | Calendar (full access), Camera, Health read, Health update (text required by Apple, nothing is written) | `project.yml` |
| Extras in Info | `ITSAppUsesNonExemptEncryption` false; `LSSupportsOpeningDocumentsInPlace` true; `UIFileSharingEnabled` false | |
| URL scheme | `amsworkoutsync` (used for the Dropbox sign-in return) | `Info.plist`, `Dropbox.swift` |

### 1.3 Where data lives

| Data | Where | Notes |
|---|---|---|
| The plan, results, extras, zones, test results | The workbook in Dropbox (or a read-only copy picked in Files) | The only record that counts. |
| Last workbook read successfully | `Application Support/workbook.xlsx` | Lets the app open offline. Overwritten on every successful read that is not from cache. |
| Waiting log ("the queue") | `Application Support/queue.json` | Logged on the phone, not yet in Dropbox. **The only copy** until it is sent. If it cannot be read, a copy is kept as `queue-unreadable.json`. |
| Photographs | `Application Support/photos/<id>.jpg` and `photos/index.json` | Never in the workbook, never in Dropbox. Included in the iPhone's own backup. |
| Move log | UserDefaults key `moveLog` | One record per moved session; at most 600 kept. |
| Which sessions had Health numbers used | UserDefaults key `healthFilled` | At most the last 800 ids. |
| Dropbox refresh token | Keychain, service `com.schabbauer.AMSWorkoutSync`, account `dropbox.refresh`, accessible after first unlock | Never in UserDefaults. |
| Other settings | UserDefaults: `dropboxPath`, `dropbox.account`, `workbookBookmark`, `workbookName`, `workbookReadAt`, `health.asked`, `health.enabled`, `log.showAllFields`, `calendar.enabled`, `calendar.start`, `calendar.allDay`, `calendar.id`, `calendar.events`, `calendar.count`, `calendar.lastSync` | |
| Calendar events | The iPhone Calendar app, in a calendar called "Training" | Section 9.7. |

From 2.0, once the plan has moved in, the plan itself is kept on the phone as well (`plan.json`, `plan-original.xlsx`, `backups/`, and spreadsheet copies in Documents; see P.6), and `plan.home`, `plan.switchedAt` and `plan.lastSpreadsheet` join the UserDefaults keys.

What is kept **only on the phone** and is not in the workbook: the waiting log, photographs, the move log (used by Progress "moved rather than lost"), the Health-used marks, the cached copy, the calendar memory, and all settings.

### 1.4 Dependencies

`WorkoutCore` (local package), `HealthKit`, `EventKit`, `PhotosUI`, `AuthenticationServices`, `CryptoKit`, `Security`, `Charts`, `Compression`. No third-party packages.

---

## 2. Navigation: the bottom bar and swiping

Source: `AMSWorkoutSyncApp.swift`.

### 2.1 Root

* `RootView` is a `TabView` in page style (`.tabViewStyle(.page(indexDisplayMode: .never))`) with four pages tagged `today`, `plan`, `progress`, `settings`. The pages are swiped between; there is no system tab bar.
* The keyboard does not move the layout (`ignoresSafeArea(.keyboard)`).
* A custom `BottomBar` sits in a bottom safe-area inset.
* The accent tint of the whole screen is the open page's colour: Today green, Sessions blue, Progress violet, Settings slate (section 11).

### 2.2 The bottom bar

Four equal cells, left to right:

| Id | Word | Glyph | Colour |
|---|---|---|---|
| `today` | Today | swim | Today green |
| `plan` | Sessions | bike | Plan blue |
| `progress` | Progress | run | Progress violet |
| `settings` | Settings | strength | Settings slate |

* Every glyph keeps its own colour whether open or not. The word is in the colour only when the tab is open, otherwise grey.
* The open tab fills its whole cell with its colour at 16 % opacity, from the top of the bar to the bottom of the phone.
* Each cell is at least 50 points tall; the bar has a 0.5 point top line and a bar material background.
* Tapping another tab animates (0.2 s ease) to it. **Tapping the tab already open** resets that tab's navigation path to its first screen (Today, Sessions, Settings; Progress has no path).
* Accessibility identifiers: `tab-today`, `tab-plan`, `tab-progress`, `tab-settings`.

### 2.3 App life

* On every return to the foreground (`scenePhase == .active`) the app calls `store.refresh()` and `HealthImport.readMorning()` (the night's numbers arrive while the app is closed).
* The Store is created once and shared through the environment.

---

## 3. The Store: what the app holds and how it behaves

Source: `Store.swift`.

### 3.1 Loading states

`Store.Phase`: `empty`, `loading`, `ready`, `failed(message)`.

* On start the queue is loaded, then the cached workbook (if any) is parsed as "from cache".
* Every screen shows `EmptyWorkbook` when there is no mapping yet (section 5.2).
* A read that fails keeps the old plan if there is one and sets `lastProblem`; if there is no plan the phase becomes `failed`.

### 3.2 Where the plan comes from

1. **Dropbox (normal).** `dropboxPath` is set (the file the user chose in the app's Dropbox browser) and Dropbox is connected. Refresh downloads the file through the Dropbox API and remembers its revision `rev`.
2. **Files (read only).** A workbook picked with the Files app is remembered as a security-scoped bookmark and read with a coordinated read (so Dropbox's provider hands over its current copy). A stale bookmark is renewed. This path can never write.
3. **Cache.** The last good copy.

`refresh()`:

* If Dropbox is connected and a path is set: **if the queue is not empty it calls `syncNow()` and returns** (it does not download separately). Otherwise it downloads, stores `rev` and the file name, and parses.
* Else if a bookmark exists: a background coordinated read, parsed on the main actor.
* Pull-to-refresh on Today and Sessions calls `refresh()`.

A successful (non-cache) parse: clears `lastProblem`, stamps `readAt`, and writes the bytes to the cache file. Every parse also tells the calendar to update (section 9.7).

`parse` builds, from one `Workbook`: the mapping (`Plan.mapping`), the plan (`Plan.build`), the extras (`Extras.read`), the zones (`Zones.read`). If no mapping is found the error is "Nothing in this workbook looks like a training plan."

**2.0:** when the plan lives in the app (`home == .app`) none of the three sources above is used: the plan is the book `plan.json`, `refresh()` does nothing, and nothing is downloaded. See P.1.

### 3.3 The displayed plan

`displayed = Sync.overlay(plan, queue)`: the sheet's plan with the waiting log laid over it, so what was just logged or moved shows at once (rules in 9.2). `view` is a `PlanView` of the displayed plan plus `allExtras`.

`allExtras` = waiting extras first (newest first), then the sheet's extras (already newest first). A waiting **correction** to a saved extra is not a row of its own: it is laid over the row it corrects (the last correction for that row wins) and that row is marked waiting.

### 3.4 "Today"

`store.today` is the phone's own calendar date as `YYYY-MM-DD` (`PlanView.todayKey`). In DEBUG builds `AMSWS_TODAY` overrides it (section 14).

### 3.5 Can the app write? — `canLog`

`canLog` is true when `dropboxPath != nil` **and** Dropbox is connected (a refresh token is in the Keychain). In DEBUG, `AMSWS_SHOW_BUTTONS` forces it true.

When `canLog` is false (not connected, or connected but no plan chosen):

* Today shows a **Connect Dropbox** / **Choose your plan** button in the header instead of the waiting chip.
* Hidden: the Extra workout pill; the Done / Log details / Missed / Move row on a session; the pen buttons (on sessions in the list, on a session screen, on extras); "Fill from Garmin"; the **Add** button on Settings → Extra workouts; the Waiting to sync and Dropbox sections show their not-connected forms.
* Still available: reading everything, Progress, zones, photographs (viewing; adding happens behind the pen, so also hidden), sharing a session, Health and Calendar settings, the guide.
* All the Store's writing methods (`log`, `logAsPlanned`, `logExtra`, `editExtra`, `move`, `swap`) return without doing anything when `canLog` is false.

### 3.6 Logging methods (all queue first, then send)

| Method | What it queues |
|---|---|
| `logAsPlanned(w)` | Only when planned seconds > 0. A `LogEntry` with `actualDuration` = whole minutes of the planned length, rounded half up (`floor(seconds/60 + 0.5)`) as a string. Nothing else. |
| `log(w, entry)` | The entry from the log form (only changed boxes). |
| `markMissed(w, note)` | `missed = true`; `notes` = trimmed note if not empty. |
| `move(w, to)` | Only if the day differs and `canLog`. `moveTo = day`. Also remembers the move (3.7). |
| `swap(a, b)` | Only if the days differ. Two queue entries: a moves to b's day, b moves to a's day (both days read before either is queued). Remembers both moves. |
| `logExtra(e)` | A `QueuedEntry` carrying the extra. |
| `editExtra(original, entry, fields)` | See 9.4. |

Each of these saves the queue file (atomic write) and then calls `syncNow()`. Saving the queue also tells the calendar to update.

### 3.7 The move log

`moves[workoutKey] = MoveRecord(from, to, disciplineId, at)`. A session moved twice is one move from where the plan first put it (`from` is kept from the first record). Kept only while the sport still matches the row (`Stats.moveFor`). Over 600 records, the oldest are dropped. Stored as JSON in UserDefaults `moveLog`. `movesSince` is the date of the oldest record.

### 3.8 Waiting too long

`waitedTooLong` is nil until the oldest queue entry is at least 24 hours old. Then it is `"<n> entry has / entries have waited a day|N days. <reason>"` where N days is shown from 48 hours, and the reason is the last queue entry's `lastError`, else `lastProblem`, else "The phone may have been offline, or Dropbox unreachable." Today shows it as a red-framed card (5.1).

### 3.9 Sync from the Store

`syncNow()` runs only when not already syncing, the queue is not empty, a path is set and Dropbox is connected. It takes a snapshot of the queue and runs `Sync.run` (section 9.3). Afterwards:

* entries in `written` or `dropped` are removed from the queue;
* every entry in `failed` gets `attempts + 1` and its `lastError`;
* the queue is saved;
* if an upload happened: `rev` is updated and the uploaded bytes are parsed as the new plan;
* `lastProblem` = "Some logging could not be written — see Settings." if any failed, else nil;
* a second conflict: "The plan kept changing in Dropbox while sending. Your logging is still waiting; try again in a moment.";
* any other error: "Could not send your logging just now: <error> It is still waiting on this phone."

`discard(id)` removes one queue entry (Settings → Discard).

### 3.10 Progress inputs

`store.progress` is derived on the spot from the displayed plan: `Stats.summarise`, `Stats.trends`, `Stats.load` over the last 12 **completed** weeks, `Stats.road`, and the fitness/fatigue curve (section 10). Nothing is cached and nothing is written.

---

## 4. Reading the workbook

Sources: `Zip.swift`, `Xlsx.swift`, `Mapping.swift`, `Plan.swift`, `Extras.swift`, `Zones.swift`.

### 4.1 Zip and xlsx

* `ZipArchive` reads the central directory for sizes and CRC, and the local header for where the data starts. Writing copies every unchanged entry **still compressed with its original CRC**; only parts an edit touched are compressed again. Headers are written one fixed way (version 20, UTF-8 flag, fixed 1996-01-01 date, no extra fields) so that the native and web writers differ only in deflate bytes.
* `Workbook` reads `xl/workbook.xml` (sheet names, hidden state `hidden`/`veryHidden`, the 1904 date system), the relationships, shared strings (rich text joined across runs), and styles. Only the `<cellXfs>` table maps a cell's `s=` index.
* A style is a **date style** if its number format id is one of the built-ins 14–22, 45, 46, 47, or its custom format code contains one of `y m d h s` after removing quoted text, bracketed text and backslash escapes.
* Cell types: shared string, inline string, formula string and error (raw value as text), boolean (`TRUE`/`FALSE`), number. A number in a date style becomes a date and its text is its `YYYY-MM-DD` key (read in UTC, so no timezone slides a workout a day). Other numbers become text the way JavaScript prints a number (`40`, not `40.0`; `jsNumberString`).
* 1904 workbooks add 1462 days. A cell's formula text is kept; the value read is **Excel's last answer, never recalculated**.
* Errors: "This file is not a workbook — xl/workbook.xml is missing."; "This workbook has no readable sheets."; "No sheet named "<name>" in this workbook."; "This workbook has no relationships part, so a sheet cannot be added."

### 4.2 Finding the plan: header detection (`Mapping.swift`)

The mapping is guessed from the workbook; there is no screen to correct it.

**Fields.** Each field has an id, label, group (plan, section, result) and a list of synonyms (English and German). Headings are normalised first: lower case; ä ö ü ß flattened; accents removed; anything outside `a–z 0–9 /` becomes a space; spaces collapsed.

| Group | Field id (label) | Synonyms (normalised) |
|---|---|---|
| plan | `date` (Date) | date, datum, day, tag, when, workout date, trainingstag |
| plan | `phase` (Phase or block) | phase, block, period, mesocycle, trainingsphase, zyklus, makrozyklus, stage |
| plan | `weekday` (Weekday) | day, weekday, tag, wochentag, week day |
| plan | `discipline` (Discipline) | discipline, sport, sportart, activity, aktivitat, type, art, workout type, trainingsart, disziplin |
| plan | `title` (Session name) | session, workout, title, name, einheit, training, session name, ubung, beschreibung kurz |
| plan | `plannedDuration` | planned duration, plan duration, duration plan, target duration, soll dauer, geplante dauer, dauer plan, planzeit, target time, duration, dauer, zeit, time |
| plan | `plannedDistance` | planned distance, plan distance, target distance, soll distanz, geplante distanz, distance, distanz, strecke, km, meter |
| plan | `description` | description, details, detail, beschreibung, inhalt, content, ubung, vorgabe, aufgabe, programm, purpose, zweck, focus |
| plan | `plannedIntensity` | intensity, intensitat, zone, target zone, zielzone, belastung, target hr, ziel puls, target, ziel, pace target |
| section | `warmup` | warm up, warmup, warm-up, aufwarmen, aufwarmung, einlaufen, einschwimmen, einrollen, warming up |
| section | `intervals` | intervals, interval, intervalle, main set, mainset, main, hauptteil, hauptsatz, set, sets, belastung, kernsatz, body |
| section | `cooldown` | cool down, cooldown, cool-down, abwarmen, auslaufen, ausschwimmen, ausrollen, abkuhlen |
| section | `technique` | technique, technik, drills, drill, form, technikubungen, skills, koordination |
| section | `sectionLabel` | section, abschnitt, teil, part |
| result | `actualDuration` (Duration) | actual duration, duration actual, ist dauer, dauer ist, real duration, tatsachliche dauer, actual time, ist zeit, gesamtzeit, moving time, elapsed time, actual min/mins/minutes/h/hours/hrs, ist min, ist minuten |
| result | `actualDistance` (Distance) | actual distance, ist distanz, distanz ist, gelaufen, real distance, tatsachliche distanz, actual km |
| result | `avgHr` (Average heart rate) | avg hr, average hr, avg heart rate, average heart rate, hr, heart rate, puls, herzfrequenz, durchschnittspuls, hf, mittlere hf, ø puls |
| result | `maxHr` (Max heart rate) | max hr, maximum hr, max heart rate, maxpuls, max puls, maximalpuls, hf max, max hf |
| result | `avgPace` (Pace) | pace, avg pace, average pace, tempo, schnitt, min/km, pace /100m, pace per km |
| result | `avgSpeed` (Speed) | speed, avg speed, average speed, geschwindigkeit, km/h, schnitt kmh, ø geschwindigkeit |
| result | `avgPower` (Power) | power, avg power, average power, watt, watts, leistung, np, normalized power |
| result | `cadence` (Cadence) | cadence, kadenz, trittfrequenz, schrittfrequenz, rpm, spm |
| result | `elevation` (Elevation gain) | elevation, elevation gain, ascent, hohenmeter, hm, anstieg, climb |
| result | `calories` (Calories) | calories, kalorien, kcal, energy, energie |
| result | `rpe` (Perceived effort (RPE)) | rpe, perceived effort, effort, anstrengung, borg, empfinden, gefuhl, feeling |
| result | `notes` (Notes) | notes, note, notizen, notiz, comment, comments, kommentar, bemerkung, bemerkungen, remarks |
| result | `done` (Completed) | done, completed, complete, erledigt, fertig, status, abgehakt, absolviert, ok |
| result | `completedAt` (Logged on) | logged, logged on, completed on, completed date, erfasst, eingetragen, log date |

The **result fields** are the ones the app may write (`write: true`): the eleven from `actualDuration` to `completedAt` plus `done`; the plan fields are never written except `date` and `weekday` by a move.

**Heading score** (`scoreHeading`) for a heading and a field, over its synonyms, taking the best:

* heading equals the synonym: `1000 + 10 × length`;
* heading starts with `synonym + " "` or ends with `" " + synonym`: `400 + 10 × length`;
* heading contains the synonym: `200 + 10 × length`;
* otherwise 0.

**Header row** (`scoreHeaderRow`), for rows 1 to min(last row, 40) of every non-hidden sheet:

* a row with fewer than 2 non-empty cells, or with any real date cell, is not a header;
* every (cell, field) pair with a score is sorted by score, ties by order met; then assigned greedily: a field takes one column, a column takes one field;
* total = sum of the assigned scores; **if neither `date` nor `discipline` was assigned the total is divided by 4** (integer division);
* a row with no assignment is not a header.

The best-scoring row over all sheets wins (first one on a tie).

**Section column.** If `sectionLabel` was claimed, it is dropped unless it *looks like* one: within 120 rows after the header, at least 3 non-empty cells and at least `max(3, 40 %)` of them equal or contain a section synonym.

**Mode.**

| Mode | When |
|---|---|
| `section-rows` | `sectionLabel` survived. One session spans several rows (one per section). |
| `section-columns` | any of warmup, intervals, cooldown, technique has a column. |
| `simple` | otherwise. |

**Sheets.** The plan sheet, plus every other non-hidden sheet whose heading row (same row number) has the same normalised text in the same order.

**Last data row** (`findLastDataRow`): from the first data row, a row with any non-blank cell counts; 12 blank rows in a row end the search (the search never goes past last row + 5).

### 4.3 Units and the done marker (`Plan.mapping(for:)`)

Always build the mapping with `Plan.mapping(for:)`, never the bare detection; the wrapper reads units.

* **Duration unit** (`hours`, `minutes`, `time`): taken from the actual-duration heading, else the planned-duration heading (a word like min/mins/minute/minutes/minuten gives minutes; h/hr/hrs/hour/hours/std/stunden gives hours; hh, hh mm, hh mm ss, h mm gives time); else inferred from the data in the actual column, then the planned column (first 200 data rows): if at least one cell has a date style and at least half of the numbers do, `time`; else the median of positive numbers ≥ 10 means minutes, below 10 hours; else `hours`.
* **Distance unit** (`km` or `m`): heading words (km, kilometer…; m, meter, metres, meilen) else the median of positive numbers ≥ 400 means metres; else `km`.
* **`paceIsTime`**: true when at least half of the pace column's styled cells have a date/time style.
* **Done and missed markers**: read from COUNTIF formulas anywhere in the workbook that reference the done column and a quoted word of 1–24 characters. The first quoted word among {✓ ✔ ✅ x yes y ja done ok erledigt fertig complete completed true 1} is the **done value**; the first among {missed miss skipped skip verpasst ausgefallen versaumt nein no not done dnf abgebrochen false 0} is the **missed value**. Defaults: `Yes` and `Missed`.

Durations convert to seconds: `time` × 86400; `minutes` × 60; `hours` × 3600.

### 4.4 Building sessions (`Plan.build`)

For each plan sheet, for rows from the first data row to the last data row:

* The date is the row's date; an empty date **carries over** from the row above.
* A date cell is read from a date-styled number, else from text: ISO `YYYY-M-D` at the start, or `D.M.YY(YY)` / `D/M/YY(YY)` (two-digit years become 20xx). An impossible day rolls over like JavaScript's `Date.UTC` (31 February = 3 March) in the plan reader.
* A row with no discipline text, no title, no section text and no description is empty; an empty row ends the current session group.
* In `simple` and `section-columns` mode a row **must** have a discipline text.

**Simple / section-columns mode**: one session per row. Key = `<sheet>!<row>`.

**Section-rows mode**: consecutive rows with the same day and the same normalised discipline (a blank discipline carries the one above) are one session; its key is `<dayKey>|<normalised discipline>`; its `rows` lists every row. The section text is the description, else the title; its kind is classified from the section column. Planned durations of the rows are added up.

**Sections** (the blocks shown on a session): in column mode, one per non-empty section column in the order warm-up, intervals, technique, cool-down; if none, one "Session" block from the description, else the title (its heading is the description column's heading if there is one). Labels: Warm-up, Intervals, Cool-down, Technique, Session. Sorted into that order, ties keep sheet order.

**Discipline** (`Disciplines.classify`): normalise the text; empty gives Other. Match against every synonym of Brick, Race, Rest, Swim, Bike, Run, Strength, Mobility: equal, or starts with, or contains; **the longest matching synonym wins**; none gives Other.

| Id | Label | Synonyms |
|---|---|---|
| swim | Swim | swim, swimming, schwimmen, schwimmtraining, pool, open water, freiwasser, kraul, crawl, bahnen |
| bike | Bike | bike, biking, cycling, cycle, rad, radfahren, radeln, velo, ride, spinning, mtb, rennrad, turbo, rollentraining, indoor bike |
| run | Run | run, running, laufen, lauf, jog, jogging, joggen, trail, trailrun, dauerlauf, bahn |
| strength | Strength | strength, kraft, krafttraining, gym, weights, lifting, core, rumpf, stabilisation, stabi, athletik |
| mobility | Mobility | mobility, mobilitat, beweglichkeit, yoga, faszien, foam roll, faszientraining, mobi, stretch, stretching, dehnen, dehnung, flexibility, dehnprogramm |
| brick | Brick | brick, bike run, bike + run, rad lauf, koppeltraining, koppel |
| race | Race | race, rennen, wettkampf, ironman, event, competition |
| rest | Rest | rest, rest day, ruhetag, ruhe, pause, frei, off, day off, recovery day |
| other | Other | (none) |

`Disciplines.order`: swim 0, bike 1, run 2, strength 3, mobility 4, anything else 5.

**Title.** If empty it becomes the discipline label, plus " — " and the first 40 characters of the first section.

**Results.** For each result field with a column, the cell's trimmed text (and number and date). A session is **logged in the sheet** (`loggedInSheet`) if any of `actualDuration`, `actualDistance`, `avgHr`, `done`, `notes`, `rpe` is not empty. **Missed** is true when the `done` cell's normalised text equals the normalised missed value.

**Order.** Sessions are sorted by date, then row, then reading order.

**Planned seconds** = planned duration cell × the duration unit (section 4.3); nil if the cell has no number.

### 4.5 What is shown vs. hidden: rest rows (`Week.swift`)

A rest row says "nothing today". `PlanView.visible` hides a rest row on a day that also has a training session (a session moved onto a rest day). The rest row stays in the plan; moving the session away brings the rest day back. If the whole plan has no training at all, everything is visible.

### 4.6 The Extras sheet reader (`Extras.swift`)

* Sheet name: `Extras`. If a sheet by that name exists but its first row is not ours (see below), the names `AMS Extras`, `AMS Extras 2` … `AMS Extras 20` are tried in turn; if all are taken by foreign sheets, the error "There is already a sheet called "Extras" that is not this app’s, and no free name to use instead."
* **Ours** means row 1 has `Date` in column A, `Activity` in column C, and a heading starting `Duration` in column E (normalised).
* Columns, in order: `Date`, `Day`, `Activity`, `What it was`, `Duration (min)`, `Distance (km)`, `Avg HR`, `Effort`, `Counts as training`, `Notes`, `Ref`.
* Reading: rows 2 to last; a row with neither date nor activity text is skipped. The activity text is matched to a known activity label (normalised) else becomes "other" with the text as label (empty gives "Something else"). "Counts as training" is true when the text starts with `y`, `j`, `1` or `true` (any case). Sorted newest day first, then higher row first.
* The reader is used only if the sheet is ours; otherwise there are no extras.

### 4.7 The zones sheet reader (`Zones.swift`)

Details in section 9.8.

---

## 5. Today

Source: `TodayView.swift`. Page colour: Today green. No navigation bar. Pull to refresh re-reads the plan.

### 5.1 Order of things, top to bottom (when a plan is loaded)

1. **Header row.** Left: the phase title — the plan's phase for today (the phase of today's session, else the nearest earlier session with a phase, else the first phase in the plan), in bold green; if there is none the word "Today". Right: if `canLog`, the **plan chip**; otherwise the **Dropbox chip**.
   * *Plan chip* shows only when something is to say: "Sending…" while syncing; "N waiting" when the queue has N entries; "TEST COPY" (white on orange) when the file name contains "test" (any case) and nothing is waiting. Otherwise nothing.
   * *Dropbox chip* is a small bordered button: "Connect Dropbox" or, if Dropbox is connected but no plan is chosen, "Choose your plan". It switches to the Settings page. Identifier `today-connect-dropbox`.
2. **Waiting warning** (only when the oldest waiting entry is a day old, 3.8): a card with a red frame: heading "Logging has not reached Dropbox", the reason text, and a small green button **Send it now** (green since 2.4: it is the step that puts things right; the red frame is the warning) (reads "Sending…" and is disabled while syncing).
3. **Morning line** (5.3).
4. **The morning question** (5.3, `FeelCard`; section "New in 1.2" below): "How do you feel?" with five faces. Present only while today has no answer, or while the answer is being changed.
4a. **Suggestion area**, straight after the morning question: a suggestion card when there is one, or one grey line when suggestions are paused (see the suggestions section).
5. **This week card** (5.4).
6. **Today's sessions.** If the day has none: a rest card "Nothing planned today". If every row of the day is a rest row: a rest card with the rest row's title. Otherwise one session card per session (5.5).
7. **Extras of today** under the heading "EXTRA, OUTSIDE THE PLAN": one extra card each. Tap opens the extra's detail screen (8.5).
8. **Extra workout pill** (only if `canLog`): when there is **no** Tomorrow block it stands alone at the right; otherwise it sits at the right end of the TOMORROW line (item 10).
9. **Behind you, not recorded** (heading "BEHIND YOU, NOT RECORDED"): training sessions with a day before today and not logged, **only from the last 7 days** (`dayKey >= today − 7`), each as a session card that also shows its day.
10. **Tomorrow block** (only if tomorrow has any visible row): on a pale blue ground (section 11). A "TOMORROW" tab with a rounded top; if `canLog` the Extra workout pill sits at the right end of the same line on the page's own ground. Under it: a rest card if every row is a rest row; otherwise the non-rest sessions' cards (rest rows hidden).

11. **Not well?** (only when the plan lives in the app): one small grey pill, centred, the last thing on Today, under the Tomorrow block. It opens the plate with Stop sign and I'm ill (see "The one pill").

Only tomorrow is shown, not the week ahead.

Each session card on Today is a link to the session detail (section 7). If a session has photographs, up to three micro-thumbnails (30 × 30 points) sit in the card's bottom-right corner and the pills keep clear of them. Session cards' identifiers: `today-session-<dayKey>-<disciplineId>`.

Extra workout pill: small bordered "＋ Extra workout" (plus glyph and text), identifier `today-add-extra`. It opens the extra form (8.1) for today.

### 5.2 Empty state (no plan loaded)

Centered: the plan glyph in green, "Your training plan", the failure message in red (if the phase failed) or a spinner (if loading), a full-width green button **Choose the workbook** (opens the Files picker, read-only), and the line "In Files, open Dropbox and pick your plan. This app only reads it." The same empty state appears on Sessions. On Progress the empty card says "Nothing loaded — Choose your plan in Settings and this fills itself in."

### 5.3 The morning line

A single row, footnote size, one line (shrinks to 80 %), directly under the heading (pulled up by 9 points), identifier `morning-line`. It is shown only if Health gave at least one of sleep, resting heart rate, HRV, or today's morning question has an answer (1.2). Parts in this order, separated by three spaces:

* `Slept 7h 24m` — name grey, value bold. If whole minutes are 0, `7h`.
* `Resting 48 (−2)` — resting heart rate, rounded.
* `HRV 64 (+6)` — HRV, rounded.
* `Feeling good` — last, only once the morning question is answered (1.2); name grey, word bold (`Feeling OK` for the middle answer). A tap on the line brings the question back to change the answer.

The bracket always follows resting and HRV:

* with a normal: the difference `value − normal`, rounded to a whole number, shown as `+n`, `−n` or `±0`;
* the bracket is **green** if the difference is at least `max(1, 4 % of normal)` in the good direction (lower is good for resting heart rate, higher for HRV), **red** if that big in the bad direction, otherwise grey;
* without a normal: the bracket says `(normal tomorrow)` when one more day is needed, else `(normal in N days)`, where N = `max(1, 4 − days available)`; grey.

The spoken label (VoiceOver and tests) is the same in words: "Slept 7h 24m. Resting heart rate 48, 2 below your normal. HRV 64, 6 above your normal." (and, since 1.2, "Feeling good." last) with "as usual" when the difference is small and ", normal tomorrow" / ", normal in N days" without a normal.

The line is read again every time the app comes to the front and when Today appears (`readMorning`). Rules for the numbers: section 9.9.

### 5.4 The "This week" card

* Title "This week" and a small **Key** button (becomes **Hide key**); tapping anywhere on the card also toggles the key.
* At the right, top: if anything is done: `<done> of <planned>` else `<planned> planned`, in semibold digits (`formatDuration`).
  * *planned* = the sum of the planned seconds of the week's training sessions (Monday to Sunday of today's week).
  * *done* = the sum, over this week's sessions that are done, of the **actual** time (the waiting log first, then the sheet), or the planned time where a session was marked done without a time.
* Under it, if planned > 0, the **week hairline** (96 × 4 points): a capsule in the surface colour; filled green for `done / planned` (at least 3 points wide if > 0); a faint grey notch at `dueByToday / planned` where `dueByToday` = planned seconds of days up to and including today (drawn only between 2 % and 98 %). Under it, **extra blocks**: for extras this week that count as training, one block per quarter hour (`round(seconds / 900)`, at least 1, at most 13), 5 points wide with 2 points gap; every 4th block is amber (`extraHour`), the others green at 75 %. Identifier `week-extra-blocks`, label "Extra activities this week: <time>". Extras are **never** in the week's hours; they get their own blocks.
* **Seven columns**, Monday to Sunday, each 96 points tall, with a one-letter weekday below (today's letter is heavy, green, on a green 18 % circle).
  * One bar per training session, stacked. Bar height = `max(9, columnHeight × seconds / tallest − 3)` where `tallest` is the largest day total (planned plus extra seconds) of the week, at least 1. Bar fill: the sport colour, by state (section 11.3).
  * A **done** bar carries a small green tick in its top-right corner (7 points if the bar is under 16 points tall, else 10).
  * One dotted bar per extra of that day (height by its minutes), with a paler tick.
  * A rest day (all rest rows, no extras) is a flat grey line, 60 % of the column wide and 3 points tall.
* **Key** (also shown in Settings → Colours and shapes): see section 11.5.

### 5.5 The session card (used on Today, Sessions, Move)

Layout: the sport badge (44 points; the sport colour at 22 % behind the sport's glyph in the sport's ink colour); then a column: the sport name in capitals (caption, bold, tracked) in the sport ink; the title (headline, up to 3 lines); a flowing row of pills; the green tick at the right if done.

Pills, in this order, wrapping to the next line when full:

1. the short day (only where `showDay` is set; only the **Behind you** list on Today sets it; the Sessions list does not, because it groups by day);
2. planned length (`formatDuration`), if the planned seconds > 0;
3. planned intensity text;
4. a red **Missed** pill if missed;
5. a green waiting pill: "Waiting to sync" (a record is queued), "Missed · waiting to sync" (a missed record is queued) or "Moved · waiting to sync" (only a move is queued);
6. photograph count pill (camera glyph and number) — only when the card does not make room for thumbnails.

Frame: a done session has a 2-point green frame; a missed one a 2-point red frame at 70 %; a session still to do has none. Card background: the surface colour, corner radius 14.

### 5.6 The rest card

A rest-grey badge (rest glyph is a moon, `icon-rest`, since 1.2; before that it was the check), the text in secondary colour (two lines at most).

---

## 6. Sessions (the list)

Source: `PlanTab.swift`. Page colour: Plan blue. No navigation bar.

### 6.1 Layout

* Large title "Sessions" (identifier `sessions-title`).
* A **pinned header** that stays while the list scrolls: four filter buttons and the plan bar.
* The list, grouped by day.

### 6.2 The four filters

Buttons left to right: **Upcoming**, **Done**, **Missed**, **All**. Each is a rounded card at least 50 points tall with the word (caption) over the **count** (title3, bold digits). The open one is blue at 16 % with blue text; others grey on the surface. Identifiers `sessions-filter-upcoming|done|missed|all`. The default is Upcoming. The count is the length of the list the word opens, counted from the same list (uncapped).

Lists:

| Filter | Contents | Order |
|---|---|---|
| Upcoming | first, every training session before today that was never recorded (`outstanding`); then every visible row on or after today still to do (not done, not missed). **Capped to the first 120 rows shown**; the count is not capped. | oldest day first |
| Done | every session that is done, **plus all extras** | newest day first |
| Missed | every session marked missed | newest day first |
| All | every visible row of the plan, **plus all extras** | oldest day first |

Empty texts: Upcoming "Nothing left in the plan."; Done "Nothing recorded yet."; Missed "Nothing marked missed."; All "The plan is empty."

Rows are grouped under a day heading (long date, capital letters). Extras come after the sessions of the same day; a day with only an extra makes its own group. Days are sorted in the list's own direction.

### 6.3 The plan bar

One 10-point capsule under the four counts, from the same three lists: solid blue for done, hatched blue for missed, light blue (34 %) for upcoming, widths in proportion to their counts with 1.5-point gaps; invisible if all three are zero. Identifier `sessions-bar`, label "The plan so far", value "N done, N missed, N to do".

### 6.4 Rows

* **Session row**: the session card, a link to the session detail, identifier `sessions-session-<dayKey>-<disciplineId>`. Up to three photograph micro-thumbnails sit in the bottom-right corner. If the session is done and `canLog`, a round grey **pen** button sits beside the thumbnails (identifier `sessions-adjust-<day>-<sport>`); it opens the log form (7.4) as a sheet for correcting a typo. The pen is drawn over the card, not inside it.
* **Extra row** (Done and All only): the extra card; tap opens the extra's detail (8.5). With `canLog` a round pen (identifier `sessions-extra-adjust-<day>-<activity>`) opens the extra form in correction mode (8.1). Row identifier `sessions-extra-<day>-<activity>`.

---

## 7. Session detail, log form, move and swap

### 7.1 Session detail (`SessionView.swift`)

Reached by tapping a session card; navigation bar inline; a share glyph at top-right (accessibility label "Send it to somebody"). If the session no longer exists: "This session is no longer in the plan."

Order, top to bottom:

1. **Header**: sport badge (56 points); sport name in capitals; long date; the green tick if done.
2. **Title** (title2, bold; identifier `session-title`).
3. **Pills**, wrapping: planned length; planned distance with the sheet's distance unit; the intensity — **if the workbook has a zones sheet the intensity is a tappable pill** (sport-coloured with a `›`, identifier `zone-pill`) that opens the zone sheet (section 9.8); otherwise a plain pill; the phase name.
4. **Section cards**: one card per section (upper-case label, then the text).
5. If a record is waiting: "Logged on this phone · waiting to sync" (or "…missed · waiting to sync", "…moved · waiting to sync"), green headline.
6. **Action row** (only if `canLog` and the session is not a rest row):
   * **Done session** (record or sheet): a small row with, left, **Fill from Garmin** (heart glyph; identifier `session-fill-from-garmin`; shown only if Health has a matching workout for that day and the numbers are not already in, see 7.6) and, at the right, a grey pen button only if the session has no figures yet (otherwise the pen is beside the "What you did" heading). No Done / Missed / Move any more.
   * **Not done**: one row, all the same small size, scaled to 85 % if needed:
     1. **Done · <planned length>** — filled green, with a check glyph, only if the planned length > 0 (identifier `session-done-as-planned`). One tap writes the planned length in minutes and the done marker (3.6).
     2. **Log details** (or **Log it after all** if the session is marked missed); a heart glyph is added if Health has matching workouts (identifier `session-log-details`). Opens the log form.
     3. **Missed** — red; hidden if already missed (identifier `session-missed`). Opens an alert "Mark this session as missed?" with a text field "Why? (optional)", buttons **Mark missed** (destructive) and **Cancel**, and the message "Only the missed marker and your note are written. Nothing else in the row changes, and you can still log it later if you did it after all."
     4. **Move** — blue (identifier `session-move`). Opens the move sheet (7.5).
7. **"How hard was it?"** (1.2, `HowHardCard`, where the Done button was): shown while the session is done, `canLog`, not a rest row, the workbook has an Effort column and the sheet's Effort for the session is still empty. See "New in 1.2".
8. **"Marked missed"** in red, if missed.
9. **What you did**: heading "WHAT YOU DID" (with the pen button beside it when `canLog` and done) and a two-column grid of figure cards **taken from the sheet only** (not from the waiting log), in this order, each only if the sheet holds it: Duration (`formatDuration` if numeric, else the text); Distance (text plus the distance unit); **Speed** (bike) / **Pace /100 m** (swim) / **Pace /km** (anything else) from the pace column; Heart rate (bpm); Max heart rate (bpm); Effort ("n / 10"). Average speed, power, cadence, elevation and calories are never shown here.
10. **Notes**: the sheet's notes text in a card, in full.
11. **Photograph strip** (7.7), without the add button.

Toolbar share glyph: a confirmation dialog "Send it to somebody" with **Send what you did** (only if done) and **Send the whole session**; both open the system share sheet with the text and the session's photographs (section 9.12).

On appearing, if Health is in use (or faked), the app loads the day's Health workouts and keeps those whose sport matches: session sport `other` or `brick` takes all; otherwise equal sport; a run also accepts a Health walk.

### 7.2 "What you did" figures — unit rule

`Distance` prints the sheet's text and the sheet's distance unit (`km` or `m`). The duration prints as `Xh MMm` / `Xm SSs` / `Xm` / `Xs` (`formatDuration`: ≥ 1 h gives `1h 05m`; ≥ 1 min gives `35m`, with seconds `35m 20s`; below a minute `42s`).

### 7.3 The Done button and what it writes

`Done · 35m` writes **only** `actualDuration` (planned minutes, half up), the done marker and "Logged on". Nothing else is invented.

### 7.4 The log form (`LogFormView.swift`, `LogForm.swift`)

A sheet with a navigation title "How did it go?" for a new log, or "Adjust logged data" when the session is already recorded in the sheet or waiting. **Cancel** at top-left. The big green **Save** button is at the bottom (never grey).

Top to bottom:

1. Header line: `<SPORT> · <short date>`, and the title (grey, 2 lines).
2. **Health block** (section 7.6).
3. **Field boxes**: the primary set (the sport's own order), or all of them after "Show N more field(s)".
4. **Photo strip with the Add photo menu** (7.7).
5. If not showing all fields and some are hidden: a button "Show N more field(s)".

**Which boxes** (`LogForm.fields`): a field is offered only if the workbook has a column for it. Preferred order per sport:

| Sport | Primary order |
|---|---|
| swim | duration, distance, pace, avg HR, max HR, effort, calories, notes |
| bike | duration, distance, pace, speed, power, avg HR, max HR, cadence, elevation, effort, calories, notes |
| run | duration, distance, pace, avg HR, max HR, cadence, elevation, effort, calories, notes |
| strength | duration, effort, avg HR, calories, notes |
| mobility | duration, effort, notes |
| other | duration, distance, avg HR, max HR, effort, calories, notes |
| brick | duration, distance, pace, speed, power, avg HR, max HR, effort, calories, notes |
| race | duration, distance, pace, avg HR, max HR, effort, calories, notes |
| rest | none |

"All" = primary plus every other result column the sheet has; notes always last. The done marker and "Logged on" are never boxes. If any extra (non-primary) box already holds a value when the form opens, the form shows all fields. Showing all is remembered (`log.showAllFields`).

**Boxes**:

| Field | Label | Unit shown | Placeholder | Keyboard |
|---|---|---|---|---|
| duration | Duration | — | "e.g. 45" plus hint "Just a number means minutes — 45 is 45 minutes, 90 is an hour and a half. Or write it out: 1:15, 1h20, 90min." | text |
| distance | Distance | a km/m switch (default m for swim, km otherwise) | "e.g. 2400" (swim) / "e.g. 12.4" | decimal |
| pace | bike: "Average speed" km/h "e.g. 32.5" (decimal); swim: "Pace" per 100m "e.g. 1:45" (text); others "Pace" min/km "e.g. 4:52" (text) | | | |
| avg / max HR, cadence | Average heart rate / Max heart rate / Cadence | bpm, bpm, rpm / spm | — | digits |
| speed | Speed | km/h | — | decimal |
| power | Power | watt | — | decimal |
| elevation | Elevation gain | m | — | decimal |
| calories | Calories | kcal | — | decimal |
| effort | Perceived effort (RPE) | 1-10 | "1 easy — 10 all out" | digits |
| notes | Notes | — | "How it felt, conditions, anything worth remembering" | multiline, 3–6 lines |

**Effort box** shows a one-line description under/beside it (`rpeScale`; half steps are read down: 6.5 reads as 6):

1 Barely moving. You could keep this up all day. · 2 Very easy. Warming up, or coming back down. · 3 Easy. Talking takes no effort at all. · 4 Steady. Still talking in whole sentences. · 5 Moderate. The sentences are getting shorter. · 6 Firm. A few words at a time. · 7 Hard. Single words, and you are watching the clock. · 8 Very hard. Talking is out. · 9 Nearly everything. You are counting down to the end. · 10 Everything. You could not hold this for long.

**What a box opens with** (`recordedValue`): the waiting entry's value if one is queued (the last queued record for this session); a waiting missed entry opens empty; else what the sheet holds, shown in the unit the box asks for: a duration as minutes rounded to 2 decimals; a distance in the box's unit (metres for swim) rounded to 3 decimals; everything else as the cell text. The distance unit switch opens on the waiting entry's unit if there is one.

**Changed boxes**: a box with a different value from the one it opened with gets a 2-point green outline. `changedOnly` returns only boxes whose text differs from what they opened with (an emptied box is a change). Saving writes **only** those.

**Save button** label: "Save" with no change (or "Done" if a photograph was added), "Save 1 change", "Save N changes". Pressing it:

* with no change and no photo added: shows in red "Nothing has changed yet — fill in the time you did, or a number you want to correct." (identifier `log-problem`) and stays;
* with no change but a photo added: closes;
* else: remembers a Health use if a Health workout filled the form (`HealthMark.remember`), builds a `LogEntry` from the changed boxes (trimmed; the distance unit is attached if there is a distance), calls `store.log`, closes.

Identifiers: `log-save`, `field-<id>` for text boxes.

### 7.5 Move and swap (`MoveView.swift`)

Sheet "Move", **Cancel** top-left. Top to bottom:

1. The session card.
2. Heading "MOVE IT TO" with a small bordered **+1 day** button beside it (hidden when tomorrow is the session's own day; identifier `move-tomorrow`, label "Move to tomorrow"). It moves the session to **tomorrow counted from today** (not from the session's own day) and closes.
3. A date picker (UTC, date only, opens on the session's day) and a full-width green **Move the session** button, half and half on one line. Pressing it with the same day does nothing.
4. A caption: "Pick a different day first." while the date is unchanged, else "+1 moves it straight to tomorrow. Only the date is rewritten either way: the session keeps its place in every weekly total, because your sheet counts by week number and sport, never by date."
5. If there are candidates: heading "OR SWAP IT WITH", the caption "Exchanges the two days — for when you did one session in the other’s place. Only sessions still to do are offered.", then up to 12 candidate rows (sport badge, title, "<short date> · same day | in N day(s) | N day(s) ago").
6. Tapping a candidate opens a confirmation dialog titled "<Sport A> → <short day of B>\n<Sport B> → <short day of A>" with **Swap these two** and **Cancel**.

**Swap candidates** (`Sync.swapCandidates`): from the displayed plan: not the same session, not a rest row, not done (sheet or waiting); within **10 days** either side; sorted by absolute gap, then **the one still ahead first** on a tie, then plan order; first 12.

### 7.6 Apple Health suggestions in the forms

* If Health has workouts for the day, a block "FROM APPLE HEALTH" lists each: `<type> · <start time>` and `<duration> · <distance> · <avg bpm> · <source>`, with a small green **Use** button (identifier `health-use-<sport>`). The note: "Everything Health has for this day, the matching sport first. Use fills time, distance and heart rate; the pace is yours to type. Nothing is saved until you press Save."
* The sport's own workouts come first, then all the others; nothing is hidden. Matching: see 7.1.
* **Use** fills: duration in whole minutes (rounded); distance (metres for a swim and the unit switch is set to m; kilometres rounded to 2 decimals otherwise, only if > 0); average heart rate rounded. **It never fills pace or speed.** It never saves anything.
* If Health is in use and returns nothing: "Nothing in Apple Health for this day and sport." and "If your watch has it, look in Health → your picture → Apps → Workout Sync." (identifier `health-empty`).
* If Health is off: "Apple Health is switched off, so nothing is offered here." with a **Use it** button, or "Apple Health is not connected, so nothing is offered here." with **Connect** (identifier `health-turn-on`). Hidden if Health is not available or was denied.
* **Is the Garmin data already in?** (`garminIn`, decides whether the session offers **Fill from Garmin**): true if this phone remembers using Health for this session (`HealthMark.used`, key = session key + day), or if the recorded duration is within 1 minute of a matching Health workout **and**, where the watch measured a distance (> 0 m), the recorded distance is within `max(0.02 km, 2 %)` of it (a recorded distance that is missing fails the test).

### 7.7 Photograph strip and viewer (`PhotoViews.swift`)

* Heading "PHOTOS" (or "PHOTOS · N") only when there are pictures or adding is allowed. A 3-column grid of 96-point thumbnails.
* **Add photo** (identifier `photo-add`; only inside forms, behind the pen): a menu with **Take one now** (only if a camera exists) and **From my photos** (library picker, up to 6 at a time). Caption: "Kept as soon as you add one — on this phone only, not in the workbook, not in Dropbox. Save them out from Settings → Photos."
* A photograph is kept the moment it is added; the forms' Save button then reads **Done**.
* Tapping a thumbnail opens the **viewer**: full screen, black, swipe between the owner's pictures, **Close** at top-left, a share glyph and a red **Delete** at top-right. Delete asks "Delete this photo? It is the only copy." with **Delete** and **Keep it**.
* Picture handling: longest edge 1600 points, JPEG at quality 0.72, honouring the EXIF orientation; if shrinking would not make the file smaller, the original bytes are kept. The camera path hands over JPEG at 0.95 first. File id: `p` + milliseconds in base 36 + a random base-36 number.

---

## 8. Extra workouts

Sources: `ExtraViews.swift`, `PhotoViews.swift` (detail), `Extras.swift`, `Store.swift`.

### 8.1 The extra form

Sheet. Title "Extra workout" for a new one, "Adjust logged data" when correcting. **Cancel** top-left. The green button at the bottom reads **Save** (new; "Save it" until 2.4), or "Save" / "Done" / "Save N change(s)" when correcting.

Top to bottom:

1. **When**: a date picker (UTC, date only), opening on the given day (today when added from Today).
2. Apple Health block (as 7.6), with the note "Fills time, distance and heart rate. Nothing is saved until you press Save." The workouts of the chosen day load again when the day changes; the Health sport of this activity comes first. A new extra also takes the Health workout's kind when Health knows it (swim, bike, run, strength, rowing, mobility, walk); a saved extra keeps its own kind.
3. **What kind of thing**: a menu picker of the activities (36-point badge in the activity's own colour). Changing it resets "Counts as training" to the new activity's default. Default activity: **Walk**.
4. **What it was** (text, e.g. "Dog walk along the river").
5. **Duration** (hint "Just a number means minutes. Or 1:15, 1h20, 90min.").
6. Only for activities that are not "restorative": **Distance (km)**, **Average heart rate (bpm)**, **Effort (1–10)**.
7. **Counts as training?** — a two-way switch: "No — it does not add load" / "Yes — count it as training". Default: yes for activities of kind *training*, no for the others; the user's choice stays.
8. When correcting: the photo strip with Add photo.
9. **Notes** (3–6 lines).

**Activities** (`Extras.defaultActivities`):

| Id | Label | Kind | Colour id |
|---|---|---|---|
| swim | Swim | training | swim |
| bike | Bike | training | bike |
| run | Run | training | run |
| strength | Strength | training | strength |
| rowing | Rowing | training | rowing |
| mobility | Mobility | restorative | mobility |
| yoga | Yoga | restorative | mobility |
| meditation | Meditation | restorative | rest |
| breathing | Breathing | restorative | rest |
| walk | Walk | everyday | rest |
| hike | Hike | everyday | rest |
| ski | Ski | everyday | rest |
| other | Something else | everyday | rest |

An unknown id resolves to "Something else". `wantsMetrics` = kind is not restorative.

**Saving a new extra**: needs a duration or a text of what it was or notes, else the red message "Give it at least a duration — "35", or 1:15 — or a word about what it was." (identifier `extra-problem`; the button is never grey). The entry stores: day, activity, what (trimmed), minutes (duration parsed to seconds then **rounded to whole minutes**), distance, average heart rate, effort (numbers with a decimal comma allowed), the counts flag, notes (trimmed), and a new **ref** (`x` + milliseconds in base 36 + 4 random base-36 characters).

**Changed boxes when correcting** are compared as the sheet would hold them, so typing `1:15` over `75` is not a change and `4,2` over `4.2` is not a change. A changed box is edged green. Saving with no change shows "Nothing has changed yet — alter a box and Save writes just that." (or closes if a photo was added).

Identifiers: `extra-activity`, `extra-activity-<id>`, `extra-field-<id>`, `extra-counts-yes`, `extra-counts-no`, `extra-save`.

### 8.2 Extra cards

* A badge in the activity's colour with its own hand-drawn glyph; the line "EXTRA · <LABEL>"; the title (what it was, else the label; two lines); pills: duration, a "counts" mark pill (for training), "Waiting to sync".
* A **dotted** outline in the activity colour; a **washed** green tick (60 %) always at the right; on its own screen a round pen under the tick.

### 8.3 Settings → Extra workouts list

Navigation title "Extra workouts". Newest first, grouped by day. Tap opens the detail. A toolbar **Add** (only if `canLog`) opens the form for today. Empty text: "Nothing outside the plan yet."

### 8.4 Extra written to the sheet

Section 9.4.

### 8.5 Extra detail

A sheet "Extra workout" with **Close**. The extra card (with the pen when `canLog`), and the photograph strip (view only). The pen opens the correction form; after a correction is saved the detail screen closes itself once the form has closed, so the list behind shows the new reading.

---

## 9. Rules

### 9.1 Weeks and days (`Week.swift`)

* Day keys are `YYYY-MM-DD`; all date arithmetic is in UTC, so a workbook opened in any time zone never slides a session to the day before.
* **Week start**: Monday. `weekStart(key) = key − ((weekday + 5) mod 7)` days with Sunday = 1.
* `week(of:today:)` returns seven `PlanDay`s, Monday to Sunday; each holds all rows of the day, the training rows, `isRest` (has rows and all are rest rows), planned seconds (training rows' planned seconds), the day's extras, `isToday`, `isPast`.
* `outstanding(before: today)` = rows with a day before today, not rest, not logged (uses the **whole plan**, including hidden rest rows, which are rest anyway).
* `upcoming(from:limit:)` exists (default 20) but the screens use the lists in section 6.
* `phase(on: today)` = the phase of the last row on or before today that has a phase; if none, the first phase in the plan; else empty.
* **A day is "done"** only per session: a session is `done` if logged (sheet or waiting) and not missed; `missed` if missed; else `todo` (`Workout.state`).

### 9.2 The waiting log laid over the plan (`Sync.swift` — `overlay`, `entries(for:)`)

* The queue's **session entries** (not extras) belonging to a session are those whose `workoutKey` equals the session key; if there are none, those with the same day, discipline and sheet.
* For each session: `logged` starts as the sheet's logged state and `pending`/`pendingMove` are cleared.
* The **last queued move** (an entry with `moveTo`) sets a new date and day key on the displayed session and `pendingMove`.
* The **last queued record** (an entry without `moveTo`) sets `pending`, `logged = true` and `missed` = that entry's flag.
* The result is sorted by date then row. **A move never hides that a session is done.**
* Nothing here writes anything.

### 9.3 Sync: the queue, conflicts and checks (`Sync.swift`, `Dropbox.swift`)

Rules, each one there because something went wrong:

1. Nothing reaches the workbook until it is queued; nothing leaves the queue until Dropbox has accepted the upload.
2. Every sync **downloads the copy in Dropbox right now**, never an older copy.
3. A queued entry names a row, and a row is not a stable identity; the session is re-found before writing (below).
4. One entry that cannot be written is recorded and kept; it never blocks the entries behind it.
5. The bytes about to be uploaded are opened and read again; a workbook that does not read back, has no sheets, or **has fewer sessions than before**, is **never uploaded**.
6. The upload carries the revision that was downloaded. If the file changed, Dropbox refuses with a conflict and **the sync starts once more** from the newer copy with the same queue. If the second try conflicts too, the conflict is given up (error "The plan kept changing in Dropbox while sending…", 3.9). Only one retry is allowed.

`Sync.apply(queue, to: data)`:

1. Reads the workbook, builds the mapping and plan ("The layout of this workbook could not be worked out." if none).
2. For each entry in queue order, in a `do/catch` that records failures:
   * **Extra entry with `editing`** (a correction): finds the Extras sheet (it is **not** created here) and the row (9.4); "The <label> you adjusted is no longer on the Extras sheet — its row may have been removed or rewritten in Excel. Nothing was written; the correction is still waiting." if either is gone. Builds edits for the changed columns only; none gives *dropped*.
   * **New extra**: ensure the Extras sheet exists (creating it, 9.4); if the same ref is already recorded it counts as written without writing again; else build and write the row. "This entry had nothing that could be written to the Extras sheet." if empty.
   * **Session entry**: find the workout (below) or fail with "The session this was logged against ("<title, 40 characters>") is no longer in the workbook, or has been changed into a different one. Nothing was written; log it again against the row you want."
   * For a move without weekday names, the weekday names are learned from the sheet.
   * A record (not a move) without `completedAt` gets **the time of the sync** as "Logged on" (`now`), including a missed one. **The app never sets `completedAt` from the logging time**, so "Logged on" is the day the entry was *sent*, not the day it was logged on the phone (see section 15).
   * Build the edits (9.5); none gives *dropped* (the entry is removed from the queue without a write).
3. If nothing was written, no bytes are produced. Else the workbook is saved (`save`) and `verify`d (rule 5).

**Finding the session** (`findWorkout`): consider the plan rows on the entry's sheet (all sheets if the entry has none).

* **First choice:** the row with the entry's key, **if it is still the same session** — discipline equal (when known), and either the day equals the entry's day or the titles agree.
* **Titles agree** (normalise: lower case, whitespace collapsed, trimmed): both non-empty and equal, or one is a prefix of the other, or their first 20 UTF-16 characters are equal.
* Otherwise the candidates are the rows that are still the same session **and within 7 days** of the entry's day. None: no session. One: it. More: prefer rows whose title agrees (else all), then prefer rows **not yet logged in the sheet**, then the one whose **row number is nearest** to the entry's row.
* A session changed in all three ways (discipline, day and wording) is a different session and nothing is written.

**Dropbox transport** (`Dropbox.swift`):

* OAuth 2 with **PKCE**: a 64-byte random verifier (first 128 characters of its base64url), SHA-256 challenge, a random 16-byte `state`. Sign-in opens an `ASWebAuthenticationSession` (shares Safari's cookies) at Dropbox's authorize URL with `token_access_type=offline`. The redirect goes to a page on the web app's GitHub Pages site (`native-auth.html`), which hands the code to `amsworkoutsync://oauth`. The `state` must match ("the answer did not belong to this sign-in"). The code is exchanged for a refresh token (Keychain) and a short-lived access token (default 14 400 s, renewed 60 s early). The app key is public by design (no secret); it is in `Dropbox.swift`.
* The account shown in Settings is the e-mail (else the display name) from `users/get_current_account`.
* **List** (`files/list_folder`, limit 500, follows `has_more`): only folders and `.xlsx` files; folders first, then by lower-case name.
* **Download** (`content/files/download`, 45 s timeout): returns bytes, `rev` and name from the `Dropbox-API-Result` header.
* **Upload** (`content/files/upload`, 90 s timeout): `mode: update` at the downloaded `rev`, `autorename: false`, `mute: true`. HTTP 409 whose body contains "conflict" becomes `RemoteError.conflict`; any other non-200 is an error "Dropbox answered <code>. <first 160 characters>".
* Header arguments are JSON with every non-ASCII character written as `\uXXXX`.
* The path stored is the **displayed** path (not lower-case), because an upload re-cases the file name to the path sent.
* Error texts: "Not connected to Dropbox."; "Sign-in was cancelled."; "Dropbox refused the connection: <why>"; "The workbook changed in Dropbox since it was read."; "Dropbox sent an answer the app could not read."

**Queue storage**: a `QueuedEntry` holds an id, the session key, sheet, row, day, discipline id, title, a `LogEntry`, an optional extra, `createdAt`, `attempts` and `lastError`. **Every decoder is tolerant**: a missing key defaults rather than throwing, so a queue written by an older app still reads. A queue file that does not decode as a whole is read entry by entry; the bad ones are lost singly, the original is kept as `queue-unreadable.json`, and a message says how many were recovered ("The waiting log on this phone could not be read. Nothing has been thrown away — it is kept as queue-unreadable.json." or "Part of the waiting log could not be read; N of it was recovered. The original is kept as queue-unreadable.json.").

### 9.4 Writing extras (`Extras.swift`)

* **Appended** at the **first row with nothing in it**, starting at row 2 (`nextRow`).
* Cells written: Date (text `YYYY-MM-DD`), Day (the sheet's own weekday spelling learned from the plan, else `Sun…Sat`), Activity (label), What it was, Duration (minutes), Distance, Avg HR, Effort (numbers only if present), Counts as training (`Yes`/`No`), Notes, Ref. Empty text is not written.
* **Heading repair**: a sheet written before refs existed has ten headings; the heading `Ref` is added in the same write.
* **Creating the sheet** (`createSheet`): four parts must agree — the sheet XML (frozen first row, headings as inline strings), an override in `[Content_Types].xml`, a relationship in `workbook.xml.rels`, a `<sheet>` entry in `workbook.xml`. The first free `sheetN.xml`, `rIdN` and `sheetId` are used.
* **Replay protection** (`alreadyRecorded`): with a ref, the same ref anywhere in the Ref column means written already; without a ref (entries from before refs), same day, same activity and same duration.
* **Corrections** (`editing` set): the row is found by **ref first**; if the ref is not found, rows **without a ref** are matched by day, activity label and duration. Only the columns named in `fields` are written; an emptied box empties the cell (an extra is the app's own row). A date change also rewrites the weekday cell. A row without a ref gains one in the same write, and the heading too.
* Store rules for a correction (`editExtra`): an extra still waiting becomes what it now says (no correction is queued behind it); a second correction to the same row replaces the first and merges the changed fields; photographs follow an extra when its day, activity or length (which together identify it) change.
* An extra's identity for photos and for anything that points at it: `extra:<date>:<normalised label>:<minutes>`.

### 9.5 Writing a logged session (`Edits.swift`, `Writer.swift`)

**What is written** (`Plan.buildEdits`), after parsing the entry's text the way JavaScript does (decimal comma changes the first comma only; `parseFloat` reads a leading number and ignores the rest; `Math.round` rounds halves up):

| Entry | Cells written |
|---|---|
| **Move** (`moveTo`) | only the **date** (as a serial into a date-styled cell, else as text `YYYY-MM-DD`) and, if the sheet has a weekday column and its spelling is known, the weekday text. Nothing else. |
| **Missed** | the done column gets the sheet's missed value; notes (trimmed) if any; "Logged on" if the column exists. Nothing else. |
| **Record** | duration (parsed, converted to the sheet's unit); distance (converted from the entered unit to the sheet's unit: km↔m ×1000 or ÷1000); average HR, max HR, speed, power, cadence, elevation, calories, RPE (numbers); pace — as a time fraction of a day if the pace column is time-formatted, else as text with a decimal comma turned into a dot; notes; the done marker (the entry's label, else the sheet's done value, else `Yes`); "Logged on". Only cells for columns the sheet has. Empty text is never written. |

* **Distance unit if not given:** metres for swim, kilometres for everything else.
* **Duration parsing** (`parseDuration`): `45` = 45 minutes; `45min`; `1:15` = 1 h 15; `1:15:30`; `1h20`; `1,5h`; `90 min`; units h, hr, hrs, hour, hours, std, stunde, stunden (hours), m, min, mins, minute, minuten and a bare number (minutes), s, sec, secs, sek, sekunden (seconds). Result rounded to a whole second; not a duration gives nothing.
* **Pace parsing** (time-formatted column): `4:52` or `4:52 /km` gives seconds; else a decimal number is minutes, rounded.
* **`protectPlanColumns`**: the last gate. Any edit aimed at a column that holds a **plan** field (anything not a result field, except date and weekday) is dropped unless the edit is for that very field. A result can never land on the plan's own text.
* **`Writer.writeCells`** changes only the cells named. Each cell is rebuilt; every other row, cell and part is copied as the exact text or bytes it was.
  * Cell style: the existing cell's style, else the edit's, else none.
  * Number: `<v>` with JavaScript number text. Text: an inline string with `xml:space="preserve"`. Blank: an empty styled cell. Date: a bare serial only into a cell that already has a date style; otherwise `YYYY-MM-DD` text.
  * Text is XML-escaped (five entities) and **control characters are dropped**.
  * Rows are spliced in order; a new row is created if missing; the `spans` attribute is recalculated; the sheet's `<dimension>` is widened if needed; all slicing is in UTF-16 units like JavaScript so an emoji cannot shift a cut.
  * A cell that had a formula and is overwritten marks the formula as dropped; at save time `xl/calcChain.xml` is then **removed** (it would be stale).
  * At save, if anything was edited, `fullCalcOnLoad="1"` is put on `<calcPr>` (added if missing), so Excel recalculates when the file is opened.
  * The result is checked by the sync (rule 5) before it is uploaded.
* Writing to a sheet whose name is missing: "No sheet named …".

### 9.6 Statistics (`Stats.swift`)

All figures come from the plan's session rows each time Progress is opened. The Progress sheet's formulas are never read.

**Past sessions** = non-rest rows with a day **before today** (today is neither due nor behind). Outcome: `missed` if missed, else `done` if logged (sheet or waiting), else `unlogged`.

* **So far / kept**: counted = all past; done, missed, unlogged; answered = done + missed.
* **Streaks**: oldest first; a done session adds one to the run; anything else breaks it. `current` = the done sessions in a row at the very end; `longest` = the longest run.
* **By sport**: per discipline in training order (swim, bike, run, strength, mobility, then others): planned count, done, missed, unlogged, planned seconds, done seconds (planned length of done sessions), `rate = done / planned`. The **worst** sport is the lowest rate (first in training order on a tie).
* **Moved rather than lost**: past, non-rest, not missed sessions that have a move record (sport still matching, `from` and `to` both set and different). `keptByMoving = moved / (moved + missed)`.

**Actuals of a logged session** (`actualsOf`): minutes, kilometres, average heart rate, RPE — from the waiting entry if one is queued (not missed), else from the sheet. A queued distance in metres is divided by 1000; when the entry says nothing and the sheet's unit is metres, also divided by 1000. Sheet durations convert through the sheet's duration unit.

**Is it working** (`trends`), for swim, bike and run only:

* *Usable* row: minutes > 0, kilometres > 0, average HR between 60 and 220 inclusive.
* *Easy* usable rows: RPE greater than 0 and at most 5. If there are **at least 8 easy** rows, only easy rows are used (`easyOnly`); otherwise all usable rows.
* Fewer than **8** rows (4 per half × 2): "not enough" (`have` of `need`).
* Rows are sorted by day (ties keep order) and **split by count**: the first half (`count / 2`) is "then", the last half "now" (an odd middle row is left out). Each half: mean speed (km per hour, per session), mean HR, sessions, first and last day; pace seconds; **per-beat** = speed ÷ HR.
* `change = (now.perBeat − then.perBeat) / then.perBeat`. Verdict: **better** if ≥ +3 %, **down** if ≤ −3 %, else **level**.
* Speed change and HR change are also kept.

**Twelve weeks and where the hours went** (`load`): over 12 **completed** weeks — Mondays from the last finished week back 12 weeks (`completedWeekStarts`: the week that has just ended is the last; this week is left out, "a week still being lived shows every session not yet done as time missed"). Rows before the first week's Monday or on or after this week's Monday are ignored. Each non-rest session contributes planned seconds and **actual** seconds (actual minutes × 60 if the session was done, else 0). A week's session count is the number of sessions with actual > 0. Sport totals are sorted by actual hours (then planned, then first met). Shares: actual / total actual and planned / total planned.

**The road** (`road`, from the visible plan, non-rest rows for counts):

* **Race**: the first `race` row on or after today, else the last race row in the plan; the race day is its day, else the plan's last day. Title: the race row's title, or "Race day", or "The last day of the plan" if the plan has no race.
* **Phases**: walk the visible rows in order; consecutive rows with the same trimmed phase name are one phase (`from` first day, `to` last day). Per phase: sessions (non-rest rows) and done (logged and not missed).
* **Counts**: `sessions` (non-rest rows), `done` (logged and not missed), `behind` (past and not logged), `toCome` (days after today); `plannedAll`, `plannedSoFar` (past sessions' planned time), `doneSeconds` (actual seconds, else planned for sessions done without a time).
* `daysToGo = days(today → raceDay)`; `weeksToGo = ceil(daysToGo / 7)`; `through = days gone / total days` (clamped 0…1; `started` = today ≥ first day).
* **Phase blocks** (`phaseBlocks`): the bar is the road from the first day to the race day, both included. A phase starting after the race day gets no block; one that straddles it is cut at the race; each width = days ÷ total days, never more than what is left of 1 (overlapping phases cannot overflow the bar).

### 9.7 The Training calendar (`TrainingCalendar.swift`)

* **Opt-in** from Settings → Calendar. Needs **full** calendar access (write-only cannot see, so cannot update, the events the app made itself).
* Events live in a calendar called **Training** (green, iCloud source if present, else the default source, else local). A Training calendar already there from an earlier install is adopted, not doubled.
* **What is wanted**: every row from today to the end of the plan, by day in plan order.
  * A **rest row**: an all-day event "Rest day" with the row's title as notes.
  * A session: the heading is the sport and its length only — `Run 35`, `Swim 40` (minutes as a bare number under an hour), `Bike 2h30min`, `Run 1h`, `Run 1h10min` (from an hour: `<h>h` plus `<m>min` if not zero). A session with no planned length is headed by the sport only and is **all-day**.
  * **Notes**: lines, de-duplicated case-insensitively: the title; "Intensity: <text>"; "Purpose: <description>"; each section as "<label>: <text>" (a section equal to the purpose is skipped).
  * **Times**: "At a time" mode puts the first session at the chosen hour (default 06:00, `calendar.start` minutes) and each next session of the same day starts when the previous one ends; a session without a length is all-day and does not move the clock. **All day** mode makes every session an all-day event. Times are **floating** (no time zone: 06:00 stays 06:00 wherever the phone is). All-day events end at 23:59:59.
* **Keeping in step**: the app remembers which event is which session (key, event id, and an FNV-1a 64-bit hash of title, notes, day, start and length). An unchanged session is not rewritten. A moved session moves its event; a removed session removes its event if its day is today or later; days **behind today are left as they were** (the record). A saved event that has disappeared is rewritten fresh. If anything fails the app starts again from nothing remembered.
* **Strays**: from today's midnight onwards the calendar holds the plan and nothing else; any other event there is removed. The search window is 2 years back to 3 years ahead.
* The app updates the calendar after every read of the plan and every change of the waiting log. Syncs queue: while one runs, the latest request is kept and run next.
* **Take them out** (`disable`) removes the whole Training calendar and forgets the events.
* Needs "Settings → Apps → <app> → Calendars → Full Access" if denied.

### 9.8 Zones (`Zones.swift`, `ZonesView.swift`)

The sheet whose name contains "zone" (any case; first match) is read **by shape**, not by fixed addresses; Excel's last answers are read, nothing is recalculated.

1. **Results table**: the first row with a cell reading "Test block" (any case). Its column is the label column; the headings to the right that contain `lthr`, `ftp`, `css`, `weight` are the value columns; a heading containing `date` is the dates column.
2. Below it: the row whose label cell starts with `CURRENT` carries the numbers in use; the last row before it whose label starts with `test` and has a number in any value column is the **latest test**.
3. **Current**: the CURRENT row's values; if all are empty (the CURRENT cell is a formula whose answer is missing), the latest test's own cells are used.
4. **Latest test text**: the test row's label, plus ", " and its dates.
5. **Zone tables**: after the CURRENT row, the first row whose label cell contains "ZONE" is the heading row; each non-empty heading on it is a table: its rows run down the heading's column until a blank, the value is the next column. A table's **kind** is swim if the title contains SWIM, bike if it contains POWER or BIKE, else heart.
6. **Note**: the first row at or after the tables' end whose label starts with "note".
7. **Abbreviations**: after the row reading exactly "ABBREVIATIONS", pairs of label and value until either is empty.
8. Without a results table or without any zone table, there are no zones (`nil`).
* **LTHR** = the current row's value for the heading containing "LTHR", read as a number; ignored if below 60 or above 230.
* **`waitingForExcel`**: there are tables but every value in them is empty (Excel's answers are missing, not "nothing entered").
* **Zone number** of a label: `Z` followed by one digit 1–9 and not another digit ("Z2 — Aerobic" gives 2).
* **Zones named by an intensity text**: `Z` + one digit not followed by a digit and not preceded by a letter; two or more found give the whole range between the lowest and highest ("Z4–Z5" gives 4 and 5; "Z2 + strides" gives 2; "RPE 6" nothing).
* **What a pill shows** (`explain`): heart-rate tables always (rows of the named zones); bike power only for a bike or brick; swim table (whole, all rows) only for a swim; rows with an empty value are left out; empty tables are left out.

**Screens**

* **Zone sheet** (tap an intensity pill; medium and large detents; **Done** at top-right): large intensity text (identifier `zone-sheet-title`); "For you, from <latest test>"; the table cards (rows identifier `zone-row`); if the intensity says RPE and the sheet has an RPE abbreviation, an "RPE" card with its words; for a bike or brick with zones named but no power table: "No bike FTP is entered in the sheet yet, so there are no power zones — heart rate only."; the "waiting for Excel" card, or "Nothing in your zones sheet matches <intensity>." if nothing matched; a small bordered **All your zones ›** link. Without a zones sheet: "Your workbook has no Test Results & Zones sheet, so the app cannot say what this means."
* **Your zones** (Settings → Your zones; navigation title "Your zones"): "IN USE" grid of the current values (title2 digits, grey label) or "No test result is entered in the sheet yet."; "From <latest test>"; the waiting-for-Excel card ("Your zone tables are empty — The sheet works the zones out with formulas, and the numbers Excel had worked out are not in the file any more — another program saved it without them. Your test results themselves are still there. Open the plan in Excel on the Mac once and save it, and the tables fill in again.", identifier `zones-waiting-for-excel`); every table card (an empty value reads "—" while waiting for Excel, else "not entered yet"); the note; "THE WORDS" (abbreviation cards); "Read from the sheet <name> in your workbook. The app never works a zone out itself." Without a sheet: "Your workbook has no Test Results & Zones sheet, or it could not be read. The zones come from that sheet; the app never works them out itself."

### 9.9 Session cost, fitness, fatigue, freshness (`Effort.swift`)

**Cost of a session** = `hours × intensity² × 100`, so one hour at threshold is 100. The intensity comes from the first source that exists:

1. **Heart rate**: `avgHR / LTHR`, only if avgHR > 30 and LTHR > 60; clamped to **0.40 … 1.15**. Source `heartRate`.
2. **Effort** (RPE 1–10): `0.45 + RPE × 0.065`, clamped 0.40 … 1.15 (RPE outside 1…10 is not used). Source `effort`.
3. **Planned zone**, from the plan's intensity text: Z1 0.60, Z2 0.70, Z3 0.82, Z4 0.92, Z5 1.05; a range is the **mean** of the zones found (digits 1–5 following a `Z`). Source `planned`.
4. Otherwise no cost (source `none`).

No minutes (≤ 0) gives no cost. Heart rate reads low in water, so a swim's cost is modest (the app says so).

**Daily cost** (`dailyCost`): for every plan session that is logged, not missed and not rest: actual minutes if > 0, else the planned minutes; plus every **extra that counts as training** (its minutes, average HR and effort; no planned zone). Costs on one day add up.

**Fitness and fatigue** (`form`): from the first day to today, **every day, rest days included**:

```
fitness += (cost − fitness) / 42
fatigue += (cost − fatigue) / 7
freshness = fitness − fatigue
```

Both start at 0 on the first day. The first day is the earlier of the plan's first day and the first day with a cost. Nothing is drawn if the sheet has **no LTHR** (no threshold) or no costs.

**Standing word** from the freshness: below −25 "Deep in it"; −25 up to −10 "Building"; −10 up to 5 "Holding"; 5 up to 20 "Fresh"; 20 and above "Very fresh". The word is shown in lower case beside the freshness figure.

### 9.10 Morning numbers (`Fortnight.swift`, `Sleep.swift`, `Health.swift`)

**Resting heart rate and HRV** (read from Health for the last 16 days):

* Each calendar day is **one value, the last reading written for that day** (a day Health holds twice counts once; Garmin may rewrite a day as it goes on).
* The newest day is shown only if it is **today or yesterday**.
* The **normal** = the average of the earlier days in the 14 days before the newest day (day of newest − 14 up to the day before it), one value per day, and **there is no normal at all until 4 days are there** (`daysNeeded = 4`).
* The result also tells how many earlier days stand behind the normal.
* HRV is the SDNN in milliseconds; resting heart rate in beats per minute.

**Sleep** (`Sleep.asleepSeconds`): pieces from Health with the values core, deep, REM or "asleep" (awake and in-bed are not sleep), read from **18:00 yesterday** (start of today − 6 hours) to now. Each **source's** pieces are laid on one timeline and an overlap counts once; a gap (lying awake) stays a gap. Two sources are two opinions of the same night, never two nights: **the source that saw the most sleep is taken whole**. Nothing recorded gives no sleep value. Shown as hours and minutes.

**Health reading** (`HealthImport`): it asks for workouts, heart rate, walking/running, cycling and swimming distance, resting heart rate, HRV and sleep. Read only; never writes. `enabled` (user switch, default on) can be turned off in Settings; iOS gives no way for an app to give its own permission back.

* *In use* = permission asked (UserDefaults `health.asked`) and enabled.
* iOS never tells whether reading was granted; a refused read looks like an empty day. The app asks again when it has learned to want something new (it asks iOS whether it would put the question).
* **Workouts of a day** (`workouts(on:)`): every workout that **started** on that calendar day in the phone's own time zone, newest first, at most 50. For each: average heart rate over its time span; distance from walking/running, else cycling, else swimming statistics; sport mapping — swimming → swim; cycling or hand cycling → bike; running or track and field → run; traditional or functional strength, core, cross training → strength; rowing → rowing; yoga, flexibility, cooldown, pilates → mobility; walking, hiking → walk; anything else → other. The display name: Swim, Ride, Run, Walk, Hike, Yoga, Rowing, Strength, Core, Cross training, or "Workout".
* **Form values** of a workout: duration = minutes rounded; distance (metres whole for swim, else kilometres to 2 decimals) only if > 0; average HR rounded. **No pace or speed ever.**
* **Summary line**: `formatDuration`, distance (`1.3 km` style above 1000 m, else `N m`), `N bpm`.
* **Probe** (Settings): asks Health for the last 7 days and for anything at all (limit 5) and reports counts, any error and what iOS says about the permission.

### 9.11 Photograph matching (`PhotoMatch.swift`, `Photos.swift`)

* A photograph remembers the key of the row it was taken against, its day and its sport. A row number is not a name (a line inserted in Excel shifts every row), so:
  * If either the photo's key or the owner's key starts with `extra:`, the match is **exact** (the keys must be equal).
  * Otherwise the **sport must agree** (a row that became another kind of session is a different session);
  * then equal keys match; else a non-empty equal **day** matches.
* Two sessions of one sport on one day would share pictures; this is accepted as a smaller harm than pictures that cannot be found.
* **Orphans** are pictures that match no session or extra; they are counted in Settings, kept, and included in the export.
* **Export** is a stored (uncompressed) zip of every picture with the name `<day or undated>_<sport or session>_<title: diacritics removed, other characters become spaces, collapsed, first 40 characters, spaces to dashes>.jpg`; duplicates get `-2`, `-3`.
* **Import** (Settings → Photos → Bring in a zip): takes `.jpg`, `.jpeg`, `.png` files named `YYYY-MM-DD_sport_Title`; matches a session on that day with that sport (title words first: the first 12 characters of the file's title words against the session title prefix; else the first session of that day and sport), or an extra of that day (sport equal or the file says "session"); otherwise keeps it as an **orphan** (counted as imported and as unplaced).

### 9.12 Sharing a session (`ShareText.swift`)

Two plain-text messages; heart rate and effort are **never** in either; the session's photographs go along.

**The whole session** ("brief"):

```
<long date> — <Sport>, <planned length>        (", length" only if planned)
<title>                                          (if any)

  • Intensity: <text>                            (if any)
  • Purpose: <description>                       (if any)
  • <section label>: <text>                      (each section, except one equal to the purpose)

Done — <actual length>   |   Done.   |   Marked missed.     (after a blank line; nothing if still to do)
```

**What you did** (one sentence for the person at home):

* on today: `Just finished today’s <sport> — <figures>.`
* on another day: `<long date>’s <sport> is done — <figures>.`
* then the title on a second line (if any).
* `figures` = the actual time, then the distance with the sheet's distance unit, comma separated.
* The actual time uses the waiting log first, then the sheet.

### 9.13 Number formats

* `formatDuration(seconds)`: `1h 05m` for ≥ 1 hour (minutes zero-padded), `35m` for whole minutes, `35m 20s` with seconds, `42s` under a minute.
* Progress hours: `hoursShort`: under 60 s `0`; under an hour `Nm`; else `Xh Ym` or `Xh`.
* Pace text in "Is it working": bike `32.5 km/h`; others `m:ss /km`; swim `m:ss /100m` (per kilometre ÷ 10); a rounding to 60 s carries into the minute.

---

## 10. Progress

Source: `ProgressView.swift`. Page colour: Progress violet. Large title "Progress" (identifier `progress-title`). No navigation bar. Cards in this order:

1. **Road card** (always, if there is a plan).
2. If no past session exists: "Nothing has happened yet — Once sessions are behind you, this is where the patterns in them show up." Otherwise, in order:
   1. **Is it working?** (TrendsCard)
   2. **Fitness and freshness** (FormCard)
   3. **Load** (LoadCard, 1.2; id `load`; only when a plan is loaded)
   4. **Twelve weeks** (WeeksCard)
   5. **Where the hours went** (MixCard)
   6. A note "Too early to read much into this." when fewer than 12 sessions have gone by ("N session(s) has/have gone by. The figures below are real, but a fortnight of training is a fortnight — the patterns need more road behind them.")
   7. **So far**
   8. **Consistency**
   9. **Which sport runs behind**
   10. **Missed, or moved**
3. A closing grey caption: "Worked out from the sessions in your workbook each time this screen is opened. Nothing here is stored in the plan, and nothing here writes to it — the totals and the chart on your Progress sheet remain the ones Excel keeps."

### 10.1 Road card

* Top row: the **clock**, big rounded digits in violet and a grey unit: `—` "the race has been" if the race day is past; `Today` "race day" (or "the last day" if the plan has no race); from 1 to 21 days: `N` "day(s) to go"; more: `N` "weeks to go" (weeks rounded up). At the right a round **flag** button (identifier `race-what`, label "What the race is") that toggles the race's own words and the phase list.
* If the flag is open: the race title (identifier `race-title`).
* The race day in long form with the year.
* If there are phases: the **phase bar** (18 points tall): each phase as wide as its days (9.6), in the phase colour (section 11.4) at full strength if it is now, 75 % if past, 55 % if future; the number of sessions in the phase, small, inside the block, placed in the roomier side of today's line, and **omitted if less than 17 points of room**; a thin surface-coloured gap at the end of each block. **Today's line**: 2 points wide, 22 points tall, in the text colour, shown if the plan has started and today is not past the race. Under the bar: "You are in <phase>" and "N of its M sessions done" (identifier `phase-now-done`).
* If the flag is open: an explanation ("Each block is a phase, as wide as it is long, and the figure after its weeks is how many sessions it holds. The line is today. The bar ends at the race, so anything after it has no block.") and one row per phase: colour chip, name, "N week(s) · M" (weeks = max(1, days ÷ 7)) or "after the race" (identifier `phase-row`).
* Three figures in a row: "N done of M"; "<banked> banked of <due> due"; "<all> the whole build" (times as `formatDuration`, `0m` under a minute).
* If any: red "N session(s) behind you was/were never recorded."

### 10.2 Is it working?

Rules in 9.6. If **no** sport has enough sessions: a card with "Not enough logged yet to answer this honestly. It needs 8 sessions of one sport carrying a distance, a time and an average heart rate — there are none yet / there is one so far / there are N so far." (for the sport with most). Otherwise per sport that has enough: the sport name (Swims, Rides, Runs); "then" figure (pace or speed, "at N bpm") → arrow ("↑" green better, "↓" red down, "→" grey level) → "now" figure; "+N% · <verdict>" (verdict texts: "Better — you are covering more ground for the same heartbeats.", "Down a little. Heat, fatigue, hills and a hard block all do this; one stretch is not a verdict.", "Holding steady."); "N logged easy sessions|sessions of every kind, the first X against the last Y." Below: "Not enough yet for swims (3 of 8)." for sports with some but not enough, and a standing footnote.

### 10.3 Fitness and freshness

Shown only when there are **at least 14 days** of the curve (an LTHR exists). Three figures: fitness; "fatigue of the last week"; freshness (signed, with the standing word as its label). A **chart** (150 points tall, identifier `form-chart`) of the last **84 days**: fitness as a violet line with a light area; fatigue as a red dashed line; four evenly spaced date labels ending on today; a key "fitness" / "fatigue". Footnote: "Under zero means you are carrying fatigue, which is where the work gets done; over zero is rested. Worked out from your heart rate where you recorded it, your effort where you did not, and the zone the plan asked for failing both. Heart rate reads low in water, so a swim costs modestly."

### 10.4 Twelve weeks

Only weeks with something in them (planned or actual > 0) are drawn; **hidden if fewer than 3 such weeks**. A bar chart: bars = hours done (the newest week solid violet, others 55 %), a short line (in the text colour) across each bar where the plan asked to reach (the planned hours). X labels: about five (every `ceil(n / 5)`-th counting back from the last, so the newest is always named); Y axis in hours. Lede: "<done> of <planned> asked for over the last twelve finished weeks — N%." or "Nothing planned in the last twelve finished weeks." Footnote explains that this week is not counted.

### 10.5 Where the hours went

Hidden if fewer than 2 sports have hours or plan. A stacked bar of actual shares (sport colours), then a row per sport: colour dot, name, hours, actual %, "plan N%" with a signed point difference in red if the difference is **5 points or more**. Caption: "The balance is within five points of what the plan asked for on every sport." or "<Sports> sit(s) five points or more from the share the plan asked for. That is worth knowing rather than worth worrying about: a block often leans on purpose."

### 10.6 So far, Consistency, Which sport runs behind, Missed or moved

* **So far**: since 2.5 "Of the M sessions due up to yesterday, N were done" (before: "N of M sessions behind you were completed") and ", and K were never answered either way" if any; three figures: done (before 2.5: completed), missed, unanswered; a footnote if any are unanswered ("An unanswered session counts against you here, because a plan you did not reply to is not a plan you kept. Log or dismiss them and this settles down.").
* **Consistency**: lede "N in a row right now." or "The run ended at the last session. Longest so far is N."; figures: "in a row now" and "most in a row" (before 2.5: "current run", "longest run", which read like the sport Run), "of those answered" (done ÷ (done + missed), `—` if none).
* **Which sport runs behind**: lede "<Sport> is furthest behind, at N% of its sessions kept." only if the worst sport has **at least 3 planned**, rate below 99.9 % and there are at least two sports; else "Nothing is being dropped more than anything else." Per sport: colour dot, name, a bar, percent, "done/planned".
* **Missed, or moved**: lede "N session(s) was/were moved rather than lost, against M missed outright." or "M session(s) missed, and none rescheduled." or "Nothing missed and nothing moved."; two figures; footnote "Moving a session rewrites its date in the workbook, so the sheet keeps no record that it ever moved. This app remembers its own moves since <date>, on this phone only. Anything rescheduled in Excel or in the web app is invisible here."

---

## 11. Colours and marks

Sources: `Theme.swift`, `Components.swift`. Every colour is `sRGB`; a pair is *day / night* (the screen follows the system appearance).

### 11.1 The ground and text

| Name | Day | Night | Stands for |
|---|---|---|---|
| `bg` | `#F6F8F8` | `#0A1F1F` | page ground (dark teal at night) |
| `surface` | `#FFFFFF` | `#1A3535` | cards |
| `surface2` | `#EEF3F3` | `#21403F` | pills, quiet fills |
| `text` | `#16302F` | `#FFFFFF` | main text |
| `secondary` | `#5C7373` | `#A0B8B8` | captions, labels |
| `border` | `#DCE6E6` | `#2A5555` | hairlines, unframed cards |
| `danger` | `#C81E1E` | `#FF6B6B` | missed, red buttons, warnings, "taken away", worse trend |
| `tomorrow` | `#E8F1FB` | `#122B3D` | the pale blue ground under TOMORROW on Today |

### 11.2 The four page colours

| Name | Day | Night | Page | Also means |
|---|---|---|---|---|
| `today` | `#00875A` | `#00C97B` | Today | **done** (green tick and frame), the main action (Save, Done, Log), "waiting to sync", a box you changed, a good morning delta |
| `plan` | `#1266C8` | `#3B9EFF` | Sessions | Move; the plan bar |
| `progress` | `#7C3AED` | `#C084FC` | Progress | fitness line, week bars, the clock |
| `settings` | `#5A6B7B` | `#94A3B8` | Settings | |
| `extraHour` | `#DE9B26` | `#F0B855` | — | the amber block on the hour in the extra-time blocks |

### 11.3 Sport colours (`sportHex`; the same by day and night)

| Id | Hex |
|---|---|
| swim | `#4F87F8` |
| bike, brick | `#FFD60A` |
| run | `#85CE6C` |
| strength | `#FF8C1A` |
| rowing | `#0D9488` |
| mobility | `#8650FE` |
| race | `#EF4444` |
| rest (and breathing, meditation, walk, hike, ski, Something else) | `#64748B` |
| any other id | `#22D3EE` |

**Sport ink** (a colour that carries words): by day the sport colour multiplied by 0.55 (darker, so the bike's yellow reads on white); at night the sport colour itself, except rest which is `#A3B1C2` (the slate is too dim on dark cards at 2.8 : 1).

**Sport icon** (`Theme.icon`): swim, bike, run, strength, mobility have their own glyph; brick uses the bike glyph; rest uses a moon (`icon-rest`, since 1.2; the check means done and nothing else); everything else `icon-other`. Glyphs are hand-drawn template images in the asset catalog (`icon-*`), tinted by the view: back, bike, breathing, camera, check, clock, cloud, counts, heart, hike, meditation, mic, mobility, other, pen, plan, plus, progress, race, rest, rowing, run, settings, share, ski, strength, stretch, swim, sync, today, walk, yoga.

### 11.4 Phase colours

A fixed ramp of eight stops, from cool to warm: `#4F87F8`, `#18A5B8`, `#14A37A`, `#85CE6C`, `#D8B931`, `#FF8C1A`, `#F0603C`, `#EF4444`. The i-th of n phases takes the colour at `i / (n − 1)` along the ramp (blended in sRGB between neighbours); with one phase the first stop. In the bar: now = 100 %, past = 75 %, future = 55 % opacity.

### 11.5 Marks (what each shape means)

| Mark | Where | Meaning |
|---|---|---|
| **Solid block** (sport colour) | week strip, key | recorded (done) |
| **Light block** (sport colour at 34 %) | week strip | still to do |
| **Hatched block** (diagonal lines every 4 points, 1.4 wide, at 80 %) | week strip, Sessions bar | marked missed |
| **Dotted block** (activity colour at 22 % with a dashed outline, dash 2/2) | week strip, extra cards (dashes 4/3, 1.5 wide) | an extra, outside the plan |
| **Flat grey line** (3 points tall) | week strip | rest day |
| **Moon** (`icon-rest`, grey-blue) | rest card, rest rows | rest day (1.2; was a check) |
| **Dotted purple bar** (Progress violet at 22 % with a dashed outline, dash 2/2, stacked above the solid one) | Load card | load from outside the plan (hikes, gym, anything not in the plan) |
| **Solid purple bar** | Load card | load from sessions in the plan |
| **Five faces** (bad, tired, OK, good, great) | Today, morning question | how he felt this morning |
| **Row of numbers 1 to 10** | session page, extra page, Load card | how hard it was |
| **Grey 2-point stub** | Load card (empty week), Mornings (no answer) | nothing recorded |
| **Green circle with a white check** (26 points) | session and extra cards, detail header | done — and nothing else since 1.2 |
| **Paler green tick** (60 %) | extra cards, extra bars | an extra is done, but it is not part of the plan |
| **Tiny tick** (7 or 10 points, with a ring in the card colour) | done bars on the week strip | done |
| **Green 2-point frame** | session card | done |
| **Red 2-point frame at 70 %** | session card | missed |
| **Plain card** | session card | still to do |
| **Red framed card** | Today | logging has waited a day |
| **Green pill "Waiting to sync"** | card, session | recorded on the phone, not yet in Dropbox |
| **Red pill "Missed"** | card | missed |
| **"counts" mark pill** | extra card | this extra counts as training |
| **Camera pill with a number** | card | the number of photographs |
| **Micro-thumbnails** (30 × 30) | card corner | the first three photographs |
| **Round grey pen** (30 points) | list rows, session, extras | adjust logged data |
| **Small blocks, green, every 4th amber** | week card | extra time that counts as training: a block per quarter hour, amber on the hour |
| **Green hairline with a grey notch** | week card | week's done time; notch = where the week should stand after today |
| **Sport-coloured pill with `›`** | session detail | intensity: tap to see what it means for you |
| **Plan bar (blue)** | Sessions | solid done, hatched missed, light to do |
| **Green outline on a box** | forms | the box was changed |
| **Green arrow ↑ / red ↓ / grey →** | Is it working | better / down / level |
| **Green / red / grey bracket** | morning line | good way / bad way / about as usual |
| **Orange "TEST COPY"** | Today | the file's name contains "test" |
| **Red small button** (Disconnect, Discard, Stop, Take them out) | Settings | takes something away |
| **Flag button** | Progress | what the race is |
| **Heart glyph** | Log details, Fill from Garmin, Health notes | numbers from Apple Health are available |

Pills: footnote semi-bold text in a capsule of the surface2 colour (`Pill`); `MarkPill` is the same with a glyph. Cards: radius 14. Buttons in Settings: caption bold, bordered, mini; a filled one only for the one or two that start something.

---

## 12. Settings, the guide, What's new

Sources: `SettingsView.swift`, `DropboxViews.swift`, `Guide.swift`, `PhotoViews.swift`.

### 12.1 Settings, top to bottom

Large title "Settings" (identifier `settings-title`).

1. **YOUR PLAN**
   * *Dropbox connected*: a row with the file name (or "No plan chosen yet") and a line (see below) and a **Change** button when a plan is chosen. If no plan is chosen: a filled **Choose your plan in Dropbox** button. Otherwise, under it, a quiet grey "Read it again now" (identifier `settings-read-again`; it calls refresh).
   * The row's line: "Pick the workbook the app should log into" if none chosen; else "TEST COPY · " (if the name contains "test") plus the read line: "Read just now", "Read <n minutes ago>", or "Copy on this phone, read …", or "Not read yet".
   * *Not connected*: a row "Not connected to Dropbox — Connect, and the app reads your plan from Dropbox and writes your logging into it."; a filled **Connect Dropbox** button ("Connecting…" while signing in; after sign-in the Dropbox browser opens); a grey **Or open a copy from Files, read only** button; if a Files copy was chosen, a row with its name and "Read only · <read line>".
   * Any problem text (the sign-in problem or the Store's last problem) in red.
2. **WAITING TO SYNC** (only when connected): "Nothing waiting — Everything logged on this phone is in Dropbox" (or "Sending…"); else one row per queued entry with the title (an extra shows "<Activity> · extra" or "<Activity> · extra, adjusted"), the line "<short date> · <last error or "waiting">", and a red **Discard** button; then **Send now** ("Sending…" while sending).
3. A grey one-line summary of what the app made of the sheet: `<sheets> · <N> sessions · <duration unit> and <distance unit> · done is written <done value>`.
4. **YOUR ZONES**: a row (chevron) whose title is the current numbers (e.g. "LTHR 148 bpm · CSS 120 sec/100 m": each current value with its label's own name and unit in brackets) or "No zones sheet in this workbook" / "No test entered yet", and a line "From <latest test>. Tap a session’s Z2 or Z4–Z5 for what it means for you." Opens Your zones.
5. **COLOURS AND SHAPES**: the week key (11.5 in the week key form) and "Also one tap away: tap the This week card on Today."
6. **EXTRA WORKOUTS**: a row "N recorded — Walks, yoga, breathing — everything outside the plan, newest first" (chevron) opening the list (8.3).
7. **PHOTOS**: "N photo(s) · X.X MB — On this phone only, and in the iPhone's own backup. Not in the workbook, not in Dropbox." plus "N belong to a session that has since changed — still here, still exported." for orphans (identifier `photos-count`); small buttons **Save all** (writes `workout-photos-<today>.zip` to a temporary file and opens the share sheet; disabled with no pictures), **Bring in a zip**, and a red **Delete all** (identifier `photos-delete-all`; confirmation "Delete every photo? They are the only copies." with "Delete all N" and "Keep them"); a result note ("N photo(s) brought in, K without a matching session (kept, counted, exported)." or "That zip could not be read: …"); an explanation line.
8. **APPLE HEALTH** (12.2).
9. **CALENDAR** (12.3).
10. **DROPBOX**: connected: the account (e-mail) or "Connected", the line "The app can read and write only the files you point it at." (plus, if entries are waiting, a warning that disconnecting keeps them on the phone but nothing goes to Dropbox until you connect and choose the plan again), and a red **Disconnect** (deletes the refresh token and the chosen path). Not connected: "Not connected — Use Connect Dropbox above."
11. **THIS APP**: **How this works** (chevron, "The week strip, logging, syncing and what keeps your plan safe") and **What’s new** (chevron, "AMS Workout Sync <version> (<build>)"; identifier `settings-whats-new`).

The **version number** is shown in this row (version and build from the bundle). Settings sections have ids `zones`, `photos`, `calendar` for scrolling.

The Dropbox browser (sheet): a navigation stack titled "Dropbox" listing folders (tap goes in) and `.xlsx` workbooks (plan glyph; tap chooses it and closes the sheet); "No folders or workbooks here." when empty; errors in red; a spinner while loading.

### 12.2 Apple Health section

| State | Row | Buttons |
|---|---|---|
| unavailable | "Not available on this device — Apple Health is iPhone only." | |
| asked and enabled | "In use — The log form offers the day’s workouts from Health to fill the boxes. Health is only read, never written." | red **Stop**; a caption "Stop means the app never asks Health for anything again. To also take the permission away, open the Health app → your picture → Apps → Workout Sync."; **Open the Health app** |
| asked but not enabled | "Not in use — The app does not read Health. The permission may still be granted in the Health app." | **Use again** |
| denied | "Could not ask — iOS did not let the app ask for access. Open the Health app → your picture → Apps → Workout Sync." | |
| unknown | "Not connected — Let the app read your workouts, heart rate and distances, and the log form can fill itself from what your Garmin sent to Health. Optional." | **Connect** (asks, then enables) |

When in use, a disclosure **What Health hands over** (identifier `health-what`, a chevron that rotates; "showing"/"hidden") opens: "WHAT APPLE HEALTH HAS TODAY" and "…HAD YESTERDAY" (each workout line `<type> · <summary> · <source>`, or "Nothing."; identifiers `health-today-row/none`, `health-yesterday-row/none`); "WHAT APPLE HEALTH HAS FOR THE NIGHT": Sleep ("N.N hours" or "none since 6 pm yesterday"), Resting heart rate ("48 bpm · normal 50 over 13 days" or "· no normal yet (N of 4 days)"), HRV ("64 ms …"); a hint if all three are empty (Garmin Connect shares sleep once switched on; HRV may not be shared); the probe lines (identifier `health-probe`; red "Health said: …" with `health-error`); and, if both days are empty, a hint to switch the rows on in Health. Buttons: **Read Health again** (`health-today-again`) and, only if both days are empty, **Ask iOS for access** (`health-ask-ios`). It loads again when today changes.

### 12.3 Calendar section

* On and allowed: a row "N sessions and rest days in your Training calendar" with "Updating…" / "Not written yet" / "Updated just now · from today to the end of the plan" / "Updated <relative> · from today to the end of the plan" and a red **Take them out**; a segmented control **At a time | All day** (identifier `calendar-kind`); in "At a time" a time picker "The day’s first session starts at"; an explanation text (two variants).
* Denied: "Not allowed — iOS is not letting the app write to your calendar. Settings → Apps → Workout Sync → Calendars → Full Access." and **Open Settings**.
* Not asked / off: "Not in your calendar — Put every session from today onwards into a Training calendar at 06:00, each as long as it is planned, and keep them right when sessions move." with a green **Put them in**.
* Any calendar problem in red.

### 12.4 How this works

A scrolling page of cards, one per part, in this order: What this app is; Today; Logging a session; The Sessions tab; Missed, Move, Swap; Extra workouts; How syncing keeps your plan safe; Photographs; Before you train; Progress; Your zones; In your calendar; Sending a session; Speaking instead of typing. Each card has a headline and one or more paragraphs. **Since 2.8 the parts also include (in page order) Notes that travel beside the plan; Reminders; Notes beside a log; The pool card; From your watch on a done session; Favourite sessions and repeating; Search and print; Keys, Spotlight and Siri; Away; Your race page; Shoes and bikes (see D.16).** **Since 2.1 there is also the part "On a session's page" (after "Logging a session"). Since 1.2 there is also "Signs in this app", and since 2.0 two more parts, "Where the plan lives" (after "What this app is") and "Changing the plan" (after "Missed, Move, Swap"); "How syncing keeps your plan safe" became "How your plan is kept safe" and every part says what is true before and after the switch.**

### 12.5 What's new

A scrolling page of cards, newest first, each with the version and build, the date, a green headline and bullet paragraphs. Entries run from "0.1 (1) Read only" to "2.8 (84) Forty-one things you picked: Body in more depth, reminders, away mode, a race page, notes beside a log, Garmin on a done session, and Claude on your week". Every release adds an entry at the top.

### 12.6 The name in the app's texts (done in 1.2)

Done in 1.2 (73): `project.yml` (`CFBundleDisplayName` `Triathlon`, `CFBundleName` `AMS Triathlon Training`, the Health read and update texts), the What's new row in Settings ("AMS Triathlon Training <version>"), the Health and calendar help lines ("Apps → Triathlon"), the Health help in the log form, the guide and the README. The version test (`testOpensOnTodayAndSettingsShowsTheVersion`) matches `AMS Triathlon Training \d+\.\d+ \(\d+\)`.

Left on purpose: the bundle id, the URL scheme `amsworkoutsync`, the target, scheme, folder and Swift package names, the UI test file name `WorkoutSyncUITests.swift`, and the old name in What's new entries up to 1.1 and in the guide's one sentence that says the app used to be called Workout Sync.

---

## 13. Colours of state, in one table

| State | Session card | Week bar | Sessions bar |
|---|---|---|---|
| Still to do | plain, grey border not drawn | sport colour at 34 % | light blue |
| Done | green frame and tick | solid sport colour with tick | solid blue |
| Missed | red frame at 70 %, red "Missed" pill | hatched | hatched blue |
| Done, waiting to sync | green frame and tick, green "Waiting to sync" pill | as done | as done |
| Moved, waiting to sync | "Moved · waiting to sync" pill | on the new day | |

---

## 14. Tests, checks and tools

### 14.1 How tests run (`.github/workflows/tests.yml`)

Workflow **Tests** runs on every push, every pull request and by hand. Runner `macos-15`, 30-minute limit. The repository is public so GitHub's Mac runners are free. Steps:

1. Show Xcode and the available iPhone simulators.
2. Install XcodeGen and generate the project.
3. Pick an Xcode that has an iPhone simulator (keep the current one if it has; otherwise the newest installed that has one; fail with an error if none).
4. Pick the highest-numbered iPhone simulator on the runner.
5. **Model tests**: `swift test --package-path Core` (seconds, no simulator).
6. **Soak**: build the `soak` product and run it for 3 rounds against `UITests/Fixtures/plan.xlsx`.
7. **UI tests**: `xcodebuild test` on the simulator, unsigned (`CODE_SIGNING_ALLOWED=NO`), result bundle `TestResults.xcresult`.
8. On failure the result bundle is uploaded as an artifact `TestResults`.

A red run means the build is not fit to send to TestFlight. All fixtures are invented; the user's real plan is never used.

Local equivalent: `xcodebuild test -project AMSWorkoutSync.xcodeproj -scheme AMSWorkoutSync -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/amsws-dd CODE_SIGNING_ALLOWED=NO`.

### 14.2 Model tests (`Core/Tests/WorkoutCoreTests`, XCTest; fixture `Fixtures/plan.xlsx`)

| File | Covers |
|---|---|
| `BrokenWorkbookTests` | a workbook with nothing recognisable is refused quietly; a plan with no Extras sheet reads; zones survive a workbook without them; the same extra is never appended twice; an extra with a rubbish date is not placed on a wrong day |
| `EffortTests` | an hour at threshold is 100; hard vs easy hour; linear in time; fallback order and source named; no time is no cost; zone ranges at their middle; an absurd heart rate is held inside; rest lowers fatigue faster than fitness; curves cover every day; a backwards range is refused; the standing words; only done work costs; a day adds up; only extras that count are counted |
| `ExtrasWritingTests` | an extra is appended to the first free row; it reads back as itself; writing it twice does not double it; a correction writes only the boxes named |
| `FortnightTests` | this morning against the days before; a day held twice counts once; the last reading of a day stands; no normal until enough days; yesterday stands until today arrives; an old reading is not this morning; older than a fortnight is left out |
| `LoadTests` | five rules (1.2): load is minutes × how hard; the score falls back in order and says which; a Health workout already written down is not counted twice; weeks add up and a usual week is the four before this one; the morning question is answered once a day |
| `PhotoMatchTests` | the plain row match; a shifted row does not orphan; the sport must agree; another day's session is not it; a moved session keeps its pictures; an extra matches exactly; a photo with no day falls back on nothing |
| `ProgressTests` | a week adds up what is in it; each week keeps its days; days outside the window are left out; a sport with nothing is not listed; an empty plan says nothing; the weeks asked for; a phase after the race gets no block; a phase straddling the race is cut; blocks never exceed the bar; weekly figures stop at the week just gone; Monday leaves the new week out; a phase knows its session count and done count; phases add up to the road's totals |
| `ReadingTests` | durations as typed; things that are not durations; durations written back in the sheet's unit; numbers written as Excel would; the week starts on Monday (also across month and year); day counting across month ends; a non-day key is refused; only an altered box is written; emptying a box is a change; an extra knows whether it counts by its kind; an unknown activity keeps its row; every activity has its own mark; every pattern in the reader compiles; **`QueueTests`**: an entry from an older app still reads, an entry from a later app does not take the others with it, the queue round-trips through its file |
| `SleepTests` | one night is its own length; the same night twice counts once; phases inside a whole night count once; a waking stays out; two devices are not added; nothing recorded is nothing |
| `WriterSoakTests` | awkward values (Swedish letters, long note, decimals, zero, emptied cell, a cell twice) survive; many writes in one go; write then empty leaves nothing; the file is still a workbook after a series of writes |
| `WritingTests` | a cell written comes back out; the rest of the workbook is untouched; an emptied cell empties the cell; a workbook survives being saved twice; rubbish is refused rather than guessed at |

### 14.3 UI tests (`UITests/WorkoutSyncUITests.swift`)

Controls are found **by accessibility identifier, never by words**. Every test starts clean (`AMSWS_RESET`) on the fixed day **Wednesday 16 September 2026** (`AMSWS_TODAY`) with the invented workbook `UITests/Fixtures/plan.xlsx` (a plain fortnight plus an invented zones sheet) whose one session that day is a 35-minute run at Z2. Test names:

1. `testOpensOnTodayAndSettingsShowsTheVersion`
2. `testASessionsZoneOpensWhatItMeans`
3. `testTheRaceIsBehindTheFlag`
4. `testLoggingLeavesOnlyAdjust`
5. `testUseFromGarminLeavesThePaceAlone`
6. `testExtraFormOffersGarminFromHealth`
7. `testExtrasUnderDoneCarryTheTick`
8. `testTheSessionsFiltersStayWhileScrolling`
9. `testAnExtraDoneYesterdayCountsInThisWeek`
10. `testTheExtraFormNeverGoesDead`
11. `testTheFormSaysWhenAppleHealthIsOff`
12. `testTheFormOffersWorkoutsOfAnotherSport`
13. `testSettingsSaysWhatHealthHandsOver`
14. `testDeletingEveryPhotographAsksFirst`
15. `testPlusOneMovesTheSessionToTomorrow`
16. `testTheSessionsBarAgreesWithTheFourCounts`
17. `testTodayShowsLastNightsNumbers`
18. `testWithoutDropboxTodayOffersToConnectIt`
19. `testTheTwoQuestionsTakeOneTapEachAndLoadCounts` (1.2)

### 14.4 Mac command-line checks (`Core/Sources/*`)

| Product | What it does |
|---|---|
| `plan-dump` | prints every session of workbooks as JSON (for parity with the web app) |
| `write-dump` | applies logging scenarios to copies of workbooks (for parity) |
| `sync-check` | runs the whole sync engine against a file-backed fake Dropbox: a queue of four in one upload; a conflict retried; a second conflict refused; a reworded row followed; a row changed to another sport refused; one bad entry not blocking the rest; verify refusing bad bytes; the overlay and swap list; extras appended without doubling |
| `form-check` | checks the log form's shape against a workbook |
| `stats-dump` | prints the Progress figures as JSON |
| `zones-dump` | prints the zones read |
| `soak` | "weeks of use in seconds": rounds of four logged sessions, a missed mark, a move and two extras through the real sync engine, with a file saved in Excel before one upload so a conflict is survived; then every logged session's minutes, every missed mark, every move's date and unchanged words, every extra exactly once, and that every cell on every other sheet is as it was; ends "errors: none"; works on a copy |

### 14.5 Parity tools (`tools/`, see `tools/README.md`)

The native reader and writer are line-for-line ports of the web app's, and are proven against it:

* `parity.py` (reading, field by field), `write-parity.py` (writing: same parts, same order, same headers and CRC; unchanged parts the same compressed bytes; changed parts the same bytes once unpacked), `stats-parity.py` (Progress figures), `zones-parity.py` (an independent reader in openpyxl).
* `make-scenarios.py`, `make-edge-books.py` (eight workbooks that reach rare branches: no calcPr, formulas and calcChain in result columns, date-styled dates, the 1904 date system, h:mm:ss durations, one row per section, a stale dimension), `js-dump.js`, `js-write.js` (web app side).
* The icons come from the central AMS-Icons package since 2.4 (the `tri…` app marks; `make_assets.py` is gone); `render-icon.js` and `app-icon.svg` make the app icon; `ExportOptions.plist` is the App Store Connect export.
* These need the web app served on `http://localhost:7810/`, Playwright and Chrome. Every change to the writer or to `buildEdits` must be re-run through them before it ships.
* Build the mapping in any harness with `Plan.mapping(for:)`, never the bare `autoDetect`: otherwise the duration unit stays hours and a harness writes seconds into a minutes column.

### 14.6 DEBUG launch switches

Compiled **only in DEBUG** builds; none exists in a release build. Pass them as environment variables (`SIMCTL_CHILD_<NAME>=…` with `xcrun simctl launch`, or `launchEnvironment` in UI tests).

| Variable | Effect | Source |
|---|---|---|
| `AMSWS_TODAY` | Fixes "today" to a day key (`YYYY-MM-DD`) | `Store.swift` |
| `AMSWS_FILE` | Reads this local workbook instead of Dropbox/Files; refresh then does nothing | `Store.swift` |
| `AMSWS_RESET` | Clears the queue, the move log, the Health marks and Health settings at start; since 1.2 also deletes `diary.json` | `Store.swift`, `Health.swift`, `Diary.swift` |
| `AMSWS_SHOW_BUTTONS` | `canLog` is true without Dropbox | `Store.swift` |
| `AMSWS_FAKE_PATH` | Pretends a Dropbox path is chosen | `Store.swift` |
| `AMSWS_FAKE_CONNECTED` | Pretends Dropbox is connected (account shown as an example address) | `Dropbox.swift` |
| `AMSWS_FAKE_HEALTH` | Health is "asked and in use"; three invented workouts for any day (a ride, a walk, a pool swim); since 1.2 also four invented Health workouts for Load (a 147-minute hike 2 days back, a 40-minute strength 4 days back, a 195-minute hike 9 days back, and 12 minutes of breathing 1 day back, which is not load); invented morning numbers (sleep 7.4 h, resting 48 vs 50, HRV 64 vs 58, 13 days); a fake probe | `Health.swift` |
| `AMSWS_FAKE_PHOTOS` | With a session key as value: creates two invented pictures for it if the index is empty | `Photos.swift` |
| `AMSWS_FAKE_SPORT` | The sport those fake pictures carry (default run) | `Photos.swift` |
| `AMSWS_CALENDAR` | Switches the Training calendar on at launch (if iOS already granted access) | `TrainingCalendar.swift` |
| `AMSWS_TAB` | Opens on `today`, `plan`, `body`, `progress` or `settings` (`body` since 2.6) | `AMSWorkoutSyncApp.swift` |
| `AMSWS_LIST` | Opens Sessions on `Upcoming`, `Done`, `Missed` or `All` | `PlanTab.swift` |
| `AMSWS_SESSION` | Overlays a session screen for this session key | `AMSWorkoutSyncApp.swift` |
| `AMSWS_LOGFORM` | Opens the log form when a session screen appears | `SessionView.swift` |
| `AMSWS_MOVE` | Opens the Move sheet when a session screen appears | `SessionView.swift` |
| `AMSWS_ZONE` | Opens the zone sheet for the session's intensity | `SessionView.swift` |
| `AMSWS_SHARE` | Opens the "Send it to somebody" dialog | `SessionView.swift` |
| `AMSWS_ZONES` | Overlays the "Your zones" screen | `AMSWorkoutSyncApp.swift` |
| `AMSWS_EXTRAS` | Overlays the extras list | `AMSWorkoutSyncApp.swift` |
| `AMSWS_EXTRA_DETAIL` | Overlays the detail of today's first extra (else the first extra) | `AMSWorkoutSyncApp.swift` |
| `AMSWS_EXTRAFORM` | Opens the extra form on Today: `1` for today, or a day key for that day | `TodayView.swift` |
| `AMSWS_SCROLL` | Scrolls Settings to the section id `zones`, `photos` or `calendar`; with the value `load` scrolls Progress to the Load card (1.2) | `SettingsView.swift`, `ProgressView.swift` |
| `AMSWS_HOME` | 2.0: `app` with `AMSWS_FILE` takes that file in and makes the app the plan's home (no Dropbox needed) | `Store.swift` |
| `AMSWS_MOVEIN` | 2.0: opens the page "The plan moves in" | settings screens |
| `AMSWS_EDIT` | 2.0: opens "Change session" | session screens |
| `AMSWS_CHANGES` | 2.0: opens "Changes to the plan" | settings screens |
| `AMSWS_TEST` | 2.1: `1` opens the test list in Your zones; `new` opens the page "Enter a test result" | settings screens |
| `AMSWS_SAFETY` | 2.1: `1` opens "Safety copies" | settings screens |
| `AMSWS_RIDES` | 2.1: `1` opens "Thursday rides" | settings screens |
| `AMSWS_GARMIN` | 2.1: `1` opens a session with the Garmin card | session screens |
| `AMSWS_FEEL` | 1.2: `1` to `5` answers this morning's question with that face; `week` fills the thirteen days before today (pattern 3 4 4 2 3 5 4 3 · 4 2 3 4, one day left unanswered) so the Mornings bars have something to draw | `Diary.swift` |
| `AMSWS_SIDE` | 2.2: `today`, `plan`, `sessions`, `body` (2.6), `progress` or `settings` opens the wide look on that row | `WideRoot.swift` |
| `AMSWS_PLAN` | 2.2: `week`, `month` or `year` opens the Plan page on that view | `WideRoot.swift` |
| `AMSWS_DEVICE` | 2.2: `phone`, `ipad` or `mac` fakes the kind of device (screens and tests on any simulator) | `Device.swift` |
| `AMSWS_FAKE_CLOUD` | 2.2: a folder path used as the app's iCloud folder (`Sync/` is made inside it); iCloud is also switched on in a run that has `AMSWS_FILE` or `AMSWS_RESET`, which otherwise run without iCloud; the quiet look is every 3 seconds instead of 30 | `PlanCloud.swift` |
| `AMSWS_CLOUD_SEED` | 2.2: with `AMSWS_FAKE_CLOUD`, a workbook path; if the fake folder has no `plan.json`, the plan taken in from that workbook is written there, with an invented iPhone device file, as if an iPhone had put it there | `PlanCloud.swift` |
| `AMSWS_CLOUD_PAGE` | 2.2: `1` opens Settings → iCloud | `SettingsView.swift` |
| `AMSWS_WAITING` | 2.2: `off`, `working`, `none`, `excel`, `ready`, `update` or `problem` forces one state of the page an iPad or Mac shows before the plan has arrived | `WaitingForPlanView.swift` |
| `AMSWS_FAKE_GARMIN` | 2.2: invented Garmin numbers (read at 07:12, HRV 64, sleep 7 h 20, resting 47, Body Battery 71, stress 28) and "a key is saved", no network, no key | `GarminKey.swift`, `GarminReader.swift` |
| `AMSWS_GARMIN_PAGE` | 2.2: `1` opens Settings → Garmin | `AMSWorkoutSyncApp.swift` |
| `AMSWS_MORNING_PLATE` | 2.2: `1` opens the plate "Garmin, this morning" with invented numbers | `AMSWorkoutSyncApp.swift` |

For a calendar check: `xcrun simctl privacy <udid> grant calendar com.schabbauer.AMSWorkoutSync`, launch with `SIMCTL_CHILD_AMSWS_CALENDAR=1`, then read the simulator's calendar database (`tools/README.md`).

### 14.7 How a release is made

1. Change the code. Every build adds an entry at the top of `WhatsNewView.releases` in `Guide.swift`; when behaviour changes, the matching part of `GuideView.parts` is updated; this specification is updated.
2. Raise `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (App Store Connect refuses a build number it already has). Run `xcodegen generate`.
3. Run the model tests and, for the writer or `buildEdits`, the parity tools (14.5). Push; the **Tests** workflow must be green.
4. **TestFlight** — two ways, same result:
   * On the Mac: archive with `-allowProvisioningUpdates`, export with `tools/ExportOptions.plist` (`method app-store-connect`, `destination upload`, automatic signing), which uploads to App Store Connect; TestFlight internal group "Me".
   * On GitHub: workflow **TestFlight** (`.github/workflows/testflight.yml`), started by hand (`workflow_dispatch`). Runner `macos-26` (Apple refuses anything built with an SDK older than iOS 26), 60-minute limit. It needs three repository secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, an App Store Connect API key) and stops at the first step if any is missing. Steps: write the key to the runner; use the newest Xcode; read the version and build from `project.yml`; install XcodeGen and generate; **archive** unsigned-for-distribution (ad hoc `-` identity, **keeping the entitlements file**: blanking it once shipped seven builds with no HealthKit entitlement); **check the archive carries the HealthKit entitlement** and fail if not; **export and upload** with `-allowProvisioningUpdates` and the API key; on failure keep the export and logs for 5 days. Ad hoc archiving avoids minting a new Apple Development certificate on every runner (an account has a certificate cap).
5. Apple takes a few minutes to process the build.
6. Workflow **Crash reports** (`crash-reports.yml`, by hand, input `how_many`, default 3) fetches the newest TestFlight crash reports for bundle id `com.schabbauer.AMSWorkoutSync` from App Store Connect with the same key (read only) and prints them and keeps them as an artifact `crash-reports`.
7. The code lives in its own GitHub repository; commit and push with every release.

---

## 15. Surprising or doubtful things found while writing this (as the code is today)

These are described so the next author can decide. Nothing here was changed.

1. **Refresh is skipped while anything is waiting** (while Excel is the home; since 2.0, once the plan lives in the app, `refresh()` returns at once and a stuck entry no longer blocks reading the plan, because there is nothing elsewhere to read). `Store.swift:273`: `refresh()` with a non-empty queue calls `syncNow()` and returns. If the sync cannot write an entry (for example "no longer in the workbook"), nothing is uploaded, no new copy is parsed, and the plan on screen is not refreshed from Dropbox until the entry is sent or discarded.
2. **"Logged on" is the sync time.** `Sync.swift:710–711` sets `completedAt = now` at sync; no screen sets `completedAt` (checked: no write to it in `App/Sources`). A session logged offline gets the date it was *sent*.
3. **Distance in a shared message.** `ShareText.swift` `doneFigures` prints a waiting distance with the **sheet's** unit even if the entry was typed in the other unit (a swim typed in metres on a kilometre sheet would read as metres labelled "km").
4. **Two speed-like boxes on a bike.** `LogForm.swift:664, 682`: the bike form offers "Average speed" (the *pace* column) and "Speed" (the speed column) in the same form; the session screen shows only the pace column, labelled "Speed".
5. ~~Guide has no "Signs in this app".~~ Closed in 1.2.
6. **Out-of-date comments.** `Store.swift:5–17` says the app "cannot write even by accident" and "nothing here ever opens the file for writing" (it writes through Dropbox); `Writer.swift` header says "Nothing in the app calls this yet"; `Mapping.swift` header says the Sheet setup screen is not part of the app (true, but the detection is final: there is no way to correct a wrong guess).
7. **Hard-coded app name in a row.** `SettingsView.swift` What's new row text "AMS Workout Sync <version>".
8. **Conflict detection by text.** `Dropbox.swift` treats HTTP 409 as a conflict when the body merely contains the word "conflict".
9. **Orphans can still match.** `Photos.swift` `importZip` stores an unplaced picture with an empty key but the day and sport from its name; `PhotoMatch` can then show it against a session of that day and sport (it would normally have been placed already).
10. **The Today empty state promises read-only** ("This app only reads it") while the Settings flow can connect Dropbox for writing; the text is only true for the Files path.

---

## New in 1.2 — the two questions and load

Release 1.2 (73), 24 November 2026. Sources: `Core/Sources/WorkoutCore/Load.swift`, `App/Sources/Diary.swift`, `FeelViews.swift`, `LoadViews.swift`, and the spots named below. All examples are invented.

### N.1 The name change

* **Changed.** The shown name is **AMS Triathlon Training**. Under the icon the home screen reads **Triathlon** (`CFBundleDisplayName` `Triathlon`; `CFBundleName` `AMS Triathlon Training`). The version is 1.2, build 73 (`project.yml`: `MARKETING_VERSION` 1.2, `CURRENT_PROJECT_VERSION` 73). The Health read and update texts and the Settings "What's new" row use the new name; the help lines say "Apps → Triathlon" (the name iOS lists the app under).
* **Not changed.** Bundle id `com.schabbauer.AMSWorkoutSync`, URL scheme `amsworkoutsync`, the Xcode target, scheme and folder names, the Swift package `WorkoutCore`, the repository. The data (workbook choice, waiting queue, move log, Health marks) carries on; nothing is set up again. The plan still lives in the Excel file.

### N.2 The morning question

* **Where.** On Today, directly under the morning line (`TodayView.swift`, `FeelCard`; list in 5.1 item 4). Heading "How do you feel?" (identifier `feel-question`).
* **The five answers**, each a drawn face with a word under it (`FaceMark`; the faces differ only in the mouth; "Tired" has closed eyes), stored as a number: **1 Bad, 2 Tired, 3 OK, 4 Good, 5 Great** (`Feel`). Identifiers `feel-1` … `feel-5`; the spoken label is the word.
* **Once a day.** The card shows only while today has no answer (`FeelLog.asks`). One tap answers and the card is gone until tomorrow. A day holds one answer; a second tap the same day replaces it, it never adds.
* **Changing it.** The answer is added to the morning line as `Feeling good` (`Feeling OK` for 3; spoken "Feeling good"). The line shows even when Health gave no numbers if an answer exists. A tap on the line (only when there is an answer) brings the card back with today's answer outlined; one tap replaces it and the card goes again.
* **Storage.** On this phone only, in `diary.json` in Application Support (see N.4 for the whole file). The workbook has no column for it and nothing is written to Excel or Dropbox. It is not in the waiting queue.
* **Nothing reacts to it.** No other screen, number or colour changes with the answer, no advice, no reminder. Its only other appearance is the Mornings bars on the Load card.

### N.3 "How hard was it?"

* **Where.** `HowHardCard`: heading "How hard was it?" (identifier `how-hard-question`) and a row of the numbers 1 to 10 (`EffortRow`, identifiers `effort-1` … `effort-10`, each labelled "n out of 10") with the words "1 very easy", "7 hard", "10 all out" under the row.
* **On a session's page** (`SessionView.swift`), in the place the Done button had, when all of these hold: `canLog`; the session is done; it is not a rest row; the workbook has an Effort column (mapping column `rpe`); and the sheet's Effort figure for it is 0 (empty). Until answered it simply waits there; no reminder.
* **On an extra's page** (`PhotoViews.swift`, `ExtraDetailView`): `canLog`, the extra's Effort is empty, it was not just answered, and the activity is not breathing or meditation. After the tap a line "Effort n / 10 saved" (identifier `extra-effort-saved`) replaces the card.
* **What one tap writes** (`Store.swift`). Only the plan's own Effort column, the same box the log form calls Effort. Nothing new is added to the workbook.
  * Session — `setEffort(workout, score)`: nothing happens unless `canLog` and the score is 1 to 10. It builds a log entry holding only the effort, **except** that if the session already has a waiting entry that is not a "missed" entry, that entry is taken and the effort is added to it. Reason: the screens show the last waiting entry, so a bare number would hide the length just logged. The entry goes through the normal queue (3.6): first on the phone, then sent.
  * Extra — `setEffort(extra:, score)`: an edit of the extra that names only the Effort field (`ExtraField.effort`); the other fields of the entry are copied from the extra unchanged, so only that box is written (9.4).
* **Health workouts** outside the plan have no row in the workbook: their number goes to the diary instead (N.4, "How hard?" rows).

### N.4 Load

**The formula** (`Load.points`): load = **minutes × how hard (1 to 10)**. A score outside 1 to 10, or no minutes, counts 0. Example: a 60-minute run at 5 counts 300; a 147-minute hike left at the guess of 3 counts 441; that week is 741.

**Where the score comes from** (`Load.score`), first that exists:
1. **His own answer**, 1 to 10 (the sheet's Effort for a session or an extra; the diary's answer for a Health workout).
2. **The plan's intensity text** (`Load.fromZone`; sessions only): Z1 2 · Z2 3 · Z3 5 · Z4 7 · Z5 9. A range is the middle of its zones ("Z4–Z5" is 8, "Z1-Z2" is 2.5). If the text has no zone but has "RPE" followed by numbers, those are already on the scale and averaged ("RPE 6–7" is 6.5). Only numbers 1 to 10 count.
3. **A guess of 3** (easy) when nothing else exists.
The card says which of the three it used only as a count (below).

**What counts** (`Load.items`; an item with no minutes is dropped):
* every **done plan session** — not missed, not a rest row; minutes are the sheet's figure, else the planned length;
* every **extra** except breathing and meditation, **whatever its "counts as training" switch says** (a hike is load either way); no plan score exists for it, so it is his answer or 3;
* every **Health workout not already recorded** (next), of **at least 10 minutes**, apart from breathing and meditation (Health's mindfulness and recovery types, marked "mind").

**The matching rule** (`Load.outside`), so nothing is counted twice:
1. From Health's list drop workouts shorter than 10 minutes and the "mind" ones.
2. Take what is recorded, in this order: the done plan sessions, then the extras (`Load.recorded`). For each, look among the Health workouts left **on the same day** for one of a related sport (`kinship`): 0 = the same sport (yoga and mobility are one family, hike and walk are one family; a recorded brick matches a bike or a run); 1 = near enough (a run with a walk, either way; a recorded race with a swim, bike or run). The best is the lowest kinship, then the smallest difference in minutes. It is taken out of the list. **Each recorded thing takes out at most one workout**, so a morning and an evening run are two.
3. A recorded thing that found no related sport and has minutes: take out the workout of that day whose length is within **5 minutes** of it (the closest), whatever its sport — an extra written under another name.
4. What is left is "outside the plan".

**Weeks and "usual week"** (`Load.weeks`, `Load.usual`): a week is Monday to Sunday; items add into the week of their day, in-plan and outside kept apart. Eight weeks are drawn (`Diary.weeks`), the last being the current one. The **usual week** is the average of the (up to) four finished weeks before the current one, leaving out weeks before the first day anything was recorded, so the first month is not averaged with zeros. With no finished week it shows "—".

**The Load card** (`LoadViews.swift`, on Progress after "Fitness and freshness"; title "Load"):
* **Three figures**, rounded, thousands separated: "this week so far" (identifier `load-this-week`), "last week", "usual week".
* **Eight bars**, one per week, the last labelled "now"; the others by the Monday (day and month at the first bar and each new month, the day alone between). Height scales to the tallest week (96 points, at least 5); an empty week is a 2-point grey line. **Solid** (Progress violet) = load from sessions in the plan; **dotted** (violet at 22 % with a dashed outline) = load outside the plan, stacked above the solid part. Identifier `load-bars`; its spoken label lists the eight totals.
* **Key** under the bars: "In the plan" (solid) and "Outside the plan (hikes, gym)" (dotted).
* **Explanation line**: "Load = minutes × how hard (1–10). A 60-minute run at 5 counts 300. Hikes and gym sessions come from Apple Health." and, if any counted activity in the eight weeks has no answer of his own: "N of M had no number from you: counted from the plan's zone, or as 3 (easy)."
* **"How hard?" rows**: Health workouts outside the plan from the **last 14 days** (today and the 13 days before) with no answer yet, newest first, **at most 3 shown**. Each row reads "<short date> · <name> · <length>" with a small **How hard?** button (identifier `load-how-hard`); it opens the number row (identifiers `load-effort-1` … `load-effort-10`); a tap stores the answer, the row goes and the week's load moves. A line "and N more from the last two weeks" follows when there are more than 3.
* **Mornings**: shown only if at least one of the last 14 mornings has an answer. Fourteen small bars, oldest first, height `answer × 4 + 2` points (taller = felt better); an unanswered morning is a 2-point grey stub. Caption "taller = felt better". Identifier `load-mornings`, spoken label lists the words.

**Where Health is read** (`Health.swift` `found(from:to:)`, `Diary.readHealth`): every time the app comes to the front (`AMSWorkoutSyncApp.swift`, with `readMorning`), if Health is in use, the workouts from the first Monday of the eight weeks to today are asked for (a workout's id, day, sport, name and length only — no heart rate, no distance). A failed read returns nothing and the last good list is kept.

**Storage — `diary.json`** (`Diary.swift`, Application Support; written atomically): the mornings (`feel`), his answers to Health workouts by the workout's own id (`answers`) and the last list Health handed over (`found`), so the card draws at once. Kept on this phone only. A DEBUG switch removes it (`AMSWS_RESET`). It holds no plan data.

### N.5 What 1.2 deliberately does not do

* No suggestions, no advice, no warning colours, no "too much" or "rest more". Load and mornings are shown, nothing is concluded.
* The plan is not changed by any of it; nothing is moved, added or removed.
* There is no Garmin key and no Garmin call in the app; Health is the only source for what the plan does not hold.
* There is no plan store: the plan stays in the Excel file in Dropbox.
* **Sleep is shown only** (the morning line) and never drives anything: not load, not the question, not any colour.
* Nothing new is written to the workbook; the only written figure is the Effort that already had a column.

### N.6 Signs added or changed

* **Moon** = rest day (rest card, rest rows). It replaced the check, which now means **done and nothing else**.
* **Dotted purple bar** = outside the plan (Load card). The same dotted look means an extra on Today's week strip.
* **Solid purple bar** = in the plan (Load card).
* **Five faces** = how he felt this morning; **row of numbers 1 to 10** = how hard it was.
* **"Feeling good"** on the morning line = today's answer; a tap changes it.

All are also in section 11.5 and in "How this works" ("Signs in this app").

### N.7 Tests and DEBUG switches added

* **Rule tests** (`LoadTests`, seconds): `testLoadIsMinutesTimesHowHard`, `testTheScoreFallsBackInOrderAndSaysWhich`, `testAHealthWorkoutAlreadyWrittenDownIsNotCountedTwice`, `testWeeksAddUpAndAUsualWeekIsTheFourBefore`, `testTheMorningQuestionIsAnsweredOnceADay`.
* **Screen test**: `testTheTwoQuestionsTakeOneTapEachAndLoadCounts` (UI test 19): the question is asked and gone after one tap, the morning line says "Feeling good"; a done session is followed by "How hard was it?" which goes after a tap on `effort-6`; Progress shows the Load card and a Health hike asks its own question, and giving it 9 changes the week's figure.
* **DEBUG switches**: `AMSWS_FEEL` (new), `AMSWS_SCROLL=load` (new value), `AMSWS_RESET` now also clears the diary, and `AMSWS_FAKE_HEALTH` now also gives four invented workouts for Load (14.6).
* Counts after 1.2: model-test files 11 (was 10), UI tests 19 (was 18), DEBUG switches 23 (was 22; the new one is `AMSWS_FEEL`).

### N.8 Housekeeping

Two stray duplicate project folders, `AMSWorkoutSync 2.xcodeproj` and `AMSWorkoutSync 3.xcodeproj` (stale copies from builds 51 and 57), were removed from the repository. `AMSWorkoutSync.xcodeproj` (generated by XcodeGen from `project.yml`) is the only one.

---

## New in 2.0 (74) — the plan lives in the app

Until 1.2 the plan's home was the Excel workbook in Dropbox and the app a careful guest in it. From 2.0 the user may move the plan into the app. It is his choice, by one tap, and reversible for three weeks. Until he taps, nothing in this section is in effect: `home` is `.excel` and sections 3 to 9 describe the app unchanged. Files: `Core/Sources/WorkoutCore/PlanBook.swift`, `PlanImport.swift`, `PlanExport.swift`, `BookOracle.swift`, the end of `App/Sources/Store.swift` ("the plan's home in this app (2.0)"), `Core/Sources/BookCheck/main.swift`.

### P.1 The two homes

`Store.Home` is `excel` or `app`, kept in UserDefaults `plan.home`. `planLivesHere` is `home == .app`.

| | Excel is the home (as before) | The app is the home |
|---|---|---|
| Where the plan is | the workbook in Dropbox (or Files, read only); a cached copy | `plan.json` in Application Support |
| Logging | queued, then sent (9.3) | written into the book at once (`writeHere`, P.4); the queue holds only what could not be applied |
| `refresh()` | downloads, parses | returns at once: "the plan lives here: there is nothing elsewhere to read" |
| `canLog` | Dropbox connected and a path chosen | always true |
| Changing the plan | not possible | possible (P.9) |
| "Waiting to sync" | shown | nothing waits; a stuck entry stays in the queue with its reason but no longer blocks reading the plan |

At start-up, if `plan.home` is `app`, the store reads `plan.json` and publishes it. If the book will not open, `lastProblem` says "The plan kept in this app could not be opened. Its safety copies are untouched — see Settings." and the store falls back to the last cached workbook rather than show nothing.

`publish(book)` sets the displayed plan, extras, zones and mapping from the book (`fromCache = false`, `phase = .ready`) and tells the calendar the plan changed. Everything that reads `plan`, `extras`, `zones` (Today, Sessions, Progress, Load, the calendar, photographs, sharing) therefore works unchanged.

### P.2 The book (`PlanBook`)

A `Codable` document the app owns. Fields:

* `format` (1, `currentFormat`).
* `sessions: [Workout]` — every session, in order: by day, then by the row it had in the workbook, then insertion order (`inOrder`).
* `extras: [ExtraRecord]` — newest day first, then highest row.
* `zones: Zones?`, `weeks: [PlanWeek]` (`number`, `monday` as a day key, `phase`, `tag`; `isEasy` when the tag contains "recovery" or "easy", `isTest` when it contains "test"), `mapping: Mapping` (units and which boxes a session has, as the workbook had them), `origin: PlanOrigin` (`fileName`, `takenAt`, session and extra counts at the move).
* `changes: [PlanChange]` — see P.9; at most 400 are kept, oldest dropped first.
* `stamps: [String: Date]` — when each session (by key) or extra (`"extra:" + id`) last changed. It is what "the newest change wins" will go by between devices; nothing reads it for that yet.
* `removed: [String: Date]` — sessions taken out of the plan and when, so that another device would not bring one back.
* `counter: Int` — how many sessions have been made in the app.

**Permanent session names.** A session keeps the key it had in the workbook (for example `Weekly Schedules!7`: sheet name, `!`, row) for good, whatever is changed or moved afterwards. Photographs (9.11), the move log (3.7) and the Training calendar (9.7) hang on that name, and a session that changed it would quietly lose them. Sessions made in the app are named `App!<n><random>` (P.9).

**`source`.** A `Workout` taken from a single-row workbook line also carries `source`: that row's cells word for word by heading (`[heading: text]`, a formula's cell as its last answer). It holds, for example, the plan week (`planWeek`, from heading "Week") and the key-session star (`isKey`, from heading "Key": any text other than blank).

**Tolerant reading.** `init(from:)` requires only `mapping` and `sessions`; without them there is no book. Every other field falls back (extras `[]`, weeks `[]`, origin invented from the counts, changes `[]`, stamps and removed empty, counter 0). A `Workout` needs `key` and a valid `dayKey`; its other fields fall back, and its sport is classified again from `disciplineRaw`. `PlanChange` also decodes field by field. `missed` is settled on reading: a session is missed when its `done` box holds the plan's own missed word (`mapping.missedValue`, compared after `normalise`). A book written by an older app therefore opens in a newer one (test `testABookFromAnOlderAppStillOpens`).

On disk: JSON, dates as milliseconds since 1970, keys sorted (`encoded()` / `decoded(_:)`).

### P.3 Logging into the book, and the both-ways check

`PlanBook.apply(_ queued: QueuedEntry, now:)` turns the very same queued entries as before into book changes:

1. An entry with an `extra` goes to `apply(extra:)` (below).
2. The session is found by `Sync.findWorkout(for:in:)` or by its key; none → `BookError.noSession`.
3. The entry's weekday names are cleared (the weekday is worked out from the date now); `completedAt` is set to `now` unless the entry is a move or already has one.
4. The cell edits come from **`Plan.buildEdits(session, entry, mapping)`** — the function that wrote the workbook. An empty list means `.dropped`.
5. Each edit is stored as the reader would have read the cell back (`readBack`): a number as its text and number, text trimmed (blank → no value), a date as its day key. A `date` edit moves the session to that day; a `weekday` edit is ignored (it is derived). Nothing about what "logged" means is decided twice.
6. `loggedInSheet` and `logged` come from `Plan.isLogged(results)`; `missed` from the done box; `pending` and `pendingMove` are cleared; the sessions are put in order and the stamp set.

`apply(extra:)`: an edit (`editing` set) changes only the fields named in the target (`ExtraField.*`), keeping the row, and a change of activity also changes the label; the target is found by `ref`, else by day, label and minutes. A new extra is appended on the next row (highest row + 1, at least 2); one already recorded (same `ref`, or same day, label and minutes) is not added twice, which makes a replay harmless. The activity id is found again from its label (`activityID(forLabel:)`, else `other`), as the sheet always did.

**`BookOracle`** (library, so it can run on the Mac against a copy of the real plan as well as in tests) writes one spread of entries twice: into a workbook with the old writer (`Sync.apply`) and into a book made from that same workbook, then reads both and compares session by session and box by box. The spread: a one-tap Done, a full form with awkward text (ö å ä, `<`, `&`, quotes, a decimal comma, a pace), a missed with a note, two moves, a how-hard answer, a second entry on the same session, corrections of two done sessions, a new extra, the same extra again (replay), a correction of it, and a correction of the last old extra. It reports "written / dropped / failed" for each entry on each side (they must agree) and every difference; the book is also saved and read again and compared with itself ("after saving: …"). No difference means logging in the app is what logging into Excel was.

**`book-check`** (`Core/Sources/BookCheck`): `book-check <workbook.xlsx> [today]`. Prints the side-by-side counts and the months, the weeks, the key sessions and the book size, every odd value, the proof verdict, the both-ways result ("differences: none" is wanted), then rehearses the road back: logs the spread into a book, changes one open session (five more minutes, zone Z1, a day later), adds one, removes one rest day, writes the spreadsheet copy and reads it back; and checks that an unchanged book copies to the very same bytes as the workbook. Exit 0 only if all hold. It writes nothing; run it on a copy.

### P.4 Taking the plan in (`PlanImport`)

`PlanImport.read(data, fileName:, today:)` reads the workbook with the app's own readers (`Plan.build`, `Extras.read`, `Zones.read`), then adds what the app never needed while Excel was the home: each single-row session's `source` cells, and the week headings. A week heading is a row whose date column holds a range such as "07 Sep – 13 Sep 2026" (`monday(of:)`: day, month, day, month, year; the year written is the last day's, so a week from December into January starts the year before). The week number comes from the "Week" column, else the running count; the phase and tag from the phase column split on " · ". A plan with no such rows simply has no weeks.

**The proof is taken on the book as it comes back off the disk**: the book is encoded and decoded before it is counted, so what is stored is what he will train from.

**Tally** (`PlanTally`), counted the same way on both sides — `before` from the sessions as `Plan.build` read them, `after` from the decoded book:

* `sessions` — every session; `rest` — sessions whose sport is rest; `training` — all the others.
* `done` — training sessions logged and not missed; `missed` — training sessions marked missed.
* `toCome` — training sessions on `today` or later that are not logged.
* `extras` — every extra; `extrasThatCount` — those that count as training.
* Sessions before today only: `plannedMinutes` — sum of each session's planned minutes (`Plan.plannedSeconds`, rounded to whole minutes per session); `recordedMinutes` — sum of `Load.minutes` for done sessions.
* `months` — for every month with a training session before today: sessions, done, missed, planned and recorded minutes.

The proof lines shown are: Sessions, Training, Rest days, Done, Missed, Still to come, Extra activities, Planned minutes so far, Recorded minutes so far. `PlanProof.matches` is true only when `differences` is empty **and** both tallies are equal. `differences` compares session by session and box by box (day, sport, sport as read, words, phase, blocks, planned, done, missed, and every result box by text and number) and the extras; it also reports a different count, order or a missing session, and stops after 200.

**Oddities** (`Oddity`: `kind`, `place`, `words`), taken in as written, never repaired:

* `order` — rows out of date order within a sheet (one line with a count; the app goes by the date, as it always has).
* `pace` — an average pace written as minutes:seconds with seconds of 60 or more.
* `effort` — a session's or an extra's how-hard value below 1 or above 10.
* `future` — a training session ticked as done on a day after today.
* `restDay` — a training session on a day (before today) that the plan also calls a rest day.

### P.5 The switch

**`Store.takePlanIn()`**: refused with a message if the queue is not empty ("N entries are still waiting to go to Dropbox. Send them first …"). Otherwise it downloads the workbook afresh (DEBUG: `AMSWS_FILE`; else Dropbox; else the cached copy), reads it with `PlanImport.read` and keeps the result in `incoming` with the downloaded bytes. **Nothing is saved.** `cancelTakingIn()` drops both.

**`Store.makeAppTheHome()`** runs only if `incoming` exists, its proof `matches`, the bytes exist and the queue is empty. It then: writes the workbook exactly as downloaded to `plan-original.xlsx`; writes the book to `plan.json` (both atomically; on failure it says "Nothing was changed" and stops); sets `plan.home` = `app` and `plan.switchedAt` = now; publishes the book; and makes the first spreadsheet copy at once (`force`).

Screens: Settings → Your plan → "Move the plan into this app" → Start opens the page "The plan moves in": the button "Take the plan in and count"; the table "EXCEL AND THE APP, SIDE BY SIDE" (Excel's figure and the app's figure for each proof line, a green tick when they are the same, the red word "differs" when not); "MONTH BY MONTH"; "LOOKED ODD IN THE FILE"; the verdict "Everything matches."; the main button "Make this app the plan's home". Words are given in the guide (What's new 2.0). Note the tick: see P.12.

### P.6 Files on disk and keys

| Item | Where | What |
|---|---|---|
| `plan.json` | Application Support | the book |
| `plan-original.xlsx` | Application Support | the workbook exactly as it stood at the switch: the template of every spreadsheet copy and the road back |
| `backups/plan-<yyyy-mm-dd>.json` | Application Support | a safety copy: the book as it was before the first save of that day. Kept only when it does not exist yet; the newest 30 days are kept |
| `plan-left-<yyyy-mm-dd>.json` | Application Support | the book put aside when going back to Excel |
| `Triathlon plan <yyyy-mm-dd>.xlsx` | Documents (Files → On My iPhone → Triathlon) | a spreadsheet copy; the newest eight are kept |
| `plan.home` | UserDefaults | `excel` or `app` |
| `plan.switchedAt` | UserDefaults | when the plan moved in; the three weeks of "Go back" run from here |
| `plan.lastSpreadsheet` | UserDefaults | when the last copy was made |

`save(book)`: encode; keep the day's safety copy (`keepSafetyCopy`: the file that stands on disk before this write); write `plan.json` atomically; publish; then `keepWeeklySpreadsheet`. A failed write sets `lastProblem` ("Could not save the plan on this phone: …") but the book is still shown. `safetyCopies` gives the count and newest day for Settings. Only the plan is in these files; photographs, the move log, the diary and the queue keep their own files (3.x).

### P.7 The spreadsheet copy (`PlanExport.workbook(_:template:)`)

Made from `plan-original.xlsx` by the writer that has always written his plan, so every sheet, heading, colour and formula of his stays. **Only cells that differ are written**:

* For every session that is in the original: the day (and the weekday name, learned from the sheet's own wording), sport, words, planned duration, planned distance, intensity, description, and every result box whose text differs; a box that is now empty is emptied.
* A session taken out of the plan: its row is emptied of what makes it a session (sport, words, description, planned duration, intensity); the row itself stays.
* A session made in the app (not in the original): appended on the first free row after the last used row (+ 2) of the first plan sheet, with its phase, day, weekday, and the boxes above.
* Extras: every row that is new or reads differently is written whole (day, weekday, activity, what, duration, distance, heart rate, effort, "Yes"/"No" for training, notes, ref), through `Extras.ensureSheet`; the Ref heading is added if needed.
* Multi-row sessions (`rows.count > 1`) are not written.
* If nothing differs, the bytes returned are the template itself: an unchanged plan copies to the very same file.

**Read-back check.** Before the bytes are returned they are opened again, the plan is read from them and held against the book: same number of sessions; for each session the day, sport, words, planned, missed and done and every result box; and the extras. A session made in the app is found in the copy by day, sport and words. Any difference throws `PlanExport.Problem.doesNotMatch` ("… It was not saved.") and no file is given out. Photographs and the Training calendar are not part of a spreadsheet.

`Store.spreadsheetCopy()` writes `Triathlon plan <day>.xlsx` into Documents, sets `plan.lastSpreadsheet` and returns the URL (Settings: "Save a copy now" then shares it). `keepWeeklySpreadsheet` runs after every save and after the switch: when no copy has been made for 7 days (or on the switch) it makes one and deletes all but the newest eight. So "by itself every week" means: the first save after a week has passed.

### P.8 Going back to Excel

`Store.goBackToExcel()` is available for 21 days after `plan.switchedAt` (`canGoBackUntil`) while Dropbox is connected and a path is set (`canGoBack`). It downloads the file now in Dropbox and **refuses if its bytes are not identical to `plan-original.xlsx`** ("The Excel file in Dropbox was changed after the plan moved into the app … nothing was done."). Otherwise it makes the spreadsheet copy from the book and original, uploads it against the revision it just read, moves `plan.json` aside as `plan-left-<day>.json`, sets `plan.home` = `excel`, forgets the book and parses the uploaded workbook as before. On any error the plan stays in the app and nothing is changed. The button is red. Since 2.5 it is offered (`canGoBack`) only when `!planIsShared` and iCloud has been checked (`cloud.root != nil` and `cloud.lastMet != nil`); until then `goBackWaits` shows the grey line "Going back to Excel is offered once iCloud has checked whether your iPad or Mac uses this plan too." (`plan-go-back-waits`). The book version is noted when the write-back starts; if a meeting changed the plan while the workbook was being fetched, nothing is written and `homeProblem` reads "The plan changed while it was being written back. Nothing was switched; try again."

### P.9 Changing the plan

Only when `canChangePlan` (`home == .app` and a book). The Store methods `changeSession`, `addSession`, `removeSession`, `undoChange` each call the matching `PlanBook` method and then `save`.

* **`SessionDraft`**: `dayKey`, `sport` (a discipline id: swim, bike, run, strength, mobility, brick, race, rest, other), `title`, `minutes` (always minutes; stored in the plan's own duration unit by `durationToCell`), `intensity`, `purpose`, `isKey`. The page "Change session" shows them as Day, Sport, Words, Length in minutes, Zone or effort, Purpose, Key session.
* **`change(key, to:)`**: the title cannot be emptied (the old one stays); a draft equal to the current one returns nil and records nothing; a bad day throws `badDay`. The session is shaped (sport, words, planned length, zone, description, the star), and a plain one-block session gets one block of words (the purpose, else the title); a plan with warm-up and cool-down columns keeps its own blocks. A moved day also calls `rememberMove` in the Store so Progress "moved rather than lost" counts it. The key is **not** changed, so photographs, the Training calendar and the move history stay with it.
* **`add(draft)`**: counter + 1; key `App!<counter><6 random lowercase letters or digits>`; row `100000 + counter` (above any real row, so it sorts after the workbook's sessions of that day); sheet `App`; phase from the week of that day, else the nearest session's.
* **`remove(key)`**: the session leaves `sessions`, is put in `removed` with the time, and its record is kept in the change (with `undo`).
* **`undo(changeID)`**: an added session goes (and is marked removed); an edited or removed one returns to the plan's side as it was; what was logged since (results, done, missed) stays. A change can be undone once (`undone`).
* **`PlanChange`**: `id`, `at`, `kind` (edit, add, remove), `key`, `title`, `before`, `after` (only what differs, in words, such as "60 min → 40 min"; joined by " · "), `why`, `undo` (the session as it was; nil for an add), `undone`. Settings → "Changes to the plan" lists them newest first with an "Undo" button; an undone one reads "Undone" in grey.

### P.10 Weeks and phases in the book

`week(on:)` finds the heading for the Monday of a day; `phase(on:)` gives that week's phase, else the nearest earlier session's phase, else the first session's.

### P.11 Tests, switches and counts

* **Model tests** (`PlanBookTests`, six, seconds, on the fixture workbook): `testTakingThePlanInChangesNothing`; `testLoggingIntoTheBookIsWhatLoggingIntoExcelWas` (the oracle); `testASessionCanBeChangedAndTheChangeTakenBack`; `testASessionCanBeAddedLoggedAndRemoved`; `testABookFromAnOlderAppStillOpens`; `testAWeekHeadingGivesItsMonday`.
* **Screen tests** (UI tests 20 and 21, controls found by identifier): `PlanHomeUITests` (the page "The plan moves in": counting, the proof, the switch) and `PlanChangeUITests` (changing a session, making and taking one out, taking a change back).
* **DEBUG switches** (compiled only in DEBUG; see 14.6): `AMSWS_HOME=app` (with `AMSWS_FILE`: the same file, taken in, the app as the plan's home, no Dropbox needed); `AMSWS_MOVEIN` (opens the page "The plan moves in"); `AMSWS_EDIT` (opens "Change session" for a session); `AMSWS_CHANGES` (opens "Changes to the plan").
* `AMSWS_RESET` also clears `plan.home` and `plan.switchedAt` (`Store.swift`).

### P.12 What 2.0 deliberately does not do

* No iPad or Mac app, no sync of the book between devices (the `stamps` and `removed` fields are there for it, unused). The plan lives on this iPhone, and in the iPhone's backup.
* The app does not follow the Excel file after the switch; there is no merge from Excel into the app. The only way back is "Go back to Excel" (three weeks) or a spreadsheet copy.
* No page for entering a new zone test; the zones are those the workbook held at the switch.
* No change of a session's several-row blocks (a session whose workbook lines span more than one row cannot be written into a spreadsheet copy) and no editing of weeks or phases.
* Nothing is "mended" on the way in: odd values are shown, not changed.
* No suggestions, no advice, no health claim; the app changes the plan only when told.
* Not in 2.0, said honestly in What's new as "Coming next": iPad and Mac, the morning check with Garmin numbers, suggestions by the rule book, Claude built in, links to Workout Companion and Magic Morning.

**Signs added.** Green word "same" in the side-by-side table = the two figures agree (see P.15); red "differs"; red buttons "Go back to Excel" and "Take out of the plan" take something away; "Undone" in grey; "Lives in this app". **Judgement for the owner:** the green tick otherwise means "done and nothing else" (11.5, N.6); in the side-by-side table it means "the same". This breaks the rule that a mark means one thing in the whole app. The guide says so openly, but a word ("Same") or an equals sign would be cleaner.


### P.13 A copy outside the phone (added during 2.0)

While Dropbox is connected and a plan path is known, `Store.copyToDropboxSoon()` runs after every save of the book: fifteen seconds after the last change, `copyToDropboxNow()` writes `PlanExport.workbook(book, template: plan-original.xlsx)` to `<folder of the old workbook>/Triathlon plan from the app.xlsx` through `Dropbox.uploadCopy` (mode `overwrite`, no revision: the file is written by the app and never read). A failure leaves the copy owed and it is tried again when the app next comes to the front (`refresh()` in app mode). `UserDefaults` key `plan.lastDropboxCopy`; Settings row id `plan-dropbox-copy`. The original workbook is never touched by this. Skipped in DEBUG runs that use `AMSWS_FILE`.

### P.14 Tabs change at once

`BottomBar` sets the tab without `withAnimation`. With the 0.2 s slide, the paged `TabView` could stop half-way between two pages when a tab was tapped after a session had been added from the Sessions tab (caught by `PlanChangeUITests`). Swiping between pages is unchanged. `SessionEditView.save()` also resigns the keyboard before closing.

### P.15 Words, not the tick, in the side-by-side table

The move-in page marks agreeing figures with the green word "same" and differing ones with the red word "differs". The done tick is not used there: it means done and nothing else.


### P.16 Hardening after the expert review (25 Nov 2026, before 2.0 was released)

A data-safety review and 35 adversarial tests (`PlanBookEdgeTests`) changed the following before release:

- **Nothing looks saved that is not.** `Store.save` returns whether the book reached the disk; the screen is updated and the waiting list cleared only then. A failed save leaves every entry waiting and says so. An entry already written is remembered by its id in `PlanBook.applied` (newest 300) and is not written twice if the app was stopped between saving the book and clearing the list. Entries still waiting at launch are written in then.
- **No number that is not a number.** `PlanBook.readBack`, the extras and a draft's length accept finite values only (a typed "Infinity" or "1e999" is dropped); the encoder turns any that still got in into text instead of refusing every later save.
- **Reading is strict about damage, tolerant about age.** A field that is absent takes its default; a field that is present and unreadable throws. `Store.init` then puts back the newest safety copy that opens (the unreadable file is kept as `plan-unreadable-<time>.json`) and says which day it is from; with no safety copy the app shows the problem and does not fall back to the Excel file. A book with `format` above this app's is never saved over (`BookError.newerApp`).
- **The switch re-reads the Excel file at the tap** (`makeAppTheHome` → `finishSwitch`): if it changed since it was counted, it is counted again and shown again. A `plan.json` already there is moved aside (`plan-before-<time>.json`), never overwritten. With Dropbox set but not reachable, an older copy on the phone is not taken in.
- **Going back** blocks logging and changes while it runs, checks the book did not change meanwhile, and recognises a write-back that an earlier, interrupted try already made.
- **Undo.** Only the newest change to a session can be undone (`PlanBook.canUndo`; the list says "Changed again since" on older ones). Undoing an "add" of a session that has been logged takes it out as a removal, which keeps what was logged and can itself be undone. A session moved after a change stays on its day when that change is undone (`PlanChange.afterDay`). A removal is never pruned from the list of changes.
- **An entry means the session it names.** `PlanBook.apply` looks a session up by its key; the looser search by day and wording is used only for an entry that has no key. An entry for a session taken out of the plan is refused, not written into a similar one.
- **Small:** day keys are stored normalised; an impossible date in a week heading gives no week; a corrected "what it was" of an extra is trimmed; the months of the count include anything already logged, so they add up to Done and Missed; the spreadsheet copy carries the key-session star and the week number of sessions made in the app.

Tests: 130 data tests (`swift test --package-path Core`), of which 7 in `PlanBookTests` and 35 in `PlanBookEdgeTests`; two screen tests for 2.0.


## New in 2.1 (75) — tests, safety copies, Thursday rides, lines on a session's page

Four additions. The first three work only once the plan lives in the app (`canChangePlan`, see P.9). The session lines (S.4) show always. Files: `App/Sources/ZonesView.swift` (test list and test page), the safety-copy page, the Thursday-rides page, `SessionView.swift`; Store groundwork in `Store.swift` ("tests and zones", "putting a safety copy back", "changing the plan itself"). The words of the screens are in What's new 2.1.

### S.1 Enter a test result

**Where.** Settings → "Your zones" (identifier `tests-list`): the zone sheet, and under it every test the plan holds, newest first, one row each (`test-row`). The main button (full colour, never grey) "Enter a test result" (`test-enter`) comes first; under it the tests that have numbers, newest first; then one card "Still to come" (`test-row-waiting`) with the plan's tests that have no numbers yet. Before the plan lives in the app a test is entered in Excel as before.

**The page** "Enter a test result" has these boxes, each its own row; an empty box means "not tested this time" and at least one number is needed; with Cancel (`test-cancel`; Escape on a Mac keyboard) and Save (`test-save`):

| Box | Identifier | Format | Limits |
|---|---|---|---|
| Threshold pulse | `test-lthr` | beats a minute | 80 to 220 |
| Bike power (FTP) | `test-ftp` | watts | 50 to 500 |
| Swim pace per 100 m | `test-swim` | minutes and seconds, like 1:50 | 1:00 to 4:00 (stored as seconds a 100 m) |
| Weight | `test-weight` | kilograms | 35 to 150 |
| First day | `test-first` | a day | not after the last day |
| Last day | `test-last` | a day | not before the first day |
| Notes | `test-notes` | free text | none |

* "Same as the last test" (`test-same`) fills the four numbers with those of the newest test and leaves the days and the notes alone.
* A grey line (`test-becomes`) says which test the entry becomes: it fills the next test the plan has waiting for numbers (for example "Saves as Test 3"); if none is waiting it becomes a new test.
* **Save never greys out.** A tap on Save with something missing or out of its limits writes nothing and shows one red line (`test-problem`), above Save, saying what is missing or wrong. A good Save calls `Store.recordTest`: the test is added to the book and saved, the page closes, the list shows it first.
* The zones follow the newest numbers. The app stores and shows what is entered; it never says whether a result is good or bad. Sessions already logged are not changed.

### S.2 Safety copies

**Where.** Settings → "Safety copies" is one row; it opens the page `plan-safety`, title `safety-title`. A copy is made at the start of each day the plan changes (not every day) and kept for 30 days. One row per day that has a copy (`safety-row`), newest first; each row gives the day and what the copy holds, like "310 sessions · 64 done · 4 changes so far" (`Store.safetyCopySummary`; invented numbers). With no copy the page shows one grey line (`safety-none`): "No safety copies yet. The first one is made the next time the plan changes." The page can only be reached once the plan lives in the app.

**Putting one back.** Each row has the red outlined button "Put this copy back" (`safety-put-back`). It asks first (`safety-confirm`) with Cancel and a red confirming button. On confirming, `Store.restoreSafetyCopy(day)` copies the plan as it is now aside (`plan-before-restore-<time>.json`), writes the chosen copy over `plan.json`, empties the waiting list, refreshes the screen and owes the copy in Dropbox. The plan goes back to how it was at the start of that day; everything logged or changed from that day on is taken out. A green line (`safety-done`) says "The plan is back as it was at the start of Mon 23 Nov." A copy that will not open, or a failed write, shows a red line (`safety-problem`) and changes nothing. Refused while Going back to Excel runs. Everything logged or changed from that day on is not in the copy. (From 2.2, on a plan shared with another device, what was logged since stays; and the list also holds the copies kept around iCloud: see W.3.6.)

### S.3 Thursday rides

**Where.** Settings → "Thursday rides" (`plan-rides`, title `rides-title`). Source of the rule: a private coach note (option 1); the page itself carries no personal numbers.

**The rule.** An easy ride (sport Bike, not a key session) each Thursday from the next Monday to the race (no fixed start date), by the phase of that week:

| Week | Ride |
|---|---|
| Base 2 | 45 min |
| Base 3 | growing from 50 to 60 min |
| Build | 60 min |
| Peak | 45 min |
| Easy week, test week, the taper | 30 min easy spin |
| Race-practice week, race week | none |

**The page.** Every ride, one row each (`rides-row`); every week with its planned time before → after in hours and minutes (`rides-week-row`); the main button "Add 29 rides" (`rides-add`; the number is the real count); Cancel (`rides-cancel`). Nothing is added until the button is tapped. The tap adds all rides in one save through `Store.addSessions(_:why:)` (all or none), each as a change in Changes to the plan, so each ride can be undone there (P.9: the newest change to a session) or changed, moved and taken out like any session. Cancel before, "Done" after; afterwards a green line (`rides-done`) says "29 rides added. Undo them under Changes to the plan." A Thursday that already has its ride is skipped; when all are there the page says "These rides are already in your plan." (`rides-already`, `rides-none` when there is nothing to list). If adding fails, a red line (`rides-problem`) says so and nothing is changed.

### S.4 On a session's page (`SessionView.swift`)

Shown whether the plan is in Excel or in the app, on the kinds of session below.

* **Eating and drinking** (`session-fuel`): a session over 90 minutes that is still to do carries one grey line: "Over 90 minutes: eat and drink as you go — about 30–60 g of carbohydrate an hour."
* **Protein** (`session-protein`): a strength session, to do or done, carries one grey line: "After strength: a meal or snack with 20–30 g of protein within an hour or two."
* Both are general sport habits, not medical advice; text only, no button, no count.
* **Garmin Connect card** (`garmin-card`, "Build it like this in Garmin Connect"): a run or ride made of repeats, like 3 × 8 min at Z3, carries the card while it is still to do. Swims, strength, finished sessions and texts the app cannot read into steps have none. Folded it is one line with a small green button "Show the steps" ("Hide the steps" when open). The steps: open Garmin Connect, More → Training & Planning → Workouts → Create a Workout, the sport, a warm-up, a repeat with its effort and recovery, a cool-down, name and save. "Copy the steps" (`garmin-copy`) copies them as text. Saved there, the workout stays in the Workouts list: copy it for next week and send it to your watch. The app itself sends nothing to the watch.

### S.5 Switches, identifiers, signs

* **DEBUG switches** (see 14.6): `AMSWS_TEST=1` opens the test list in Your zones; `AMSWS_TEST=new` opens the page "Enter a test result"; `AMSWS_SAFETY=1` opens "Safety copies"; `AMSWS_RIDES=1` opens "Thursday rides"; `AMSWS_GARMIN=1` opens a session with the Garmin card.
* **Identifiers:** `tests-list, test-row, test-enter, test-lthr, test-ftp, test-swim, test-weight, test-notes, test-same, test-save, test-cancel, test-problem, test-becomes, test-row-waiting, test-first, test-last · plan-safety, safety-title, safety-row, safety-put-back, safety-confirm, safety-done, safety-problem, safety-none · plan-rides, rides-title, rides-row, rides-week-row, rides-add, rides-cancel, rides-done, rides-already, rides-none, rides-problem · session-fuel, session-protein, garmin-card, garmin-copy`.
* **Signs.** The red button "Put this copy back" joins the red buttons that take something away. A red line above Save on the test page, or at the top of Safety copies or Thursday rides: what is missing or what failed. A grey line above Save: which test the entry becomes. A green line after putting a copy back or adding rides: done. A grey line on a session: a general habit, text only. "before → after": a week's time now and with the rides. "Show the steps / Hide the steps" opens and closes the Garmin steps on the session's own page. No new mark or colour; "Signs in this app" lists these in words.
* **Words.** What's new has "2.1 (75) Enter a test, safety copies, Thursday rides". How this works changed in Where the plan lives, Changing the plan, On a session's page (new), How your plan is kept safe, Your zones, What this app does not do and Signs in this app.

### S.6 What 2.1 deliberately does not do

* It puts nothing on the watch; the Garmin card is a set of steps to copy.
* It judges no test and advises on none; zones are the sheet's formulas, never worked out by the app.
* No second Thursday option (a run off the bike, a Monday ride) and no strength change.
* The three new pages offer nothing while the plan lives in Excel.
* No iPad or Mac app, as in P.12.

## New in 2.2 (76) — iPad and Mac, the same plan everywhere, Garmin in the morning

Three additions, and one rule that holds them together: **nothing leaves the user's own devices except through his own iCloud (the plan, his answers, the iPhone's Health numbers) and, when he has saved a key, a read-only request from the device to Garmin.** Nothing goes to the watch. Nothing the app shows here is advice, and the Garmin numbers never reach the plan. Files: `WideRoot.swift`, `PlanPage.swift`, `WeekBoard.swift`, `MonthGrid.swift`, `YearView.swift`, `SeasonView.swift`, `PlanNumbers.swift`, `Core/.../PlanOverview.swift` (iPad and Mac); `PlanCloud.swift`, `ICloudPage.swift`, `SafetyCopiesView.swift`, `WaitingForPlanView.swift`, `SyncStatus.swift`, `Device.swift`, `Store.swift`, `Core/.../BookMerge.swift`, `CloudFiles.swift`, `DiaryDoc.swift`, `HealthShare.swift` (iCloud); `GarminSettingsView.swift`, `MorningNumbersView.swift`, `GarminClient.swift`, `GarminKey.swift`, `GarminReader.swift`, `Core/.../GarminMorning.swift` (Garmin). The words of the screens are in What's new 2.2 and How this works. All numbers and times in examples are invented.

### W.1 Which device is which (`Device.swift`)

One build serves the iPhone, the iPad and the Mac. The Mac runs the iPad app ("Designed for iPad", installed from TestFlight; `ProcessInfo.isiOSAppOnMac`). `Device.kind` is `iPhone`, `iPad` or `Mac` (DEBUG: `AMSWS_DEVICE`). `TARGETED_DEVICE_FAMILY` is `1,2`. `Device.word` is the word the screens use. `Device.rank` orders marks that carry no time: Mac 1, iPad 2, iPhone 3. `Device.id` is this installation's own name, made once and kept in UserDefaults (`sync.deviceID`).

Per device:

| Belongs to | What |
|---|---|
| The iPhone only | Dropbox and the copy in Dropbox, the Training calendar, "Go back to Excel" |
| The iPhone and the iPad | Apple Health: Settings → Apple Health (`SettingsView.swift`) hides Connect only on the Mac, which shows "From your iPhone" instead; an iPad shows Connect like the iPhone, and also the numbers the iPhone shared |
| Each device itself | Photographs (not in iCloud), the safety copies, the spreadsheet copies in that device's Files, the copy from before iCloud, the Garmin key and the last Garmin reading, waiting log (iPhone on Excel only) |
| Shared through iCloud | The plan (sessions, logs, extras, tests, zones, changes), his morning and how-hard answers, the iPhone's Health numbers (read only on the others), the list of devices |

An iPad or a Mac with no plan of its own has no Excel, no Dropbox and nothing to choose. Settings → Your plan then shows the row "Not on this iPad yet" (`plan-from-icloud`): "Your plan arrives from iCloud by itself. Today says what it is waiting for." (iPad or Mac in place of iPad). Once the plan is there the row says "Lives in this app and in iCloud" (iPhone: "Lives in this app"), with the counts. Settings → Calendar on an iPad or Mac shows "Kept by your iPhone" (`calendar-on-iphone`): "The Training calendar is written by your iPhone and appears in Calendar on this iPad through iCloud." On a Mac, Settings → Apple Health shows "From your iPhone" (`health-from-iphone`): "Apple Health lives on your iPhone; its numbers arrive from there — from iPhone, as of 07:12." Dropbox, "Waiting to sync" and "Copy in Dropbox" are not shown off the iPhone. "Move the plan into this app" is on the iPhone only.

### W.2 The wide look (iPad and Mac)

**When.** `horizontalSizeClass == .regular` and the device is not an iPhone (an iPhone on its side keeps the phone look). `AMSWorkoutSyncApp` then shows `WideRoot` instead of the three-tab bar. Pages inside are held to a reading width of 680 points where they are text (`readableWidth`; Today and Sessions 760).

**The side list** (216 points wide, left): the heading "Triathlon" and **six** rows in order (since 2.6; written as five before), each word in its part's colour (Today green, Plan blue = the plan's blue, Sessions blue, Body raspberry, Progress purple, Settings grey), identifiers `side-today`, `side-plan`, `side-sessions`, `side-body`, `side-progress`, `side-settings`. There is no separate Week page and no separate Season page: both are on Plan. The row open has a pale box and the selected trait. The app opens on Today. Tapping the open row comes back to that row's first screen (as the phone's bar does); Progress has none. Keyboard (Mac): Command + 1 to 6. At the foot, the sync line (`sync-status`): a dot and its words, see W.4. Pull to refresh works on Today and Plan.

**Plan** (`PlanPage.swift`; `SideRow.plan`). One scrolling page, top to bottom:

1. **The season** (`season-view`), always, across the whole width (see below).
2. **The heading row**: the switch **Week · Month · Year** (`plan-switch`, buttons `plan-switch-week|month|year`; the chosen word white on the plan's blue, the others blue on nothing, in a blue capsule outline); the title of what is shown (`plan-title`); its time; and the small green outlined step buttons, which change nothing in the plan: Week has "Previous week" (`week-prev`), "This week" (`week-this`), "Next week" (`week-next`); Month has "Previous month", "This month", "Next month" (`month-prev|this|next`); Year has none. The title is "Week 12 · Build · Easy week" (the week's number, its phase's short name, then "Test week", "Easy week" or the week's tag; with no week number in the plan, the first and last day), or "November 2026", or "Season 2026–27" (the years of the first and last day of the plan; "Season 2026" within one year). The time is "<planned> planned", or "<planned> planned · <done> done" once something is done, over the days shown. When the row does not fit on one line, the switch and the buttons take a line of their own and the title is never cut.
3. **The hint** `plan-hint` "Drag a session to another day" (footnote, grey) above the Month view when the plan can be changed (`canChangePlan`); on Week the board shows the same words itself (`week-hint`, with "swipe sideways for the other days" after a dot when fewer than seven columns fit, unless the week stands in two rows, see 2.5). Year has none.
4. **The view** (Week, Month or Year) and, with it, **his numbers** (`plan-numbers`, `PlanNumbers.swift`): in a column 290 points wide on the right of the view when the page (the window less the side list, less 32 points of margin) is at least **1,150 points** wide; under the view, in two columns, when it is narrower. The numbers follow what the view shows: this week ("This week", or "Week of 23 Nov"), the month ("November 2026") or the season ("The season").

**State.** The view (`AMSWS_PLAN` in DEBUG: `week`, `month` or `year`), the Monday of the week shown and the month shown are kept by `WideRoot` while the app runs, so leaving Plan and coming back finds them as they were. The app starts on this week and this month. Week · Month · Year share the choice: a tap on a season bar sets the week and switches to Week; "+2 more" in a month cell does the same for that day's week; a tap on a month block in Year sets the month and switches to Month.

**Week** (`WeekBoard.swift`, board `week-board`, title `week-title` where the board draws its own head). One column per day, Monday to Sunday (`week-day-<day key>`), as many as fit but at most seven, each at least **118 points** wide with 6 points between, sharing the width exactly; with fewer than seven, the board scrolls sideways in steps of a whole column, starts where today can be seen, and the hint adds "swipe sideways for the other days" (since 2.5 not when four to six columns fit: then two rows, see "New in 2.5").

* A day column: the heading "Mon 23" (today's heavier and green), the day's training sessions (a rest row is not shown on a day with a session moved onto it; a rest day shows its rest row), under a hairline the day's extras, and "+ Add" (`week-add-<day key>`, in the plan's blue) at the foot, only when the plan can be changed. Today's column is tinted differently.
* A session card (`week-card-<key>`): its sport's colour as a 4-point edge (hatched once marked missed), its name (up to four lines, cut at a dash, bracket or slash by `BoardCard.boardTitle`), its length ("45 min", "1h 05m"), the green tick in a circle when done (label "Done"), and the red word "Missed" with a red frame when missed. Tapping opens the session page.
* An extra (`week-extra-<id>`): dotted outline and light ground in its own colour, its words, its length, the paler tick extras carry everywhere; tapping opens the extra's page.
* **Drag.** Only a session **still to do** that is not a rest day can be lifted (`draggable`); a done, a missed or a rest session cannot. Dropping on another day's column (`dropDestination`; the column gets a 2-point blue outline while targeted) calls `Store.moveSession(key, to:)` through `MovedLine.move`: the same change the Change page makes with only the day new, an entry in Changes to the plan. Dropping on its own day, or a drop that is refused, changes nothing. There are no arrow buttons anywhere.
* **After a move** (`MovedLine`, on Week and on Month). A line (`week-moved`) says "<title> moved to Fri 27 Nov" for eight seconds, with the button "Undo" (`week-undo`, in the plan's blue, shown while that change can still be undone), which undoes exactly that change.
* **+ Add** opens "New session" (`SessionEditView`, no key) with that day and the sport run chosen.
* With no plan loaded the page shows the empty-workbook page.

**Month** (`MonthGrid.swift`, `month-grid`). The month as a calendar with a row for each week that touches it. At the left of a row (74 points): "Week 12" (or the Monday's date when the plan has no such week), "Easy week" or "Test week" where so, the planned time, and "<time> done" once something is done, one line each. Then seven cells, Monday to Sunday (`month-day-<day key>`), minimum 62 points tall, all of a row as tall as its fullest. A cell: the day's number ("23", today's "23 · Today" bold and green); days of the neighbouring months at 45 % strength. One chip per session (`month-chip-<key>`): the sport's colour as a 3-point edge (hatched when missed), a short name (`MonthChip.chipTitle`: the board's title cut at a comma or a plus when that leaves six letters or more; in a cell narrower than about 100 points the sport's own word, "Run"), the length, the green tick or the red word "Missed" with a red frame (in a narrow cell a missed chip leaves out its length). Extras (`month-extra-<id>`) are dotted chips with the paler tick. **At most three chips a cell** (`MonthGrid.mostChips`): with more, two chips and a green line "+N more" (`month-more-<day key>`), which opens that day's week. Drag works as on Week (chips of sessions still to do are lifted; the cell gets a blue outline while targeted); the same `MovedLine` stands under the grid. A tap on a chip opens the session.

**Progress on a wide window** (`ProgressView.swift`). From 860 points of page width the cards under the road card stand in two columns (`progress-two-columns`): left Is it working?, Fitness and freshness, Load; right Twelve weeks, Where the hours went, the "too early" note, So far, Consistency, Which sport runs behind, Missed or moved. Reading width 1,280 instead of 820. Card sentences wrap; none is cut. Below 860 points: one column, as on the iPhone.

**Year** (`YearView.swift`, `year-view`). One block for every month from the plan's first to its last (`year-month-<yyyy-mm>`; adaptive grid, 150–250 points a block, so an 11-inch iPad on its side shows six months a row and the whole plan year in two rows). A block: the month's name (bold, green for the month today is in), "<planned> · <done> done" (or only the planned time), and a calendar of squares, seven across, one for each day of the month's weeks (days of other months empty). A square (`PlanOverview.main` picks the day's main session, the longest planned one that is not rest): in the main session's sport colour, **solid** when recorded (`StateFill` done), **pale** while to do, **hatched** when missed; an **empty outline** on a rest day or a day without a session; the race's colour on race day; a **green outline** (the green of today everywhere else) round today. A tap on a block opens that month in Month. Under the blocks the key (`year-key`) with the same squares and the words "Recorded", "Still to do", "Missed", "Rest day", "Race day" (only when the plan has a race), "Today", and "Colour = the day's main sport · Tap a month to open it". Under the key, **Phases** (`SeasonPhases`): a heading "Phases", then one row for each named phase (`season-phase-<index>`): its colour chip, name (bold for the phase today is in), first and last day, "<n> week(s)", the planned time. Each figure sits right beside its name.

**The season** (`SeasonView.swift`, `season-view`; always above the heading row).

* **Weeks.** From the book's weeks; a plan read from Excel has none, so they are made from its sessions. Weeks after the race's Monday are left out. Planned time per week is summed from the sessions as they stand now (moves included). Phases are runs of weeks with the same phase name.
* **Bars** (`season-week-<n>`, height 104 points): height = planned time against the tallest week (at least 4 points); colour = `Theme.phase(index, of: phases)`, cool early, warm near the race, as on Progress; every bar has the phase's **full colour** (since 2.4.1 (79) no bar is pale; before, an easy week was drawn at 38 % strength); a **test week** shows "T" and an **easy week** "E" above its bar, the whole words "Test" and "Easy" where the bar is at least 26 points wide (rule in "New in 2.4.1 (79)"). **The outline** (2 points, text colour, 3 points outside the bars) stands round the bars of what the page shows: the week on Week, all the weeks of the month on Month (one outline round the run), none on Year. A tap on a bar sets that week and switches to Week. A thin green line (`season-today`, 1.5 points, label "Today") stands inside the week that holds today at the day's place, with the word "Today" at its top. Phase names (short: the part before a dash or colon) stand centred under their weeks in their colour, pushed apart only as far as they must be.
* **The race** (`season-race`): at the right above the bars, the race flag, the race's name (or "Race") and its date with the year, in the season colour (amber-brown). Only when the plan has a race.
* **The key** (`season-key`), under the bars: with letters: "E = easy week · T = test week · Tap a bar to see its week" (only the letters that occur in the plan are named); with the whole words: "Tap a bar to see its week". (Before 2.4.1 (79): "Pale = easy week · Tap a bar to see its week".)

**His numbers** (`PlanNumbers.swift`). Four cards on the surface colour, each with a purple bold title (the Progress colour); no judgement words:

| Card | Id | Holds |
|---|---|---|
| "By sport" + the scope | `plan-by-sport` | one line for each sport that has something planned in the days shown: its name, "<done> of <planned>" (or only the planned time while nothing is done), and a 6-point bar: pale for planned, solid for done, in the sport's colour, all against the sport with the most. With nothing planned: "Nothing planned". |
| "Load · last 12 weeks, up to today" (title "Load", note "last 12 weeks, up to today", since 2.5) | `plan-load` | twelve small purple bars (`Load.weeks` of the last twelve weeks, the same load as on Progress; this week at full strength, the others 55 %), and under them "This week so far 1,671 · usual week 1,540" (invented numbers; "usual week" only when there is one; numbers written as on Progress, thousands comma, real minus sign) and the line "Load = minutes × how hard (1–10)". Always the twelve weeks up to today, whatever week or month is shown. |
| "Plan followed" + the scope | `plan-followed` | "<done> of <due> sessions due so far" (since 2.5; before: "<done> of <due> sessions"; and, when `PlanOverview.doneAhead` is above 0, a grey caption "<n> more done ahead of its day") and "<percent> %": of the sessions in the days shown that were due by today (every one before today, and today's once recorded; `PlanOverview.followed`), how many are recorded and not missed. With none due: "Nothing due yet". |
| "To the race" | `plan-race` | "<n> week(s)" (whole weeks from today to race day, a part week counted as one) and the race day with the year. Only when the plan has a race that is not past. |

**Escape.** On the Mac every page with Cancel has Escape as Cancel (the keyboard shortcut `cancelAction`), including Settings → Garmin and the plate's "Done".

### W.3 iCloud — the files, the meeting, the merge

**Where.** The app's own container `iCloud.com.schabbauer.AMSWorkoutSync` (entitlement `CloudDocuments`; hidden from Files on purpose), folder `Sync/`:

| File | Written by | Holds | Rule |
|---|---|---|---|
| `plan.json` | every device that has the plan in the app | the whole plan book | joined at every meeting (W.3.3) |
| `diary.json` | every device | his morning answers (key `feel:<day key>`) and how-hard answers (key `answer:<Health workout id>`) | the answer with the later mark wins per day or workout; the same mark with two answers, the larger; nothing is ever taken out |
| `health-from-iphone.json` | the iPhone only | the last 14 days of morning numbers and Health workouts, the workouts the Load card draws, and `writtenAt` | never joined: the newest `writtenAt` wins; read forgivingly (a field a newer app added is passed over, one workout that cannot be read loses only itself) |
| `devices/<device id>.json` | that device only | kind, app version and build, `lastMet`, `joinedAt`, `home` (`app`, `excel` or `none`) | rewritten when something in it changed, otherwise at most every ten minutes |
| `plan-original.xlsx` | the first device that has it | the frozen workbook the plan was taken from | written once, never over; a different workbook goes beside it as `plan-original-<ms>.xlsx`; a device without it takes the one whose hash the plan's `origin.originalHash` names (so "Save a copy now" works everywhere) |
| `plan-left-<unix time>.json` | the only device, when the plan goes back to Excel | the plan put aside | kept; nothing adopts it later |

**W.3.1 When a device meets iCloud.** At launch and whenever the app comes to the front (`start()`); 1.5 seconds after a change here (several quick changes go up together); half a second after iCloud's own notice that something in the folder is new (files not yet here are asked for); every 30 seconds while the app is active (a quiet look in case a notice was missed); "Sync now" on the iCloud page. A meeting that is already running asks for one more afterwards (0.3 s). **The first meeting waits for iCloud's list of the folder** (`gathered`, up to 20 seconds): before the list comes, a plan that is there can look absent, and a device with an old plan of its own would put it beside the real one. If no list has come after 20 seconds the status stays "On its way", `planState` is "looking" and nothing is written. A device with iCloud off, signed out or a simulator build stays as before 2.1 (status "iCloud is off"). Screen tests and pictures that pass `AMSWS_FILE`, `AMSWS_RESET` or run under XCTest do not meet iCloud, unless `AMSWS_FAKE_CLOUD` hands them a folder.

**W.3.2 What a meeting does, in order.** (1) Reads the devices folder. (2) The plan, by the device's role: *busy* (moving in, going back, or a plan that would not open) — iCloud waits; *Excel* (an iPhone whose plan still lives in Excel) — nothing is shared, and the move-in page offers iCloud's plan; *empty* (an iPad or Mac with no plan) — takes the plan in iCloud without asking, there being nothing here to lose; *member* — joins (below). A member whose file is absent while another device's file says its plan lives in the app does not write the plan up: it waits (the page says "Your plan from your iPhone has not reached this iPad yet. Nothing is sent from here until it has.", `waitingWhy`; `PlanMeeting.shouldWriteUp`). (3) The diary. (4) Health: the iPhone writes (asked of Health at most every twenty minutes, since the numbers change once a morning), the others read. (5) This device's own file. Then the dot: green if everything settled, amber if something is still on its way, red with words if there is a problem.

**W.3.3 The rules of the join (`BookMerge`).** In plain words:

* A session has two sides, each with its own mark: the plan side (day, sport, words, length) and the log side (what he recorded). Each side comes from the copy that changed it last, so a change of plan on one device and a log on another both stay.
* Only a "removed" mark takes anything out. A removal as late as the last thing done to the session takes it out, with two exceptions that bring it back: a log made after the removal, and a log the removing device never saw (the removal's own undo line holds another log, or none, so taking it out would lose what was logged: `neverSeen`). Changes to the plan then has a line, already marked undone, with the words "Came back: logged after it was taken out" or "Came back: logged on another device before it was taken out".
* Extras are joined by id the same way.
* A copy that is missing, empty or not yet downloaded is "nothing there yet", never "everything was removed". A file that is there but still on its way is "waiting"; one that cannot be read just now is "waiting", never empty.
* Same answer whichever copy is named first; joining twice is joining once. A tie on marks goes to the longer text, then the larger.
* Every conflict copy iCloud parked beside a file is read and joined; after writing, only the conflict copies that were joined are cleared, so one that arrived in the meantime waits for the next meeting.
* It refuses rather than guesses: a plan from a newer app (`format` higher than this app's) is never written over, and the device says "Update Triathlon on this device". Two plans taken in separately (a different workbook, or the same one taken in at another time) are never joined: the status is "Two different plans — choose one in Settings › iCloud".
* When the join changes the plan here, it is put in place only if the plan here did not change while the two were being joined (otherwise it joins again in a moment); if there is no room or it cannot be written, nothing changes and nothing goes up: "The plan from your other devices could not be saved on this iPad". A plan or diary iCloud holds that cannot be read is kept on this device (`parkFromICloud`) before anything is written over it.
* A mark more than five minutes ahead of this device's clock sets "clock behind" (the red line on the iCloud page).

**W.3.4 Before iCloud.** The first time a device is about to meet iCloud it keeps one copy of its plan, diary and waiting log, "for good" (`Application Support/Before iCloud/`: `plan-<stamp>.json`, `diary-<stamp>.json`, `waiting-<stamp>.json`). If there is no room, nothing is shared and the status says "No room for a copy before iCloud, so nothing was shared". Settings → iCloud → "Copy from before iCloud" (`icloud-before-copy`) says "The plan on this iPad as it was before it first met iCloud. Kept for good." with the button "Share"; a device that had no plan then says "None on this iPad: it had no plan of its own before iCloud." Choosing one of two plans keeps the one not kept among the safety copies instead (W.3.6).

**W.3.5 Going back.** "Go back to Excel" is closed once another device has met iCloud with this plan (`goBackClosed`): Settings shows "Your iPad or Mac uses this plan too — a spreadsheet copy is the way out." (`plan-go-back-closed`). On the only device, going back puts `plan.json` aside as `plan-left-<time>.json`. Safety copies, spreadsheet copies and the iPhone's backup work as in 2.0 and 2.1, per device. (OPEN, in the code: a device that adopted the plan and then sees it gone keeps its own copy and puts it back at its next meeting; that is why going back is closed once another device has joined.)

**W.3.6 Copies around a meeting, and putting one back.**

* **Before a meeting that changes this device's plan** (`Store.takeFromCloud` → `keepBeforeMerge`): after the day's copy (`keepSafetyCopy`), the plan as it stands here is copied to `backups/before-merge-<yyyy-MM-dd-HHmmss>.json`, or, when the meeting takes something away from this device, `before-merge-<stamp>-from-<device>-took.json` (`<device>` is mac, ipad, iphone or other_devices). The newest **20** of each kind are kept: the `-took` copies are counted apart, so twenty quiet meetings cannot push them out. If the copy cannot be made the plan is not put in place ("No room for a safety copy, so the plan from your other devices was not put in place. Nothing was changed.").
* **One of two plans** (`PlanCloud.choose`): keeping this device's plan puts the iCloud plan aside as `other-plan-<stamp>-icloud.json`; taking iCloud's plan first puts this device's plan (with what the iCloud file adds to it, when it is the same plan) aside as `other-plan-<stamp>-here.json`. These two are never pruned.
* **Words in the list** (`SafetyCopiesView.rowTitle`): "Wed 25 Nov 2026, 09:12 — before your Mac's changes came in" (`-took`; "your iPad's", "your iPhone's", or "your other devices'" for a quiet one); "… — the other plan from iCloud, put aside when you kept this one"; "… — the plan this iPad had before it took the other one"; the older "… — just before a copy was put back".
* **Putting one back** (`Store.restoreSafetyCopy`). A copy of the other of two plans is put back whole with its own marks, and iCloud then asks which plan to keep. On a plan that is **shared** (`planIsShared`: another device has met this plan) the copy goes back through `PlanBook.putBack(_:over:)`: its days, words and lengths, its weeks and which sessions are in it go back and are marked as a change made now, so every device takes them; what was logged since stays (a session's log is the copy's only where the copy's log mark is the later one; a logged session the copy does not have stays; extras, test results and zones stay as they are). The question says: "The plan goes back to how it was in this copy: its days, words and lengths, and which sessions are in it — on all your devices. What you logged since then stays. The plan as it is now is kept aside first." On a plan that is not shared, the old rule holds (everything since the copy is taken out). The green line afterwards for these copies: "The plan is back as it was on <day and time>."
* **What a meeting took out** (`PlanCloud.takenNotice`, kept in UserDefaults `sync.takenNotice`): when a join takes sessions away from this device, "<n> thing was taken out by your Mac — see Safety copies" ("2 things were taken out by …"; "your other devices" when the others are of more than one kind). It shows as the sync status `.noted` (a green dot like `.same`, these words instead of "Same on all devices") and on the iCloud page (`icloud-taken`, bold footnote), until the iCloud page or the Safety copies page has been seen (`takenNoticeSeen`: on appearing / on leaving), when the status goes back to `.same`.

### W.4 Settings → iCloud, the dot, the waiting page

**The sync dot** (`SyncStatus`): always a dot with words, never alone. Five states: **green** "Same on all devices" (everything settled; the iCloud row adds " · 07:12"); **green with other words** (`noted`): what a meeting took out (W.3.6), until it has been seen; **amber** "On its way" (the colour of the amber extra-hour block, `Theme.extraHour`); **grey** "iCloud is off" (iCloud off, or the device not signed in); **red**, the words say which (a refusal, no room, a plan that cannot be saved, "Update Triathlon on this device", "Two different plans — choose one in Settings › iCloud", "This app's iCloud folder is not available" when the app was built without its iCloud permission). It is shown: at the foot of the side list (iPad and Mac, `sync-status`), on the iCloud row in Settings (above the page), on the iCloud page, and in the waiting page.

**Settings → iCloud** (row `settings-icloud`, the first under "Your plan"; page title `icloud-title` "iCloud"). Top to bottom:

* The dot and its words in a headline (`icloud-status`), and under it one grey line (`icloud-detail`): off — "Sign in to iCloud on this iPad (Settings → your name → iCloud), then open Triathlon again. Until then the plan on this iPad is not shared." (on a Mac: System Settings → your name → iCloud); on its way — the waiting words when there are some ("Your plan from your iPhone has not reached this iPad yet. Nothing is sent from here until it has."), else "Your plan is on its way between your devices." (an iPhone still on Excel: "Your plan still lives in Excel on this iPhone, so it is not shared yet."); same, or green with the taken-out words — "Last met iCloud 07:12." (the taken-out words, bold, stand above, `icloud-taken`) (an iPhone on Excel: "Your morning answers are shared. The plan is shared once it lives in this app."); problem — "Nothing on this iPad was changed. Last met iCloud …" (two plans: "Your iCloud holds a plan from another move into the app. Look at both below and choose the one to keep — the other is kept in Settings › Safety copies, where it can be put back.").
* Red line (`icloud-clock-behind`) when the clock is behind: "This iPad's clock is behind. Set it to the right time (Settings → General → Date & Time → Set Automatically), so the newest change always wins."
* When two plans exist: "Two different plans" with two cards, "On this iPad" (`two-plans-left`) and "In iCloud, from your iPhone" (`two-plans-right`; "your other devices" when it cannot be told): sessions and how many are done, last change, moved in on; each with the green button "Use this one" (`two-plans-left-use`, `two-plans-right-use`). "Use this one" under the plan on this device keeps it at once. Under the plan in iCloud it opens a question first (`two-plans-words`): "Use that plan here?" and, in words, "On this iPad: 214 sessions, 31 done, last change Wed 25 Nov 2026, 09:12." and the same for iCloud's plan (invented numbers), then "The plan on this iPad is replaced by the one from your iPhone. It is kept in Settings › Safety copies, where it can be put back."; with the buttons "Cancel" (`two-plans-cancel`) and the red "Use that plan here" (`two-plans-confirm`). The one not kept is listed in Safety copies (W.3.6).
* The full-width button "Sync now" (`icloud-sync-now`); since 2.5 not shown while iCloud is off (status `.off`).
* "Your devices" (`icloud-devices`): one row per device (`icloud-device-<kind>`), iPhone first, then iPad, then Mac: "iPad · this one · last seen 07:12 · 2.2 (76)". With none: "None yet. Each iPhone, iPad and Mac appears here once it has met iCloud."
* "What is shared": "The plan, everything you log and change, and your morning and how-hard answers are the same on your iPhone, iPad and Mac. Apple Health numbers come from your iPhone. The Training calendar and Dropbox stay on your iPhone."
* "Before iCloud": "Copy from before iCloud" (W.3.4).

**The waiting page** (`WaitingForPlanView`, shown as Today on an iPad or Mac that has no plan yet, and for two seconds after the plan arrives): the plan mark, the title "Your training plan" (`waiting-plan-title`), then one card with a dot and one line (`waiting-plan-<state>`), and a grey note under it. States (identifier suffix; dot colour; line):

| State | Dot | Line |
|---|---|---|
| `icloud-off` | grey | "Sign in to iCloud on this iPad (Settings → your name → iCloud), then open Triathlon again." (Mac: "…this Mac (System Settings → your name → iCloud)…") |
| `working` | amber | "Bringing your plan from iCloud…" and the file's size when known |
| `none` | amber | "Your plan lives on your iPhone. Open Triathlon there once — it puts the plan in iCloud." |
| `excel` | amber | "Your plan still lives in Excel. On your iPhone: Settings → Your plan → Move the plan into this app." |
| `ready` | green | "Plan from your iPhone · 214 sessions · last change 07:12" (sessions without rest days since 2.5, `PlanBook.trainingCount`) (or "from iCloud" when no iPhone has met it); the note says "Opening it now." |
| `update` | red | "Update Triathlon on this device"; the note: "This plan was saved by a newer Triathlon. Nothing here was changed. Update the app in TestFlight, then open it again." |
| `problem` | red | the words of the problem, or "iCloud could not be reached just now" |

The note under the other states: "Your iPhone, iPad and Mac show the same plan once it is here. Nothing needs choosing on this iPad." (Mac). `excel` is shown when an iPhone's device file says its home is Excel. The page leaves by itself when the plan has arrived (after the two seconds).

**The move-in page on an iPhone.** When iCloud already holds a plan (`cloudHasPlan`) and no Excel file has been taken in this time, "The plan moves in" shows, instead of the Excel steps, "Your plan is already in iCloud — it was moved into the app on another device. Use it here, and this iPhone shows the same plan as your other devices." and "Anything still waiting on this iPhone is written into it. Your Excel file is not changed." with the green button "Use the plan from iCloud" (`movein-use-icloud`; while working "Bringing the plan from iCloud…"). A newer plan: "The plan in iCloud comes from a newer version of Triathlon. Update the app on this iPhone first."; still on its way: "The plan is still on its way from iCloud. Try again in a moment."; unreadable: "The plan in iCloud could not be read. Nothing was changed." The finished page says "It is the same plan as on your other devices. Your Excel file stays in Dropbox, untouched."

**Health numbers on the iPad and Mac.** The Today morning line is the iPhone's, taken from `health-from-iphone.json`, with a grey line under it (`morning-from-iphone`): "from iPhone, as of 07:12"; older than 18 hours: "from iPhone, earlier today 07:12", "from iPhone, yesterday 07:12" or "from iPhone, 22 Nov 07:12", and the row at 60 % strength. The Load card's Health workouts follow the same share.

### W.5 Morning numbers from Garmin

**Settings → Garmin** (all devices; row `settings-garmin` under "Garmin"). The row says "Garmin · not connected" with "Overnight HRV, sleep, Body Battery and stress from your Garmin watch", or "Garmin · connected" with "Today and Body show your Garmin numbers". The page (`garmin-title` "Garmin"):

* *Not connected:* a grey paragraph (make a personal key once in your Garmin Connect account at connect.garmin.com, paste it here once), a secure field "Paste your Garmin key" (`garmin-key`), a red line (`garmin-problem`) when needed, and **Cancel** (`garmin-cancel`; Escape on a Mac) and **Save** (`garmin-save`, full green; "Checking…" while it asks Garmin). Save with nothing typed: "Nothing typed yet. Paste your Garmin key into the field first." A key Garmin refuses: "Garmin did not accept this key." Other words: "Could not reach Garmin. Try again in a moment.", "Garmin did not answer as expected.", "This device could not keep the key. Try again." A good Save keeps the key, clears the field, and reads the numbers once.
* *Connected:* a card with "Connected" (green, `garmin-status`), a row of dots (the key is never shown again) and "Last read 07:12"; the red problem line if the last read failed; **Read again now** (`garmin-again`; "Reading…" meanwhile; ignores the half hour) and **Remove the key** (`garmin-remove`, red, asks: "Remove the key?" with "Remove the key" and "Keep it"; "Today and Body stop showing Garmin numbers. You can paste a key again at any time."). Removing deletes the key, forgets the access token, and deletes the numbers file.
* Always at the foot: "The key stays on this device only. The numbers are shown, they never change your plan."

**The key.** Keychain, service `com.schabbauer.AMSWorkoutSync.garmin`, account `personal-key`, accessible after first unlock, not synchronised. Never in UserDefaults, the plan, a copy, iCloud, a log, an error message, the numbers file, or the repository (it is public). An iPad or a Mac that should show the numbers needs its own key typed there. The access token Garmin gives for it is kept in memory only (about a day; a new one a few minutes before it runs out, or after a 401), and the session has no cache and no cookies.

**What is asked of Garmin** (`GarminClient`, host `personal.connectapi.garmin.com`, read only, six small reads for one morning, a failed one only meaning "no number"; the key, a refused key or no connection end the read): `POST /personalapitoken-service/personal-api/personal-api-key/token` (the key goes in the Authorization header, once, to get the token); then `GET` `/usersummary-service/usersummary/daily?calendarDate=<day>`, `/sleep-service/sleep/dailySleep?date=<day>`, `/hrv-service/hrv/<day>`, `/hrv-service/hrv/daily/<from>/<day before>`, `/sleep-service/sleep/dailySleepSummariesByDate?startDate=<from>&endDate=<day>`, `/usersummary-service/v2/dailysummaries?startDate=<from>&endDate=<day>`. Nothing is ever written to Garmin. The answers are read forgivingly (`GarminMorning`: a missing field, a number as a string or an answer wrapped one level deeper gives "no number", never a crash).

**When it reads** (`GarminReader`): when Today appears, at most once in 30 minutes (`readEvery`); "Read again now" and a good Save at once. The morning's day is today, except before 04:00, when the night that last ended belongs to yesterday. An answer with no numbers (the watch has not sent the night yet) never replaces numbers already held. The last reading is kept in `Application Support/garmin-morning.json` (numbers only, plus Body Battery at waking, one value a day for 20 days, to make its own normal); it shows at once on launch. Removing the key empties it.

**On Today** (`morning-garmin`, one line, two at most): "HRV 64 (+3) · Sleep 7h 20m · Resting 47 (−2) · Body Battery 71" (since 2.5 `GarminWords.sleep` uses `formatDuration`; before: "7 h 20"). Names grey, figures bold. A bracket is always there on HRV and Resting: the difference from his own normal as "+3", "−1" or "±0", **green** the good way (HRV higher, resting lower), **red** the other way, **grey** when it is within the larger of 1 and 4 % of the normal, and, while there is no normal yet, grey "(normal in 3 days)" or "(normal tomorrow)". The normal is the average of up to 14 earlier days and exists from the fourth day (`Fortnight.daysNeeded`, as for Health). Sleep and Body Battery carry no bracket. Under the line, the dot and its words (`morning-dot`): **green** "Garmin · this morning, read 07:12"; **grey** "Garmin · older numbers from Mon 23 Nov". The line leaves itself out with no key or no number. Where Garmin has a number Apple Health also has (sleep, HRV, resting), the Health line drops its own (`withoutDuplicates`); with no Health line, the Garmin line sits right under the heading. Tap the line for the plate.

**The plate** (`MorningNumbersView`, `morning-plate`, a sheet that opens at half height or full): "Garmin, this morning" in green; the dot with "From this morning · read 07:12 from Garmin" or "Older numbers from Mon 23 Nov · read 07:12 from Garmin" (`morning-plate-dot`); five cards (`morning-row-hrv`, `-sleep`, `-resting`, `-bodybattery`, `-stress`): "HRV overnight 64 ms (+3)" with "Normal 61 over 13 days · Garmin's balanced range 52–68"; "Sleep last night 7h 20m"; "Resting heart rate 47 bpm (−2)"; "Body Battery on waking 71"; "Stress yesterday 28"; each with the name first and the figure right beside it, and under it "Normal … over N days" or "No normal yet · N of 14 days"; a missing one says "none yet" and "Garmin has not given this one yet."; "Your watch last sent its numbers to Garmin at 07:05."; "Shown only. These numbers never change your plan."; and **Done** (`morning-plate-done`; Escape on a Mac).

**Shown only.** No judgement, no advice, no score, no suggestion, nothing written into the plan; the numbers are not in iCloud and not in any copy.

### W.6 Identifiers, signs, switches, tests

* **Identifiers (new):** `side-today, side-plan, side-sessions, side-progress, side-settings, sync-status · plan-switch, plan-switch-<week|month|year>, plan-title, plan-hint, plan-numbers, plan-by-sport, plan-load, plan-followed, plan-race · week-board, week-title, week-hint, week-prev, week-this, week-next, week-day-<day key>, week-card-<key>, week-extra-<id>, week-add-<day key>, week-moved, week-undo · month-grid, month-prev, month-this, month-next, month-day-<day key>, month-chip-<key>, month-extra-<id>, month-more-<day key> · year-view, year-month-<yyyy-mm>, year-key · season-view, season-key, season-race, season-today, season-week-<n>, season-phase-<i> · settings-icloud, icloud-title, icloud-status, icloud-detail, icloud-clock-behind, icloud-sync-now, icloud-devices, icloud-device-<kind>, icloud-before-copy, icloud-taken, two-plans-left, two-plans-right, two-plans-left-use, two-plans-right-use, two-plans-words, two-plans-cancel, two-plans-confirm · waiting-plan-title, waiting-plan-<icloud-off|working|none|excel|ready|update|problem> · plan-from-icloud, plan-go-back-closed, calendar-on-iphone, health-from-iphone, movein-use-icloud · settings-garmin, garmin-title, garmin-key, garmin-save, garmin-cancel, garmin-status, garmin-again, garmin-remove, garmin-problem · morning-garmin, morning-dot, morning-from-iphone, morning-plate, morning-plate-dot, morning-plate-done, morning-row-<hrv|sleep|resting|bodybattery|stress>`.
* **DEBUG switches:** see 14.6 (`AMSWS_SIDE`, `AMSWS_PLAN`, `AMSWS_DEVICE`, `AMSWS_FAKE_CLOUD`, `AMSWS_CLOUD_SEED`, `AMSWS_CLOUD_PAGE`, `AMSWS_WAITING`, `AMSWS_FAKE_GARMIN`, `AMSWS_GARMIN_PAGE`, `AMSWS_MORNING_PLATE`).
* **Signs added** (each with words in How this works → Signs in this app):
  * the **sync dot**: green "Same on all devices" (or, with other words, what a meeting took out), amber "On its way", grey "iCloud is off", red = a problem, the words say which; never without its words;
  * the **Garmin dot**: green "Garmin · this morning, read …", grey "Garmin · older numbers from …";
  * a **letter E above a Season bar** = an easy week, **T** = a test week (since 2.4.1 (79); before, a pale bar meant an easy week); the **outline** = the week or the weeks of the month being looked at; the **thin green line** with "Today" = today; the **flag** = the race;
  * the **Plan switch** (chosen word white on blue), the **blue frame** round a day or a cell while a session is dragged over it, "+ Add" and "Undo" in blue: the plan's blue;
  * on **Year**: solid, pale, hatched, empty-outline and race-colour squares and a green outline (solid = recorded, pale = still to do, hatched = missed, empty outline = rest day, race colour = race day, green outline = today), each in the key in words;
  * the green **"+N more"** in a month cell = more than three chips; a tap opens that day's week;
  * the **purple** titles and bars in his numbers (the Progress colour);
  * a **grey "from iPhone, as of …"** line = the iPhone's Health numbers, shown on iPad and Mac;
  * the side list's five coloured words.
* **Collisions with older signs, checked against "a mark or colour means one thing":**
  * *Green dot (sync, Garmin) and the green tick.* The tick (a white check in a green disc) means "done" and nothing else; the dots are small plain circles and are always beside their words. They never carry the meaning alone. Same family of green as "today" and "same" (`Theme.today`), as before.
  * *Amber sync dot and the amber block.* The sync dot's amber is `Theme.extraHour`, the colour of the amber block under the week card (a full hour of extra training time). Different place, size and shape; the dot always has its words. Recorded as the one near-collision of 2.2. The waiting page uses the same amber dot for "waiting".
  * *Red.* The red dot means a problem, as red words everywhere mean something went wrong; no change in meaning.
  * *Grey.* The grey sync dot (off) and the grey Garmin dot (older) both mean "not live"; no change.
  * *Pale.* On the Season, a pale bar meant an easy week (until 2.4 (78); since 2.4.1 (79) it does not); on the week card on Today a lighter block means still to do; and "paler tick" means an extra. Three uses of "paler", each in its own place; the Season bar says "Easy" in words where it has room and has a label for the screen reader.
  * *Blue.* The side list's Plan and Sessions share the plan's blue, and so do the switch, + Add, Undo and the drag frame. All are about the plan; none of them means anything else.
  * *Today.* Today is green on the Season line, on the week board's day name and in a month cell, and a green outline on a Year square (since 2.4; before, a dark frame). The word "Today" or the key's line says it in each place.
  * *Pale again.* On Year and in By sport, pale means still to do (as on the week card). Until 2.4 (78) the Season bar's pale meant an easy week, and the key said so ("Pale = easy week"); since 2.4.1 (79) pale means still to do only.
  * *Amber-brown* (`Theme.season`, the Season's colour) is a different, darker orange than the amber block.
* **Tests (new):** `Core/Tests/WorkoutCoreTests/BookMergeTests.swift` and `CloudMeetingTests.swift` (the join, two devices through a plain folder), `GarminMorningTests.swift` (the readers, the normal, the 30 minutes); UI tests `UITests/WideLayoutUITests.swift` (the Plan page with Week, Month and Year, the season, his numbers, the phone look unchanged), `ICloudUITests.swift` (the iCloud page, a second device waiting then opening the plan), `GarminMorningUITests.swift` (the line and the plate, no key no line, an empty key refused in words), all with `AMSWS_DEVICE`, `AMSWS_FAKE_CLOUD` and `AMSWS_FAKE_GARMIN`.

### W.7 What 2.2 deliberately does not do

* It never writes to Garmin and puts nothing on the watch; the Garmin numbers never change a plan, and no rule uses them.
* It gives no advice and says nothing medical.
* It sends nothing anywhere but the user's own iCloud (and the read-only request to Garmin from a device that has a key).
* Photographs are not shared between devices; the Garmin key is not shared; safety copies are per device. The spreadsheet copy in Dropbox is written by the iPhone only.
* Dropbox, the Training calendar and Apple Health stay on the iPhone; Apple Health's numbers are shown, not written, on iPad and Mac.
* It does not join two separately imported plans; he chooses, and taking the other device's plan asks first. The plan not kept goes into Safety copies.
* Going back to Excel is closed once another device uses the plan.
* The iPad and Mac look has no new editing screens: Plan uses New session and Change, and the drag is a Change with a new day. Plan shows and moves; it suggests nothing.

## New in 2.3 (77) — suggestions by the rule book, Claude built in, the link to two neighbour apps

Three additions and one rule that holds them together: **nothing in the plan changes except by the user's own tap; nothing is ever driven by sleep; the app never speaks like a doctor.** Files: `Core/Sources/WorkoutCore/RuleBook*.swift` (the engine, pure: no clock, no network, no files), `SuggestionLog.swift` (what is kept and how a card is applied), `App/Sources/Suggestions.swift` (`SuggestionKeeper`), `SuggestionCard.swift`, `StopSignView.swift`, `SuggestionsSettingsView.swift`; `ClaudePick.swift`, `ClaudeWiring.swift`, `ClaudeExport.swift` (Core), `ClaudeClient.swift`, `ClaudeKey.swift`, `ClaudeSettingsView.swift` (App); `NeighbourNotes.swift` (Core), `Neighbours.swift` (App). `MARKETING_VERSION` 2.3, `CURRENT_PROJECT_VERSION` 77.

### V.1 The rule book (`RuleBook.evaluate`)

**What it is.** A fixed set of triggers, a menu of seven moves and thirteen hard limits, written from the user's own training guide (his "guide", section numbers in the code comments). It takes a value, `RuleBookInput` (sessions, weeks, week caps, today, the morning answers, the log of earlier cards, his stop-sign and illness taps, "something hurts" days, settings), and returns an `Outcome`: the trigger that fired, one `Suggestion` or nothing, and every candidate it tried with the limits that failed. `rule-check` (Mac command line, `Core/Sources/RuleCheck`) walks it over past days of a copy of a workbook and prints the cards it would have shown; it writes nothing.

**Order.** Asked in this order, the first trigger that has candidates builds them: his own taps (S5, the illness steps), a session that came in already breaking a limit (IN), T3 (back after a break), T2 (a missed key session), "something hurts" (Q2), T1 (tired signs), T4 (a long session too far ahead), T5 (a big week), T6 (behind the plan; **switched off**, `planReviewOn` false, no switch on screen), back-to-back quality (Q1, only when the user asked for it). Each candidate is applied to a copy of the plan and run through every limit; the first that passes is the card, the next two that pass (at most) are "Other choice". If none passes, the next trigger gets its turn, unless the calm limits (L10, L11) said no: then the day stays silent. The check is run: when Today appears, after the morning answer (or from 07:00 without one), after a session is logged, and (Sunday from 18:00) in the evening, which today only T6 uses. A check that nothing changed since the last one does nothing (`lastCheck`).

**The moves** (the only changes a card, or Claude, can ever propose): M1 take a session out (becomes "rest (your choice)", status changed, counted 0, followed, never missed), M2 swap with the next easy session of the same plan week, M3 shorter (a share of the planned minutes, to 5, or T4's step), M4 easier (zones 1–2; strength: effort 4–5; optionally as a row or an easy spin), M5 another day in the same week (never a Friday), M6 the next easy week brought forward to today, M7 a whole day rest.

**The limits** (`RuleBookLimits.swift`): L1 Friday is rest. L2 no new hard days in a row (the plan's own pairs are left). L3 a week stays within the minutes the plan first gave it. L4 a week that gains minutes may not outgrow 1.10 × the mean of the last three weeks. L5 long rides and runs grow a step (a tenth of the longest in the last 21 days; at least 5 min ride, 3 min run). L6 protected: tests, race simulations, the race and race week are never touched (the illness steps may drop tests and key sessions); easy weeks and the taper only get easier; M6 only from a load week into an easy week at most one phase ahead. L7 nothing longer, nothing harder, no new session. L8 no make-up (T2's swap excepted). L9 the Monday swim does not go two weeks running. L10 until 48 h symptom-free, nothing but the illness steps. L11 calm: one open card, one a day, two in seven days, none in race week (week 44), a session a taken card changed is left alone for seven days. L12 each trigger may use only its own moves (menu table in code). L13 no doctor talk: the words healthy, fit, safe, your heart never appear in a card, and the footer is on every card.

**Cool-downs and ladders** (numbers in `RuleBookSettings`, tunable in code, no screen): T1's ladder (extra rest day or an easier session; then the next 3 days easy or at 70 %; then the next easy week brought forward, or the 3 days) climbs one step at a time, the next only after a taken step has passed; after Keep my plan silent for 4 days (`tiredCoolDownDays`), after 14 days the ladder starts over; T4 after Keep my plan silent for that sport for 14 days; T5 only on a Monday, at most once in 14 days, when last week was 1.3 × its cap and 1.3 × the mean of the last four weeks (hikes count); T3 starts at a gap of 4 days, under 7 days two easy days, 7 to 20 days a week at half then (seven days after a taken week) a week at three quarters, 21 days or more is T6's review (off). T2 needs a gap of 2 or 3 days that held a key session (not a test, not a simulation) and puts it on the day of the first later non-key session of the same week.

**Reads and never reads.** Reads: the morning answers (a "bad signal day" is Bad or Tired, i.e. 2 or less; two such days in a week make a tired week), how hard a session felt against its plan (`feltHarderMargin` 2), minutes planned and done, extras, hikes and walks of 30 minutes or more from the watch (counted as training: `hikesAlwaysCount`), and his own taps. **Never read: sleep, resting pulse (fixed to "shown only", Q5 has no screen), Body Battery, stress, a single HRV value.** HRV has code behind it (`hrvLowDays`, active only from `hrvStartDay` 2027-01-15 with 42 nights, and then only together with a morning answer of 3 or less) but **the app never gives the engine any HRV number**, so it cannot act. A single poor morning, a single hard session, a single missed day, doing more than planned are not triggers.

**Words** (`RuleBookWords.swift`): fixed templates, British, no percentages in reasons ("about a third more than"). The buttons "Take it", "Keep my plan", "Other choice"; the footer "Training suggestion — not medical advice."; the reasons start "Why: …"; "your guide" in a reason means his own training guide.

### V.2 Today: the card, the keeper, what is kept

**Where.** `SuggestionArea` is directly under the morning question on Today (`TodayView`), and takes no room when there is nothing to show. Cards are made **on the iPhone only** (`Device.isPhone`) and only once the plan lives in the app (`store.canChangePlan`) and the switch is on. An iPad or Mac never makes a card.

**The card** (`SuggestionCardView`, `suggestion-card`): headline (`suggestion-headline`, headline font), reason (`suggestion-why`, grey), when Claude's pick is in use the grey caption "Picked by Claude from the rule book's choices" (`suggestion-claude`), then two buttons side by side (stacked at accessibility text sizes), the same size and the same blue outline (`Theme.plan`), neither filled: "Take it" (`suggestion-take`) and "Keep my plan" (`suggestion-keep`). Then, when there are other choices, the blue word "Other choice" (`suggestion-other`), which opens up to two rows (`suggestion-other-1`, `suggestion-other-2`), each a headline with its own blue "Take it". The footer in tiny grey. A plan review has no "Take it" (T6 is off).

**After "Take it".** The card's place shows "Changed —" (`suggestion-changed`) and the blue small button "Undo" (`suggestion-undo`) with the headline under it, for the rest of that day. "Take it" writes through `Store.applySuggestion`: one entry per changed session in Changes to the plan, with the reason "Suggestion: <headline>"; the log is written first, then the plan, and if the log cannot be saved nothing is written; a second tap while one is being written is ignored. Undo takes back exactly those changes and only while none of them has been changed since; otherwise it says "This session was changed again since, so nothing was undone." (`suggestion-undo-refused`); if they are already gone: "This change is no longer in your plan." (`suggestion-gone`). An undone card reads as Keep my plan to the rule book, and the log still says it was taken and undone.

**Before it writes.** `SuggestionApply.fits`: the sessions the choice touches must still be exactly as when the card was made (the snapshot `before`), none done, none moved into the past, nothing longer or harder, and every limit but L11 must still pass. If not, nothing is written and the card is put away with the grey line "The plan has changed since this suggestion, so it was put away." (`suggestion-stale`). The same check runs when the app comes back to the front.

**Answers** (`RBAnswer`): took(n) (0 the card's own choice, 1–2 the others), keptPlan, closedUnanswered (a card not answered by the end of the day of its first session, closed silently as Keep my plan), planChanged (put away: it no longer fitted), paused (put away: Stop sign or "I'm ill"). `closesOn` is the day of the first session it would change (today at the earliest).

**What is kept** (`suggestions.json` in the device's Application Support, `SuggestionKeep`, format 1, plus `rulebook-caps.json`): the switch (`on`: nil until he touches it, which means **on**), his answers (`RuleBookSettings`), every card oldest first (`SuggestionEntry`: the record with its choices, the limits each candidate failed, his answer; the other headlines; changeIDs; undone; the `before` snapshots; `claudeAsked`, `claudePicked`), his Stop sign and illness taps (`RBHealthTaps`), the days he tapped a place under "Something hurts?", and the sessions already asked. The week caps (what each week held when the plan was taken in) are frozen once per plan. A different plan taken in (`origin.takenAt`) starts a fresh list of cards and "asked" marks; his answers and taps stay. **Every part must read or the whole file counts as unreadable**: then no card is shown and nothing is written (never the defaults over his answers, never a pause ended silently); the page says "The suggestions' own notes could not be read, so suggestions are resting. Your plan is untouched." (`suggest-unreadable`), and Settings → Suggestions offers "Start the notes afresh" (`suggest-afresh`, asks "Start the suggestions' notes afresh?", then "Start afresh" `suggest-afresh-yes` / "Cancel"): the unreadable file is moved to `suggestions.unreadable-<time>.json`, never deleted.

**Per device, except the pause.** Neither file is in iCloud and neither is in a copy or the plan. The log of cards, his answers to them, "Something hurts?" and the settings are therefore **per device**. What is shared of a card is only its effect, an ordinary change to the plan.

**The pause, shared** (`PauseShare.swift`, `PlanCloud.pauseShare`, `SuggestionKeeper.tapsChanged` / `pauseFromICloud`). Stop sign and "I'm ill" (`RBHealthTaps`) are the same on all his devices: they go through the app's own iCloud folder as a separate small file, `Sync/pause.json` (format 1: `health`, and a stamp per part, `stop` and `ill`, each `{at, lifts}` in milliseconds), beside the plan and never inside the plan document or its merge. Every meeting with iCloud (the same plumbing as the diary: found, watched, coordinated, conflict copies read and cleared) reads it and any conflict copies, joins them with this device's taps and writes back what is joined; a file that cannot be read is parked (`parkFromICloud`) and never taken for "all clear"; nothing is read or written while this device's `suggestions.json` cannot be read. A tap here (`openedStopSign`, `stopSignByMistake`, `doctorSeen`, `ill`, `illByMistake`, `symptomFree`, `stillNotRight`) stamps the part it changed (`SuggestionKeep.stopStamp` / `illStamp`, kept in `suggestions.json`) and starts a meeting at once (`PlanCloud.localChanged`). **The rule, per part** (`PauseShare.join`): the newest stamp wins, except that a part that is on (stop: `stopSignSince` and no `doctorSeenOn` since; ill: `illSince` set) is lifted by an all clear only if that all clear ended this very pause or a later one (`lifts` ≥ the pause's stamp) and is not older than it. So an older all clear, an all clear from a device that never saw this pause, and a device from before 2.3 (stamps 0) never lift a pause. Two versions of the same illness keep every "Still not right" day of both. The join is done once more against the taps as they are at that moment, so a tap made while iCloud was being read is never lost. A pause or an illness that arrives puts away the open card (`putAwayOpen(.paused)`) and the iPhone makes no card while it lasts. **With iCloud off**, or before a device has met iCloud, each device keeps its own taps, exactly as before. Tests: `PauseShareTests.swift`.

### V.3 Stop sign, "I'm ill", "Something hurts?", his own edits

**The one pill** (`NotWellPill`, `not-well`): "Not well?", a small bordered caption-size pill (the size of the week card's "Key" pill), shown on Today only when the plan lives in the app (on a session's page it always shows). **[Place and colour as built in 2.3; since 2.4.2 (80) it is grey (`Theme.secondary`) and sits centred at the very foot of Today, see "New in 2.4.2 (80)" below.]** On Today it was not in the header (the phase heading keeps the whole line): in 2.3 it sat in the Today colour at the right end of the morning question's title (`FeelCard`) while that was open, otherwise right-aligned on a row of its own under the morning line; at the foot of a session's page (`StopSignButton`) it stands as before (grey since 2.4.2 (80)). It opens a sheet (medium detent, title "Not well?", "Done" `not-well-close`, Escape closes) with two rows, each a button with one line under its words: "Stop sign" (`stop-sign`; "Chest pain, unusual breathlessness, dizziness, a racing or uneven heartbeat. Opens the stop sign and pauses suggestions.") and "I'm ill" (`ill-button`; "A cold, fever or stomach bug. Opens the illness questions and the steps back."). Tapping a row swaps the sheet's content for the page (one sheet, no second presentation); behaviour of both pages is unchanged. On a session that is today or later the page shows, beside them, "Paused" or "Rest — not until 48 h symptom-free" (`session-ladder`).

**Stop sign page** (`StopSignView`, navigation title "Stop sign", close button "Done" `stop-close`, Escape closes). Words, fixed, from `RuleBookWords`: "Stop training now." (red, `stop-title`); "Chest pain or pressure · unusual breathlessness · dizziness or fainting · a racing or uneven heartbeat."; "These need a doctor to look at them before you train again. If it is strong or does not pass, call 112."; "The app pauses all training suggestions until you tap "A doctor has seen me"."; "Training app, not medical advice." **Opening the page pauses at once** (`stopSignSince` = today, `doctorSeenOn` cleared) and puts away any open card (answer paused). While paused: "Paused" (`stop-paused`) and the full green button "A doctor has seen me" (`stop-doctor`), the only way out; no number and no waiting lifts it. "Opened by mistake" (`stop-mistake`) appears only on the day it was opened and takes it back (the cards it put away come back).

**I'm ill page** (`IllnessView`, title "I'm ill", close "Done" `ill-close`): the current step's fixed sentence (`stop-step`); the question "Fever, or chest / body aches?" with "Yes" (`stop-fever`, below the neck) and "No, a cold above the neck" (`stop-neck`), unless he is already resting or paused; "Symptom-free since" with a date (between the illness day and today) and "Save" (`stop-free`) while he is resting or has a cold; "Still not right" (`stop-not-right`, once a day, in week 1 back); "I tapped this by mistake" (`ill-mistake`) only on the day of the tap.

**The steps** (`RuleBook.ladderStep`, whole days, never hours: "48 h" is read as the two whole days after the symptom-free day, a little longer, never shorter). Fever: Rest ("Rest until 48 hours completely symptom-free. Your guide asks you to respect this strictly.") until two days after the symptom-free day; two extra easy days ("Two extra easy days, as your guide says after fever or chest symptoms."); then, by the number of days out: under 7 the plan as written; 7 to 20 days week 1 ("about half, all easy, no key sessions"), week 2 ("about three quarters, one quality session mid-week") and a week of "Back on your plan."; 21 days or more "The whole plan shifts instead (your guide, section 5)." (no card; T6's review is off). "Still not right" adds three easy days to week 1. A cold above the neck: "Cold above the neck: easy only, shorter, until it has gone." The steps come as cards of trigger S5 (their own, they may follow another card the same day; limits L10 and L11 do not apply to S5); keys and tests may be dropped by them, a simulation, the race and race week never.

**The grey line on Today** (`ladder-line`, `ladderStatus`; only when the plan lives in the app): "Suggestions are paused — Stop sign"; "Resting after illness: day 2 — until 48 hours symptom-free"; "Back after illness: day 1 — easy only"; "Cold: day 3 — easy only, shorter"; "Back after illness: day 4 — about half, all easy"; "Back after illness: day 9 — about three quarters" (day numbers invented). **No card is shown while paused or resting** (`quiet`; L10 also stops every other trigger); in the later steps only the steps' own cards come.

**"Something hurts?"** (`HurtsAsk`, `hurts-ask`): on a session's page, under "How hard was it?", for a logged session of today or yesterday, once per session (`hurtAsked`), when the switch (Q2, `somethingHurtsTap`) is on: buttons "Calf" (`hurts-calf`), "Achilles" (`hurts-achilles`), "Knee" (`hurts-knee`), "Other" (`hurts-other`), "Nothing hurts" (`hurts-none`), green outlined. Calf, Achilles and Knee mark the day; "Other" and "Nothing hurts" are only remembered. A marked day (today or yesterday) makes trigger Q2 build, for the first easy run within six days that may be touched: "row, same minutes, easy", "easy spin, same minutes", or rest (drop); the reason "Why: you said something hurts; your guide makes the Thursday run a row or an easy spin." The app says nothing about what is wrong.

**His own edit** (`OwnEditNote`, `own-edit-note`, one grey footnote, never red, never a question, never a block): on the Move page (`MoveView`, when the chosen day differs) and the Change page (`SessionEditView`), the first of the rule book's warnings for L1, L2, L3, L6, L8, said as a statement: "Friday is your rest day." / "That makes two hard days in a row." / "That week goes over its planned time." / "It is in your easy week; it is meant to stay." / "This one is protected in your plan." / "Missed sessions are gone — no catching up needed." **The drag on iPad and Mac** (`MovedLine.move` in `WeekBoard.swift`, used by the week board and the month grid): the same statement, from `SuggestionKeeper.note(forMoving:to:)` worked out on the plan before the move, is shown as a grey footnote (`week-moved-note`) under "<title> moved to <day>" (`week-moved`) in the eight-second notice with "Undo". The move is always made; the line never blocks it.

### V.4 Settings → Suggestions

Row `settings-suggestions` under "Changes to the plan" in Settings → Your plan, shown only once the plan lives in the app: "Suggestions", sub "On — the app suggests, you decide" or "Off". The page (title "Suggestions", Cancel `suggest-cancel` with Escape, Save `suggest-save`; changes are held until Save): switch "Suggest changes to my plan" (`suggest-on`; "The app suggests, you decide: nothing in your plan changes until you tap Take it."); heading "Your answers"; four switches, blue: "Keep hard bike and hard run on days in a row" (`suggest-q1`; off lets the app suggest the run quality on Thursday), "Ask "Something hurts?" after a session" (`suggest-q2`), "An easy week brought forward leaves the later one easy too" (`suggest-q3`), "Long rides and runs grow a step at a time" (`suggest-q4`); heading "What was suggested" with every card newest first (`suggest-log-row`: day, headline, reason, and his answer in words: "Taken", "Other choice: …", "Kept my plan", "No answer", "Put away — the plan had changed", "Put away — you paused", "Taken, then undone", "Other choice: … — undone"; "No answer yet" while open), or "Nothing yet." (`suggest-log-empty`). The fifth open question (resting pulse) has no screen: it is fixed to "shown only". Save is disabled when the notes cannot be read.

### V.5 Claude built in (optional)

**Off until two things are done**: a key typed and the switch turned on. The switch (`claude-on`, "Let Claude choose among the suggestions", `UserDefaults` `claude-on`, per device) is disabled and says "Needs a key first." until a key exists; removing the key switches it off. Nothing about Claude happens without both.

**What Claude may do.** Only pick one number of the card's menu and write the reason. `ClaudePick`: 0 keeps the plan, 1 is the rule book's own pick, 2 and 3 its other choices. The rule book alone decides whether a card exists and what is on its menu (limits included); Claude never sees a move it could invent. Asked **once per card** (`claudeAsked`, so a restart or a second check never asks again), only right after a card was made today, never for a plan review.

**The card never waits.** It is shown at once with the rule book's pick. Claude gets **one attempt, no retry, 20 s** (`ClaudePick.requestTimeout`, `attempts` 1; the request and the session use the same timeout). When the answer comes it is used only if all hold: it came within 25 s of the ask (`ClaudePick.lateAfter`) and he has not touched the card since — opened "Other choice" or tapped anywhere on it (`SuggestionKeeper.touched`, `ClaudePick.mayUse`); the card is still the open card of today, unanswered, unchanged (same words, moves and snapshot), no change written; the pick is 1 or more (0, "keep the plan", leaves the card as it is, because the card has its own Keep button) and inside the menu; the reason passes `cleanWhy`; the card is re-checked against the plan (`fits`). Then the chosen choice takes the first place, its reason replaces the rule book's, the order of the other choices follows, `claudePicked` is set and the caption shows. So the card can change its words only within the first seconds and never after he has touched it. Any other outcome leaves the rule book's card.

**What the app checks in an answer** (`ClaudePick.read`): the stop reason must be a normal end (a refusal or cut-off is never read); the answer must be JSON with an integer `pick` (not a true/false) and a text `why`; the pick inside the menu; the reason made one line, given "Why: " if missing, 5 to 160 characters, and **none of** doctor, diagnos, injur, should see, medication, sleep, slept, hrv, pulse, medical, symptom, illness, sick, fever, physio, heart, pain (any case, anywhere in the text), no links or markup; and it must pass the rule book's own word check too (`RuleBook.l13Words`, L13: healthy, fit, safe, your heart, as whole words), inside `ClaudePick.cleanWhy`, so `read` and `accepts` both apply it. A reason that fails leaves the rule book's pick and reason. The footer stays on the card. The instructions sent with each question say: ONE short sentence, never medical, never sleep, resting pulse or HRV, never a number not in the situation.

**What is sent** (`ClaudePick.request`, `ClaudeContext.make`) to `https://api.anthropic.com/v1/messages` (model `claude-opus-5-5`, headers `anthropic-version` 2026-10-21 and the fallback beta, key in `x-api-key`, structured answer `{pick, why}`, effort low, `max_tokens` 16000, fallbacks default; an ephemeral session: no cache, no cookies): the fixed instructions; the menu (0 = keep my plan; 1 = the headline and the rule book's reason; 2, 3 = the other headlines); today's date; for each of the last 14 days that had a planned session, a done session, an extra or a morning answer: minutes planned, minutes done, the highest effort as "n of 10", the morning answer 1 to 5, extras such as "hike 90 min"; for each of the next 7 days: the sports, minutes and zone words, or "rest". **Not sent:** name, photographs, notes, session titles, tests, zones, weight, the race, Garmin or Health numbers, sleep, the key of any other service, the plan file, anything of another device. A freshly typed key is checked with one tiny message ("Reply OK", 16 tokens, nothing of his). Nothing goes anywhere else.

**The key** (`ClaudeKey`): Keychain generic password, service `com.schabbauer.AMSWorkoutSync.claude`, account `anthropic-key`, accessible after first unlock, not synchronised. Never in `UserDefaults`, the plan, a copy, iCloud, a log, the meter, an error message or the repository (public). Typed in a secure field (`claude-key`; spaces removed); "Save" (`claude-save`, full green; "Checking…" meanwhile) keeps it only if Anthropic accepts it; "Cancel" (`claude-cancel`, Escape) clears the field. Words: "Nothing typed yet. Type your Anthropic key into the field first."; "Anthropic did not accept this key." (also shown under "Key saved" after a 401 on a real question, `claude-problem`); "Anthropic could not be reached just now. Try again in a minute."; "This device could not keep the key. Try again." Saved: "Key saved" (green, `claude-status`) and dots; "Remove the key" (red outlined, `claude-remove`) asks "Remove the key?" with "Remove the key" and "Keep it" and the message "Claude stops choosing. The suggestions come from the rule book alone. You can type a key again at any time."

**The cap and the log.** `ClaudeMeter`: the month's ledger (`claude-meter.json`, per device): tokens in and out, US dollars, answers. Dollars are the app's own estimate from the tokens of each answer at 4.00 per million in (cache writes as input), 0.20 per million cache read, 20.00 per million out. A question is asked only while the month's dollars are under the cap **5.00** (`defaultCap`, fixed in code, checked before the question: the last answer can take the month a little over); a new calendar month starts from nothing. An answer that cannot be used is still counted. The page line (`claude-month`): "This month: 0.12 US dollars of 5.00 · 6 answers" (invented). The log (`claude-log.json`, per device, 200 kept, 30 shown, `claude-log-row`, heading "What Claude answered"): time, "Kept your plan" / "Chose: <headline>" / "No usable answer, the rule book's own pick stood", the reason, the cost; never the key and never the plan. The explanation on the page (three lines): what it does ("It picks among the choices the rule book offers and words the reason. It changes nothing; you still tap."), what goes (`claude-sent` and the line before it: the choices on the card and the rule book's reason; today's date; for each of the last 14 days the minutes planned and done, how hard the hardest session felt, the morning answer and any extras, such as a walk or hike of 30 minutes or more the watch recorded; the next 7 days of the plan, each session's sport, minutes and effort; the key, so Anthropic knows the question is his; then "Nothing else is sent: not your name, notes, session titles, photographs, tests, zones, weight, or the Health and Garmin morning numbers."), the cost ("It costs about a dollar a month, never more than 5 US dollars a month. The app stops asking when the month reaches it."). At the foot: "Your key stays on this device only." Only the iPhone makes cards, so only the iPhone ever asks; a key typed on an iPad or a Mac is kept there and unused.

**Export for Claude** (`ClaudeExport.brief`, heading "Export for Claude", button "Share the plan as text" `claude-export`, opens the system share sheet): plain text, no code: "MY TRAINING SEASON" with the date; PHASES (with special weeks); TESTS AND ZONES (every test with threshold pulse, bike power, swim pace, weight, notes; the zones in use); THE LAST 8 WEEKS (minutes done / planned per sport, total, missed and not logged, extras that count as training); THE NEXT 4 WEEKS (each day's sessions: sport, minutes, zone words, title, "(done)" or "(missed)"). It **sends nothing by itself**, works with no key, and what happens to it after sharing is up to the app he shares it to. Settings row `settings-claude` under the heading "Claude" (between Garmin and Calendar): "Claude", sub "Off · lets Claude choose among the suggestions, and shares your plan as text" or "On · This month: …"; page title `claude-title`.

### V.6 The link to AMS Workout Companion and AMS Magic Morning Routine (`Neighbours.swift`, `NeighbourNotes.swift`, commit 7f32f05)

**It only works once the neighbour apps' matching versions are installed** (they write and read the same note). Until then there is no note, none of it shows, and the app behaves as before. The screens call the apps "Workouts" and "Magic Morning".

**The note.** One small piece of JSON in one Keychain item: service `ams.training.notes`, account `v1`, access group `D24ENP83QQ.com.schabbauer.AMSWorkoutSync` (this app's own group; the neighbours list it in their entitlements), accessible after first unlock, **not synchronised**: on this iPhone only. It holds `format` (1), `feel` (day, value 1–5, time, from: "morning", "training" or "workouts") and `done` (a list: id, day, kind "strength", "stretch" or "routine", title, minutes, effort, time, from). Fields this app does not know are kept and written back unchanged; a note that is broken or of a higher `format` is neither read nor changed (as if there were none); only the last 14 days of `done` are kept when this app writes (`pruned`); a note larger than 8000 bytes is not written. Every failure is silent. Which apps are installed is asked with `canOpenURL` for `amsworkouts` and `amsmorning` (`LSApplicationQueriesSchemes`), nothing else of them is read. This app opens on `amsworkoutsync://today` (its existing scheme) from the neighbours, onto the first screen of Today.

**When.** `Neighbours.cameToFront` runs when Today appears and when the app comes to the front: reads the note, takes over this morning's answer, or hands on his own.

**The morning answer, taken once** (`NeighbourRules.takeOverFeel` / `writingFeel`). If the diary has no answer for today and the note's `feel` is of today and a value 1–5, that answer goes into the diary (`Diary.setFeel`) and the question card is not shown (`hasFeel`). The first answer of the day wins: an answer given in this app is never replaced by a note. An answer that was itself taken over (marked by day in UserDefaults, `neighbour.feelTakenOverDay`, or equal to a neighbour's note of today) is not his own: while the note of today is from another app, a changed value in it replaces the diary's answer (`takeOverFeel(..., ownAnswerWasTakenOver:)`, test `testTakenOverAnswerFollowsTheNotesButOwnAnswerNeverChanges`). If he answered here, the answer is put in the note (`from: "training"`) unless a note of today from another app is there; this app only ever changes its own earlier answer, and an earlier day's note is replaced. The five words: Bad (1), Tired (2), OK (3), Good (4), Great (5). The answer is **a normal answer after that**: shared through iCloud (`diary.json`), in the Mornings bars, read by the rule book (T1 and the "tired week"), and given to Claude as the morning number. The line on Today (`feel-from-neighbour`): "Feeling good — from Magic Morning" (or "from Workouts"); grey, one line, no tap: an answer taken over cannot be changed here, so one calm grey caption under it says "Answered in Magic Morning — change it there." (`feel-from-neighbour-note`; "Workouts" when that app gave it). It replaces the answer on the Health line for that day. No line when he answered here; that answer is changed by a tap on the morning line as before.

**Strength done in Workouts** (`Neighbours.strength(for:among:)`, `NeighbourDoneLine`, `neighbour-done`). On a strength session still to do that is the first strength session of its day still to do, when the note holds a `strength` item for that day that has not been used: the grey line "Done in Workouts at 07:40 · 35 min" (time in the phone's zone; a missing part is left out) and the small full-green button "Log it" (`neighbour-log`); on the session's page and under the session on Today. "Log it" logs through the ordinary logging (`Store.log`): duration = the note's minutes, or the planned length if there are none (nothing is logged if there is neither), effort = the note's if 1–10. Nothing is logged without the tap. The note's id is kept (`neighbour.loggedFrom` in `UserDefaults`, **per device**) so it is used once; afterwards the session says "Logged from Workouts". "Open Workouts" (`open-workouts`, small grey) on a strength session's page, shown only when Workouts is installed; it opens `amsworkouts://open`.

**Stretching** (`NeighbourRules.stretchMornings`): "Stretching: 4 of the last 7 mornings" (`stretch-line`, caption, grey) in the Load card on Progress, the number of different days with a `stretch` item in the last 7 days, today included; no line when there is no stretch item at all. A count only: nothing reads it and no suggestion uses it.

**What it does not do.** It never writes to the plan by itself. The only things that enter from the neighbours are the morning answer (into the diary) and a strength session he logs with "Log it". Nothing is sent to the internet.

### V.7 Identifiers, signs, switches, tests

* **Identifiers (new):** `suggestion-card, suggestion-headline, suggestion-why, suggestion-claude, suggestion-take, suggestion-keep, suggestion-other, suggestion-other-1, suggestion-other-2, suggestion-changed, suggestion-undo, suggestion-stale, suggestion-gone, suggestion-undo-refused, ladder-line, session-ladder, stop-sign, ill-button, stop-title, stop-paused, stop-doctor, stop-mistake, stop-close, stop-step, stop-fever, stop-neck, stop-free, stop-not-right, ill-close, ill-mistake, hurts-ask, hurts-calf, hurts-achilles, hurts-knee, hurts-other, hurts-none, own-edit-note, week-moved-note, settings-suggestions, suggest-on, suggest-q1 to suggest-q4, suggest-cancel, suggest-save, suggest-log-row, suggest-log-empty, suggest-unreadable, suggest-afresh, suggest-afresh-yes · settings-claude, claude-title, claude-key, claude-save, claude-cancel, claude-status, claude-remove, claude-on, claude-month, claude-problem, claude-log-row, claude-export, claude-sent · feel-from-neighbour, neighbour-done, neighbour-log, open-workouts, stretch-line`.
* **DEBUG switches:** `AMSWS_SUGGEST` (`card`, `other`, `changed`: a card on Today made by the real engine from two invented poor mornings, or a fixed sample), `AMSWS_SUGGEST_LOG` (three invented log rows), `AMSWS_STOP` (the Stop sign page), `AMSWS_HURTS` ("Something hurts?"), `AMSWS_CLAUDE_PAGE` (the Claude page), `AMSWS_FAKE_CLAUDE` (a saved key, invented rows, no network), `AMSWS_FAKE_NOTES` (invented neighbour notes: a feel from Magic Morning, a strength note for today, four stretch mornings).
* **Signs added** (each with words in How this works → Signs in this app): the card's two equal blue-outlined buttons; the blue "Other choice"; "Changed — Undo"; the grey ladder line; the small "Not well?" pill (with the plate's "Stop sign" and "I'm ill"); the grey "Answered in Magic Morning — change it there."; the red "Stop training now." and the green "A doctor has seen me"; the green outlined place buttons; the grey own-edit line; the grey "Picked by Claude…"; green "Key saved" with dots; the cost line; the grey "— from Magic Morning" line; the grey "Done in Workouts…" with the small green "Log it"; "Open Workouts"; the grey "Stretching: n of the last 7 mornings".
* **Collisions with older signs, checked against "a mark or colour means one thing":**
  * *Blue.* Blue means "changing the plan" (Move, Change, + Session). The card's "Take it" changes it; "Keep my plan" does not, but is outlined in the same blue on purpose, so that the two answers weigh the same. Said in the signs as "your answer to a change"; a soft collision, recorded.
  * *Full green.* The full green "Done" means "recorded as planned" and "Log it" (small, beside the Workouts line) means "record what Workouts says": both mean "record it"; "Log it" is small and always beside its words. A session can show both. Recorded as the near-collision of 2.3.
  * *Green outlined.* The place buttons under "Something hurts?" are green outlined ordinary actions, as defined; they change nothing in the plan.
  * *Red.* "Stop training now." is the one red heading, as red means a warning. The own-edit line is grey, never red, on purpose.
  * *Grey lines.* The ladder line, the own-edit line, the Workouts line, the "— from Magic Morning" line and the stretching line are all grey information; none carries a different meaning by colour alone; each has its words.
  * *Green switch (Claude) and blue switches (Suggestions).* A switch's colour is not a sign; the words beside it say what it does.
* **Tests (new):** model tests (`Core/Tests/WorkoutCoreTests`): `RuleBookTests.swift`, `RuleBookTriggerTests.swift`, `RuleBookExampleTests.swift` (the worked examples), `SuggestionLogTests.swift`, `SuggestionSafetyTests.swift`, `ClaudePickTests.swift`, `ClaudeWiringTests.swift`, `PauseShareTests.swift` (the shared pause, Claude's word check, the late answer), `NeighbourNotesTests.swift` (with `RuleBookFixture.swift`); UI tests: `UITests/SuggestionUITests.swift`, `ClaudeUITests.swift`, `NeighbourUITests.swift` (invented plan, the DEBUG switches above). Pass/fail is Apple's run after each push; they were not re-run for this text.

### V.8 What 2.3 deliberately does not do

* It never changes the plan without a tap. It never adds a session, lengthens, hardens, makes up the missed, or touches a test, a race simulation, the race or race week.
* It is never driven by sleep, resting pulse, Body Battery, stress or HRV; Garmin's numbers still never reach a rule.
* It never speaks like a doctor: fixed words, the footer on every card, the Stop sign sends him to a doctor, not to a number.
* Claude never decides whether a card appears, never adds a choice, never changes the plan and never receives the key's owner's name, photographs, notes, tests, weight, or Health's and Garmin's morning numbers (walks and hikes of 30 minutes or more the watch recorded go as extras, as listed above).
* The cards, his answers to them and the Claude key, switch, count and log are per device; the iPad and Mac make no cards. The pause and the illness steps are shared through iCloud (`pause.json`), and stay per device only with iCloud off.
* The plan review (T6) is off.
* The neighbour link needs the neighbour apps' matching versions and reaches nothing but the iPhone's own password store.

## New in 2.4 (78) — Claude says when it cannot choose, one morning answer on every device, sign fixes

One idea: **when something is not as it seems, the screen says so in words, and a mark or colour means one thing.** Nothing in the plan, the rule book or the data of the plan changes. Version shown: 2.4 (78), 25 November 2026.

### X.1 Claude says when it cannot choose

**Before (2.3).** When Anthropic refused (key ended, no credit), the app silently used the rule book's own pick; only one line in the log under Settings → Claude said so.

**Now.** While the trouble lasts, two places say so in words: one line on Settings → Claude under "Key saved", and one grey line on the suggestion card on Today, under the reason (`Why:` line). The suggestion itself always appears and works; only who picks changes. Nothing is ever bought by the app.

**What decides the case** (from the answer to the request for a card; the first rule that fits wins):

| Answer from Anthropic | Case |
|---|---|
| HTTP 401 or 403 | key no longer accepted |
| HTTP 402, or an error of type `billing_error`, or an error message that speaks of the credit balance | no credit |
| the app's own month meter is at its 5-dollar cap (checked before the question, so nothing is sent) | cap reached |
| anything else: no network, timeouts, HTTP 429, 5xx, an unusable answer | no line at all; one line in the log, as in 2.3 |

**The words** (fixed; page / card):

1. Key no longer accepted. Page: "Anthropic no longer accepts this key. It may have ended or been removed. Until you type a new one, the rule book chooses alone." Card: "Claude could not choose: Anthropic no longer accepts your key. Settings → Claude."
2. No credit. Page: "Your Anthropic account has no credit left. Until you add credit at Anthropic, the rule book chooses alone." Card: "Claude could not choose: your Anthropic account has no credit left. Settings → Claude."
3. Cap reached. Page: "This month's 5 US dollars are used. Claude chooses again next month. Until then the rule book chooses alone." Card: "Claude could not choose: this month's 5 US dollars are used." (no pointer to Settings: nothing to fix there.)

**The row** Settings → Claude then reads "On, but not choosing · " followed by "key no longer accepted", "no credit left at Anthropic" or "this month's 5 US dollars are used".

**When it clears.** At the next answer with HTTP 200, or when a new key is typed and accepted (a key change). It is kept across restarts (it is a small per-device note, never in iCloud, never in the plan or a copy). The cap case also ends by itself when the month turns, because the meter does. The grey card line is shown on the card only while the trouble lasts, in the same grey as the other card lines; it carries no colour of its own and no button. It changes nothing in the card's menu, its buttons, its checks or its words. It is not read by the rule book and never sent anywhere.

**Unchanged:** one try of at most 20 seconds per card, the answer checks, the word check, the data sent, the 5-dollar cap, the log (a line is still written for every refusal, including these).

### X.2 A taken-over morning answer says so on every device

**Before.** Only the iPhone that took the answer over from AMS Magic Morning Routine (or AMS Workout Companion) showed "Feeling good — from Magic Morning" with the grey "Answered in Magic Morning — change it there." and kept it unchangeable. The diary document that travels through iCloud held only the value, so an iPad or Mac showed the answer as its own and offered to change it.

**Now.** The diary document gains an optional field `feelFrom` (day → the app that answered; `"morning"` for Magic Morning, `"workouts"` for Workouts, the same words as the note's `from`). It is written when an answer is taken over. When two devices meet (the iCloud merge), `feelFrom` follows the winning answer of the day: whichever device's answer for that day wins, its `feelFrom` (or its absence) wins with it, so a value is never shown with another answer's origin. An answer given in this app (the five faces, or a change of an own answer) removes that day's `feelFrom`. An older app version ignores the field and keeps writing the document as before; a newer version reading a document without it shows the answer as the user's own. iPad and Mac now show the same line, "Feeling good — from Magic Morning", and the grey line "Answered in Magic Morning — change it there."; the answer cannot be changed there. Everything else about taking over (first answer of the day wins, Mornings bars, rule book reading, Claude's numbers) is as in V.6.

### X.3 Sign fixes (a mark or colour means one thing)

1. **Year view, today.** Today's day square is outlined in **green**, the green of today everywhere else (before: a dark outline). The key under the months shows the green outline for "Today". Rest day stays a grey empty outline; race day stays red.
2. **Waiting to sync.** The "Waiting to sync" labels (cards, the session's page) and the waiting headline on a session's page are **grey** (before: green, which means done). Green means done only.
3. **"Send it now".** In the red warning at the top of Today (logging has waited more than a day; only while the plan is in Excel) the button "Send it now" is **green** (before: red). Red stays for the warning's frame and for things that take something away.
4. **Words beside marks.** The share mark says **"Send"** (a session's page, and photographs); the flag on Progress says **"The race"**; in Move, "+1" reads **"+1 day"**; the small mark on an extra reads **"Counts as training"** (before: marks alone).
5. **Sessions, the four numbers.** No number counts rest days any more (`PlanTab.filterCount`, rule `PlanOverview.countedInAll`; before: Upcoming and All counted rest days still to come, and so did the bar). All = Done + Missed + Upcoming, and the bar is drawn from the same three counts. The lists themselves still show rest days.
6. **Race day badge.** A race day's badge shows the **flag** (before: the general "other" mark), so the flag means the race everywhere (Progress, the Plan page's season bars, badges).

### X.4 Icons

All the app's hand-drawn marks now come from the central AMS icon library that every AMS app shares. Nothing looks different.

### X.5 Identifiers, signs, tests

* **Signs added or changed** (each with words in How this works → Signs in this app): the grey "Claude could not choose: …" line on a card; the grey line under "Key saved" and the row "On, but not choosing · …"; the green outline on Year; grey "Waiting to sync"; green "Send it now"; "Send", "The race", "+1 day" and "Counts as training" beside their marks; the flag on a race day's badge; the heart on "Log details" (Apple Health holds numbers for this session) is now listed there too; "Feeling good — from Magic Morning" is the same on iPhone, iPad and Mac.
* **Collisions checked:** green means done only (no waiting words, no warning in green except the one action that puts things right, a button, never a status); grey lines are information, each with words; red is the warning frame and what takes something away.
* **Tests:** one small data test per rule: the case chosen from each kind of answer (401, 403, 402, `billing_error`, the credit-balance message, the cap, 429, 5xx, timeout); clearing on HTTP 200 and on a key change; kept across a restart; `feelFrom` written, merged with the winning answer, removed by an own answer, ignored by the older shape; the count on All against Done + Missed + Upcoming. One screen test finds the new lines and buttons by their identifiers.

### X.6 What 2.4 deliberately does not do

* It does not buy, top up or change anything at Anthropic; it only says what happened.
* It shows nothing for a short hiccup (no network, Anthropic busy, HTTP 429 or 5xx): only the log.
* It does not change who may make cards (the iPhone only), the rule book, the plan or any figure.

## New in 2.4.1 (79) — season bars: a letter for easy and test weeks

**Also in 2.4.1: an iPad or Mac that shows an old workbook takes iCloud's plan.** Found on his Mac on 25 November 2026: a workbook bookmark and cached copy from September made `Store.hasNoPlanAtAll` false, so the device's `cloudRole` was `.excel`, which waited for a move-in page that only the iPhone has. The Mac went on showing the old Excel file, Today offered **Connect Dropbox** (`today-connect-dropbox`), and the status dot still read "Same on all devices". Rule now: `PlanMeeting.takesCloudPlanOverWorkbook(isPhone:cloudHasPlan:)` — true for an iPad or Mac when iCloud holds a plan; the meeting then adopts it (`PlanCloud.adopt` → `Store.adoptOverOldWorkbook` → `useCloudPlan`, the same path as the iPhone's "Use the plan from iCloud": anything waiting is written into that plan, the home becomes the app, the cached workbook stays on disk). The iPhone on Excel is unchanged (asked on its move-in page). Tests: data test `testAnIPadOrMacShowingTheOldWorkbookTakesTheCloudPlan`, screen test `ICloudUITests.testADeviceShowingTheOldWorkbookTakesThePlanFromICloud`.

One idea: **pale means one thing.** Only the season bars on iPad and Mac change; the iPhone has no season bars. Nothing in the plan, the rule book or the data changes. Version shown: 2.4.1 (79), 25 November 2026.

**Before (2.4).** An easy week was a pale bar (38 % strength) and showed "Easy" above it only where the bar was at least 26 points wide; a test week showed "Test" only where there was room, and nothing on a narrow bar. The key read "Pale = easy week · Tap a bar to see its week". Pale also means still to do (Year, By sport, the week card on Today), so one sign had two meanings.

**Now.**
* Every bar (`season-week-<n>`, identifiers unchanged) has its phase's full colour. Easy weeks are still shorter bars, because less is planned.
* **The letter rule** `PlanOverview.weekLetter(isEasy:isTest:)`: a test week shows "T"; otherwise an easy week shows "E"; otherwise nothing. A test week therefore always shows, also on a narrow bar.
* **Words instead of letters** from a bar width of 26 points: "Test" and "Easy" take the place of "T" and "E".
* **The key** (`season-key`): with letters, "E = easy week · T = test week · Tap a bar to see its week", naming only the letters that occur in the plan; with the whole words, "Tap a bar to see its week".
* **The outline** round the chosen week (or the weeks of the month) grows by the letter's height, so it goes round the letter too.
* Unchanged: bar height, phase colours, the Today line, the flag, tapping a bar, the screen-reader label.

**Signs.** Pale now means still to do only. The sign-check finding "pale has two meanings" is closed. How this works (Plan, the season bars; Season) and Signs in this app (On iPad and Mac, the Plan page) say it in the same words.

**Tests.** One small data test for `weekLetter` (test, easy, both, neither).

## New in 2.4.2 (80) — Not well? at the foot of Today, in grey

One thing changes: where the "Not well?" pill sits on Today, and its colour. Nothing in the plan, the rule book, the data or any other screen changes. Version shown: 2.4.2 (80), 25 November 2026.

**Before (2.3 to 2.4.1).** On Today the pill was a small bordered pill in the Today colour near the top: at the right end of the title "How do you feel?" while the morning question was open (`FeelCard`), otherwise on a right-aligned row of its own just under the morning line. The owner found it a very prominent place that "does not feel positive". At the foot of a session's page it was also in the Today colour.

**Now.**
* **Where.** On Today: one pill, centred, at the very foot of the screen, under everything else, under the Tomorrow block. It is no longer beside or under the morning question, and there is no row for it near the top. Shown on Today only once the plan lives in the app (unchanged). On a session's page (`StopSignButton`): at the foot, as before.
* **Style.** Small bordered pill, caption-size text, grey (`Theme.secondary`) on Today and on a session's page (before: the Today colour). It stays a button with its words, not a status mark; grey keeps its other meanings only for lines of information.
* **Identifier** unchanged: `not-well`.
* **What it opens** unchanged: the sheet "Not well?" with two rows, "Stop sign" (`stop-sign`) and "I'm ill" (`ill-button`), "Done" `not-well-close`; both pages behave as before.

**Signs.** The small grey pill "Not well?" at the foot of Today and of a session opens Stop sign / I'm ill. How this works (Today, the morning; Stop sign and I'm ill) and Signs in this app (Suggestions) say it in the same words.

**Tests.** No new rule, so no new data test. The existing screen test `SuggestionUITests.testStopSignPageOpens` finds the pill by its identifier `not-well`.

## New in 2.5 (81) — data kept safer, one number for one thing, a tidier look

Version shown: 2.5 (81), 25 November 2026. The base is the released 2.4.2 (80) plus one fix (the green "Done" tick's spoken name, lost in 2.4 when the drawn marks moved to AMS-Icons, is one accessibility element again). This section lists what 2.5 changes; where an older section says otherwise, this section is the newer.

### Kept safe

* **Thursday rides, one name per week.** `ThursdayRides.key(for:)` = `App!thu-<Monday of the ride's week>`. `Store.addSessions(_:why:)` passes it as `fixedKey` to `PlanBook.add(_:why:fixedKey:)` when `why == ThursdayRides.why`; if the book already holds that name, nothing is added and the existing session is returned. Two devices adding the rides before iCloud carried them over therefore make one ride per Thursday, and the meeting joins them by name (before: two, with random names). An ordinary new session still gets `App!<counter><random>`; a fixed name starts with a letter after the "!", so the two never meet. Data test: `testTwoDevicesAddingTheRidesMakeOneRidePerThursday`.
* **Suggestions never from a stale plan.** The suggestion keeper's input cache key and the plan version a Claude question was asked against both include `Store.bookVersion` (counts every plan put on screen, also a meeting's). After a change from another device the input is made afresh and a Claude answer for the old version is dropped (`claudeAnswered`), so "Take it" cannot write over that change.
* **Go back to Excel waits for iCloud.** See 3.x "Going back" above: `canGoBack` needs `!planIsShared` and `cloudChecked` (`cloud.root != nil && cloud.lastMet != nil`); `goBackWaits` shows the grey line `plan-go-back-waits`. `goBackToExcel()` notes `bookVersion` before it downloads the workbook and, if it changed, writes nothing and sets `homeProblem` "The plan changed while it was being written back. Nothing was switched; try again."
* **A taken-over morning answer keeps its time.** `NeighbourRules.takenOverMoment(_:now:)` = the note's own `at`, never later than now, now when it does not read. `Neighbours` passes it to `Diary.setFeel(_:on:from:at:)`, so an answer given later in this app on another device is newer by its mark and is not replaced. The "taken over" marker counts only while the diary still holds the `from` note (a merge that left no `from` means an own answer). Data test: `testATakenOverAnswerKeepsTheNotesOwnTime`.
* **Newest safety copy.** `Store.newestSafetyCopy()` orders by the moment the copy was made (`Store.copyMoment`), not by file name: `plan-<day>-before-0912` is newer than the start-of-day `plan-<day>` though it sorts before it. It is the copy taken when the plan file will not open.
* **iPad and Mac never log into the old workbook.** The logging gate (`canLog`) is `Device.isPhone && dropboxPath != nil && Dropbox.isConnected` when the plan is not in the app. On an iPad or Mac whose plan is not yet in the app, Today's header shows the grey caption "The plan is on its way from iCloud" (`today-plan-on-its-way`) instead of the Connect Dropbox chip (before: the chip; what was logged was lost when the device took iCloud's plan, 2.4.1).
* **An entry from the Excel days.** In `PlanBook.apply`, a queued entry made before the plan moved in (`createdAt < origin.takenAt`) is looked up with `Sync.findWorkout` (sport, and day or wording) and not by its stored row key, which may now name another session; if none is found it stays waiting with `BookError.noSession`. Its `completedAt` is the time it was made (`createdAt`), not the time it was written. Data test: `testAnEntryFromTheExcelDaysIsNotWrittenIntoAnotherSession`.

### One number for one thing

* **Sessions without rest days.** `PlanBook.trainingCount` (sessions whose discipline is not rest) is the count on Safety copies ("N sessions · M done · K changes so far"), on the iCloud page (`TwoPlansView`: "N sessions · M done", and the "N sessions, M done, last change …" line) and in "Plan from your iPhone · N sessions" (`PlanState.arrived`): the same number as the Sessions tab and Settings → Your plan. Data test: `testTrainingCountLeavesRestDaysOut`.
* **One way to write a length.** `formatDuration` writes "1h 10m" (the space is a non-breaking one, so a length never splits over two lines), "45m", "5m 30s" and, for nothing, "0m" (before: "0s"). It is used by the month chips and week cards (before: "45 min" below an hour), Thursday rides, Progress (`hoursShort`: "66h 08m", before "66h"), Today's health line and Garmin sleep (`GarminWords.sleep`: "7h 20m", before "7 h 20").
* **Plan page numbers.** By sport: "<done> done of <planned>", or "<planned> planned" while nothing is done. Plan followed: "<done> of <due> sessions due so far", plus the caption "<n> more done ahead of its day" from `PlanOverview.doneAhead` (sessions in the range recorded on a day after today; they count in the hours done, not in "followed"). The Load card: title "Load" with the note "last 12 weeks, up to today" (always about now, whatever week is chosen), "This week so far N · usual week M", the line "Load = minutes × how hard (1–10)", numbers by an en_GB decimal formatter with a real minus sign (`PlanNumbers.figure`), as on Progress. Data test: `testASessionDoneAheadIsNamedNotCountedAsFollowed`.
* **Progress words.** The race card: "done so far, of N in the plan". So far: "Of the M sessions due up to yesterday, N were done" (figure "done"). Consistency: "in a row now", "most in a row". "Which sport runs behind" and "Where the hours went": the percentage and the figure stand directly after the sport's name (fixed widths), the bar or the plan note after them. The foot line, the Missed-or-moved card and Your zones say nothing of the workbook when `planLivesHere`. Today's line in the road is `Theme.today` (before: the text colour).

### Looks, iPhone

* **Today.** The grey "Answered in Magic Morning — change it there." line has a line of its own: `GarminMorningRow(alone:)` is true only when there is neither a health line nor a taken-over answer. The Garmin line is a `ViewThatFits` that breaks between two figures (never after a " · "), last resort three lines. On a first run with no plan (`view.plan.isEmpty`) Today shows one grey line "No plan yet — Settings → Your plan brings it in." (`today-no-plan`) and no week card and no session card (before: "0s planned" and an empty card). The week card's hours stand under the title "This week" on the left; the bar stays at the right. "Rest / not a plan sport" is a row of its own in the week key.
* **Buttons.** `Theme.mainButton` is the full-colour main button's green, `#00875A` by day and at night (white words need the deeper green; `Theme.today` stays the bright mint at night for text and marks). `mainSmallButton()` is the small full-colour style. Used on a to-do session's "Done · 1h 10m" (`session-done-as-planned`), Save on the Garmin and Claude pages, and every full-width main button (Enter a test result, Save on the log, edit, extra and test forms, Add rides, Sync now, Use this one, the move-in buttons, Send it now). On the log form, "Use" for a Health workout is `.bordered` (only Save is full colour); a soft fade above Save shows the form runs under it.
* **Figures beside names.** Zone sheet rows (`zone-row`: label, then value, then a spacer); Progress SportCard and MixCard; the This week card; the date beside the version in What's new.
* **Settings sub-pages.** Garmin, Claude and The plan moves in use the small centred inline title (`garmin-title`, `claude-title`, `movein-title`) like the others; Cancel on The plan moves in is a toolbar item. "Save it" on a new extra is "Save" (`extra-save`). The Garmin morning plate (`MorningNumbersView`) is in a navigation stack with Done at the top right (`morning-plate-done`, Escape on a Mac).
* **How this works.** Each part's name is a heading (`.title3`, bold, `Theme.today`, header trait); a paragraph that opens with a short title line and a bullet list gets a bold heading (unchanged).
* **Night tint.** `Theme.stillToDo(_:)` = the sport's colour at 0.34 by day and 0.58 at night; used by the week strip's still-to-do bars (`StateFill`) and by the Year squares (`yearFill`), so the two agree and the sports read apart at night. By day nothing changes.
* **Smaller.** The zone sheet's height follows its content (`presentationDetents` `.height(content + 64)` and `.large`). Enter a test result: the boxes sit in one `Grid` (name, box 84 points, unit). The average heart rate box has the grey example "e.g. 135" (`LogForm`, `ExtraFormView`). A rest day in the Sessions list has no intensity pill when its text is empty or a dash. The iCloud page's Your devices box is full width. Photos: "On this phone only, and in the iPhone's own backup." on an iPhone, "On this device only." on an iPad or Mac, then " Not in iCloud, not in Dropbox.". Settings → Your plan on an iPad or Mac: "Lives in this app and in iCloud", or "Lives in this app — iCloud is off" when `cloud.status == .off`. Escape is Cancel on the Move page (`keyboardShortcut(.cancelAction)`). The "Done" tick's spoken name is "Done" (one accessibility element).

### Looks, iPad and Mac (the Plan page)

* **Month** (`MonthGrid(fitHeight:)`). The page tells the month the height left under the heading (`PlanPage.topHeight`); a hidden copy of the weeks with full titles is measured, and when it does not fit, every chip uses the short sport word (as in a narrow cell; the narrow-cell rule is unchanged). The Plan page's scroll view brings today's week row (`MonthGrid.rowID`) into view, anchored at the bottom, on appearing, on changing the view and on changing the month, only for the current month. The extra chip (`MonthExtraChip`) has the name on the whole width and the length and the paler tick on the line under it.
* **Week** (`WeekBoard.twoRows(in:)`). When four to six columns fit (`columns(in:)`), the week stands in two rows, Monday to Thursday over Friday to Sunday, each column `(width − 3 gaps) / 4` wide; no sideways swipe and no "swipe sideways" in the hint. Seven columns, or fewer than four, behave as before. A column's heading is "Mon 22 Mar" on a Monday and on the 1st of a month, otherwise "Tue 23". `BoardCard.keepTogether` joins ranges and units with non-breaking characters ("95–105 rpm", "Z3–low Z4", "4×3 min"); it is used on the week card and the month chip titles.
* **Heading.** The switch and the buttons stand on one line, the title and its time always on a line of their own under it (before: all on one line when the window was wide).
* **Year.** The hours of every month block stand on the second line, under the name; every block is padded to six week rows, so the blocks are the same height; Phases (`SeasonPhases(columns: 2)`) stand in two columns, each phase as its name with "dates · weeks · hours" under it (one column and one row each remains on the other uses).
* **Season bars.** `todayMark(skip:)`: the green Today line is drawn in two pieces, leaving the span of the E or T letter of today's week (`letterSpan`).

### Words in the guide

How this works, What's new 2.2 and this specification had wrong or old sentences corrected (the old Season page, Excel as the plan's normal home, the order of things on Today, and more). The guide's parts that changed with 2.5 are named at the end of the 2.5 entry in What's new.

### Tests

New small data tests: Thursday rides (`ThursdayRidesTests`), the taken-over morning moment (`NeighbourNotesTests`), an Excel-days entry (`PlanBookTests`), `trainingCount` (`PlanOverviewCountTests`), `doneAhead` (`PlanOverviewTests`). `ReadingTests` follows the new `formatDuration` ("0m" for nothing). No new screen test; the existing ones find their things by the same identifiers.

## New in 2.6 (82) — the Body page

Version shown: 2.6 (82), 25 November 2026. The base is the released 2.5 (81). One new page, **Body**, and one behind-the-scenes fix. Where an older section says otherwise (four tabs, five rows in the side list), this section is the newer. The page is shown only: it changes no plan and makes no suggestion.

### B.1 Where it sits

* **iPhone.** A fifth tab in the middle of the bar. Before: Today · Sessions · Progress · Settings (`today`, `plan`, `progress`, `settings`). Now: Today · Sessions · Body · Progress · Settings, the new id `body`. Each cell is a fifth of the bar. Identifier `tab-body`. Pressing the Body tab again does nothing special.
* **iPad and Mac.** Its own row in the side list. Before: Today · Plan · Sessions · Progress · Settings. Now: Today · Plan · Sessions · Body · Progress · Settings (six rows). Identifier `side-body`. On a Mac, Command + 1 to 6 choose a row.
* **Mark and colour.** A heart with a pulse line. The colour is raspberry, a deep pink, for the page's heading, its head card and its tab; no other part of the app uses it. (Exact values: see the code, `Theme`.)

### B.2 The page (identifier `body-page`)

* **Top line:** the day and when the numbers were read, "Wed 25 Nov · read 17:31".
* **Head card "Body Battery"** (`body-hero`): filled with raspberry, white words. The number now (example 40) with the word "now"; beside it "Highest today 82" and, when there were workouts, "2 workouts took 23" (the points the day's workouts cost: the sum of the drains of the workouts whose cost Garmin gives, others are not counted). Under it the curve from midnight to now, ending at a white dot (now); the rest of the day stays empty, no dotted line. An hour scale 00 · 06 · 12 · 18 · 24, and each of today's workouts as a short solid white bar above the curve (until 2.6 a tap on it did nothing; since 2.7 it opens a page, see "New in 2.7"), as long as the workout lasted, with its words above it and a thin white line down from each end ("Run −18", "Swim −9"; the bar runs from the workout's `start` to its `end`; no lighter or pale band). A workout whose cost Garmin does not give (`drain` is nil) shows its name only.
* **Four tiles**, each with the name in small capitals, the figure right beside its unit, one grey line and seven slim bars for the last seven days with the weekday letters under them:

| Tile | Identifier | Figure | Grey line |
|---|---|---|---|
| Sleep | `body-tile-sleep` | last night's time, "6h 10m" | "7-night average 5h 50m" |
| HRV | `body-tile-hrv` | last night's value, "48 ms" | "your normal 42–55"; while Garmin gives no range yet (`stillLearning`), "still learning your normal" (Garmin needs about three weeks of nights) |
| Resting pulse | `body-tile-resting` | today's, "52 beats" | "your normal 51" |
| Stress | `body-tile-stress` | today's average, "31 average" | "highest today 74" |

* All seven bars are the same full raspberry (no paler bars). A day without a reading shows a small grey dash "–" where its bar would be, never a zero (`DayValue.value` is nil). Today's bar is the last one; its weekday letter is bold and green (`Theme.today`, today's green everywhere).
* Lengths are written as everywhere in the app (`formatDuration`): "6h 10m", never "6 h 10".
* **Sleep is shown only.** It never leads to a suggestion (the owner's own decision).
* **Tap a tile** (`body-peek`): a small page with that instrument's seven days in numbers, newest first; title e.g. "Sleep · last 7 days"; the first row reads "Today" (for Sleep and HRV "Last night"); a day without data reads "no reading". Button Done (`body-peek-done`); on a Mac Escape closes it.
* **Foot** (until 2.6: "Tap a tile for its 7 days in numbers."; since 2.7 see "New in 2.7"): and "From your Garmin watch · shown only, it changes no plan."
* **Between midnight and about 04:00** the curve can be empty (the day has only begun); sleep and HRV then still show the night before (`nightDay`).

### B.3 Empty states

* **No Garmin key** (`body-connect`): "Connect your Garmin key to see your body's numbers here." and a full-colour button "Open Garmin settings" that opens the Garmin settings page right there on the Body page (the same page as Settings → Garmin).
* **A key but no numbers yet** (`body-empty`): "No numbers from Garmin yet. Wear the watch, sync it in Garmin Connect, then pull down here."

### B.4 Where the numbers come from

* **The key** is the personal key saved in Settings → Garmin, the same key the morning numbers on Today use (one key, two places; nothing new is stored for the key).
* **The calls** are `GarminClient.body(day:)` in `App/Sources/GarminClient.swift`: six small reads, any one of which may fail without losing the rest: the day's Body Battery report (`/wellness-service/wellness/bodyBattery/reports/daily`, with its activity events for the workouts' costs), the day's workouts (`/activitylist-service/activities/search/activities`), the sleep range, the HRV night and the HRV range, and the daily summaries (resting pulse, stress). Read only; nothing is written to Garmin.
* **The model** is `BodyDay` in `Core/Sources/WorkoutCore/BodyDay.swift`: `day` ("2026-11-25"), `readAt`, and the optional parts `battery` (`points`, `workouts` with `id`, `name`, `type`, `start`, `end`, `drain`; `now`, `highest`, `lowest`), `sleep` (`lastNight` in hours, `nights`), `hrv` (`lastNight`, `rangeLow`, `rangeHigh`, `stillLearning`, `days`), `resting` (`today`, `normal`, `days`) and `stress` (`average`, `highest`, `days`). `DayValue` is a day with a value or nil. `GarminBody.build` puts the pieces together; it forgives: a missing piece is nil or an empty list, never 0, never NaN. `GarminBody.drain` is the Board's rule for a workout's cost: Garmin's own activity event within 10 minutes of the start, else the reading at the start minus the reading at the end. `GarminBody.shownDays` = 7; the pulse's own normal looks back the same fortnight as the morning's.
* **When:** read when the page opens, at most once in 30 minutes; pull down to read now.
* **Kept on the device:** the last reading is saved in `garmin-body.json` (`GarminBodyFile`: the `BodyDay` and the time of the last try), so the page shows at once. Numbers only; the key is not in it. Nothing leaves the device except the question to Garmin.
* **The Mac Board keeps running.** The page shows four of the AMS Garmin Board's instruments (Sleep, HRV, Resting pulse, Stress) and its Body Battery, in the app's own look; it does not replace it.

### B.5 Switches and identifiers

* **Identifiers (new):** `tab-body`, `side-body`, `body-page`, `body-hero`, `body-tile-sleep`, `body-tile-hrv`, `body-tile-resting`, `body-tile-stress`, `body-peek`, `body-peek-done`, `body-connect`, `body-empty`.
* **DEBUG switches (new):** `AMSWS_FAKE_GARMIN` also gives the Body page invented numbers (see 14.6); `AMSWS_TAB=body` opens the iPhone on Body; `AMSWS_SIDE=body` opens the wide layout on Body; `AMSWS_BODY_PEEK=sleep|hrv|resting|stress` opens the page with that tile's seven days standing open (for a picture).

### B.6 Signs added

* Raspberry = the Body page (heading, head card, tab). A heart with a pulse line = Body (the small plain heart on Log details still means "Apple Health holds numbers from your watch").
* A white bar over the Body Battery curve, with its words above it and a thin white line down from each end = a workout. (Lighter and pale keep their one meaning, still to do.)
* The white dot at the end of the curve = now; the rest of the day stays empty.
* A small grey dash "–" in a tile's row of bars = no reading that day.
* A bold green weekday letter under a tile's last bar = today (green is today everywhere).

### B.7 Behind the scenes

GitHub's test run (`.github/workflows/tests.yml`) gives up on a test machine that never starts after 20 minutes (before: 30).

### B.8 Version history

* 2.6 (82), 25 November 2026: the Body page; the key in Settings → Garmin feeds Today's morning line and Body; the test run's start-up limit 20 minutes.

### B.9 What 2.6 deliberately does not do

It does not change any plan, make any suggestion (sleep least of all), write anything to Garmin, or replace the Mac's AMS Garmin Board.

### B.10 Tests

Small data tests for `BodyDay` and `GarminBody` (the readers, the workouts' costs, nil never 0). One screen test finds the Body page by `body-page`, its head card by `body-hero` and the four tiles by their identifiers.

## New in 2.7 (83) — tap a workout on the Body page, yesterday's line

Version shown: 2.7 (83), 25 November 2026. The base is the released 2.6 (82). Two additions to the Body page. Where the 2.6 section says otherwise (a tap on a workout does nothing; the old foot line; today's curve alone), this section is the newer. The page is still shown only: a tap writes nothing and changes no plan.

### C.1 Tap a workout

* **Before (until 2.6):** the workouts on the curve only showed; a tap did nothing. **Now:** tap a workout and a page opens.
* **Tap area.** The workout's words, its bar, or anywhere in the column under them, at least **44 points** wide. Neighbouring workouts share the room: where two tap areas would overlap they are cut halfway between the two workouts.
* **Identifiers.** `body-workout-0`, `body-workout-1`, … on the tap areas, in time order.
* **What opens, in this order** (the first that matches wins):
  1. **A planned session.** The plan has a session of that sport on that day: that session's page opens, right there on the Body page (the same session page as from Today), with the back arrow at the top left leading back to Body. Two workouts of one sport and two sessions of that sport on the day: the first workout opens the first session, the second the second.
  2. **An extra.** Otherwise, an extra of that kind on that day (for example a Walk extra for a walk from the watch): that extra's page opens, the same plate as when an extra is tapped on Today.
  3. **A looser match.** Otherwise, a walk or hike opens that day's run session; a swim, ride or run, or a multisport recording, opens that day's Brick or Race session.
  4. **The facts plate.** Otherwise a small plate (`body-workout-plate`) with the workout's own facts from Garmin: its name as the title (example "Morning run"), then "Started 06:45 · Lasted 1h 00m · Body Battery −17" (or "no cost from Garmin" when Garmin gives none), one grey line "Not in your plan and not among your extras for this day.", and Done (`body-workout-done`) at the top right; on a Mac Escape closes it.
* **Same day only.** Only the same calendar day counts. A rest day never matches.
* **The sport** is taken from Garmin's own sport name: swim, bike, run, strength, rowing, mobility (yoga, pilates, stretching), walk (walk or hike). Anything else is "other" and goes to the facts plate.
* **Opens only.** The tap logs nothing, writes nothing and changes no plan.
* **The session's page** opened from Body looks as it does from Today (its own green); only the back arrow belongs to Body.
* **The rule** is `BodyTap.targets` in the core (a pure function): it follows the rule a session's page already uses to offer the day's watch workouts for its log form (same day, same sport, a walk may be the run), but stricter, because here a wrong match would open the wrong page.

### C.2 Yesterday's line

* **Before (until 2.6):** the card showed today's Body Battery only. **Now:** yesterday's Body Battery is drawn too, as a thin line across the whole 24 hours, behind today's curve, with no fill under it. Today's curve is unchanged: the thick white line with a soft fill; the white dot is now.
* **Label.** At the top right of the card stands a short piece of the same line and the word "yesterday" (`body-yesterday`).
* **Look.** A thin dark line, a deep plum, darker than the card (`Theme.bodyYesterday`, `0x4E0A2C` by day, `0x45082A` at night; 1.8 points). Martin picked it on 25 November 2026 from one picture with three looks; the other two were a thin white line and white dashes.
* **Why not pale and not dotted.** In this app pale already means "still to do" and dotted already means "an extra outside the plan", so yesterday's line is neither.
* **No readings.** A day without yesterday's readings (watch not worn, or the first day) shows no second line and no word "yesterday".
* **Read.** One more small read from Garmin: yesterday's curve. **Kept.** Yesterday's curve cannot change any more, so it is read once a day and then kept on the device. It counts as whole when its last reading lies in the last half hour before midnight; a shorter one (the watch had not sent the evening yet) is read again at the next reading. Today's own read is exactly as in 2.6; yesterday is asked for by itself. The rule "at most one read in half an hour, pull down to read now" is unchanged. The readings are cut to yesterday's own 24 hours. Still shown only; nothing is written to Garmin.

### C.3 The foot of the page

Before: "Tap a tile for its 7 days in numbers." Now: "Tap a workout or a tile for more." The second line is unchanged: "From your Garmin watch · shown only, it changes no plan."

### C.4 Identifiers (new)

`body-workout-0`, `body-workout-1`, … (tap areas, in time order); `body-yesterday` (the word on the card); `body-workout-plate` and `body-workout-done` (the facts plate's grey line and its Done button); `body-workout-row-0`, `-1`, `-2` (the plate's rows: Started, Lasted, Body Battery); `body-foot` (the foot line). `body-hero` now sits on the card's row of figures (it still speaks the whole card), so the tap areas inside the card can be found.

Picture switches (test builds only): `AMSWS_BODY_WORKOUT=0|1…` opens that workout as a tap would; `AMSWS_BODY_NO_YESTERDAY=1` leaves yesterday's readings out of the invented day. The invented day now has two workouts (a morning run, strength at noon) and a day before it.

### C.5 Signs added

* A white bar over the curve = one of today's workouts; tap it to open its session, its extra or its facts.
* A thin line behind today's curve with the word "yesterday" = yesterday's Body Battery, for comparison only; neither pale nor dotted (reasons in C.2).

### C.6 Version history

* 2.7 (83), 25 November 2026: tap a workout on the Body page; yesterday's line; the new foot line.

### C.7 Tests

`BodyTapTests` (data): the matching order (session, extra, looser match, facts plate), the same-day rule, and the shared tap room (areas cut halfway between neighbours). `BodyDayTests` (data): yesterday's readings are cut to yesterday's 24 hours. Also there: a curve that stops in the evening is not kept as whole, an older kept file without yesterday still reads, and the facts plate's rows. Screen test `testAWorkoutOnTheCurveOpensItsSessionOrItsFacts`: the word yesterday and the foot line are there, the run's tap area is at least a finger wide and high and opens the run's session with a way back, the strength workout opens its facts and Done closes them.

## New in 2.8 (84) — Body in more depth, reminders, away mode, race page, notes beside a log, Garmin on a done session, Claude on the week

Version shown: 2.8 (84), 25 November 2026. The base is the released 2.7 (83). Forty-one of the 50 suggestions the owner was shown on 25 November 2026 are built here, in thirteen lanes. Four of his picks (a Mac menu bar app, a Deck Mate key, a line in PARAGON, an app tour) come separately and are not in this release. Where an older section says otherwise (four Body tiles, no notices, no Settings rows for Reminders, Weather, Away, Favourite sessions or Race and kit, Claude only choosing among the rule book's menu), this section is the newer. Everything new is shown only or is written by a tap, and no new thing changes the plan by itself. All examples are invented.

Shared rules of the release. (a) **The shelf** (D.1) holds the new things that must follow the owner between devices. (b) Per-device things live in `UserDefaults` or `Application Support` and are listed in D.14. (c) New signs are listed in D.15 with every near-clash. (d) The text of the guide, What's new, the signs and this section were written from the thirteen lane reports and checked against the code; where the two differ the code is named.

### D.1 The shelf (`Core/Sources/WorkoutCore/Shelf.swift`, `App/Sources/ShelfStore.swift`, step `shelf(_:)` in `PlanCloud.swift`)

* **What it is.** One small synced file, kept apart from the plan, the diary and the pause. On the device: `Application Support/shelf.json`, saved atomically before it is shown. In iCloud: `<container>/Sync/shelf.json`, beside `plan.json`, `diary.json` and `pause.json`. Format 1.
* **Entries.** Per key one entry: `value` (JSON text, bytes kept exactly), `stamp` (whole milliseconds), `device` (`Device.id`), `removed`. Merge per key: newest stamp, then the larger device id, then the larger entry bytes, so every device picks the same one (commutative, associative, idempotent). A removal is a tombstone and is never pruned, so an offline device cannot bring a value back. Limits: 64 KB for a value (`set` returns false), 200 characters for a key; sensible: under 2 KB an entry and the file under about 500 KB.
* **Tolerance.** An entry this build cannot read is kept as it was; unknown fields on an entry or at the top are written back. A local file that cannot be read is moved to `shelf-unreadable-<date>.json`, the shelf starts empty and the app opens; if it cannot even be moved nothing is written and nothing travels. An unreadable iCloud file is parked in "From iCloud unreadable" before it is written over; conflict copies are read and joined and only joined copies are cleared (the same `CloudFiles.read/write` path as the diary).
* **Meeting.** Step "4b" of `PlanCloud.meet()`, after the plan, the diary and the pause, never before or instead of the plan. Triggered as the diary is: launch and front, the 30-second heartbeat, an iCloud folder change, going to the background, and every local change (`ShelfStore.onChange` → `cloud.localChanged()`; one line in `Store.init`). iCloud off: it stays on the device. The one-off "Before iCloud" copy now takes `shelf.json` too. The shelf is in neither the safety copies nor Go back to Excel. DEBUG `AMSWS_RESET` empties it, and RESET/UI tests stay off iCloud (unless `AMSWS_FAKE_CLOUD`).
* **API for screens.** `ShelfStore.shared.value(T.self, for:)`, `set(_:for:) -> Bool`, `remove(for:)`, `has(_:)`, `keys(prefix:)`, `@Published revision`. Values are any `Codable`; dates as whole milliseconds; new fields need defaults.
* **Keys in use.**

| Key | Value | Written by |
|---|---|---|
| `favourites` | one ordered list, at most 40 templates | Favourite sessions |
| `away` | `{from, until, has:[pool, bike, gym, openwater]}` (removed when switched off) | Away |
| `session/<Workout.key>/brick`, `/stomach`, `/niggle`, `/openwater` | one small struct each | the log form's Save (the done page writes the niggle directly) |
| `gear/<uuid>` | one shoe or bike each | Shoes and bikes |
| `race/<race day, e.g. 2027-07-11>/pacing`, `/fuel`, `/checklist` | one entry each; the checklist holds items and ticks together | Race page |

* **Safety (r28-safety).** A shelf file that cannot be READ (for example on a locked device) blocks writing and is read again before the next use; only a file that cannot be understood is moved aside. Every refused `set` (at the eight call sites) shows a `Not saved` alert, even over a sheet (`ShelfStore`); the Away page stays open when its change is refused. Key sizes are tested (40 favourites at maximum length about 30 KB; a 141-item checklist under 32 KB).
* **Known risks.** Per key, the newest wins: two offline edits of the same key lose one. A fast clock wins. Tombstones are never pruned. A session moved by a changed key orphans its notes. No in-app way yet to put back a parked shelf file. Real two-device iCloud behaviour was not tried.
* **Design differences from the first design note** (`round-28/shelf-design.md`, the code wins): `away.has` holds four values (the note said three); the favourites list holds 40 (the note said 30); the race key is the race's day; the checklist is one entry with items and ticks (the note said a set of ticked ids); the favourites and race keys follow the code as listed above.
* **Tests.** `ShelfTests` (10): set/get/remove round trip; too-large and bad keys refused; stamp never goes backward with the clock set back; merge is commutative, associative and idempotent; a clock tie with the same device still agrees; a removal is not brought back by an older copy; unknown entries and fields survive byte for byte; a file that is not a shelf fails as a whole; a join with nothing in iCloud writes up and never empties; random interleavings of three devices end equal (300-round soak with clock skew).

### D.2 Body (`BodyView.swift`, `BodyMore.swift`, `BodyPage.swift`, `BodyDay.swift`, `GarminClient.swift`, `GarminReader.swift`)

Order of the page, top to bottom: heading; calm line (`body-calm-line`); the top card (`body-hero`, with `body-charge` and `body-yesterday` and the workout areas as in C); Body Battery · last 7 days (`body-week`); the range switch (`body-range`, `body-range-7`, `body-range-4w`, `body-range-12w`, `body-range-note`); six tiles (`body-tile-<instrument>`); Share (`body-share`, `body-share-note`); the foot (`body-foot`). Still shown only.

* **Week card.** Heading `BODY BATTERY · LAST 7 DAYS` in Body's colour; seven columns (`body-week-day-0…6`, oldest left); each a mini curve of that day over 24 hours (0 to 100, thinned to at most 48 readings, the last always kept), the weekday letter (today bold and in the green of today), the highest, then the lowest as whole points; a day without readings has `–`. A white dot on today's curve is now. The line "Under each day: the highest, then the lowest." The card is there when at least one day has readings. Garmin: the daily Body Battery report with start = 6 days ago and end = today answers a list of days; each reading (`bodyBatteryValuesArray` pairs of time and value, 0 to 100) is filed under the calendar day of its own time, whichever entry it came in, duplicates by time dropped; today's curve is the one already read. A held week is kept while it is exactly the seven days ending today and one of the six earlier days has readings.
* **Night's charge.** `BodyPage.charge`: the rise from the night's lowest reading (readings from 18:00 the evening before until midnight, from yesterday's curve; or only since midnight when that evening is not there) to the highest reading of the morning before 11:00 that is later than that low. A rise below 1 gives nothing. Words: `Charged +44 overnight`. On the top card beside the number.
* **Calm line.** `BodyPage.calmLine`: counts HRV against Garmin's range (below or above it), resting pulse against `resting.normal`, and Body Battery on waking against the morning's normal (the last two weeks); inside means less than the larger of 1 and 4 percent of the normal away (`BodyPage.within`, the morning line's rule). Only measures with a normal count; none gives no line. Words: `3 of 3 in your normal range`, with ` · HRV below it` (or above; `resting pulse below it`; `Body Battery on waking above it`) for what is outside. No colour, no advice, no suggestion.
* **Normal band.** HRV: Garmin's range as a band behind the bars; resting pulse: 0.96 to 1.04 of the normal. A grey outlined rounded box (stroke 1 pt at 45 percent) with the word `normal` at its left; the bar scale takes the band in (`BodyPage.bars(_:band:)`). Sleep, Stress, Steps and Intensity minutes have none.
* **Range.** `BodyPage.Span`: `7` ("7 days"), `4w` ("4 weeks"), `12w` ("12 weeks"). The longer ones turn every tile into weekly averages, oldest first, the last being this week (`BodyPage.weekly`): a week counts only its days with a reading, never a missing day as 0; a week with none has no value (a dash); each bar is named by its Monday, shown as its day of the month (twelve bars name every third). Today's figure stays today's; its grey line gives the span's average (`spanAverage`). The note "Each bar is one week's average, named by its Monday's date." The page of a tile's numbers has one row for each week and the same note; Intensity adds "A vigorous minute counts twice, as Garmin counts it." (`peekNote`).
* **Days kept** (`BodyHistory`, a file on the device): value per day for sleep, hrv, resting, stress, steps and intensity, plus when each longer view was last tried; nothing older than the span is kept. A longer view asks Garmin only from the first day of its oldest week that has no reading in any of the four older instruments (a day with any reading is held), at most once in 30 minutes for each view (`readHistoryIfDue`); an older kept file without the new fields still reads.
* **Tiles.** Steps: figure = today's steps grouped with a comma (`8,400`), unit `steps`, grey line `7-day average …`. Intensity minutes: figure = this week's total (Monday to today), unit `of <weekly goal>` when Garmin gives a goal, else `this week`, grey line `moderate <n> · vigorous <n>` (this week's minutes, Monday to today); the seven slim bars are the last seven days, so before Sunday they can add up to more than the figure; a day's value = moderate + 2 × vigorous (Garmin's way). A day with no steps at all is a day without the watch and is left out; a week of zeros gives short bars, not dashes. Breathing rate and blood oxygen are not built.
* **Share.** A capsule in Body's fill with the share mark and `Share`; renders `BodyShareCard` in the look on screen (day or night) through the share sheet (`SharedPicture`, `ShareSheet`); the line below reads "The picture shows your Garmin numbers of today."
* **Garmin calls and guessed shapes.** `/wellness-service/wellness/bodyBattery/reports/daily` for the week (list of days; readings filed by their own time: guessed); `/usersummary-service/v2/dailysummaries` for `movement.steps.{value,goal}` and `intensityMinutes.{moderate,vigorous,goal}` (the shape the Mac's Board code reads); sleep, HRV and the rest in chunks of 31 days for the longer views. None was called against the real service before the release.
* **Picture switches** (DEBUG): `AMSWS_BODY_RANGE=7|4w|12w`, `AMSWS_BODY_PEEK=<instrument>` (now also `steps`, `intensity`), plus 2.7's `AMSWS_BODY_WORKOUT`, `AMSWS_BODY_NO_YESTERDAY`.
* **Signs added.** Grey outlined box with `normal`; raspberry-filled word of the range switch; week bars named by their Monday (the last bold and green: this week); a dot on today's mini curve (now).
* **Tests.** `BodyMoreTests` (8): the night's charge from the evening before to the morning's high; the calm line states where the numbers sit and nothing more; weekly averages count only days with readings; the longer views keep today's figure and say their average; the normal band is inside the bars' scale; steps and intensity tiles and their parsing; the Body Battery week files each reading under its own day; the days kept decode from an old file and ask only for what is missing. Screen: `BodyUITests` (extended).

### D.3 Today (`TodayView.swift`, `TodayWeather.swift`, `WeekSoFarStrip.swift`, `ReturnLadderCard.swift`, `TodayWeatherRules.swift`, `WeekSoFar.swift`, `ReturnLadder.swift`, `Daylight.swift`)

Order of Today now (new things in bold): header; **away line** (`AwayTodayLine`); morning line and question; suggestion area; the week card; today's sessions, each followed by **the weather line**; directly under the session cards **Sunday card** (`SundayCardArea`), **The way back** (`ReturnLadderCard`) and **Your week with Claude** (`ClaudeReviewCard`) (moved there after the screen walks, so today's session stays near the top); extras and the rest as before; **Week so far** before Tomorrow; Tomorrow; Not well?.

* **Weather and daylight (picks 13, 14).** One grey line under today's outdoor session: `11° · feels 7° · breezy 5 m/s · rain likely 15–16 · Light until 16:12`; before sunrise `Light from 08:05`; after sunset the daylight part goes; the line breaks into two lines (no dot at the start of the second) when it does not fit one row. Outdoor = run, bike, brick, race, open-water swim, hike or walk; not a pool swim, strength, mobility, rest, nor anything with indoor, turbo or treadmill in its words. The hours = the plan's start time when a column named Time, Start or Uhrzeit holds one (and the plan's duration after it), else the daylight hours. Source: Open-Meteo (the same service as AMS Packing, no key), coordinates rounded to 0.1 degree, answer cached one hour, wind in m/s, °C. Location: when-in-use, reduced accuracy; the question is asked only when Today first shows an outdoor session with the switch on; `NSLocationWhenInUseUsageDescription` in `project.yml`. No permission or no network: the line is absent. Daylight is computed for the phone's time zone (`Daylight`, tested at two known places). Settings → Weather → "Weather and daylight on Today" (`settings-weather-switch`), on by default, per device (`UserDefaults`). Identifiers `today-weather`, `today-daylight`. Switch `AMSWS_FAKE_WEATHER=1`.
* **Week so far (pick 15).** Card `WEEK SO FAR` above Tomorrow (`week-so-far`, `week-so-far-<sport>`): per sport its mark and name, `1h 20m of 2h 30m` beside it, one slim bar (done = the sport's full colour, rest = `Theme.stillToDo`). The numbers are `PlanOverview.bySport` (as the Plan page) plus the extras that count as training as done only, and only for a sport the plan has that week.
* **The way back (pick 43).** `RuleBook.ladderStep` asked day by day gives the real steps: Rest, Two easy days, Week 1 back (half, all easy), Week 2 back (three quarters), Back on your plan; after a cold: easy and shorter, then the weeks (only if out seven days or more). The current step is a filled green stair, a step behind has a tick, a step ahead is pale. The words are the rule book's own sentences (the rule book has no minutes). While still ill the stairs ahead show lengths, not dates. Shown on Today while the grey ladder line shows and in the week after (`return-ladder`, `return-step-<n>`), and on the I'm ill page under its content. Switch `AMSWS_LADDER=1` (step 2).
* **Tests.** `TodayRound28Tests` (4): sunrise and sunset at two known places; weather words and which sessions are outdoor; the week so far per sport; the return stairs are the rule book's steps. Screen: `TodayRound28UITests` (compiled; assumes the fixture's 2026-09-16 has an outdoor session).

### D.4 Reminders (`Core/…/Reminders.swift`, `App/Sources/Reminders.swift`, `RemindersSettingsView.swift`)

* **Scheduling rule.** Local notifications only. Worked out on the device from the plan (`Reminders.schedule`: sessions, the clock, the switches), laid with `UNUserNotificationCenter` (notice identifiers start with `Reminders.idPrefix`; the test notice is `reminder-test-now`), laid again 1.5 seconds after any change of the plan or a pause and whenever the app comes to the front. Old pending notices with the prefix are removed first. While a pause or an illness is on (`PauseShare.stopOn` / `illOn`) nothing is scheduled at all. A time already past is skipped.
* **Evening reminder** (pick 11; default off, 20:00). Title `Training`, body `Tomorrow: Run · 45 min easy`, `Tomorrow: Swim 40 min · Strength 30 min` or `Tomorrow: rest day`. Seven evenings ahead. Lengths under an hour read `45 min`, longer use `formatDuration`. A tap opens Today.
* **Sunday card** (pick 16; default off, 18:00, its own switch). Notice `Next week: 7 sessions · 8h 40m`. A card on Today directly under today's session cards (`sunday-card`) from that time until Monday 08:00: blue head (`Theme.plan`) `NEXT WEEK`, the count, the total, the phase's name, the pill `E · easy week` or `T · test week`; rows weekday, sport badge, title, length; a small `Close` (`sunday-card-close`) puts it away until next Sunday (`reminders.closedCardWeek`). It shows only while the Sunday switch is on.
* **Missed session** (pick 42; default off, 08:00). `Yesterday's Run was not logged.` Category `reminder-missed-move` (with `Move to today`) or `reminder-missed`; actions `reminder-skip` (`Skip it`, `Store.markMissed`), `reminder-move` (`Move to today`, `Store.move`; left out when the plan cannot change or `SuggestionKeeper.note(forMoving:)` has an objection, the app's only existing rule-book check, a grey note that never blocks in the app itself), `reminder-done` (`It is done`: opens the session with its log form). Up to three sessions each morning, one notice each; only yesterday is asked. All three actions are iOS foreground actions: the app opens first; if the plan is not loaded within about eight seconds, or the session was logged or marked meanwhile, or the move is no longer allowed, the app opens on that session instead. The `amsworkoutsync://session/…` link opens a session on the phone layout only (a tap on the wide layout opens the app; Skip and Move still work).
* **Settings → Reminders** (`settings-reminders`, row `settings-reminders-row`, above the Calendar heading): a head card in Settings' slate, three switches with a time each (`reminder-evening-switch`/`-time`, `reminder-sunday-switch`/`-time`, `reminder-missed-switch`/`-time`), a plain line for what each sends, `Send a test now` (`reminder-test`, full green), `reminders-refused` (a calm line) with `Open iOS settings` (`reminders-open-settings`) when iOS refused, Cancel/Save (`reminders-cancel`, `reminders-save`; Escape is Cancel). The iOS permission is asked when the first switch is turned on (and by the test button if never asked). The row's line: `On — evening, Sunday, missed session` or `Off — evening, Sunday, missed session` when all three are off. The Weather section (D.3) stands directly under Reminders.
* **Per device.** `ReminderSettingsStore` in `UserDefaults`: `reminders.settings`, `reminders.closedCardWeek`.
* **Picture switches.** `AMSWS_REMINDERS_PAGE=1` (or `=denied`), `AMSWS_SUNDAY_CARD=1` (next week on Today, ignoring the switch).
* **Tests.** `RemindersTests` (5): tomorrow's line for one session, two and rest; the evening schedule skips a past time and fills a week; the Sunday total and card; the missed question with and without Move; silence while paused. Screen: `RemindersUITests` (2, compiled).
* **Not proven.** A real notice, the buttons, a cold-start opening of a session.

### D.5 Plan tools (`SessionSearch.swift`, `PlanPrint.swift`, `PoolCard.swift`, `SessionPurposeLine.swift`; core `SessionSearch`, `SwimSet`, `SessionPurpose`)

* **Search (21).** The Sessions page (iPhone tab Sessions, side row Sessions): field `Search sessions` (`session-search`) under the heading, `Clear` (`search-clear`). Core `SessionSearch`: fold (case and accents), every word must match, date words (weekday, month, year, day, `yyyy-mm-dd`). Groups `To come`, `Done` and `Missed` (only when one matches), newest first; rows are `SessionCard` or `ExtraCard` (`search-result-<n>`) with a grey line: `Notes: …calf…` or `Found in the title and date` (extras also begin with their date). Empty: `Nothing found for 'xyz'.` (`search-empty`). The four filters are hidden while searching. Command-F focuses the field (`KeyCommands`). Free text searched: notes and a long "Done" cell. Switch `AMSWS_SEARCH=<word>` (with `AMSWS_TAB=plan` on the phone, `AMSWS_SIDE=sessions` wide).
* **Print (22).** The Sessions page has its heading alone and under it one row of small word buttons: `Print` (`plan-print`), `+ Session` and `Ask about your plan`; `Print` is also in the wide Plan page's button row. Sheet `print-sheet` "Print the plan": `print-choice-this-week|next-week|this-month`, `print-preview` (A4), `print-cancel` (Escape), `print-save` (`Save as PDF`, share sheet), `print-do` (`Print`, the main button, the system print panel). Week landscape with a column for each day; month portrait calendar grid; black on white; each session a small sport-coloured bar plus the sport word in capitals, its length and zone words; week or month total and each sport's total. Fixed point sizes (paper). Sessions only: no extras, no done marks. Switch `AMSWS_PRINT=week|month|next`.
* **Pool card (24).** Swim session page, button `Pool card` (`pool-card-open`). Full screen `pool-card`: `Whole set 1,500 m` (`pool-total`), a row for each step (`pool-row-<n>`, e.g. `4 × 100 m · rest 20 s · Z3`, section heading above), the current row filled in swim blue, large `Back` and `Next` (`pool-back`, `pool-next`), `Done` (`pool-done`); `isIdleTimerDisabled` on while open. Text styles only (`.largeTitle`, `.title`). Core `SwimSet`: tolerant parser (`4x100`, `4 × 100m`, `200 easy`, `rest 20s`, `Z3`, joined by `+`, `then`, commas or new lines; headings Warm-up, Main set, Cool-down, Technique); what it cannot read (for example `1.5 km`) stays as a row of its own, unchanged; steps from the sections, from the title when the sections hold no distance. Switch `AMSWS_POOL_CARD=1`.
* **Why (41).** Grey footnote `Why: …` under the title of every non-rest session page (`session-why`) and on today's card (`showsWhy`). Core `SessionPurpose`: 21 kinds, reusing `RuleBook.labels`, `zones` and `sessionClass`; adds the sport, the length against the sport's median, the phase and the easy-week tag; an unknown kind has no line. The sentences are fixed text.
* **Tests.** `PlanToolsTests` (3): search matches every word anywhere, ignoring case and accents; the swim set reads the usual ways; every purpose has its own plain line. Screen: `PlanToolsUITests` (4, compiled).
* **Not proven.** The real PDF and the print panel; the purpose wording on the real plan.

### D.6 Away and No-gym version (`AwayViews.swift`, `NoGymViews.swift`, core `Away.swift`, `NoGymCircuit.swift`, `Suggestions.swift`)

* **Page.** Settings → Your plan → `Away` (`settings-away-row`: `Off - for a trip: say what you will have there` or `Until Wed 6 Jan - sessions you cannot do there are marked`); a small word button `Away` (`suggest-away`) at the top of Settings → Suggestions. Page `settings-away`: slate head card (`AWAY`, `Away until Wed 6 Jan` or `Not away`, `no pool, no gym`), switch `I am away` (`away-switch`), `From` (`away-from`), `Until` (`away-until`, the last day away), `WHAT I HAVE THERE`: switches Pool, Bike (or turbo), Gym, Open water (`away-has-pool|bike|gym|openwater`); switches and not ticks, because the tick means done. Cancel/Save (`away-cancel`, `away-save`; Escape is Cancel). Switch off and Save removes the `away` key. Follows the owner between devices (shelf key `away`).
* **Chip.** A grey `Pill` of words only (`away-chip`): `No pool while away`, `No bike while away`, `No gym while away`, and `No open water while away` for a swim whose words say open water. On `SessionCard` (everywhere it is used) and on the session page; only on open sessions inside the period. The chip reads the title and the description; the rule book only the title.
* **Today line.** One grey line under the heading (`away-today-line`): `Away until Wed 6 Jan · no pool, no gym`; a tap opens the page; only while today is inside the period.
* **Rule-book trigger `.away` (code AW)**, exact words of the lane report: "Rule: trigger AW "away: the session cannot be done as planned" (after S5 and the came-in-breaking card, before T3). Looks at the first open, non-protected, non-strength session of today and the next 2 days that lies inside the period and needs something he lacks (swim: no pool and no open water; bike/brick: no bike). Menu in this order, only M2/M5/M1: (1) swap with a LATER EASY session of the same plan week (not Friday, not key) that he CAN do there, no longer and no harder (zone top) than the planned one: the planned session then keeps the easy session's day if he can do it there (or is back), otherwise it is dropped in the same choice; (2) move to the first day after he is back, same plan week, never a Friday; (3) rest (never for a key session). Nothing added, nothing longer/harder; every limit L1-L13 judges each choice, so an EASY WEEK gives chip but no card (easy-week sessions may not go/move); week caps, "missed sessions are not made up" and calm rules (one card a day, two a week, none open) all apply. After any answer for a session it is not asked about again. Strength without a gym never gets a card: chip + "No-gym version" (which changes nothing; the rule book cannot show a card with no change)."
* **Card words.** `Mon swim: no pool while away -> easy run 40 min (swim moves to Thu)`; `… -> easy run 40 min instead`; `… -> Thu, after you are back`; `… -> rest`. Why: `Why: you are away until 16 Jan without a pool; an easy run keeps the day aerobic.` (move: `…; it waits until you are back.`; rest: `…; missed sessions are not made up.`). The arrows are the app's own arrows in the card text. Input: `input.away` is part of the check key of `Suggestions.swift`.
* **No-gym version (20).** Strength session page: word button `No-gym version` (`nogym-open`), always; filled with `First choice while away without a gym` (`nogym-first-choice`) while away without a gym. Sheet `nogym-card`: head card in the strength colour (`NO-GYM VERSION`, N rounds, 8 moves, about X min planned), a warm-up line, 8 moves (6 when planned time is 25 minutes or less) with reps or seconds, `N rounds · 60 seconds rest between rounds`, a cool-down line, a calm note, `Done` (`nogym-done`). Text only; changes nothing. `NoGymCircuit.build(plannedMinutes:)` picks the number of rounds (1 to 8) that lands nearest the planned length.
* **Compatibility (changed after the safety review).** Away cards are written in `suggestions.json` under a separate key `later`, with their place in the list; builds without the trigger skip that key and read the rest, and this build puts every card back in its place (`SuggestionKeep`; tested with the old trigger list). The file lives on the iPhone only. Claude's menu prompt uses the generic text for this trigger and was not tried with the real service.
* **Switches.** `AMSWS_AWAY_PAGE=1`, `AMSWS_AWAY=nopool` (an invented period from yesterday to +5 days with only a bike; never stored), `AMSWS_NOGYM=1`.
* **Tests.** `AwayTests` (9): a swim without a pool swaps with the easy run; a swap with a drop when the swim would still be away; a swim he can do gives no card; a bike without a bike, and the easy week; strength without a gym gets no card; no card after he is back or before he leaves; away never adds or makes harder (and Keep my plan); today's line and the period's edges; the no-gym circuit at three lengths lands within five minutes. `swift test --filter "RuleBook|Away|Suggestion|Claude|Shelf"`: 120 tests, 0 failures. Screen: `AwayUITests` (3, compiled).

### D.7 Favourites and repeating (`Favourites.swift`, `FavouritesSettingsView.swift`, `RepeatSession.swift`, core `Favourites.swift`, `RepeatRule.swift`)

* **Favourites (18).** Session page, under the title: `Save as favourite` (`favourite-save`), then `In your favourites` (blue words, same id). A template holds sport, title, purpose text, length and zone; no day, nothing logged. Full (40): the red line `Your favourites are full (40). Remove one in Settings first.` Core: `isFavourite` = same sport and normalised title; add, rename, remove, move; text clipped small. New session page, top: `Your favourites` (`favourites-block`), tiles `favourite-tile-<n>` (mark, title, length); a tap fills sport, title, length, zone and purpose; the day and Key session stay; a caption says everything can still be changed. Settings → Your plan → `Favourite sessions` (`settings-favourites`): blue head card (`favourites-head`, `favourites-empty`), rows `favourite-row-<n>` with handle `favourite-handle-<n>` (three drawn lines, explained in words under the list), `Rename` (`favourite-rename-<n>`; a Cancel/Save alert) and `Remove` (`favourite-remove-<n>`; `Remove this favourite?`; on an iPhone the question shows the red action only and a tap beside it keeps things as they are), `Done` (Escape). Drag: own handle and `DragGesture`, no `onMove` (the same on iPhone, iPad and Mac); VoiceOver `Move up` and `Move down`. Shelf key `favourites`.
* **Repeat (19).** New session page: row `Repeat` (`repeat-row`): `Does not repeat` / `Every week until` with a date (`repeat-until`; default eight weeks, never past the plan's last day, not before next week). Below: `7 sessions: Thu 3 Dec, …` (`repeat-list`), left-out lines (`repeat-left-out`) `Thu 24 Dec left out — that day already has a Bike session with this title` / `— it is in race week` / `— it is outside your plan`, and the rule book's grey line if any (`repeat-note`, from `SuggestionKeeper.note(forChanging:)`, for the first six repeats, never blocking). Race week = a week whose tag says race week. Save adds the session and its repeats in one `store.addSessions` call with the reason `Repeated every week: <title> (N sessions) #<batch>`. An existing session: `Repeat…` (`session-repeat`) opens a small page (Cancel; full-colour `Add N sessions`, `repeat-add`).
* **Changes to the plan.** The sessions of one repeat show as one entry (`N sessions: title`, their days), `change-repeat-<n>`, with one Undo (`N sessions are taken out of the plan again`), which undoes each session that can still be undone and skips sessions logged, marked missed or waiting to be written since (the dialog says they stay). `Save` and `Add N` ignore a second tap; a repeat is one `addSessions` call (all or none). Thursday rides stay one entry each.
* **Switches.** `AMSWS_FAVOURITES_PAGE`, `AMSWS_ADD_WITH_FAVOURITES`, `AMSWS_REPEAT`.
* **Tests.** `FavouritesRepeatTests` (7): the list's rules; it stops at forty; a template holds no day; a repeat skips race week, the same session and the end; it skips a day that holds the same sport and title; it never goes past the plan; one batch mark runs through the reason line. Screen: `FavouritesUITests` (3, compiled).
* **Not proven.** A drag on a real screen (iPhone or Mac); auto-scroll while dragging a long list; the Settings row's count may not refresh until the page redraws.

### D.8 Notes beside a log (`LogExtras.swift`, `FuelNotes.swift`, `NigglesCard.swift`, `LogExtrasDebug.swift`, core `LogExtras.swift`)

Four extras (`LogSave.step`: the notes are kept first; if they cannot be kept nothing is logged and a `Not saved` alert says so; notes alone never call `store.log`; a second tap on Save does nothing), kept on the shelf (`session/<Workout.key>/brick|stomach|niggle|openwater`), written when the log is saved and removed again when cleared. The plan, the log's own fields and the way a session is saved are untouched; an extras-only save is allowed. The log form has a heading `Notes beside the log` (`LogExtrasSection`); a done session's page has `Your notes on this session` with tiles, a `Niggle?` or `Change niggle` button and a `Change notes` sheet (`Notes on this session`, Cancel/Save) writing the others.

* **Brick log (23).** Brick sessions only. Boxes `Bike time` (`brick-bike`, hint 1:10), `Change-over` (`brick-change`, 1:30), `Run time` (`brick-run`, 40). Bike and run as `parseDuration` reads them; the change-over as minutes:seconds (`parseMinutesSeconds`: `1:30`, `2`, `45s`). When all three are there and the sum differs from the length box, an outlined button (`brick-use-sum`) offers to use the sum as the length.
* **Stomach OK? (29).** Sessions of 90 minutes or longer (planned, or the logged length). Words `Fine`, `So-so`, `Upset` (`stomach-fine|soso|upset`; one more tap takes the answer away), a line `What did you eat and drink?` (`stomach-line`), and `Fuel notes` (`fuel-notes-open`): every answer, newest first, under a head card `12 long sessions · 9 fine · 2 so-so · 1 upset`.
* **Niggle (30).** Places Neck, Shoulder, Back, Hip, Thigh, Knee, Shin, Calf, Achilles, Foot, Other; a side (left, right, both) for the places where one makes sense (not Neck, Back, Other); a line. `Niggle?` page: Cancel, Save, Remove; the line "A note for yourself. Nothing here is advice or a diagnosis."; an error `Pick where it is first.`. Done line `Niggle: left calf — tight after the hills`. **Progress** gets a card `NIGGLES` (`NigglesCard`, at the end of the counts, purple head): `N noted on M places`, each place with how often and since when (`Left calf · 3 times since Mon 2 Nov`, left and right apart, most often first), every note by date, `… earlier ones are kept.`, and the grey line `If something hurts, the Stop sign page is under Not well?`. The suggestion called it "shows on the timeline"; the card on Progress is what was built.
* **Open-water notes (31).** Swim sessions only: switch `Open water`, `Wetsuit` Yes/No (`openwater-wetsuit`, `openwater-wetsuit-no`), `Water temperature` (°C), a line `Sighting and conditions`.
* **Chosen word.** A chosen word is a filled blue button (`ChoiceWord`, `Theme.plan`), with no tick; answers are uncoloured.
* **Tests.** `LogExtrasTests` (4): the brick sum only when all three are there; the stomach tally and tolerant decoding; niggle counting and words; open water and keys. Screen: `LogExtrasUITests` (compiled). Switch `AMSWS_DONE_EXTRAS`.

### D.9 From your watch on a done session (`GarminActivityReader.swift`, `DoneSessionGarmin.swift`, `GarminClient.swift`, core `GarminActivity.swift`)

Placed on a done session's page after "What you did" and the notes, before the photographs (one line in `SessionView`). Shown only; nothing is written to the plan or Garmin.

* **From your watch (26)** `watch-section`: the route as a line in the sport's colour (`watch-route`; hidden for indoor, pool or no track) and the pulse curve `Average 138 · Highest 156 beats` (`watch-pulse`).
* **Laps (27)** `watch-laps`: columns Lap, Distance, Time, Pulse, plus `km/h` (Garmin's own average speed) and `Watts` only when Garmin gives them; no pace is worked out. The first 12, then `Show all 27 laps` (`watch-laps-all`).
* **Last time (28)** `last-time-card`: `Last time · Wed 16 Sep`; Length, Distance, Average pulse and How hard, each as `now ← last time`; header `This session ← last time`. The same kind = same sport and same title, ignoring case, punctuation and spacing. Shown without a Garmin key (the plan only).
* **Time in zones (35)** on Progress, in the fitness group (`ZonesWeekCard`, `zones-card`): `Time in zones · this week`; Z1 to Z5 with the minutes beside the name (`zones-bar-1…5`), `· last week …` in words, five slim bars in Progress' purple; a grey plan line (`zones-plan-line`), `The plan asks for mostly Z1–Z2 this week`, only when this week's sessions name zones (`GarminZoneWeeks.planLine`: each planned session spreads its length over the zones its intensity names; the zones that together hold at least 60 percent of the planned time, taken from the heaviest down, give the range).
* **Garmin calls** (`GarminClient`): `/activitylist-service/activities/search/activities` (`startDate`, `endDate`, `limit=99`, `start=0`; the list, with `hrTimeInZone_1…5` read as pulse-zone seconds), `/download-service/files/activity/<id>` (the recorded file: route, pulse, laps) and, when the file holds no laps, `/activity-service/activity/<id>` (Garmin's own split list). All shapes are guessed; nothing was called against the real service; a missing piece does not show. Answers are kept per device in `Application Support/garmin-activities`; `GarminReader.keyChanged` forgets them.
* **Switches.** `AMSWS_FAKE_GARMIN` (with `AMSWS_SESSION=<key>` or `AMSWS_HURTS=1` on a done session), `AMSWS_ZONES_CARD=1` with `AMSWS_TAB=progress`.
* **Tests.** `GarminActivityTests` (6): two runs on one day are not mixed up and a swim is never a run; the list is read forgivingly; laps from the detail answer keep only Garmin's own numbers; the recorded file gives route, pulse and laps; the same kind and the last-time card; time in zones this week against last and the plan's words. Screen: `GarminActivityUITests`.

### D.10 Progress (`ProgressLook.swift`, `MonthReview.swift`, `PersonalBests.swift`, `TestHistory.swift`, `SteadyWeeks.swift`, `MonthReport.swift`; core `ProgressReviews.swift`)

One hook line (`ProgressRound28()`) puts the new cards under the cards that were there before (after the screen walks), in this order: Month in review, Steady weeks, Your bests, Tests; on a wide window side by side (`ProgTileGrid`, equal rows, 2 to 4 across by width). Nothing new is stored; morning answers already travel by the diary, tests by the plan. Local look: `ProgressLook.fill` (`0x7C3AED` by day, `0x6D28D9` at night, white words) and `.tile` (a light purple tint), the hue of `Theme.progress`.

* **Month in review (32).** `month-review`: purple head `MONTH IN REVIEW` / `November 2026` (`month-review-title`); tiles `HOURS` (done, `done of 16h 40m planned`, `month-hours`), `SESSIONS` (`month-sessions`), `PLAN FOLLOWED` (`PlanOverview.followed`, `7 of 8 sessions, as on the Plan page`, `month-followed`), `LONGEST SESSION` (`month-longest`); `HOURS PER SPORT` (`month-sports`; `2h 30m of 3h 00m` with a slim bar); `HOW YOU FELT` (`month-felt`; `Bad 0 Tired 1 OK 0 Good 2 Great 0`, or `No morning answers this month`); closing line (`month-closing`) `7 of 8 sessions done, 14h 20m of 16h 40m planned. Longest: Bike, Wed 9 Sep, 2h 30m.` Shown for the month before today (from the 1st); `Earlier months` (`month-review-earlier`, `month-review-earlier-<yyyy-mm>`) lists every finished month back to the plan's first. Extras are not in the hours.
* **Your bests (33).** `bests-card`: `LONGEST RIDE`/`RUN`/`SWIM` (`best-ride|run|swim`: time, the distance beside it when logged, the date; a grey `Farthest: …` only if another session went farther; a tap opens the session), `BIGGEST WEEK` (`best-week`; `Week of …`), `LONGEST ROW OF WEEKS` (`best-row`; `Ending the week of …`). Logged, not-missed plan sessions only; extras are not counted.
* **Tests (34).** `tests-card`, heading `Tests`; one tile each, `test-series-pulse|power|swim` (named Threshold pulse, Bike power (FTP) and Swim pace, shown in capitals; the unit beside the figure is bpm, W and "per 100 m"): the newest value big beside the name, a grey line (`Steady since Test 1`, `Was 200 at Test 1`, `First value, Test 1`), large purple dots, a faint line, the test's first day under each dot (`14 Sep`); equal values at the same height; the swim chart higher = more seconds (slower), no judging. Shown whenever at least one test has a number (`TestHistory.series`: a tile only for a measure with at least one value; no values at all, no card), whether the plan lives in the app or not.
* **Steady weeks (36).** `steady-weeks`: `WEEKS IN A ROW WITH THE PLAN FOLLOWED`, the count big with `weeks`, twelve squares (`steady-square-1…12`, oldest first; full purple = followed, outlined = not), `now` under this week; a key line under the squares (`steady-key`): full square = followed, outlined square = not followed. Followed = the Plan page's figure ≥ `SteadyWeeks.threshold` (90, one constant, tested). This week adds one when followed and never breaks the row; a week with nothing due counts as not followed.
* **Report as PDF (38).** A full-colour purple button `Report as PDF` with the share mark (`icon-share`) on the month card (`report-pdf`) → page `report-page` listing exactly what is in it, `Make the PDF` (`report-make`, purple) and `Cancel` (`report-cancel`, Escape) → an A4 PDF made with `ImageRenderer` and a `CGContext` PDF → the system share sheet (`ActivitySheet`; the Mac saves through it). Page 1: month facts, hours per sport, a week-by-week table (done of planned per sport), tests, zones. Page 2 (and more only beyond 40 sessions): morning words per day, the sessions list (day, sport, title, planned, done or Missed, how hard 1 to 10). The paper colours are fixed light.
* **Switches** (DEBUG; use `AMSWS_FILE`, `AMSWS_HOME=app`, `AMSWS_TODAY` such as 2026-10-02 with `UITests/Fixtures/plan.xlsx`): `AMSWS_MONTH_REVIEW`, `AMSWS_BESTS`, `AMSWS_TESTS_CARD`, `AMSWS_STEADY`, `AMSWS_REPORT`; they add invented mornings and tests when there are none and let the month card show today's month.
* **Tests.** `ProgressReviewsTests` (5): the month in review agrees with the plan followed; steady weeks use the threshold and the current week never breaks the row; bests come only from logged sessions and the biggest week; test history shows equal as equal and never judges; the report facts clip weeks to the month and list every session. Screen: `ProgressRoundUITests` (5, compiled).
* **Not proven.** The PDF was never rendered or opened (fonts, page fit); spacing and the fit of twelve squares; dot labels with many tests; light and night looks.

### D.11 Claude on the week and on a question (`ClaudeReviewView.swift`, `ClaudeAskView.swift`, `ClaudeClient.swift`, `ClaudeSettingsView.swift`, core `ClaudeReview.swift`, `ClaudeAsk.swift`, `ClaudeTrouble.swift`)

Shared plumbing: `ClaudeClient.run(...)` was added beside `pick()`: the same key, meter, 5-US-dollar cap, log, refused state and one 20-second try. Log rows have a kind and a label (`Wrote the week review`, `Answered a question` with the question); a paid-for answer that the app refuses is logged with its cost. `ClaudeTrouble.restLine` was added. Model and effort are the pick's (`claude-opus-5-5`, effort low, the same beta and route); `max_tokens` 1200; the stop reason must be `end_turn`. The key, the meter and the log stay per device.

* **Your week with Claude (39)** (`ClaudeReviewCard` under the suggestion area; window Sunday 17:00 to the end of Monday by the device clock, `ClaudeReview.window`; one review for each week; only when the plan lives in the app, because the suggestion input must exist). Green head (`Theme.mainButton`, white words) `YOUR WEEK WITH CLAUDE`. Before: `Five short lines about the week, and one question to think about.`; the body `This week's training numbers and your answers to the two questions — no names, no notes. It counts toward the 5 US dollars a month.`; the full-colour `Write my week`. After: the question in the head, five lines, `Written by Claude from this week's numbers. Kept under Settings → Claude.` Not passed: `Claude's answer did not pass the app's check — nothing shown.`; nothing came back: `No answer came back. Nothing was changed.`; refused: the calm line `Claude is resting: …` replaces the button. Kept per device (`UserDefaults` key `claude-reviews`, one for each week, the last 12), listed in Settings → Claude under the log as `Your weeks with Claude` (`claude-review-saved-row`). Identifiers: `claude-review-card`, `-write`, `-line-1…5`, `-question`, `-sent`, `-message`, `-trouble`.
  * **Sent, exactly:** the week's dates Monday to Sunday; minutes done and planned for each sport and in all; the five morning words for each day (or `no answer`); the effort 1 to 10 of done sessions beside the plan's own effort text (at most 8); the number of missed sessions (with day, sport and minutes), moved, changed or dropped; the extras (activity, minutes); the number of suggestions taken, kept or otherwise answered, and the headlines of those taken; next week's plan day by day (sport, minutes, effort text). **Not sent:** names, notes, session titles, photographs, tests, zones, weight, Health or Garmin numbers.
  * **System prompt in short** (the exact text is `ClaudeReview.system`): a calm look back at one week, only the week's numbers, a JSON answer `{"lines":[5],"question"}`; each line one plain sentence of at most 120 characters; no praise or blame; no medical talk; never sleep; only numbers that appear; one question of at most 140 characters; not advice.
  * **Check:** exactly 5 lines, each at most 140 characters; the question ends with `?` and is at most 160; no blocked words (doctor, sleep, heart, pain, …, the pick's list); no praise words; no links or marks; the rule book's word check (healthy, fit, safe, your heart); no number that was not in the sent facts.
* **Ask about your plan (40)** (`ClaudeAskButton`: small button `Ask about your plan` in the row of word buttons under the Sessions heading in `PlanTab`, under the heading row of the wide Plan page, and a row of the same name in Settings → Claude). Page: blue (plan) head card, what is sent (`claude-ask-sent`), the field (`claude-ask-field`; hint `Why is Thursday's ride only 45 minutes?`), three example chips (`claude-ask-example-1…3`; a tap fills the field), the full-colour `Ask` (`claude-ask-send`), the last five questions as tiles `YOU ASKED` with their answers (`claude-ask-answer`, older `-answer-2…`), `Clear` (`claude-ask-clear`, red, takes them away), `Done` (`claude-ask-done`, Escape), `claude-ask-message`, `claude-ask-trouble`. Last five kept per device (`UserDefaults` key `claude-ask-history`).
  * **Sent, exactly:** the question (at most 300 characters); today's date; the phase and the week number and tag; the rule book's limits in words (12 lines, the numbers from `RuleBookSettings`); the zone names only (no figures); this week and the next two, day by day: sport, minutes, effort text, `(done)` or `(missed)`. **Not sent:** titles, notes, tests, weight, Health or Garmin numbers.
  * **System prompt in short** (`ClaudeAsk.system`, 127 words): explain the plan and the rule book in plain British English in at most 120 words, only from what is given; never change the plan; point to Move, Change or the suggestion card; no medical advice (the doctor line); no race-time promises; say Zone 2, never heart rate, pulse or HRV; never sleep; JSON `{"answer"}`.
  * **Check:** at most 900 characters; the same word check (an answer holding doctor, sleep, heart, healthy … is not shown); no links or marks.
  * **Illness and pain words** in the question (ill, sick, fever, pain, hurt, injur, ache, chest, …): the app answers itself, `That is a question for a doctor. The app's Stop sign page is under Not well? at the foot of Today.` Nothing is sent, no cost, nothing in the log.
* **Switches.** `AMSWS_FAKE_CLAUDE` with `AMSWS_CLAUDE_REVIEW=1` (the answered card) or `=write` (the button; a fake answer on tap); `AMSWS_CLAUDE_ASK=1` (one question and answer) or `=empty`. The window uses the device clock, so a picture needs the switch.
* **Tests.** `ClaudeReviewTests` (12 new; with the old ones 39 pass in `--filter Claude`): the window is Sunday evening until Monday night; the facts hold numbers and words but no titles; five clean lines and a question pass; anything off is not shown; the answer is read only after an ordinary end; the request uses the pick's model and a small limit; one review for each week and twelve kept; illness and pain questions are never sent; the question request holds plan, rules and zone names only; question text is tidied; the answer passes the same word check; only the last five questions are kept. Screen: `ClaudeReviewUITests` (4, compiled).
* **Not proven.** The real service was never called (no key): the live JSON shape and how often Claude's lines pass the number check; if too many are refused the number check is the first rule to relax. Claude's menu prompt for the AW trigger (D.6).

### D.12 Mac, iPad, Spotlight and Siri (`KeyCommands.swift`, `SpotlightIndex.swift`, `AppIntents.swift`, `WideRoot.swift`; core `SystemWords.swift`, `KeyGuide.swift`)

* **Keys (45).** In the side list's foot the word `Keys` (`keys-open`); also `?` and Command-/. Plate `Keys` (`keys-plate`): a head card in Settings' slate and one tile for each key (`keys-row-0…7`, `keys-done`): Command 1 to 6 pages; Command N a new session on the day shown or today (only where the plan can change); the arrows the week or month on Plan (not while typing, not with a session page or a sheet open); Command T jumps to today; Space on an open session = Done as planned, only while no sheet, alert or dialog of the page is up (`spaceLogs`; before, a space typed in the Why? box of the missed question could log the session) (that button has no confirmation in the app, so none here: one tap is one press); Command F focuses the field `session-search` (does nothing when absent); Escape closes (Cancel on every edit page; Done on the Keys plate). Hooks: `WideRoot` (the word, hidden key buttons, two sheets, `systemLinks`), `SessionView` (Space on Done).
* **Spotlight (46).** The next 14 days still to do and the last 14 days done, `Tue 1 Dec · Swim · 40 min`, keywords sport, weekday and title words; rebuilt 1.5 s after any change of the plan; emptied when the plan is empty and rebuilt when the plan moves home (Go back to Excel changes the keys). Link `amsworkoutsync://session/<key>`, also from a Spotlight result.
* **Siri.** `What's my session today/tomorrow in Triathlon`, `Log today's <sport> as done in Triathlon`, `How is my week in Triathlon`. Logging uses `Store.logAsPlanned`; it refuses, changing nothing, for none, two, already done, missed, no length, or logging not allowed on this device. Plan not loaded: opens the app. All three intents need an unlocked device; there is exactly one `Store` (`IntentStore.shared`). The app uses `IntentStore.shared` as its store; `systemLinks` on the phone.
* **Stored.** Nothing new.
* **Safety of the readers.** The FIT reader uses `Int(exactly:)` and reads nothing over 32 MB; `GarminMorning.number` drops NaN, infinite and absurd numbers; weather figures are bounded; the weather request sends only coordinates rounded to 0.1. A cancelled re-plan of notices stops (identifiers fixed per day and session, old ones removed by prefix before each lay). Test class `Round28SafetyTests` (5): older-build read of away notes, `LogSave` never logs for notes, a repeat's Undo keeps a logged session, hostile FIT/zip/numbers, shelf key sizes.
* **Tests.** `SystemWordsTests` (6): the Spotlight window and words; the spoken day; the week sentence; log-today's-run picks only one open session; the session link round trip; the keys list and the new session's day. Screen: `KeysUITests` (compiled).
* **Not proven** without a signed build on real devices: the Siri phrases and speech; Spotlight results and opening; hardware keys (the arrows and Space without a modifier must not fire while typing); the hold-Command list's names; Command-F focusing the other lane's field.

### D.13 Race page and Shoes and bikes (`RacePage.swift`, `RaceEditViews.swift`, `GearView.swift`; core `RacePlan.swift`, `Gear.swift`)

* **Race page (25).** (Look after the screen walks: red is only the head card, the headings and the tile names; every action button is the plan's blue, full colour for `Type your times` and `Add a row`, outlined for `Arrange or change`, `Change the list` and `Add to …`; `Remove` and `Untick all` use the danger red; the link `Open your race page ›` is blue; on an iPad the page is 1000 wide with the five leg tiles in one row and the kit groups in two columns; tiles are top-aligned in equal rows.) From Settings → Race and kit → Race (`settings-race`), Progress → The race (expanded) → `Open your race page ›` (`race-page-link`), the Plan numbers card `To the race` → `Race page ›`, and the season flag (wide look). Over another page it is a sheet with Done. There is no race flag on Today.
  * **Head** in race red: `RACE`, the race's name from the plan, its date, and a big countdown (`race-countdown`): `228 days` with `32 weeks and 4 days`; race week `5 days`; `Today`; `Done · Sun 11 Jul`.
  * **Your plan for the day.** `Planned finish 5h 57m` (`race-finish`; with `So far … · 3 of 5 times typed` when not all are typed); five tiles Swim, T1, Bike, T2, Run (`race-leg-swim|t1|bike|t2|run`) with his time, distance words only when the race's title says half, 70.3, sprint, olympic or full, and his line (`pulse Z2`). `Type your times` (`race-edit-pacing`) → a page with Cancel/Save (`race-pacing-cancel`, `race-pacing-save`; fields `race-pacing-<leg>`, `race-pacing-note-<leg>`); legs as h:mm, changeovers as m:ss. No pace, speed or prediction anywhere.
  * **Fuel plan.** Tiles for Before, Bike and Run in grams; bike and run also `<n> g an hour` (worked from his leg time; with no time typed the tile says "Type your bike time for grams an hour") with `from your times`; his rows (`race-fuel-row-n`); `Add a row` (`race-fuel-add`); `Arrange or change` (`race-fuel-edit`) → drag handles (`race-fuel-handle-n`), a tap on a row changes it, `Remove`, Cancel/Save. A row's grams are the grams for that row over the whole part (said on the screen).
  * **Kit checklist.** `packed 7 of 22` (`race-checklist-count`), groups Before, Swim, Bike, Run, After, 21 starting items, ticks `race-check-n` (a green filled circle with a tick = packed), `Untick all` (`race-untick-all`; asks `Untick all N packed items?`), `Change the list` (`race-check-edit`) → rename, `Remove`, `Add to <group>`, drag within a group (`race-check-handle-n`), Cancel/Save.
  * **Dragging.** Own handle and `DragGesture` (iPhone, iPad, Mac; no `onMove`); the pure rule `RaceOrder.move` is tested.
  * **Shelf.** `race/<race day>/pacing`, `/fuel`, `/checklist`. The checklist is one key holding items and ticks: a tick on one device and a list change on another while both are offline lets the later one win whole.
  * **Switch.** `AMSWS_RACE_PAGE=1` (an invented race 228 days ahead if the plan has none; seeds targets, four fuel rows and eight ticks when the shelf is empty).
* **Shoes and bikes (37).** Settings → Race and kit → `Shoes and bikes` (`settings-gear`): a slate head card (`2 in use`), tiles `gear-tile-n`: `Blue runners · 412 km`, kind, `In use since Wed 16 Sep`, `14 runs, 3 without a distance`, a limit bar (a solid part and an outlined track) `412 of 700 km`; past the limit one grey line `Past the 700 km you set.`, no red. A put-aside item reads `Not in use now` (it was `Put aside`, the name of the button). On a tile: `Use from today` / `Put aside` (switching sets a date; the other of the same kind is put aside that day) and `Change`. `Add shoes or a bike` (`gear-add`) → a page with Cancel/Save (`gear-cancel`, `gear-save`), `Retire` and `Remove` (both ask; the question shows the red action only, a tap beside it keeps things; `Remove` in the change page is the danger red). The retired list (`gear-retired-n`) keeps the final figure. Kilometres = starting km + the logged distance (`Stats.actualsOf`) of done run (shoes) or bike (bike) sessions on the days in use; `Other` counts only the starting km; extras outside the plan and brick sessions are not counted. Shelf: `gear/<uuid>`. Switch `AMSWS_GEAR_PAGE=1` (Blue runners, Grey trainers past its limit, Road bike).
* **Tests.** `RacePlanTests` (7): the finish adds only what was typed; times are read from what he types; countdown words; fuel grams per leg and per hour from his times; the kit list starts full, ticks, unticks and moves; tolerant reading; distances in words only when the plan names the kind. `GearTests` (4): a shoe counts only its sport from its day and says what was left out; switching the shoe in use mid-month splits the runs; a retired shoe keeps its final figure; tolerant reading, and Other counts nothing. Screen: `RaceGearUITests` (2, compiled).
* **Not proven.** Pictures and screen tests; a drag with a real pointer; iCloud meeting of these keys.

### D.13b The today note for AMS Deck Mate and PARAGON (Triathlon side only; `Core/…/TodayNote.swift`, `App/Sources/TodayNote.swift`; contract `round-28/today-note-contract.md`; picks 48 and 49, this app's side)

Not in this version: Deck Mate's key and PARAGON's line themselves. Triathlon is the only writer; the other two apps only read, and may send one link. No server, no network, no health numbers, no new Apple capability. Team `D24ENP83QQ`.

* **Screen.** Settings, a new heading `Your two neighbour apps` above Reminders, with the row `Today's session is shared` (`settings-today-note`): "This app also tells Deck Mate and PARAGON today's session: its sport, length and whether it is done, and this week's hours. Nothing else. Deck Mate may log today's session as done, only as planned, and only when you press its key." No picture switch.
* **The note** (format 1, plain UTF-8 JSON, sorted keys, under 3 KB; `TodayNoteMaker`): `v` (1), `day` (`2026-12-01`), `dayWords` (`Tue 1 Dec`), `written` (UTC time), `sessions` (list; each: `key`, `sport`, `sportWord`, `title`, `minutes`, `length` (`45 min`; absent or empty when the plan gives none), `state` = `todo` | `done` | `missed` | `rest` (a rest day is one session with sport `rest` and no length), `canDone`, `open` (the session link) and, only when `canDone`, `done` (the done link)), `tomorrow` (`Bike, 1 h 10 min`; `Rest day` on a rest day; absent when nothing is planned), `week` (`40 min done of 3 h 35 min planned`), `weekDoneMinutes`, `weekPlannedMinutes`. `canDone` is true only when the done link would log right now on that phone (today, to do, has a length, logging allowed there, plan loaded). Readers ignore unknown fields; a `v` above what they know shows nothing.
* **Channels.** (1) Keychain, every device: generic password, service `ams.training.today`, account `v1` (item `ams.training.today/v1`), access group `D24ENP83QQ.com.schabbauer.AMSWorkoutSync`, accessible after first unlock, not synchronised (that device only); the same group as the neighbour notes (`ams.training.notes`) but a separate item, so no app rewrites another's data. (2) File, Mac only (Triathlon runs there as the iPad app): `today-note.json` in the app's own Application Support (container path `~/Library/Containers/com.schabbauer.AMSWorkoutSync/Data/Library/Application Support/today-note.json`), atomic replace. Not iCloud and not an App Group.
* **Refresh and stale rule.** Rewritten when the app opens or comes to the front and within about a second of any change to the plan or a log (only if the content changed); not written while the app is closed. A reader must show Open Triathlon when `day` is not its own local today or `written` is older than 36 hours, and never yesterday's session.
* **Links** (`amsworkoutsync://`): `session/<key>` (exists) opens the session's page; `done/<key>` (new; `SystemLink.doneURL`, `doneKey`) logs that session as planned through `store.logAsPlanned`, the function of the in-app Done button, but only when the guard in Core holds (`DoneFromOutside`): a session of TODAY, to do (not done, not missed), with a planned length, `canLog` true on this device, and the plan loaded (a cold start waits up to 6 seconds). Otherwise it only opens the session and changes nothing. The app always comes to the front on the session page. No link moves, edits or removes anything; pressing twice is harmless. Anything on the phone that can open URLs can send it; the worst it can do is log today's planned session as planned. Hook: `TodayNoteHook` in `SystemLinks` (`SpotlightIndex.swift`).
* **Per device.** Nothing travels. On the Mac `canLog` is false, so the note says `canDone: false` there and a press only opens the session; a real press for done works through the iPhone.
* **Tests.** `TodayNoteTests` (6). **Not proven:** the Keychain read across the three apps, the Mac container path and its permission prompt, the link from Deck Mate, and a cold-start done press; all need signed builds on real devices.

### D.14 What is per device and what follows him

* **Follows him between devices (shelf):** `favourites`, `away`, `session/…/brick|stomach|niggle|openwater`, `gear/<uuid>`, `race/<day>/pacing|fuel|checklist`.
* **Per device (`UserDefaults`):** `reminders.settings`, `reminders.closedCardWeek`; the weather switch; `claude-reviews`, `claude-ask-history`; the key, meter, log and refused state of Claude (as before).
* **Per device (files):** `Application Support/garmin-activities` (Garmin's answers for a session), the Body days kept (`BodyHistory`) and the held week, `shelf.json` (the device's copy of the shelf).
* **Computed, nothing stored:** search, print, the pool card, Why, Week so far, the way back, the month in review, bests, tests, steady weeks, the PDF, Spotlight (rebuilt on the device).

### D.15 Signs added, and the sign check

New signs, each with its one meaning: see the new paragraphs of "Signs in this app" in the guide. Checked against the existing signs (green = today and done, pale = still to do, hatched = missed, dotted = an extra, red = race, danger and taking away, the tick = done, a plain heart = Apple Health, a heart with a pulse line = Body). Near-clashes found, and what was done:

1. **Filled green stair (The way back)** is "the step you are on", while green and the tick mean today and done. Kept as built; the guide says: the tick is still done and nothing else, and the green step means now, here only.
2. **Tick on the kit list** (green circle with a tick) means packed, not done. Kept; the guide says packed is done here.
3. ~~Race red on buttons~~ — gone after the screen walks: red on the race page is only the head card, the headings and the tile names; the buttons are the plan's blue; only `Remove` and `Untick all` use the danger red.
4. **Outlined purple square (Steady weeks)** means a week not followed, while a grey empty outline in the Year squares means a rest day. Kept; different colour and page; the card now has a word key under the squares (`steady-key`).
5. **Large purple dots in Tests** are one test each, while a dotted purple bar in Load means outside the plan. Different shapes (a dot on a chart, a dotted bar); noted.
6. **Chosen word as a full blue button** (Stomach OK?, wetsuit) while the Something hurts? answers are green outlined buttons. A real difference: one asks for an answer to a question, the other marks a chosen word; both are unchanged as built.
7. **Current row in swim blue (pool card)** while blue is also the plan's colour. Blue is the swim's colour wherever a sport is meant; the guide says so.
8. **Bold green name on the last week bar** (Body, longer views) means this week, which holds today; green is today. Noted.
9. **Grey chips and lines** (away chip, Why line, weather line) are words only, like other grey pills (photos count, Not well?). No new colour.
10. **Switches in Away** instead of ticks, so the tick keeps its meaning.

### D.16 Settings, top to bottom (changes in 2.8)

Under 12.1: Your plan gains rows `Favourite sessions` (after Thursday rides) and `Away` (after Suggestions); `Race and kit` (`Race`, `Shoes and bikes`) follows Extra workouts; `Your two neighbour apps` (row `Today's session is shared`) and `Reminders` stand above Calendar, with `Weather` directly under `Reminders`; `Your two neighbour apps` (row `Today's session is shared`) heads the Reminders group; `Weather` sits directly under `Reminders`; Settings → Claude has a row `Ask about your plan` and the list `Your weeks with Claude` under the log, and its explanation has a paragraph on the two new uses. The side list of an iPad and a Mac has the word `Keys` at its foot. Settings → Suggestions has a small `Away` button at the top. How this works has new parts, in the app's page order: Notes that travel beside the plan (after The same plan on all your devices); Reminders (after Today); Notes beside a log (after Logging a session); The pool card, From your watch on a done session and Favourite sessions and repeating (after The Sessions tab); Search and print, and Keys, Spotlight and Siri (after On iPad and Mac); Away (after Changing the plan); Your race page and Shoes and bikes (after Your zones); and Signs in this app has five new paragraphs and a longer Body paragraph. What's new has the entry `2.8 (84)`.

### D.17 Version history

* 2.8 (84), 25 November 2026: forty-one picks in thirteen lanes (D.1 to D.13); the shelf; new Settings rows (D.16). Not in this release: sleep stages (pick 4), widgets (9, 10), the morning nudge (12), the hot-day swap (44), and the four that come separately (the Mac menu bar app, the Deck Mate key, the line in PARAGON, the app tour). Of the Deck Mate key and PARAGON's line only this app's side is here (D.13b); the key and the line are not.

### D.18 Tests (summary)

Core data tests: `BodyMoreTests` 8, `TodayRound28Tests` 4, `RemindersTests` 5, `GarminActivityTests` 6, `ProgressReviewsTests` 5, `PlanToolsTests` 3, `ClaudeReviewTests` 12 new, `SystemWordsTests` 6, `ShelfTests` 10, `FavouritesRepeatTests` 7, `LogExtrasTests` 4, `AwayTests` 9, `RacePlanTests` 7, `GearTests` 4. Screen tests, found by identifier: `BodyUITests`, `TodayRound28UITests`, `RemindersUITests`, `GarminActivityUITests`, `ProgressRoundUITests`, `PlanToolsUITests`, `ClaudeReviewUITests`, `KeysUITests`, `FavouritesUITests`, `LogExtrasUITests`, `AwayUITests`, `RaceGearUITests`. Written and built (build-for-testing); the lane reports say they were not run locally; Apple's run after the push is the safety net.

### D.19 What could only be proven on real devices

Siri phrases and speech; Spotlight results and opening; the hardware keys on an iPad and a Mac; real notices and their three buttons and the cold-start opening of a session; the location question and live weather; Garmin's real answers for the route, laps, zones, steps, intensity minutes and the Body Battery week; dragging with a real finger and pointer (favourites, fuel rows, kit list, kit groups); two devices meeting through iCloud (the shelf); real printing and PDF output; Claude's real answers and how often they pass the check; every screen in light and night looks at a normal iPhone size (the lane reports saw no screen).


## New in 2.9 (85) — Body gets the Garmin Board's missing cards

Version shown: 2.9 (85), 26 November 2026. The base is the released 2.8 (84). The owner picked on 26 November 2026 the cards of his Garmin Board (a web dashboard on his Mac) that the Body page lacked, "only the missing cards, no doubles"; eight are built here, in four lanes (load, health, gym, workouts), plus two small fixes found by the new menu bar app AMS Tria Menu. Where an older section says the Body page ends with six tiles and Share, this section is the newer. Everything new is shown only; sleep never leads to a suggestion. All examples are invented.

### E.1 Order of the Body page now (`BodyView.swift`, `BodyMoreCards.swift`)

Heading; calm line; the top card; Body Battery · last 7 days; the range switch; six tiles; **the part Training**: Training load and Fitness (small, side by side), Gym sessions and Workouts this month (wide); **the part Health**: Sleep debt and Weight (wide), Energy and Water (small); Share; the foot. Each part has a small heading, `Training` and `Health`, in Body's raspberry. On the iPhone two SMALL cards (about 170 points wide each) share a row and a BIG card stands full width; on the iPad and Mac, pairs share a row. A card fills its slot on the tile's fill (`Theme.bodyTile`, corner 14), with the name in small capitals (`.caption2.weight(.bold)`, tracking 0.8, `Theme.body`), the figure (`.title2.weight(.bold)`) with its unit (`.footnote.weight(.semibold)`) right beside it, one grey `.caption` line, and slim round bars. `BodyMoreCards` calls each reader's `readIfDue(today:)` when the page appears or comes back and `read(today:)` on pull-down.

* **A card with nothing to show** keeps its name and has ONE calm grey line saying what is missing and how it fills; never a zero. Without a Garmin key the Garmin cards say `Add your Garmin key in Settings to fill this.`
* **A card that opens a sheet** is a Button (the whole card, `.accessibilityElement(children: .ignore)`, label, `.isButton`); the sheet has Done and Escape = Done. Cards with a sheet: Training load, Sleep debt, Weight, and (the month's list) Workouts this month. Fitness, Gym sessions, Energy and Water have none.
* **Numbers**: thousands with `BodyPage.grouped` (note: it writes a comma, `1,412`, so the gym compare line and the load figure do too); a year or an id as `String(n)`; times with `formatDuration`; days with `Dates.short`.
* **Readers and caches** (each in Application Support; numbers only; read only with a key; invented data when DEBUG `AMSWS_FAKE_GARMIN` is set; an empty answer never replaces held numbers; 30-minute rule through `mayRead`): `BodyLoadReader` (`garmin-load.json`), `BodyHealthReader` (`garmin-health.json`), the month's reader (`garmin-month.json`). Garmin calls go through `GarminClient.tolerant(_:_:)`. Nothing is written to Garmin, the plan, Dropbox or iCloud.
* **Picture switches (DEBUG)**: `AMSWS_FAKE_GARMIN=1`, `AMSWS_TAB=body`; `AMSWS_BODY_SHEET=load|sleep-debt|weight|month`; `AMSWS_BODY_NO_WATER=1`; `AMSWS_GYM_NO_FOLDER=1`.

### E.2 Training

* **Training load** (`BodyLoadCards.swift`, rule `Core/Sources/WorkoutCore/BodyLoad.swift`; button `body-training-load`). The Board's way: load = the sum of each workout's `activityTrainingLoad` over 7 days; the 4-week average = 28 days divided by 4; ratio = 7 days over that average. Figure e.g. `412` with `7 days`; grey `4-week average 365 · ratio 1.13`; a word line; a slim raspberry scale 0 to 2 with a darker steady stretch (0.8 to 1.3) and a round marker. The word is the Board's own rule, not Garmin's (Garmin gives none): under 0.8 `Recovery`, up to 1.0 `Maintaining`, up to 1.3 `Productive`, above `Overreaching`. Only above 1.3 the words turn red: `Overreaching · well above your usual`. Empty: `No load yet` / `Fills from Garmin once workouts have a load. Tap for 12 weeks.` Sheet `body-training-load-sheet` (Done `body-training-load-done`): `Training load`, 12 slim weekly bars (the last is this week, full colour), the word and ratio, three calm sentences (steady 0.8 to 1.3; lighter; close; well above, building fast); no advice. Garmin: `GET /activitylist-service/activities/search/activities` (84 days, pages of 99; `startTimeLocal`, `activityTrainingLoad`, `vO2MaxValue`).
* **Fitness** (`body-fitness`). Figure e.g. `52` with `fitness age`; grey `Real age 58 · 6 years younger` (older, the same); then `51 VO2 max` when a workout holds a `vO2MaxValue`, else `VO2 max: Garmin does not share it yet` (it is not in the fitness-age answer). No sheet. Empty: `No fitness age yet` / `Fills from Garmin when it has worked one out.` Garmin: `GET /fitnessage-service/fitnessage/v2/{day}` (`fitnessAge`, `chronologicalAge`; the real age comes with it, no profile call).
* **Gym sessions** (`BodyGymCard.swift`, rules `Core/Sources/WorkoutCore/GymSessions.swift`; `body-gym-card`). Source: not Garmin. The file `iCloud Drive/Documents/03 Home/02 IT/01 SW/AMS Triathlon Training/AMS Workout Companion app to Garmin/Workout Companion sessions.json` written by AMS Workout Companion (fields `date`, `start`, `minutes`, `gym`, `feel`, `machines`, `sets`, `liftedKg`, `bests`, `entries[name, muscle, sets, setCount, topKg, pain]`). Rules as the Board's: a valid day, newest first, at most 60, fields checked, the feels list, the compare, the best set (heaviest weight, then most repeats); it parses `32 × 15, 35 × 12 kg`, `50 kg × 12, 10`, bodyweight and cardio lines. Card: figure = the shown session's kilograms (`body-gym-kg`) with `kg`; `body-gym-head` `Mon 9 Mar · City Gym · 55m`; `body-gym-counts` `4 machines · 11 sets · felt good · 3 days ago`; for the latest only `body-gym-compare` `vs the one before: +2 sets · −17 min · +640 kg`; each machine `body-gym-machine-N` `Leg press · best 90 kg × 10` with grey ` · new best` / ` · pain noted`; up to 6 recent sessions as rows `body-gym-row-<id>` (day, place · length, kilograms, a slim bar relative to the biggest of the six; the shown one on a pale raspberry background); foot `Tap a session to see it here.`; a tap on a row shows it in the card and `body-gym-back` `Back to the latest` returns. No sheet. No folder: `body-gym-empty` `Choose the folder once in Settings › Garmin to see your gym sessions here.` with a small `body-gym-choose` `Choose folder` (the same picker); a folder without the file: a grey line saying none found yet. Reader `GymReader`: reads when the page appears (5-minute rule) and on pull-down, through `NSFileCoordinator` (which fetches the iCloud file); it never writes.
* **Settings › Garmin, Gym sessions** (`GymFolderSection`, one line in `GarminSettingsView.swift`; `garmin-gym-section`). Heading `Gym sessions`, `From the Workout Companion app, as on your Garmin Board.`, a full-colour slate button `Choose the folder` (`garmin-gym-choose`; `.fileImporter` for a folder; a security-scoped bookmark in `UserDefaults`, per device). Once chosen: `garmin-gym-folder` the folder's name, `garmin-gym-newest` `Newest session: Mon 9 Mar` and a small `garmin-gym-change` `Change`. On a Mac the iPad app gets read access to a folder picked in the document picker; no entitlement was added.
* **The gym block on a strength session** (`GymDayBlock(day:today:)`, one line in `SessionView.swift` after `NoGymEntry`; `body-gym-session-block`). Strength sessions only: a small raspberry-tile block `GYM` with the day's place, length, counts and kilograms and the machines with their best sets. Absent when the file has no session that day.
* **Workouts this month** (`BodyMonthWorkouts.swift`, rule `MonthWorkouts.swift`; `body-month-card`). Name `WORKOUTS · NOVEMBER` (the month of today); figure e.g. `28` with `this month`; `body-month-totals` `18h 20m · 142.5 km` (km left out when no workout has a distance); the newest 6 as rows `body-month-row-<activityId>`: a pill tag (the sport word in the sport's colour from `Theme.sport`; walk, hike, breathing and yoga a grey tag), `Wed 25 · 07:45`, the name, the length (`formatDuration`), `12.4 km` and `142 bpm` when present; foot `Tap a workout to open it.` With more than 6, `body-month-all` `All 17 workouts` opens the sheet `body-month-sheet` (`Workouts · November`, Done `body-month-done`, Escape = Done) with the whole month, newest first; a tap there closes the sheet and, 0.4 s later, opens the workout. Empty `body-month-empty`: `No workouts from Garmin yet this month. They fill in once Garmin is connected and the watch has synced.` A tap calls the page's open closure with a `BodyDay.Workout` (id, name, Garmin sport key, start, end = start + length, no drain), that day's workouts earliest first and the day key: the rule of "New in 2.7" (the plan's session, else an extra, else the facts plate). Garmin: `GET /activitylist-service/activities/search/activities` (`startDate` the 1st of the month, `endDate` today, limit 99, start 0; `activityId`, `activityName`, `activityType.typeKey`, `startTimeLocal`, `startTimeGMT`, `duration`, `distance`, `averageHR`). Only Garmin's first 99 workouts of the month count.

### E.3 Health

* **Sleep debt** (`BodyHealthCards.swift`, big; `body-sleep-debt`). Figure `−6h 40m` or `+1h 05m` with `7 nights`; grey `Need about 8h a night · 1 night without the watch. Tap for each night.`; seven slim bars, each with a thin grey outline behind it that is that night's need; a night without the watch is a grey dash; today's weekday letter is green. No red, no advice. Naps count, as on the Board; where Garmin gives no need, 8 hours. No nights: `No nights recorded this week. The watch fills this once it has slept with you.` Sheet `Sleep debt · last 7 nights` (rows `body-sleep-debt-sheet-row-N` like `6h 48m of 8h`; Done `body-sleep-debt-sheet-done`). Garmin: `/sleep-service/sleep/dailySleepSummariesByDate` (`calendarDate`, `sleepTimeSeconds`, `napTimeSeconds`, `sleepNeed.actual|baseline` in minutes); its own 7-night read because the page's nights hold hours only.
* **Weight** (big; `body-weight`). The latest weight with `kg`; grey `Weighed Mon 2 Mar · +0.6 kg in 90 days · goal 78.0 kg` (the goal only when Garmin has one; the change is the first weigh-in of the 90 days against the last; the goal is not drawn as a line); a slim line over the 90 days with a dot on the latest. Empty: `No weigh-ins in 90 days. Weigh in with a Garmin scale or log it in Garmin Connect.` Sheet `Weight · last 90 days` (rows `body-weight-sheet-row-N`, Done `body-weight-sheet-done`). Garmin: `/weight-service/weight/range/{from}/{to}?includeAll=true` (`dailyWeightSummaries[].summaryDate`, `latestWeight.weight` in grams, else `previousDateWeight`) and `/goal-service/goal/user/effective/weightgoal/{from}/{to}` (`userGoals` of type `WEIGHT_GRAMS`, `goalValue`).
* **Energy** (small; `body-energy`). Total with `kcal`; `Active N · resting N`. None: `No calories yet today. The watch sends them when it syncs.` No sheet. Garmin: `/usersummary-service/v2/dailysummaries` (day − 1 to day; `calories.burnedTotal`, `burnedActive`, `burnedResting`).
* **Water** (small; `body-water`). Millilitres with `ml`, a slim bar, `Goal N ml · N%`. None logged: the name and `No water logged today. Log it in Garmin Connect.` No sheet. Same daily summary (`hydration.consumedInMl`, `goalInMl`); no separate path. Water is shown in ml only; today's summary can be absent early in the day, then the cards show their calm line.

### E.4 Two fixes found by AMS Tria Menu

* **The today note after midnight** (`TodayNote.swift`). `TodayNoteHook` rewrites the note at midnight (`NSCalendarDayChanged`) and on a five-minute check when the day has turned (`TodayNotePublisher.publishIfNewDay`). Before: only when the app came to the front, so after midnight the readers (AMS Tria Menu, AMS Deck Mate, PARAGON) found yesterday's note or none. Content and format are unchanged (see "New in 2.8").
* **Body numbers kept from yesterday.** Before: the Body numbers were read only when the Body page was shown, so an app started in the background (on a Mac, at login) left the menu bar with yesterday's Body Battery. Now `GarminReader.readBodyIfDue` reads them at the start, at midnight and on that five-minute check, and the first try of a new day skips the half-hour rule once (`GarminMorning.bodyReadDue`; data test `BodyReadDue29Tests`).

### E.5 Signs added

A slim raspberry bar in Training load with a darker steady stretch (0.8 to 1.3) and a round marker (a range, not a goal); red words only for `Overreaching` (red keeps its meaning, worse than normal; sleep debt and weight are never red); a thin grey outline behind a sleep bar (that night's need, the same idea as `normal` behind HRV); a thin line with a dot in Weight (weigh-ins over 90 days, the dot the latest); a sport-coloured tag in front of a month workout (grey for a sport with no plan colour); a pale raspberry background on the gym row shown; the Training and Health headings; the grey line for a missing thing. A slim capsule bar in Water is water against goal. No new symbol-only button.

### E.6 Tests and what is unproven

* **Data tests** (`Core/Tests/WorkoutCoreTests`): `Load29Tests` (3), `Health29Tests` (3), `Gym29Tests` (4), `Workouts29Tests` (2), `BodyReadDue29Tests`. **Screen tests** (compiled, not run locally): `Body29LoadUITests`, `Body29HealthUITests` (2), `Body29GymUITests` (2), `Body29WorkoutsUITests`.
* **Unproven**: no screen of any new card was seen by the lanes; Garmin's real answers were checked by shape with a read-only tool, not read inside the app (84 days of workouts, sleep needs, weigh-ins); the real folder picker, the bookmark and a real gym file never ran (and on a real Mac the read access of the iPad app); the gym block on a strength session on screen; the tap on a month workout without a plan session; the two fixes across a real midnight and a real Mac login. Known: the 12-week bars count back "11 … 1, now" weeks; the month counts only the first 99 workouts; the gym and load figures write thousands with a comma.

## New in 2.10 (86) — A comment with How do you feel?, and a colour for every Body card

Version shown: 2.10 (86), 26 November 2026. The base is the released 2.9 (85). The owner asked on 26 November 2026 for three things: a comment beside the morning answer, "a multitude of colours" on the Body page ("I hate this boring colour"), and clearer words on the gym card. Where an older section says every Body card is raspberry, this section is the newer. All examples are invented.

### F.1 Today: a comment with How do you feel?

* **Before.** One tap on a face saved the answer and the card was gone. **Now.** The tap saves the answer at once, and the card stays with the question `Anything to add?`, a text field with the prompt `A few words, like slept badly or sore legs` (`feel-note-field`), and two buttons: `Save` (green, full colour; `feel-note-save`) and `Skip` (`feel-note-skip`; Escape on a Mac). Either button closes the card for the day.
* **The comment line.** When a comment exists it shows under the morning line, grey, in quotes (`feel-note-line`). A tap on it opens the card again to change it; saving an empty field removes the comment.
* **Where it is kept.** In the app's diary with the answer, and through the diary to the owner's own iCloud, so the iPad and the Mac show it. Core: `DiaryDoc.notes` maps a day to its comment; the mark is `note:<day>` and the newest write wins. It is never written into the plan or the Excel file, and no rule of the rule book reads it: it leads to no advice.
* **Neighbour apps.** An answer taken over from Magic Morning or Workouts has no comment here, and the card is not shown for it.
* **Switch (DEBUG).** `AMSWS_FEEL_NOTE=1` shows the comment step for a picture.

### F.2 Body: a colour of its own for every card (`App/Sources/BodyHues.swift`)

* **Before.** Every tile and card on the Body page used Body's raspberry (`Theme.body`). **Now.** Each card has its own hue: the card's name, the marks and bars of its figures and its pale ground (`Theme.bodyTile` tinted) use it, and so does the page the card opens.
* **Code.** `BodyHue` holds one hue for each card (light and dark values); the card's view receives it through the environment as `.bodyHue(…)`, so inner marks and bars read the same value.
* **Palette** (light first, then dark; hex):

| Card | Colour | Light | Dark |
|---|---|---|---|
| Sleep, Sleep debt | indigo | 4F46E5 | A5B4FC |
| HRV | teal | 0D9488 | 5EEAD4 |
| Resting pulse | fuchsia | C026D3 | F0ABFC |
| Stress | amber | D97706 | FCD34D |
| Steps | lime | 65A30D | BEF264 |
| Intensity minutes | blue | 2563EB | 93C5FD |
| Training load | violet | 7C3AED | C4B5FD |
| Fitness | cyan | 0891B2 | 67E8F9 |
| Gym sessions | orange | EA580C | FDBA74 |
| Workouts this month | pink | DB2777 | F9A8D4 |
| Weight | purple | 9333EA | D8B4FE |
| Energy | gold | CA8A04 | FDE047 |
| Water | sky blue | 0EA5E9 | 7DD3FC |

* **Unchanged, still raspberry.** Body Battery (the big card and the 7 days of curves), the page heading, the headings `Training` and `Health`, the range buttons (7 days, 4 weeks, 12 weeks) and Share. Today's weekday letter stays bold green and the `normal` band stays grey. No card uses the green of today and done, or the red of a warning (red still appears only for `Overreaching` and the like).

### F.3 Body: clearer words on the Gym sessions card

Before the folder is chosen the card says `Your gym sessions come from the Workout Companion app. Tap Choose folder and pick AMS Workout Companion app to Garmin — it is in iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training. Once.` The button `Choose folder` opens the folder choice directly. Settings › Garmin › Gym sessions still has the same choice.

### F.4 Signs added

On the Body page each card's own colour only tells the cards apart; it means nothing else, raspberry is still Body, and no card takes the green of today and done or the red of a warning. On Today, grey words in quotes under the morning line are the owner's own comment for the day. No new symbol-only button.

### F.5 Not changed

The plan, logging, suggestions by the rule book, the Stop sign and I'm ill, the neighbour apps' notes and the Excel file.

## New in 2.11 (87) — a link to every page

Version shown: 2.11 (87), 26 November 2026. The base is the released 2.10 (86). The owner asked for AMS Deck Mate (his Stream Deck app, Mac 0.24) to open Triathlon's pages, which needs a link for each page. Nothing on any screen changed. All examples are invented.

### G.1 The links

* **Before.** One page link existed, `amsworkoutsync://today`, besides `amsworkoutsync://session/<id>`. Deck Mate's keys Plan, Body, Progress and Settings only brought Triathlon to the front.
* **Now.** Five more host names are known: `plan`, `sessions`, `body`, `progress`, `settings`. With `today` there are six page links: `amsworkoutsync://today`, `://plan`, `://sessions`, `://body`, `://progress`, `://settings`.
* **Core (`SystemWords.swift`).** `SystemLink.pages` lists the five names. `SystemLink.page(host:)` returns the page for a host name, or nothing when the name is not one of them. `SystemTarget.page(String)` is the new target that carries the name. The `today` link and the `session/<id>` link are unchanged, and so is their handling.
* **iPhone.** The tab is chosen by name: the tab whose name equals the host opens. The iPhone has no Sessions tab, so `sessions` is mapped to `plan` and the Plan tab opens.
* **iPad and Mac.** The side list row is chosen with `SideRow(rawValue:)` from the name, so `plan`, `sessions`, `body`, `progress` and `settings` each open their own row.
* **Unknown names.** A host that is not in the list opens nothing and changes nothing.
* **Other apps.** The links work from any app that can open a link: Shortcuts, Raycast, PARAGON, Safari and Deck Mate. A link only opens a page; it never changes the plan or logs anything.

### G.2 Why: Deck Mate's page group Triathlon (Mac 0.24, in AMS Deck Mate)

The group shows whenever Triathlon is in front on the Mac. Keys: Training today, Today (green), Plan (blue), Body (pink), Progress (purple), Body Battery, Sleep, Resting pulse, Stress, Steps (these five from the Garmin Board), the Ironman plan, Workouts, Workouts 7 days, Settings (slate) and a key back to AMS Deck. The colours are Triathlon's own page colours. Its keys Plan, Body, Progress and Settings use the links above. Deck Mate's side is described in Deck Mate's own specification.

### G.3 Signs and colours

No new mark, button or colour in this app. How this works has a short part, Open Triathlon from other apps, inside Keys, Spotlight and Siri, and a paragraph in Signs in this app.

### G.4 Not changed

The screens, the plan, logging, Spotlight (its session links), Siri and Shortcuts phrases, the neighbour apps' notes, the Excel file.

## New in 2.12 (88) — the gym folder's new name (26 Nov 2026)

His ask: "Dont call it gym app - call it Workout Companion app. Dont call the folder AMS Garmin, rename it to AMS Workout Companion app to Garmin."

* **The folder** in iCloud Drive was renamed on the Mac from `AMS Garmin` to `AMS Workout Companion app to Garmin` (same folder, so the Workout Companion app's saved folder choice follows it); the Garmin Board's weekly reports (`Week NN · ….json/.md`, `latest-week.json`) were moved back into a new `AMS Garmin` folder, where the Board's `scripts/report.sh` writes them. The Garmin Board's setting `gymFile` now points at `~/Library/Mobile Documents/com~apple~CloudDocs/AMS Workout Companion app to Garmin/Workout Companion sessions.json`.
* **Gym sessions card** (`body-gym-empty`): `Your gym sessions come from the Workout Companion app. Tap Choose folder and pick AMS Workout Companion app to Garmin — it is in iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training. Once.`; an empty folder: `No gym sessions found in that folder yet. They appear once the Workout Companion app has saved one there.`
* **Settings → Garmin → Gym sessions** (`garmin-gym-section`): `From the Workout Companion app, as on your Garmin Board.`, new line `Where: iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training › AMS Workout Companion app to Garmin` (2.13; in 2.12 `In iCloud Drive: AMS Workout Companion app to Garmin`) (`garmin-gym-where`, only before a folder is chosen), button `Choose the folder` (`garmin-gym-choose`). The invented sample folder name (DEBUG) is the new name.
* The app reads whatever folder he picks (security-scoped bookmark); the name is only in the words.

## New in 2.13 (89) — the gym folder moved into his AMS Triathlon Training folder (26 Nov 2026)

His words: "The file should not live directly in iCloud Drive … '~/Documents/03 Home/02 IT/01 SW/AMS Triathlon Training'. You have to fix everything. All links in all apps."

* **The folder** `AMS Workout Companion app to Garmin` was moved on the Mac from the top of iCloud Drive into `~/Documents/03 Home/02 IT/01 SW/AMS Triathlon Training/` (Documents is part of iCloud Drive, so on the iPhone: Files › iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training). It holds `Workout Companion sessions.json`. A move inside iCloud Drive keeps the folder itself, so the Workout Companion app's saved folder choice should follow it (unproven until its next session).
* **Garmin Board:** setting `gymFile` = `~/Documents/03 Home/02 IT/01 SW/AMS Triathlon Training/AMS Workout Companion app to Garmin/Workout Companion sessions.json` (checked: the gym panel reads it).
* **Gym sessions card** (`body-gym-empty`): `Your gym sessions come from the Workout Companion app. Tap Choose folder and pick AMS Workout Companion app to Garmin — it is in iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training. Once.`
* **Settings → Garmin → Gym sessions:** the line `garmin-gym-where` reads `Where: iCloud Drive › Documents › 03 Home › 02 IT › 01 SW › AMS Triathlon Training › AMS Workout Companion app to Garmin`. A folder chosen in 2.12 (the old place) must be chosen again once per device.

## New in 2.14 (90) — Mobility and strength (26 Nov 2026)

His ask: 30 minutes of mobility every Monday, Wednesday and Friday, and 30 minutes of strength every Tuesday and Thursday.

* **Row.** Settings → Your plan, right under "Thursday rides": `plan-mobility-strength`, title "Mobility and strength", sub-line "Mobility Mon · Wed · Fri, strength Tue · Thu, 30 min each". Shown only once the plan lives in the app (`canChangePlan`).
* **Page and Core.** Page `MobilityStrengthView`; the rule lives in Core `MobilityStrength` (no UI in it), tested by one small data test.
* **Range.** From tomorrow to the race. Nothing after the race.
* **Mobility.** Every Monday, Wednesday and Friday: 30 min, easy, not a key session, sport mobility (existing violet colour and icon). Friday stays the rest day; mobility is easy and counts as restorative. Name: "Mobility: hips, hamstrings, calves, upper back".
* **Fixed names.** Each mobility day has the fixed key `App!mob-<day>`; each added strength session `App!str-<day>` (same idea as `App!thu-<Monday>` for the rides): `PlanBook.add(_:why:fixedKey:)` returns the session already there, so two devices make one; a key this rule added once (an add change not undone) is never offered again, even after he took the session out — only an Undo frees it.
* **Strength moves.** The plan's own strength sessions move from Monday to Tuesday and from Wednesday to Thursday, keep their own exercises, and are each set to 30 min.
* **Strength added.** A week where the plan had only one strength session gets a second one on Thursday, copied from the plan's own second strength session of an earlier week; in a light week, the same light session again.
* **No strength.** Weeks without strength in the plan (race week, after the race) get none.
* **Race week.** Keeps mobility only.
* **Never touched.** A day already logged or marked missed is never changed. A day already holding mobility gets no second one.
* **Week rows** (`ms-week`): "Week 13 · Mon 30 Nov" (example), then "Mobility Mon · Wed · Fri", then "Strength Mon → Tue · Wed → Thu" (or "Strength Mon → Tue · + Thu"), and the week's minutes before → after.
* **Page ids.** Title `ms-title`; main button `ms-change` ("Change N weeks", full colour, N = real count); `ms-cancel` (Cancel, Escape on the Mac); `ms-done` (the green result line); `ms-already`; `ms-none`; `ms-problem` (red line, nothing changed).
* **Nothing changes until `ms-change` is tapped.** After the change the button goes and the top button says Done (Cancel before).
* **Result line** (`ms-done`): "Done: N mobility sessions added, N strength sessions moved, N added. Undo it all under Changes to the plan."
* **Opening again** once done: `ms-already` says "These days are already in your plan." When nothing would change, `ms-none` says so.
* **Failure.** `ms-problem` shows a red line; nothing is changed.
* **Changes to the plan.** The whole change is ONE entry (`change-ms-<index>`): "CHANGED", "Mobility and strength days" (the reason line), with the number of sessions, and ONE Undo (it asks first). Undo takes out the mobility sessions and the added strength sessions and puts the moved strength sessions back on their days; anything logged since stays.
* **iCloud.** The change is made on one device and reaches the iPhone, iPad and Mac like every change to the plan.
* **Signs.** No new marks. "→" keeps its one meaning (before → after, moves to); "+" means added. Mobility uses the existing violet.
* **Picture switch** (DEBUG, see 14.6): `AMSWS_MOBILITY=1` opens the page.
* **Words.** What's new has "2.14 (90)"; How this works changed in Changing the plan and Signs in this app.
* **Writing.** `MobilityStrength.plan(weeks:sessions:changes:mapping:from:)` says what would change (nothing written); `MobilityStrength.apply(_:to:why:now:)` writes the moves (as `edit` changes, with a `MoveRecord` at the same moment so an Undo clears it) and the adds into a copy of the book, all or none; `Store.applyMobilityStrength` saves once. Reason line `Mobility and strength days #<batch>` (8 letters), one batch per tap; `MobilityStrength.batch(of:)` groups a round in Changes to the plan.
* **Undo.** `MobilityStrength.undo(batch:in:)` takes back, newest first and in one save (`Store.undoMobilityStrength`), every change of the round that is not undone, is still the newest change to its session, and whose session holds no log, no Missed and no waiting log.
* **Start.** Tomorrow (`store.today + 1`): today is never changed.
* **Details of the strength rule.** Per week: the strength sessions on Tue/Thu stay; a session before the start, logged, missed or waiting stays where it is and counts as one of the two; a session this rule moved before and he put back himself is not moved again. The rest move to the free days of Tue/Thu, earliest first, as many as are still needed for two. When one more is needed beside a session that stays, it goes on the later free day (Thursday), so the two are apart. A moved session's name loses the words "(single weekly session)". The copied second session: the week's own when its name holds "light", else the plan's last earlier week's second strength session, else the week's first.
* **Before → after minutes** on a week row: the week's planned minutes without rest days, then + 30 per mobility and per added strength session, and + (30 − old length) per moved one.
* **Tests.** Data: `MobilityStrengthTests` (2: the whole rule on an invented five-week plan incl. apply + one Undo back to the start; mid-week start and a logged session). Screen: `MobilityStrengthUITests` (the page says one honest thing; one tap changes and says so; the button goes; Cancel becomes Done).
