# Brief shared by every chapter writer (25 Nov 2026)

You write chapters of the guided course for the app **AMS Triathlon Training 2.12 (88)** (iPhone, iPad, Mac). The repo is
this repository's folder (PUBLIC — invented figures only).

1. Read completely, in this order: `docs/intro/HELPERS.md` (the contract), `docs/intro/src/chapters/00-wel.js` + `00-wel.css`
   (the worked example), `docs/intro/src/example/99-exa.js`, `docs/intro/src/core.js` (the `K` building blocks), `docs/intro/src/kit.css`.
2. Learn your screens from the code and the texts named in your prompt: every word on a pretend screen and in a step must be the
   app's own word. The lane reports of the last round are in
   the last round's report folder (kept outside this repository; its path is in the helper's prompt); earlier real pictures (day and night,
   contact sheets `walk-a…f-N.png` and single pictures in the folders beside them) are in
   the picture folder beside it — look at the ones of your screens so your
   pretend screens look like the real ones. Read nothing else outside the repo.
3. Write ONLY your own new files `docs/intro/src/chapters/NN-id.js` and `NN-id.css` (numbers and ids are in your prompt). Touch no
   other file, do not build, do not commit, do not run the app or a simulator.
4. **Real pictures.** Other helpers are taking them right now into `docs/intro/shots/` (names start with your chapter's id, e.g.
   `tod-01-…jpg`; `shots/INDEX-A.md`, `INDEX-B.md`, `INDEX-C.md` say what is on each — they are written at the end, the pictures
   come first). Write your practice steps first. Then `ls docs/intro/shots/`, Read each picture of your chapters, and give
   2 to 5 look steps per chapter a `shot` — describing exactly what that picture shows. iPad pictures (numbers from 90, or the
   `pln-` ones) need `set: { device: 'pad' }`. If a chapter's pictures are not there yet when everything else is done, look again
   a few times; if there are still none, write the chapter without and say so in your report.
5. Check with `node docs/intro/check.mjs <id>` (from the repo folder) until it says OK for each of your chapters.
6. Final answer, at most 15 lines: your chapters with their step counts (look / try / check), the check's result, which pictures
   you used, every place where the guide and the code differ, and anything you were not sure of.
