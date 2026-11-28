#!/usr/bin/env python3
"""Makes the pictures of Settings › How this works (2.22).

Every picture is the real screen with the INVENTED plan (UITests/Fixtures/plan.xlsx, the day 2026-09-16) and the app's
DEBUG picture switches — never real data. Each one is taken by day and by night, cut to the part the guide shows, and
saved as App/Resources/Guide/guide-<name>-day.jpg / -night.jpg at 2 pixels a point (GuidePicture.pixelsPerPoint).

    1. Your OWN simulators (other conversations use theirs):
         xcrun simctl create "Guide phone" "iPhone 17e"      and      xcrun simctl create "Guide pad" "iPad Pro 13-inch (M5)"
       boot them one at a time, install a Debug build of the app (xcrun simctl install <id> <path>/AMSWorkoutSync.app) and,
       BEFORE its first start, xcrun simctl privacy <id> grant location com.schabbauer.AMSWorkoutSync — an unanswered
       location question stays over every later picture.
    2. python3 tools/guide-pictures.py shoot phone <phone id> <raw folder> [name ...]
       python3 tools/guide-pictures.py shoot pad <pad id> <raw folder> [name ...]
    3. python3 tools/guide-pictures.py cut <raw folder> [name ...]
    4. Delete the simulators you made.
Look at every picture before you ship it; when a screen changed, move its circles (GuideMark in Guide.swift) too.
"""
import os, shutil, subprocess, sys, tempfile, time
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..")
OUT = os.path.join(REPO, "App", "Resources", "Guide")
BUNDLE = "com.schabbauer.AMSWorkoutSync"
PIXELS_PER_POINT = 2

# name: the picture switches for that part (on top of the invented plan, its day and AMSWS_HOME=app).
PHONE = {
    "today":     "AMSWS_TAB=today AMSWS_FAKE_DONE=1 AMSWS_FAKE_GARMIN=1 AMSWS_FEEL=4",
    "todaydown": "AMSWS_TAB=today AMSWS_FAKE_DONE=1 AMSWS_FEEL=4 AMSWS_TODAY_OFFSET=380",
    "suggest":   "AMSWS_TAB=today AMSWS_TODAY=2026-09-14 AMSWS_AWAY=nopool AMSWS_SUGGEST=card",
    "stop":      "AMSWS_STOP=1",
    "session":   "AMSWS_PLANNED=run AMSWS_FAKE_DONE=1",
    "logform":   "AMSWS_PLANNED=run AMSWS_FAKE_DONE=1 AMSWS_LOGFORM=1",
    "done":      "AMSWS_DONE=run AMSWS_FAKE_GARMIN=1 AMSWS_FAKE_PATH=/tmp AMSWS_FILE={done}",
    "sessions":  "AMSWS_TAB=plan",
    "extra":     "AMSWS_EXTRAFORM=1",
    "body":      "AMSWS_TAB=body AMSWS_FAKE_GARMIN=1",
    "progress":  "AMSWS_TAB=progress AMSWS_FAKE_DONE=1 AMSWS_FILE={done}",
    "zones":     "AMSWS_ZONES=1",
    "race":      "AMSWS_RACE_PAGE=1",
    "gear":      "AMSWS_GEAR_PAGE=1",
    "settings":  "AMSWS_TAB=settings",
    "garmin":    "AMSWS_GARMIN_PAGE=1 AMSWS_FAKE_GARMIN=1",
    "claude":    "AMSWS_CLAUDE_PAGE=1 AMSWS_FAKE_CLAUDE=1",
    "watch":     "AMSWS_DONE=run AMSWS_FAKE_GARMIN=1 AMSWS_FAKE_PATH=/tmp AMSWS_FILE={done} AMSWS_SESSION_SCROLL=end",
    "icloud":    "AMSWS_CLOUD_PAGE=1 AMSWS_TAB=settings AMSWS_FAKE_CLOUD={cloud}",
    "safety":    "AMSWS_SAFETY=1",
    "planmaker": "AMSWS_PLANMAKER=draft",
    "reminders": "AMSWS_REMINDERS_PAGE=1",
}
PAD = {
    "week":  "AMSWS_SIDE=plan AMSWS_PLAN=week AMSWS_FILE={season} AMSWS_FAKE_DONE=1",
    "month": "AMSWS_SIDE=plan AMSWS_PLAN=month AMSWS_FILE={season} AMSWS_FAKE_DONE=1",
    "year":  "AMSWS_SIDE=plan AMSWS_PLAN=year AMSWS_FILE={season} AMSWS_FAKE_DONE=1",
}


def make_season(fixture, path):
    """An INVENTED half-distance season for the Plan pictures (the fixture plan is only two weeks long): 30 weeks from
    Mon 31 Aug 2026 with phases, an easy week every fourth, the race on Sun 21 Mar 2027 and two weeks after it."""
    import openpyxl
    from datetime import date, timedelta
    book = openpyxl.load_workbook(fixture)
    sheet = book["Weekly Schedules"]
    sheet.delete_rows(2, sheet.max_row)
    sheet.cell(1, 15, "Phase")
    week = [  # weekday, sport, title, minutes, intensity, purpose
        (1, "Swim", "Technique: 6x50 drill, 8x100 smooth", 40, "Z1-Z2", "Feel for the water"),
        (1, "Strength", "Gym A: legs and core", 30, "-", "Strong to stay healthy"),
        (2, "Run", "Easy run + 4x20 s strides", 40, "Z2", "Aerobic base"),
        (3, "Bike", "Intervals: 4x6 min at threshold", 60, "Z4", "Threshold power"),
        (3, "Mobility", "Hips and T-spine", 15, "-", "Keep the hips honest"),
        (4, "Swim", "Endurance: 3x400 steady", 45, "Z2", "Swim endurance"),
        (5, "Bike", "Long steady ride, rolling", 120, "Z2", "Time in the saddle"),
        (6, "Run", "Long run, conversational", 70, "Z2", "Run endurance"),
    ]
    phases = ["Base"] * 8 + ["Build"] * 8 + ["Peak"] * 6 + ["Taper"] * 5 + ["Race"] + ["Post-season"] * 2
    start, row = date(2026, 8, 31), 2
    for w, phase in enumerate(phases):
        factor = {"Base": 0.8, "Build": 1.0, "Peak": 1.2, "Taper": 0.7, "Race": 0.4, "Post-season": 0.5}[phase]
        if (w + 1) % 4 == 0 and phase in ("Base", "Build", "Peak"):
            factor *= 0.7
        monday = start + timedelta(weeks=w)
        rest = monday
        sheet.append([w + 1, rest.isoformat(), rest.strftime("%a"), "Rest", "REST DAY - full day off", None, "-", "Adaptation happens at rest",
                      None, None, None, None, None, None, phase])
        for day, sport, title, minutes, zone, purpose in week:
            d = monday + timedelta(days=day)
            if phase == "Race" and day == 6:
                sport, title, minutes, zone, purpose = "Race", "Lakeside Half (70.3)", 330, "Race", "The race"
            sheet.append([w + 1, d.isoformat(), d.strftime("%a"), sport, title, round(minutes * factor / 5) * 5, zone, purpose,
                          None, None, None, None, None, None, phase])
            row += 1
    book.save(path)

# name: the cut-out in points of the whole screen (left, top, right, bottom); None = the whole screen.
CUTS = {
    "today": (0, 50, 390, 600), "todaydown": (0, 180, 390, 420), "suggest": (0, 50, 390, 470), "stop": (0, 50, 390, 440),
    "session": (0, 50, 390, 540), "logform": (0, 48, 390, 800), "done": (0, 100, 390, 700), "watch": (0, 50, 390, 735),
    "sessions": (0, 50, 390, 560), "extra": (0, 48, 390, 800), "body": (0, 50, 390, 750), "progress": (0, 50, 390, 640),
    "zones": (0, 50, 390, 820), "race": (0, 50, 390, 820), "gear": (0, 50, 390, 800), "settings": (0, 50, 390, 760),
    "garmin": (0, 95, 390, 430), "claude": (0, 560, 390, 780), "icloud": (0, 95, 390, 560), "safety": (0, 50, 390, 345),
    "planmaker": (0, 50, 390, 600), "reminders": (0, 50, 390, 800),
    "week": (0, 24, 1032, 990), "month": (0, 24, 1032, 905), "year": (0, 24, 1032, 915),
}


def sh(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def shoot(kind, udid, raw, names):
    table = PHONE if kind == "phone" else PAD
    os.makedirs(raw, exist_ok=True)
    # The fixtures go to a folder without spaces: simctl passes the switches through SIMCTL_CHILD_ and the repo path has spaces.
    work = tempfile.mkdtemp(prefix="guide-")
    plan = os.path.join(work, "plan.xlsx"); shutil.copy(os.path.join(REPO, "UITests", "Fixtures", "plan.xlsx"), plan)
    done = os.path.join(work, "plan-done.xlsx"); shutil.copy(os.path.join(REPO, "UITests", "Fixtures", "plan-done.xlsx"), done)
    season = os.path.join(work, "season.xlsx"); make_season(plan, season)
    for name in names or table:
        for look, tag in (("light", "day"), ("dark", "night")):
            # A fresh iCloud stand-in for every start, or the second start finds the first one's plan and shows two plans.
            cloud = tempfile.mkdtemp(prefix="cloud-", dir=work)
            env = {k: v for k, v in os.environ.items() if not k.startswith("SIMCTL_CHILD_")}
            # Invented weather: no location question over the picture.
            base = {"AMSWS_FILE": plan, "AMSWS_TODAY": "2026-09-16", "AMSWS_RESET": "1", "AMSWS_HOME": "app", "AMSWS_FAKE_WEATHER": "1"}
            for kv in table[name].split():
                k, v = kv.split("=", 1)
                base[k] = v.format(plan=plan, done=done, cloud=cloud, season=season)
            for k, v in base.items():
                env["SIMCTL_CHILD_" + k] = v
            # Each look gets its own fresh start: a page opened by day does not always redraw when the look changes (iCloud).
            sh("xcrun", "simctl", "ui", udid, "appearance", look)
            subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["xcrun", "simctl", "launch", udid, BUNDLE], check=True, env=env, stdout=subprocess.DEVNULL)
            time.sleep(8)
            sh("xcrun", "simctl", "io", udid, "screenshot", os.path.join(raw, f"{name}-{tag}.png"))
        print(name, flush=True)
    sh("xcrun", "simctl", "ui", udid, "appearance", "light")
    shutil.rmtree(work, ignore_errors=True)


def cut(raw, names):
    os.makedirs(OUT, exist_ok=True)
    for name in names or CUTS:
        for tag in ("day", "night"):
            image = Image.open(os.path.join(raw, f"{name}-{tag}.png")).convert("RGB")
            # A phone screen is 3 pixels a point, an iPad 2: find out from the width.
            scale = 3 if image.width < 1400 else 2
            box = CUTS[name]
            if box:
                image = image.crop(tuple(round(scale * v) for v in box))
            if scale != PIXELS_PER_POINT:
                image = image.resize((round(image.width * PIXELS_PER_POINT / scale), round(image.height * PIXELS_PER_POINT / scale)), Image.LANCZOS)
            path = os.path.join(OUT, f"guide-{name}-{tag}.jpg")
            image.save(path, quality=80, optimize=True, progressive=True)
            print(f"{os.path.basename(path)}  {image.width // PIXELS_PER_POINT} x {image.height // PIXELS_PER_POINT} points  {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "shoot":
        shoot(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif len(sys.argv) >= 3 and sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3:])
    else:
        print(__doc__)
