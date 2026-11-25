# AMS Triathlon Training (iPhone)

Called AMS Workout Sync up to 1.1 (72); the folder, the repository, the bundle id and the URL scheme `amsworkoutsync` keep the old name. The full description of the app is in `docs/SPECIFICATION.md`.

From 2.0 (build 74) the app can also be the plan's own home: the plan is taken in from the workbook once, counted on both sides to prove nothing changed, and then lives in the app (sessions can be changed, added and taken out; safety copies, weekly spreadsheet copies, and a road back to Excel for three weeks). Until the user chooses that, Excel in Dropbox stays the home exactly as before. The engine is `PlanBook`, `PlanImport`, `PlanExport` and `BookOracle` in `Core/`; `book-check` rehearses the move on a copy of a workbook.

The native iPhone app for Martin's training plan — a SwiftUI app around
`Core/`, a Swift package that is a line-for-line port of the web app's reader
and writer (`../AMS Workout Sync`). Since 1.0 (15 September 2026) it is the
primary training app, and since 22 September 2026 the only one: Martin said
plainly that he no longer uses the web app, so work he asks for belongs here
even when he names neither app. The web app stays as the reference
implementation the parity harness checks against.

- `Core/Sources/WorkoutCore` — zip, xlsx, mapping detection, plan, writer,
  edits, extras, sync engine, form logic. `plan-dump`, `write-dump`,
  `sync-check`, `form-check`, `book-check` are the Mac-side checks. Since 2.0 also
  the plan's book (`PlanBook`), the one-time take-in and its proof, and the
  spreadsheet copy.
- `tools/` — the parity harness against the web app: `README.md` there says
  how to run it. Every change to the writer or to `buildEdits` must be re-run
  through it before it ships.
- `App/` — the SwiftUI app. XcodeGen: `xcodegen generate`, then build. Version
  and build number live in `project.yml`; every build adds an entry to
  `App/Sources/Guide.swift` (What's new) and, when behaviour changes, to
  How this works in the same file.
- Release: archive with `-allowProvisioningUpdates`, export with
  `tools/ExportOptions.plist` (uploads to App Store Connect), TestFlight
  internal group "Me".

## The course (guided tour)

`docs/intro/` holds the guided course for the app as of 2.8 (84): 16 chapters, 268 steps, a practice iPhone and iPad drawn
in the page, and 102 real pictures taken on a simulator with the invented plan. Live page (private):
https://claude.ai/artifact/8rLownadXakfs4pMQhpstf. How a chapter is written: `docs/intro/HELPERS.md`; how the pictures are
taken: `docs/intro/PICTURES.md`; check with `node docs/intro/check.mjs`, build with `python3 docs/intro/build.py`, then publish
`index.html` together with `shots/`. **Update the course in the release that changes a taught screen.**
