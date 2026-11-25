# The course's real pictures — how they are taken

The course shows real pictures of AMS Triathlon Training beside its practice screens. Every picture is taken on a simulator
with the **invented plan** (`UITests/Fixtures/plan.xlsx`, or `plan-done.xlsx` where done sessions are needed) and the app's
DEBUG picture switches — never with the owner's real plan or health numbers. This repository is public.

## Rules for whoever takes them
- **Your own simulator.** Create it, never touch one you did not create (other conversations are using theirs):
  `xcrun simctl create "Tour <your letter> phone" "iPhone 17e"` (iPad: `"iPad Pro 11-inch (M5)"`), then `xcrun simctl boot <id>`
  and `xcrun simctl bootstatus <id> -b`. Day look: `xcrun simctl ui <id> appearance light`. A tidy top line:
  `xcrun simctl status_bar <id> override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`.
- **The app** is ready-built (2.8, build 84): `~/Developer/amsws-lanes/dd-tour/Build/Products/Debug-iphonesimulator/AMSWorkoutSync.app`
  → `xcrun simctl install <id> <that path>`. Do not build, do not change any file of the app.
- **One picture** = `docs/intro/tools/shot.sh <id> <name> [SWITCH=value ...]` (read the top of that script). It starts the app fresh
  with the invented plan on the day 2026-09-16 and saves `docs/intro/shots/<name>.jpg`.
- **Which switch opens which screen:** `docs/SPECIFICATION.md` (section "New in 2.8 (84)" and the "Switches" parts of the sections
  before it), the lane and walk reports in the last round's report folder (kept outside this repository; its path is in the helper's prompt)
  with `WALK-RULES.md` beside them, and `grep -rn "AMSWS_" App/Sources`. Useful everywhere: `AMSWS_TAB=today|plan|body|progress|settings`
  (iPhone; "plan" is the tab named Sessions), `AMSWS_SIDE=today|plan|sessions|body|progress|settings` (iPad), `AMSWS_SESSION=<key>`,
  `AMSWS_FAKE_GARMIN=1`, `AMSWS_FAKE_CLAUDE=1`, `AMSWS_FAKE_HEALTH=1`, `AMSWS_FAKE_WEATHER=…`, `AMSWS_SCROLL=…`.
  A system question over the app (notifications, location) spoils a picture: find the switch that avoids it, or take the picture
  of another state. You cannot tap; only switches. If a screen cannot be reached by switches, leave it out and say so.
- **Look at every picture yourself** (Read the .jpg). Wrong screen, a system box over it, an empty page, a spinner, the owner's
  real name or anything that is not invented → fix the switches and take it again, or delete the file.
- **Names:** `<chapter id>-<two digits>-<one or two words>`, e.g. `tod-01-morning`, `pln-02-month`. Small letters, digits, hyphens.
- **Shell:** this Mac's bash is 3.2; put a list of pictures into a small script file under `docs/intro/shots-raw/` and run that,
  rather than long one-liners. A batch takes about 10 seconds a picture: run it in the background if it has more than 10.
- **At the end:** `xcrun simctl shutdown <id>` and `xcrun simctl delete <id>` for every simulator you created.
- **Hand back** `docs/intro/shots/INDEX-<your letter>.md`: one line per picture —
  `name · what is on it, with its headings and button names word for word as the picture shows them · the switches used`.
  The chapter writers will describe each picture from this line and from the picture itself, so be exact and complete.

## Learned while taking the first set (25 Nov 2026)
- **The owner's plan lives in the app.** Every picture is taken with `AMSWS_HOME=app` (the script adds it by itself), or it shows
  things he never sees: a "Connect Dropbox" word on Today, "Waiting to sync" on a logged session, a session page without Change,
  Excel wording at the foot of Progress. Only the move-in page is taken without it (`AMSWS_HOME=excel` switches it off).
- **Zone numbers.** Pictures that show the test and zone numbers (Settings › Your zones row, the Your zones page, the Tests card
  on Progress) are taken with `AMSWS_FILE=<repo>/docs/intro/shots-raw/plan-course.xlsx`, made by `tools/course-plan.py`
  (156 bpm · 114 sec/100 m · 74 kg), not with the fixture's own 150 / 121 / 80.
- **iPad:** an "iPad Pro 13-inch (M5)" held upright shows the wide look; an 11-inch upright does not, and a simulator cannot be turned.
- Done sessions: `AMSWS_FILE=<repo>/UITests/Fixtures/plan-done.xlsx`, or `AMSWS_FAKE_DONE=1`. The Sunday card needs the day
  2026-09-13 and the Sunday switch; Claude's line on a card needs `defaults write com.schabbauer.AMSWorkoutSync claude-on -bool true`
  in the simulator. No switch reaches: How this works, What's new, the month calendar on the phone.
- The names of the pictures in use are listed by `python3 docs/intro/build.py`; a picture no step uses is not kept.
