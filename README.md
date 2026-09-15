# AMS Workout Sync (iPhone)

The native iPhone app for Martin's training plan — a SwiftUI app around
`Core/`, a Swift package that is a line-for-line port of the web app's reader
and writer (`../AMS Workout Sync`). Since 1.0 (15 September 2026) it is the
primary Workout Sync; the web app remains for the Progress tab, spoken logging
and the Mac.

- `Core/Sources/WorkoutCore` — zip, xlsx, mapping detection, plan, writer,
  edits, extras, sync engine, form logic. `plan-dump`, `write-dump`,
  `sync-check`, `form-check` are the Mac-side checks.
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
