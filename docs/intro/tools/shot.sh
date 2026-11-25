#!/bin/bash
# One real picture of the app for the course, with the invented plan.
#   tools/shot.sh <simulator id> <name> [NAME=value ...]
# e.g. tools/shot.sh 1234-ABCD tod-01-today AMSWS_TAB=today AMSWS_FAKE_GARMIN=1
# The app is started fresh with the invented plan (UITests/Fixtures/plan.xlsx) living in the app (AMSWS_HOME=app), the day
# 2026-09-16 and a clean start;
# every NAME=value after the name is one more picture switch (a later one wins, so AMSWS_TODAY=… or AMSWS_FILE=… can be changed).
# WAIT=<seconds> changes the wait before the picture (default 8). The picture lands in docs/intro/shots/<name>.jpg
# (580 wide for an iPhone, 1400 wide for an iPad) and the full-size original in docs/intro/shots-raw/<name>.png (not kept in git).
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"; repo="$(cd "$here/../.." && pwd)"
id="$1"; name="$2"; shift 2
export SIMCTL_CHILD_AMSWS_FILE="$repo/UITests/Fixtures/plan.xlsx" SIMCTL_CHILD_AMSWS_TODAY=2026-09-16 SIMCTL_CHILD_AMSWS_RESET=1 SIMCTL_CHILD_AMSWS_HOME=app
wait=8
for kv in "$@"; do
  k="${kv%%=*}"; v="${kv#*=}"
  if [ "$k" = "WAIT" ]; then wait="$v"; else export "SIMCTL_CHILD_$k=$v"; fi
done
mkdir -p "$here/shots" "$here/shots-raw"
xcrun simctl terminate "$id" com.schabbauer.AMSWorkoutSync >/dev/null 2>&1 || true
xcrun simctl launch "$id" com.schabbauer.AMSWorkoutSync >/dev/null
sleep "$wait"
xcrun simctl io "$id" screenshot "$here/shots-raw/$name.png" >/dev/null 2>&1
w=$(sips -g pixelWidth "$here/shots-raw/$name.png" | awk '/pixelWidth/{print $2}')
if [ "$w" -gt 1400 ]; then out=1400; else out=580; fi
sips -s format jpeg -s formatOptions 82 --resampleWidth "$out" "$here/shots-raw/$name.png" --out "$here/shots/$name.jpg" >/dev/null
echo "$name.jpg  ($w px wide original)"
