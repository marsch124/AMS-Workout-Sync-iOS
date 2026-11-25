# Brief shared by every fact checker (25 Nov 2026)

You check chapters of the guided course for **AMS Triathlon Training 2.8 (84)** against the app's own code. The repo is
this repository's folder. You did not write these chapters; read them
as a sceptic. Read `docs/intro/HELPERS.md` first (the contract the chapters were written to).

For each of your chapters (`docs/intro/src/chapters/NN-id.js`):
1. Read the whole chapter file. For every step, check each claim in `head`, `text`, `hint`, `ok`, `real`, `only`, each check
   question's right answer, and the words on the pretend screens (button names, headings, messages, number formats) against the
   code: `App/Sources/*.swift`, `Core/Sources/WorkoutCore/*.swift`, `App/Sources/Guide.swift`, `docs/SPECIFICATION.md`.
   The code wins over the guide and the specification. `grep` for the exact words first; read around the hit.
2. For every step with `shot: 'name'`: Read `docs/intro/shots/name.jpg` and check that the step's words describe what the picture
   really shows (the lines in `docs/intro/shots/INDEX-A.md`, `-B.md`, `-C.md` help, but the picture decides).
3. The owner's plan LIVES IN THE APP (not in Excel): nothing may tell him a button "appears only once the plan lives in the
   app", and no pretend screen may show "Connect Dropbox" or "Waiting to sync" as his normal state.
4. Fix what is wrong, in that chapter's own `.js` / `.css` only: correct the words to the code's, correct a wrong claim, remove
   a claim you cannot find any support for. Do NOT restructure, add or remove steps, rename anything, or change other files.
   Keep `head` to 9 words and `text` to 380 characters. Plain British English, no computer words, no emoji or picture signs.
5. Run `node docs/intro/check.mjs <id>` (from the repo folder) after your fixes until it says OK.

What counts as wrong: a button, heading or message whose words differ from the code; something said to be on a page that is
elsewhere; a consequence that the code does not produce (what Save writes, what a suggestion changes, what is sent to Claude or
Garmin, what follows him between devices); a limit or number format that differs; "iPhone only" / "iPad and Mac" stated wrongly;
a picture described wrongly. What does NOT count: invented sample figures and names in the practice copy, and simplifications
the step itself admits.

Final answer, at most 14 lines: per chapter, how many things you corrected, the three most important ones (before → now, with
the file and line of the code that proves it), and anything you could not settle.
