#!/usr/bin/env python3
"""
make-scenarios.py <plan-dump.json> <workbook-dir> > scenarios.json

The logging situations the two writers are put through, generated from what
plan-dump reads out of each workbook so that every step names a session that
really exists. Deterministic: the same workbooks give the same scenarios, so a
difference found once can be found again.

Each scenario starts from a fresh copy of its workbook. They cover what the
web app can write today — a full log, one tap, a correction on a session
already logged, missed, a move, several sessions in one sync — and the input
a person actually types: decimal commas, units, clock times, stray spaces,
XML's special characters, emoji, control characters, junk.
"""
import json
import os
import sys
from datetime import date, timedelta

WHEN = "2026-09-14T10:15:00.000Z"

FULL = {"actualDuration": "52", "actualDistance": "10,4", "avgHr": "142", "maxHr": "171",
        "avgPace": "5:02", "rpe": "6", "completedAt": WHEN,
        "notes": "Felt <good> & strong \"today\" — Kolmården 🏃‍♂️"}

VARIANTS = [
    ("full", [FULL]),
    ("onetap", [{"actualDuration": "45"}]),
    ("clock", [{"actualDuration": "1:15", "completedAt": WHEN}]),
    ("clock-seconds", [{"actualDuration": "1:02:30", "completedAt": WHEN}]),
    ("hours-mins", [{"actualDuration": "1h20", "completedAt": WHEN}]),
    ("comma-hours", [{"actualDuration": "1,5h", "completedAt": WHEN}]),
    ("min-sec", [{"actualDuration": "45min 30s", "completedAt": WHEN}]),
    ("odd-minutes", [{"actualDuration": "37", "avgHr": "133,5", "completedAt": WHEN}]),
    ("swim-metres", [{"actualDuration": "41", "actualDistance": "1750", "distanceUnit": "m", "avgPace": "1:52", "completedAt": WHEN}]),
    ("bike-speed", [{"actualDuration": "70", "actualDistance": "32,25", "avgPace": "32,5", "avgPower": "168 W",
                     "cadence": "88", "elevation": "240", "calories": "712", "completedAt": WHEN}]),
    ("junk", [{"actualDuration": "abc", "actualDistance": "12abc", "avgHr": "  150 bpm ", "rpe": "x", "completedAt": WHEN}]),
    ("spaces-notes", [{"actualDuration": " 30 ", "notes": "   padded note\t", "completedAt": WHEN}]),
    ("control-chars", [{"actualDuration": "20", "notes": "abcde", "completedAt": WHEN}]),
    ("custom-done", [{"actualDuration": "25", "doneLabel": "OK", "completedAt": WHEN}]),
    ("missed", [{"missed": True, "notes": "Sick — sore throat", "completedAt": WHEN}]),
    ("missed-no-note", [{"missed": True, "completedAt": WHEN}]),
    ("log-then-missed-then-log", [{"actualDuration": "30", "completedAt": WHEN},
                                  {"missed": True, "notes": "wrong one", "completedAt": WHEN},
                                  {"actualDuration": "31", "rpe": "4", "completedAt": WHEN}]),
    ("empty", [{"actualDuration": "", "notes": "", "completedAt": WHEN}]),
]


def shift(day, n):
    return (date.fromisoformat(day) + timedelta(days=n)).isoformat()


def main():
    dump = json.load(open(sys.argv[1]))
    folder = sys.argv[2]
    out = []

    for name in sorted(dump):
        book = dump[name]
        if not book.get("mapping"):
            continue
        base = os.path.splitext(name)[0]
        path = os.path.join(folder, name)
        workouts = [w for w in book["workouts"] if w["discipline"] != "rest"]
        if not workouts:
            continue
        todo = [w for w in workouts if not w["loggedInSheet"]]
        done = [w for w in workouts if w["loggedInSheet"]]
        swims = [w for w in todo if w["discipline"] == "swim"]
        bikes = [w for w in todo if w["discipline"] == "bike"]
        pick = lambda lst, i: lst[i % len(lst)] if lst else workouts[i % len(workouts)]

        for i, (label, steps) in enumerate(VARIANTS):
            target = pick(todo, i)
            if label == "swim-metres":
                target = pick(swims, 0)
            if label == "bike-speed":
                target = pick(bikes, 0)
            out.append({"name": f"{base}--{label}", "file": path,
                        "steps": [{"key": target["key"], "entry": e} for e in steps]})

        # A correction written over a session the sheet already has results for.
        if done:
            out.append({"name": f"{base}--overwrite-logged", "file": path,
                        "steps": [{"key": pick(done, 0)["key"], "entry": FULL}]})

        # Moves: forward, back across a week boundary, onto another session's day.
        for j, n in enumerate([2, -6, 1]):
            w = pick(todo, 3 + j)
            out.append({"name": f"{base}--move{j}", "file": path,
                        "steps": [{"key": w["key"], "entry": {"moveTo": shift(w["dayKey"], n)}}]})

        # One sync carrying many sessions, as after a week offline.
        many = [pick(todo, k) for k in range(0, min(len(todo), 12))]
        steps = []
        for k, w in enumerate(many):
            entry = VARIANTS[k % 10][1][0]
            steps.append({"key": w["key"], "entry": entry})
        if len(many) > 3:
            steps.append({"key": many[3]["key"], "entry": {"moveTo": shift(many[3]["dayKey"], 1)}})
        out.append({"name": f"{base}--week-offline", "file": path, "steps": steps})

    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
